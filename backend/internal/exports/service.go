// Package exports builds CSV and PDF files of a user's transactions in a
// background job and hands them out through short-lived R2 links.
package exports

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"pennywise/backend/internal/reports"
	"pennywise/backend/internal/storage"
)

// Tasks.
const (
	TaskBuild   = "exports:build"
	TaskCleanup = "exports:cleanup"
)

// Timings.
const (
	KeepFor     = 7 * 24 * time.Hour // a finished file is deleted after this
	LinkTTL     = 10 * time.Minute
	MaxRunning  = 3 // pending exports per user
	pendingDead = 24 * time.Hour
)

// Errors.
var (
	ErrNotFound  = errors.New("exports: not found")
	ErrBadFormat = errors.New("exports: format must be csv or pdf")
	ErrTooMany   = errors.New("exports: too many exports running")
	ErrTooLarge  = errors.New("exports: too many transactions for one file")
	ErrNotReady  = errors.New("exports: not ready")
)

// Export is the public view of an export.
type Export struct {
	ID          uuid.UUID  `json:"id"`
	Format      string     `json:"format"`
	From        string     `json:"from"`
	To          string     `json:"to"`
	Status      string     `json:"status"`
	Error       string     `json:"error,omitempty"`
	SizeBytes   *int64     `json:"size_bytes,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
	ExpiresAt   *time.Time `json:"expires_at,omitempty"`
	DownloadURL string     `json:"download_url,omitempty"`
	FileName    string     `json:"file_name"`
}

// Queue is the part of asynq.Client used here.
type Queue interface {
	EnqueueContext(ctx context.Context, task *asynq.Task, opts ...asynq.Option) (*asynq.TaskInfo, error)
}

// Service implements exports.
type Service struct {
	db    *pgxpool.Pool
	store storage.Store
	queue Queue
	log   *slog.Logger
	now   func() time.Time
}

// NewService creates the service. queue may be nil in the worker.
func NewService(db *pgxpool.Pool, store storage.Store, queue Queue, log *slog.Logger) *Service {
	return &Service{db: db, store: store, queue: queue, log: log, now: time.Now}
}

// WithClock sets the clock (tests).
func (s *Service) WithClock(now func() time.Time) *Service { s.now = now; return s }

type buildPayload struct {
	ExportID uuid.UUID `json:"export_id"`
}

// Create records an export and queues the job that builds it.
func (s *Service) Create(ctx context.Context, userID uuid.UUID, format string, r reports.Range) (Export, error) {
	if format != "csv" && format != "pdf" {
		return Export{}, ErrBadFormat
	}
	var id uuid.UUID
	err := pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, `SELECT 1 FROM users WHERE id = $1 FOR UPDATE`, userID); err != nil {
			return err
		}
		var running int
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM exports WHERE user_id = $1 AND status = 'pending'`, userID).Scan(&running); err != nil {
			return err
		}
		if running >= MaxRunning {
			return ErrTooMany
		}
		return tx.QueryRow(ctx, `INSERT INTO exports (user_id, format, from_date, to_date) VALUES ($1, $2, $3, $4) RETURNING id`,
			userID, format, r.From, r.To).Scan(&id)
	})
	if err != nil {
		return Export{}, err
	}
	payload, _ := json.Marshal(buildPayload{ExportID: id})
	if _, err := s.queue.EnqueueContext(ctx, asynq.NewTask(TaskBuild, payload),
		asynq.MaxRetry(3), asynq.Timeout(5*time.Minute)); err != nil {
		_, _ = s.db.Exec(ctx, `UPDATE exports SET status = 'failed', error = 'could not start' WHERE id = $1`, id)
		return Export{}, err
	}
	return s.Get(ctx, userID, id)
}

// Get returns the export, with a fresh download link when it is ready.
func (s *Service) Get(ctx context.Context, userID, id uuid.UUID) (Export, error) {
	var (
		e        Export
		from, to time.Time
		key      *string
	)
	err := s.db.QueryRow(ctx, `
		SELECT id, format, from_date, to_date, status, error, size_bytes, created_at, expires_at, object_key
		  FROM exports WHERE id = $1 AND user_id = $2`, id, userID).
		Scan(&e.ID, &e.Format, &from, &to, &e.Status, &e.Error, &e.SizeBytes, &e.CreatedAt, &e.ExpiresAt, &key)
	if errors.Is(err, pgx.ErrNoRows) {
		return Export{}, ErrNotFound
	}
	if err != nil {
		return Export{}, err
	}
	e.From, e.To = from.Format(time.DateOnly), to.Format(time.DateOnly)
	e.FileName = fmt.Sprintf("pennywise-%s-to-%s.%s", e.From, e.To, e.Format)
	if e.ExpiresAt != nil && !e.ExpiresAt.After(s.now()) {
		e.Status = "expired"
		return e, nil
	}
	if e.Status == "ready" && key != nil {
		if e.DownloadURL, err = s.store.PresignGet(ctx, *key, e.FileName, LinkTTL); err != nil {
			return Export{}, err
		}
	}
	return e, nil
}

