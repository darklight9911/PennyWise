// Package receipts handles receipt photos: presigned uploads straight to
// R2, a HEAD check before a receipt counts as uploaded, short-lived view
// URLs, and a nightly clean-up (PLAN.md section 3, "Receipt upload flow").
package receipts

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"pennywise/backend/internal/storage"
)

// Limits from the plan.
const (
	MaxBytes          = 2 << 20 // 2 MB after the phone compresses the photo
	MaxPerTransaction = 3
	UploadURLTTL      = 5 * time.Minute
	ViewURLTTL        = 5 * time.Minute
	PendingTTL        = 24 * time.Hour
)

// TaskCleanup is the nightly clean-up job.
const TaskCleanup = "receipts:cleanup"

// Errors the handlers map to HTTP answers.
var (
	ErrNotFound      = errors.New("receipts: not found")
	ErrBadType       = errors.New("receipts: only JPEG and PNG")
	ErrTooBig        = errors.New("receipts: file too big")
	ErrTooMany       = errors.New("receipts: too many receipts on this transaction")
	ErrNoTransaction = errors.New("receipts: transaction not found")
	ErrNotUploaded   = errors.New("receipts: file is not in storage yet")
	ErrMismatch      = errors.New("receipts: stored file differs from what was announced")
	ErrConflict      = errors.New("receipts: id already used for another file")
)

var extensions = map[string]string{"image/jpeg": "jpg", "image/png": "png"}

// Service implements receipts.
type Service struct {
	db    *pgxpool.Pool
	store storage.Store
	log   *slog.Logger
	now   func() time.Time
}

// NewService creates the service.
func NewService(db *pgxpool.Pool, store storage.Store, log *slog.Logger) *Service {
	return &Service{db: db, store: store, log: log, now: time.Now}
}

// WithClock sets the clock (tests).
func (s *Service) WithClock(now func() time.Time) *Service { s.now = now; return s }

// UploadRequest announces a file the phone wants to upload.
type UploadRequest struct {
	ID            uuid.UUID `json:"id"`
	TransactionID uuid.UUID `json:"transaction_id"`
	ContentType   string    `json:"content_type"`
	SizeBytes     int64     `json:"size_bytes"`
}

// Upload is a presigned PUT.
type Upload struct {
	ID        uuid.UUID         `json:"id"`
	URL       string            `json:"url"`
	Method    string            `json:"method"`
	Headers   map[string]string `json:"headers"`
	ExpiresAt time.Time         `json:"expires_at"`
}

// Key is where a receipt lives in the bucket. Everything of one user is
// under receipts/{user_id}/, so account deletion can remove the prefix.
func Key(userID, id uuid.UUID, contentType string) string {
	return fmt.Sprintf("receipts/%s/%s.%s", userID, id, extensions[contentType])
}

// UserPrefix is the bucket prefix of all of a user's receipts.
func UserPrefix(userID uuid.UUID) string { return fmt.Sprintf("receipts/%s/", userID) }

