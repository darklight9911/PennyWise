// Package account erases deleted accounts: every row (by cascade from the
// users row) and every file in R2 under the user's prefixes.
package account

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"time"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"pennywise/backend/internal/exports"
	"pennywise/backend/internal/receipts"
	"pennywise/backend/internal/storage"
)

// Tasks.
const (
	// TaskPurge erases one deleted account.
	TaskPurge = "account:purge"
	// TaskSweep erases any deleted account a lost TaskPurge missed.
	TaskSweep = "account:sweep"
)

// A second pass deletes files a job still running at deletion time may
// have written after the first pass.
const secondPassAfter = time.Hour

type purgePayload struct {
	UserID     uuid.UUID `json:"user_id"`
	SecondPass bool      `json:"second_pass,omitempty"`
}

// Queue is the part of asynq.Client used here.
type Queue interface {
	EnqueueContext(ctx context.Context, task *asynq.Task, opts ...asynq.Option) (*asynq.TaskInfo, error)
}

// EnqueuePurge queues the erase job for a just-deleted account. It fits
// auth.Config.OnAccountDeleted.
func EnqueuePurge(queue Queue) func(ctx context.Context, _ pgx.Tx, userID uuid.UUID) error {
	return func(ctx context.Context, _ pgx.Tx, userID uuid.UUID) error {
		payload, _ := json.Marshal(purgePayload{UserID: userID})
		_, err := queue.EnqueueContext(ctx, asynq.NewTask(TaskPurge, payload),
			asynq.MaxRetry(25), asynq.Timeout(30*time.Minute), asynq.Queue("critical"))
		return err
	}
}

// Purger erases accounts. store may be nil (no R2 configured).
type Purger struct {
	db    *pgxpool.Pool
	store storage.Store
	queue Queue
	log   *slog.Logger
	now   func() time.Time
}

// NewPurger creates the purger.
func NewPurger(db *pgxpool.Pool, store storage.Store, queue Queue, log *slog.Logger) *Purger {
	return &Purger{db: db, store: store, queue: queue, log: log, now: time.Now}
}

// HandlePurge is the asynq handler for TaskPurge.
func (p *Purger) HandlePurge(ctx context.Context, t *asynq.Task) error {
	var in purgePayload
	if err := json.Unmarshal(t.Payload(), &in); err != nil {
		return fmt.Errorf("account: payload: %w: %w", err, asynq.SkipRetry)
	}
	if err := p.Purge(ctx, in.UserID); err != nil {
		return err
	}
	if !in.SecondPass && p.store != nil {
		payload, _ := json.Marshal(purgePayload{UserID: in.UserID, SecondPass: true})
		_, err := p.queue.EnqueueContext(ctx, asynq.NewTask(TaskPurge, payload),
			asynq.ProcessIn(secondPassAfter), asynq.MaxRetry(25))
		return err
	}
	return nil
}

// Purge erases a deleted account's rows, then its files. A live account is
// never touched.
func (p *Purger) Purge(ctx context.Context, userID uuid.UUID) error {
	if _, err := p.db.Exec(ctx, `DELETE FROM users WHERE id = $1 AND deleted_at IS NOT NULL`, userID); err != nil {
		return fmt.Errorf("account: delete rows: %w", err)
	}
	var live bool
	if err := p.db.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM users WHERE id = $1)`, userID).Scan(&live); err != nil {
		return err
	}
	if live || p.store == nil {
		return nil
	}
	for _, prefix := range []string{receipts.UserPrefix(userID), exports.UserPrefix(userID)} {
		n, err := p.store.DeletePrefix(ctx, prefix)
		if err != nil {
			return fmt.Errorf("account: delete files: %w", err)
		}
		if n > 0 {
			p.log.InfoContext(ctx, "account: files deleted", "prefix", prefix, "count", n)
		}
	}
	return nil
}

// HandleSweep is the asynq handler for TaskSweep: accounts deleted more
// than a day ago that still have rows are erased now.
func (p *Purger) HandleSweep(ctx context.Context, _ *asynq.Task) error {
	rows, err := p.db.Query(ctx, `SELECT id FROM users WHERE deleted_at < $1`, p.now().Add(-24*time.Hour))
	if err != nil {
		return err
	}
	ids, err := pgx.CollectRows(rows, pgx.RowTo[uuid.UUID])
	if err != nil {
		return err
	}
	for _, id := range ids {
		if err := p.Purge(ctx, id); err != nil {
			return err
		}
	}
	if len(ids) > 0 {
		p.log.WarnContext(ctx, "account: sweep erased accounts a purge job missed", "count", len(ids))
	}
	return nil
}