// HandleBuild is the asynq handler for TaskBuild.
func (s *Service) HandleBuild(ctx context.Context, t *asynq.Task) error {
	var p buildPayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("exports: payload: %w: %w", err, asynq.SkipRetry)
	}
	err := s.Build(ctx, p.ExportID)
	if err == nil {
		return nil
	}
	retried, _ := asynq.GetRetryCount(ctx)
	maxRetry, ok := asynq.GetMaxRetry(ctx)
	if errors.Is(err, ErrTooLarge) || !ok || retried >= maxRetry {
		msg := "something went wrong, please try again"
		if errors.Is(err, ErrTooLarge) {
			msg = "too many transactions for one file; choose a shorter period"
		}
		_, _ = s.db.Exec(ctx, `UPDATE exports SET status = 'failed', error = $2, finished_at = now() WHERE id = $1 AND status = 'pending'`, p.ExportID, msg)
		s.log.WarnContext(ctx, "export failed", "export", p.ExportID, "err", err)
		return fmt.Errorf("%w: %w", err, asynq.SkipRetry)
	}
	return err
}

// Build makes the file and stores it.
func (s *Service) Build(ctx context.Context, id uuid.UUID) error {
	var (
		userID       uuid.UUID
		format, base string
		status       string
		from, to     time.Time
	)
	err := s.db.QueryRow(ctx, `
		SELECT e.user_id, e.format, e.from_date, e.to_date, e.status, u.base_currency
		  FROM exports e JOIN users u ON u.id = e.user_id WHERE e.id = $1`, id).
		Scan(&userID, &format, &from, &to, &status, &base)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil // deleted meanwhile (account deleted)
	}
	if err != nil || status != "pending" {
		return err
	}
	rg := reports.Range{From: from, To: to}

	var (
		body  []byte
		ctype string
	)
	switch format {
	case "csv":
		list, err := loadRows(ctx, s.db, userID, rg, MaxCSVRows)
		if err != nil {
			return err
		}
		if body, err = buildCSV(list, base); err != nil {
			return err
		}
		ctype = "text/csv; charset=utf-8"
	default:
		list, err := loadRows(ctx, s.db, userID, rg, MaxPDFRows)
		if err != nil {
			return err
		}
		rep := reports.NewService(s.db)
		sum, err := rep.Summary(ctx, userID, rg)
		if err != nil {
			return err
		}
		cats, err := rep.ByCategory(ctx, userID, rg, "expense")
		if err != nil {
			return err
		}
		body = buildPDF(statement{Range: rg, Base: base, Generated: s.now(), Summary: sum, ByCat: cats, Rows: list})
		ctype = "application/pdf"
	}

	key := fmt.Sprintf("%s%s.%s", UserPrefix(userID), id, format)
	if err := s.store.Put(ctx, key, ctype, body); err != nil {
		return err
	}
	_, err = s.db.Exec(ctx, `
		UPDATE exports SET status = 'ready', object_key = $2, size_bytes = $3,
		       finished_at = now(), expires_at = $4 WHERE id = $1`,
		id, key, len(body), s.now().Add(KeepFor))
	return err
}

// UserPrefix is the bucket prefix of all of a user's exports.
func UserPrefix(userID uuid.UUID) string { return fmt.Sprintf("exports/%s/", userID) }

// HandleCleanup is the asynq handler for TaskCleanup.
func (s *Service) HandleCleanup(ctx context.Context, _ *asynq.Task) error {
	n, err := s.Cleanup(ctx)
	s.log.InfoContext(ctx, "exports: clean-up", "removed", n)
	return err
}

// Cleanup removes expired files and old failed or stuck exports.
func (s *Service) Cleanup(ctx context.Context) (int, error) {
	rows, err := s.db.Query(ctx, `
		SELECT id, object_key FROM exports
		 WHERE expires_at <= $1 OR (status <> 'ready' AND created_at < $2)`,
		s.now(), s.now().Add(-pendingDead))
	if err != nil {
		return 0, err
	}
	type item struct {
		id  uuid.UUID
		key *string
	}
	list, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (item, error) {
		var x item
		return x, r.Scan(&x.id, &x.key)
	})
	if err != nil {
		return 0, err
	}
	for _, x := range list {
		if x.key != nil {
			if err := s.store.Delete(ctx, *x.key); err != nil {
				return 0, err
			}
		}
		if _, err := s.db.Exec(ctx, `DELETE FROM exports WHERE id = $1`, x.id); err != nil {
			return 0, err
		}
	}
	return len(list), nil
}