// UploadURL records a pending receipt and signs the upload. Asking again
// with the same id and file (e.g. after a timeout) signs a fresh URL.
func (s *Service) UploadURL(ctx context.Context, userID uuid.UUID, req UploadRequest) (Upload, error) {
	if _, ok := extensions[req.ContentType]; !ok {
		return Upload{}, ErrBadType
	}
	if req.SizeBytes < 1 || req.SizeBytes > MaxBytes {
		return Upload{}, ErrTooBig
	}
	if req.ID == uuid.Nil {
		return Upload{}, ErrNotFound
	}
	key := Key(userID, req.ID, req.ContentType)
	err := pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		// Serialise with other changes of this user (and the count below).
		if _, err := tx.Exec(ctx, `SELECT 1 FROM users WHERE id = $1 FOR UPDATE`, userID); err != nil {
			return err
		}
		var (
			owner         uuid.UUID
			ctype, status string
			size          int64
			deleted       bool
		)
		err := tx.QueryRow(ctx, `SELECT user_id, content_type, size_bytes, status, deleted_at IS NOT NULL
		                           FROM receipts WHERE id = $1`, req.ID).Scan(&owner, &ctype, &size, &status, &deleted)
		switch {
		case err == nil:
			if owner != userID || ctype != req.ContentType || size != req.SizeBytes || status != "pending" || deleted {
				return ErrConflict
			}
			return nil // same announcement again: sign a new URL
		case !errors.Is(err, pgx.ErrNoRows):
			return err
		}
		var live bool
		if err := tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM transactions
		                               WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL)`,
			req.TransactionID, userID).Scan(&live); err != nil {
			return err
		}
		if !live {
			return ErrNoTransaction
		}
		var n int
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM receipts WHERE transaction_id = $1 AND deleted_at IS NULL`,
			req.TransactionID).Scan(&n); err != nil {
			return err
		}
		if n >= MaxPerTransaction {
			return ErrTooMany
		}
		_, err = tx.Exec(ctx, `INSERT INTO receipts (id, user_id, transaction_id, object_key, content_type, size_bytes)
		                       VALUES ($1, $2, $3, $4, $5, $6)`,
			req.ID, userID, req.TransactionID, key, req.ContentType, req.SizeBytes)
		return err
	})
	if err != nil {
		return Upload{}, err
	}
	url, headers, err := s.store.PresignPut(ctx, key, req.ContentType, req.SizeBytes, UploadURLTTL)
	if err != nil {
		return Upload{}, err
	}
	return Upload{ID: req.ID, URL: url, Method: "PUT", Headers: headers, ExpiresAt: s.now().Add(UploadURLTTL).UTC()}, nil
}

// Confirm checks with R2 that the file is really there with the announced
// size and type, then marks the receipt uploaded (and syncs it).
func (s *Service) Confirm(ctx context.Context, userID, id uuid.UUID) error {
	var (
		key, ctype, status string
		size               int64
	)
	err := s.db.QueryRow(ctx, `SELECT object_key, content_type, size_bytes, status FROM receipts
	                            WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL`, id, userID).
		Scan(&key, &ctype, &size, &status)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	}
	if err != nil {
		return err
	}
	if status == "uploaded" {
		return nil // already confirmed
	}
	obj, err := s.store.Head(ctx, key)
	if errors.Is(err, storage.ErrNotFound) {
		return ErrNotUploaded
	}
	if err != nil {
		return err
	}
	if obj.Size != size || obj.ContentType != ctype {
		// Not what was signed for (should be impossible): drop the file.
		_ = s.store.Delete(ctx, key)
		return ErrMismatch
	}
	return pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		v, err := bumpVersion(ctx, tx, userID)
		if err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `UPDATE receipts SET status = 'uploaded', version = $2, updated_at = now()
		                       WHERE id = $1 AND status = 'pending' AND deleted_at IS NULL`, id, v)
		return err
	})
}

// ViewURL signs a short download link for an uploaded receipt.
func (s *Service) ViewURL(ctx context.Context, userID, id uuid.UUID) (string, time.Time, error) {
	var key string
	err := s.db.QueryRow(ctx, `SELECT object_key FROM receipts
	                            WHERE id = $1 AND user_id = $2 AND status = 'uploaded' AND deleted_at IS NULL`,
		id, userID).Scan(&key)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", time.Time{}, ErrNotFound
	}
	if err != nil {
		return "", time.Time{}, err
	}
	url, err := s.store.PresignGet(ctx, key, "", ViewURLTTL)
	return url, s.now().Add(ViewURLTTL).UTC(), err
}

// Delete removes a receipt: the row becomes a tombstone (so other phones
// drop it) and the file is deleted now, or by the nightly job if R2 fails.
func (s *Service) Delete(ctx context.Context, userID, id uuid.UUID) error {
	var key string
	err := pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		v, err := bumpVersion(ctx, tx, userID)
		if err != nil {
			return err
		}
		err = tx.QueryRow(ctx, `UPDATE receipts SET deleted_at = now(), updated_at = now(), version = $3
		                         WHERE id = $1 AND user_id = $2 AND deleted_at IS NULL
		                         RETURNING object_key`, id, userID, v).Scan(&key)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		return err
	})
	if err != nil {
		return err
	}
	if err := s.store.Delete(ctx, key); err != nil {
		s.log.WarnContext(ctx, "receipts: delete file later", "key", key, "err", err)
		return nil
	}
	_, err = s.db.Exec(ctx, `UPDATE receipts SET purged_at = now() WHERE id = $1`, id)
	return err
}

