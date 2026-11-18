package exports_test

// Integration tests on PostgreSQL (TEST_DATABASE_URL) with an in-memory
// bucket and a fake job queue.

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"

	"pennywise/backend/internal/datasync"
	"pennywise/backend/internal/exports"
	"pennywise/backend/internal/reports"
	"pennywise/backend/internal/storage"
	"pennywise/backend/internal/testdb"
)

var quiet = slog.New(slog.NewTextHandler(io.Discard, nil))

type fakeQueue struct{ tasks []*asynq.Task }

func (q *fakeQueue) EnqueueContext(_ context.Context, t *asynq.Task, _ ...asynq.Option) (*asynq.TaskInfo, error) {
	q.tasks = append(q.tasks, t)
	return &asynq.TaskInfo{}, nil
}

func push(t *testing.T, s *datasync.Service, user uuid.UUID, at time.Time, entity string, id uuid.UUID, data map[string]any) {
	t.Helper()
	raw, _ := json.Marshal(data)
	r, err := s.Push(context.Background(), user, datasync.PushRequest{Changes: []datasync.Change{
		{Entity: entity, ID: id, UpdatedAt: at, Data: raw}}})
	if err != nil || r.Results[0].Status != datasync.StatusApplied {
		t.Fatalf("push %s: %v %+v", entity, err, r)
	}
}

func TestCreateBuildDownloadCleanup(t *testing.T) {
	p := testdb.Pool(t)
	ctx := context.Background()
	user := testdb.NewUser(t, p, "USD")
	sync := datasync.NewService(p, quiet)
	at := time.Now().Add(-time.Hour)
	acct, cat := uuid.New(), uuid.New()
	push(t, sync, user, at, datasync.EntityAccount, acct, map[string]any{"name": "Bank", "type": "bank", "currency": "USD"})
	push(t, sync, user, at.Add(time.Second), datasync.EntityCategory, cat, map[string]any{"name": "Food", "kind": "expense"})
	push(t, sync, user, at.Add(2*time.Second), datasync.EntityTransaction, uuid.New(), map[string]any{
		"account_id": acct, "category_id": cat, "kind": "expense", "amount_minor": 1234, "currency": "USD",
		"occurred_at": "2026-02-02T12:00:00Z", "local_date": "2026-02-02", "note": "lunch"})

	store, q := storage.NewMemory(), &fakeQueue{}
	svc := exports.NewService(p, store, q, quiet)
	rg, _ := reports.ParseRange("2026-01-01", "2026-03-31")

	if _, err := svc.Create(ctx, user, "xlsx", rg); err != exports.ErrBadFormat {
		t.Errorf("bad format: %v", err)
	}
	csvExp, err := svc.Create(ctx, user, "csv", rg)
	if err != nil || csvExp.Status != "pending" || csvExp.DownloadURL != "" || len(q.tasks) != 1 {
		t.Fatalf("create: %+v %v", csvExp, err)
	}
	if csvExp.FileName != "pennywise-2026-01-01-to-2026-03-31.csv" {
		t.Errorf("file name %s", csvExp.FileName)
	}
	pdfExp, _ := svc.Create(ctx, user, "pdf", rg)
	svc.Create(ctx, user, "csv", rg)
	if _, err := svc.Create(ctx, user, "csv", rg); err != exports.ErrTooMany {
		t.Errorf("fourth running export: %v", err)
	}

	for _, task := range q.tasks[:2] {
		if err := svc.HandleBuild(ctx, task); err != nil {
			t.Fatal(err)
		}
	}
	got, err := svc.Get(ctx, user, csvExp.ID)
	if err != nil || got.Status != "ready" || !strings.HasPrefix(got.DownloadURL, "memory://get/exports/"+user.String()+"/") {
		t.Fatalf("after build: %+v %v", got, err)
	}
	body := store.Body("exports/" + user.String() + "/" + csvExp.ID.String() + ".csv")
	if !bytes.Contains(body, []byte("2026-02-02,expense,Bank,Food,lunch,-12.34,USD,-12.34,1,auto")) {
		t.Errorf("csv body:\n%s", body)
	}
	pdf := store.Body("exports/" + user.String() + "/" + pdfExp.ID.String() + ".pdf")
	if !bytes.HasPrefix(pdf, []byte("%PDF-")) {
		t.Errorf("pdf body starts %q", pdf[:min(len(pdf), 10)])
	}

	// Another user cannot see it.
	if _, err := svc.Get(ctx, testdb.NewUser(t, p, "USD"), csvExp.ID); err != exports.ErrNotFound {
		t.Errorf("other user: %v", err)
	}

	// After 8 days the files are gone.
	later := exports.NewService(p, store, q, quiet).WithClock(func() time.Time { return time.Now().Add(8 * 24 * time.Hour) })
	if e, _ := later.Get(ctx, user, csvExp.ID); e.Status != "expired" || e.DownloadURL != "" {
		t.Errorf("expired: %+v", e)
	}
	n, err := later.Cleanup(ctx)
	if err != nil || n != 3 { // two expired files, one never built
		t.Errorf("cleanup: %d %v", n, err)
	}
	if keys := store.Keys(exports.UserPrefix(user)); len(keys) != 0 {
		t.Errorf("files left: %v", keys)
	}
}
