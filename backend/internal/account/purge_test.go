package account_test

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"

	"pennywise/backend/internal/account"
	"pennywise/backend/internal/datasync"
	"pennywise/backend/internal/exports"
	"pennywise/backend/internal/receipts"
	"pennywise/backend/internal/storage"
	"pennywise/backend/internal/testdb"
)

var quiet = slog.New(slog.NewTextHandler(io.Discard, nil))

type fakeQueue struct{ tasks []*asynq.Task }

func (q *fakeQueue) EnqueueContext(_ context.Context, t *asynq.Task, _ ...asynq.Option) (*asynq.TaskInfo, error) {
	q.tasks = append(q.tasks, t)
	return &asynq.TaskInfo{}, nil
}

func TestPurgeErasesRowsAndFiles(t *testing.T) {
	p := testdb.Pool(t)
	ctx := context.Background()
	gone, kept := testdb.NewUser(t, p, "USD"), testdb.NewUser(t, p, "USD")
	sync := datasync.NewService(p, quiet)
	raw, _ := json.Marshal(map[string]any{"name": "Bank", "type": "bank", "currency": "USD"})
	for _, u := range []uuid.UUID{gone, kept} {
		if _, err := sync.Push(ctx, u, datasync.PushRequest{Changes: []datasync.Change{
			{Entity: datasync.EntityAccount, ID: uuid.New(), UpdatedAt: time.Now(), Data: raw}}}); err != nil {
			t.Fatal(err)
		}
	}
	store := storage.NewMemory()
	for _, u := range []uuid.UUID{gone, kept} {
		store.PutFile(receipts.Key(u, uuid.New(), "image/jpeg"), "image/jpeg", []byte("x"))
		store.PutFile(exports.UserPrefix(u)+"e.csv", "text/csv", []byte("x"))
	}
	q := &fakeQueue{}
	purger := account.NewPurger(p, store, q, quiet)

	// A live account is never erased, even if asked.
	if err := purger.Purge(ctx, kept); err != nil {
		t.Fatal(err)
	}
	if len(store.Keys(receipts.UserPrefix(kept))) != 1 {
		t.Fatal("files of a live account were deleted")
	}

	if _, err := p.Exec(ctx, `UPDATE users SET deleted_at = now() WHERE id = $1`, gone); err != nil {
		t.Fatal(err)
	}
	if err := account.EnqueuePurge(q)(ctx, nil, gone); err != nil {
		t.Fatal(err)
	}
	if err := purger.HandlePurge(ctx, q.tasks[0]); err != nil {
		t.Fatal(err)
	}
	var users, accounts int
	_ = p.QueryRow(ctx, `SELECT count(*) FROM users WHERE id = $1`, gone).Scan(&users)
	_ = p.QueryRow(ctx, `SELECT count(*) FROM accounts WHERE user_id = $1`, gone).Scan(&accounts)
	if users != 0 || accounts != 0 {
		t.Errorf("rows left: users %d accounts %d", users, accounts)
	}
	if left := append(store.Keys(receipts.UserPrefix(gone)), store.Keys(exports.UserPrefix(gone))...); len(left) != 0 {
		t.Errorf("files left: %v", left)
	}
	if len(store.Keys(receipts.UserPrefix(kept))) != 1 || len(store.Keys(exports.UserPrefix(kept))) != 1 {
		t.Error("another user's files were deleted")
	}
	if len(q.tasks) != 2 {
		t.Fatalf("second pass not queued: %d tasks", len(q.tasks))
	}
	if err := purger.HandlePurge(ctx, q.tasks[1]); err != nil || len(q.tasks) != 2 {
		t.Errorf("second pass: %v, tasks %d", err, len(q.tasks))
	}
}

func TestSweepCatchesMissedAccounts(t *testing.T) {
	p := testdb.Pool(t)
	ctx := context.Background()
	old, recent := testdb.NewUser(t, p, "USD"), testdb.NewUser(t, p, "USD")
	_, _ = p.Exec(ctx, `UPDATE users SET deleted_at = now() - interval '2 days' WHERE id = $1`, old)
	_, _ = p.Exec(ctx, `UPDATE users SET deleted_at = now() WHERE id = $1`, recent)
	if err := account.NewPurger(p, nil, &fakeQueue{}, quiet).HandleSweep(ctx, nil); err != nil {
		t.Fatal(err)
	}
	var n int
	_ = p.QueryRow(ctx, `SELECT count(*) FROM users WHERE id = ANY($1)`, []uuid.UUID{old, recent}).Scan(&n)
	if n != 1 {
		t.Errorf("users left %d, want 1 (the recent one waits for its own job)", n)
	}
}