// HandleCleanup is the asynq handler for TaskCleanup.
func (s *Service) HandleCleanup(ctx context.Context, _ *asynq.Task) error {
	r, err := s.Cleanup(ctx)
	s.log.InfoContext(ctx, "receipts: clean-up", "abandoned", r.Abandoned, "orphaned", r.Orphaned, "purged", r.Purged)
	return err
}

// CleanupResult counts what the clean-up did.
type CleanupResult struct{ Abandoned, Orphaned, Purged int }

// Cleanup (1) removes uploads still pending after 24 hours, (2) deletes
// receipts whose transaction was deleted, and (3) removes the files of
// deleted receipts that are still in R2.
func (s *Service) Cleanup(ctx context.Context) (CleanupResult, error) {
	var res CleanupResult
	cutoff := s.now().Add(-PendingTTL)

	rows, err := s.db.Query(ctx, `SELECT id, object_key FROM receipts WHERE status = 'pending' AND created_at < $1`, cutoff)
	if err != nil {
		return res, err
	}
	abandoned, err := collectKeys(rows)
	if err != nil {
		return res, err
	}
	for id, key := range abandoned {
		if err := s.store.Delete(ctx, key); err != nil {
			return res, err
		}
		// Pending rows never reached a phone, so no tombstone is needed.
		if _, err := s.db.Exec(ctx, `DELETE FROM receipts WHERE id = $1 AND status = 'pending'`, id); err != nil {
			return res, err
		}
		res.Abandoned++
	}

	rows, err = s.db.Query(ctx, `
		SELECT DISTINCT r.user_id FROM receipts r JOIN transactions t ON t.id = r.transaction_id
		 WHERE r.deleted_at IS NULL AND t.deleted_at IS NOT NULL`)
	if err != nil {
		return res, err
	}
	users, err := pgx.CollectRows(rows, pgx.RowTo[uuid.UUID])
	if err != nil {
		return res, err
	}
	for _, u := range users {
		err := pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
			v, err := bumpVersion(ctx, tx, u)
			if err != nil {
				return err
			}
			tag, err := tx.Exec(ctx, `
				UPDATE receipts r SET deleted_at = now(), updated_at = now(), version = $2
				  FROM transactions t
				 WHERE t.id = r.transaction_id AND r.user_id = $1
				   AND r.deleted_at IS NULL AND t.deleted_at IS NOT NULL`, u, v)
			res.Orphaned += int(tag.RowsAffected())
			return err
		})
		if err != nil {
			return res, err
		}
	}

	rows, err = s.db.Query(ctx, `SELECT id, object_key FROM receipts WHERE deleted_at IS NOT NULL AND purged_at IS NULL`)
	if err != nil {
		return res, err
	}
	unpurged, err := collectKeys(rows)
	if err != nil {
		return res, err
	}
	for id, key := range unpurged {
		if err := s.store.Delete(ctx, key); err != nil {
			return res, err
		}
		if _, err := s.db.Exec(ctx, `UPDATE receipts SET purged_at = now() WHERE id = $1`, id); err != nil {
			return res, err
		}
		res.Purged++
	}
	return res, nil
}

func collectKeys(rows pgx.Rows) (map[uuid.UUID]string, error) {
	out := map[uuid.UUID]string{}
	var (
		id  uuid.UUID
		key string
	)
	_, err := pgx.ForEachRow(rows, []any{&id, &key}, func() error {
		out[id] = key
		return nil
	})
	return out, err
}

// bumpVersion takes the user's next sync version under the user's row lock,
// like a sync push, so a pull never skips this change.
func bumpVersion(ctx context.Context, tx pgx.Tx, userID uuid.UUID) (int64, error) {
	var v int64
	err := tx.QueryRow(ctx, `UPDATE users SET sync_version = sync_version + 1 WHERE id = $1 RETURNING sync_version`, userID).Scan(&v)
	return v, err
}
