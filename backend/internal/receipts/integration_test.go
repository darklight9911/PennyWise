package receipts_test

// Integration tests on PostgreSQL (TEST_DATABASE_URL) with an in-memory
// bucket in place of R2.

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"pennywise/backend/internal/datasync"
	"pennywise/backend/internal/ratelimit"
	"pennywise/backend/internal/receipts"
	"pennywise/backend/internal/storage"
	"pennywise/backend/internal/testdb"
)

var quiet = slog.New(slog.NewTextHandler(io.Discard, nil))

type allowAll struct{}

func (allowAll) Allow(context.Context, ratelimit.Rule, string) (bool, time.Duration, error) {
	return true, 0, nil
}

type userKey struct{}

type fixture struct {
	t     *testing.T
	sync  *datasync.Service
	svc   *receipts.Service
	store *storage.Memory
	srv   *httptest.Server
	user  uuid.UUID
	tx    uuid.UUID
	at    time.Time
}

func newFixture(t *testing.T) *fixture {
	p := testdb.Pool(t)
	f := &fixture{t: t, sync: datasync.NewService(p, quiet), store: storage.NewMemory(),
		user: testdb.NewUser(t, p, "USD"), at: time.Now().Add(-time.Hour)}
	f.svc = receipts.NewService(p, f.store, quiet)
	auth := func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			id, err := uuid.Parse(r.Header.Get("X-User"))
			if err != nil {
				w.WriteHeader(http.StatusUnauthorized)
				return
			}
			next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), userKey{}, id)))
		})
	}
	r := chi.NewRouter()
	receipts.NewHandler(f.svc, allowAll{}, auth,
		func(r *http.Request) uuid.UUID { return r.Context().Value(userKey{}).(uuid.UUID) }, quiet).Routes(r)
	f.srv = httptest.NewServer(r)
	t.Cleanup(f.srv.Close)

	acct, cat := uuid.New(), uuid.New()
	f.push(datasync.EntityAccount, acct, map[string]any{"name": "Cash", "type": "cash", "currency": "USD"}, nil)
	f.push(datasync.EntityCategory, cat, map[string]any{"name": "Food", "kind": "expense"}, nil)
	f.tx = uuid.New()
	f.push(datasync.EntityTransaction, f.tx, f.txData(acct, cat), nil)
	return f
}

func (f *fixture) txData(acct, cat uuid.UUID) map[string]any {
	return map[string]any{"account_id": acct, "category_id": cat, "kind": "expense", "amount_minor": 500,
		"currency": "USD", "occurred_at": "2026-11-01T10:00:00Z", "local_date": "2026-11-01", "note": ""}
}

func (f *fixture) push(entity string, id uuid.UUID, data map[string]any, deleted *time.Time) {
	f.t.Helper()
	raw, _ := json.Marshal(data)
	f.at = f.at.Add(time.Second)
	res, err := f.sync.Push(context.Background(), f.user, datasync.PushRequest{Changes: []datasync.Change{
		{Entity: entity, ID: id, UpdatedAt: f.at, DeletedAt: deleted, Data: raw},
	}})
	if err != nil || res.Results[0].Status != datasync.StatusApplied {
		f.t.Fatalf("push %s: %v %+v", entity, err, res)
	}
}

func (f *fixture) call(method, path string, body any) (int, map[string]any) {
	f.t.Helper()
	var r io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		r = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(method, f.srv.URL+path, r)
	req.Header.Set("X-User", f.user.String())
	req.Header.Set("Content-Type", "application/json")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		f.t.Fatal(err)
	}
	defer res.Body.Close()
	var out map[string]any
	_ = json.NewDecoder(res.Body).Decode(&out)
	return res.StatusCode, out
}

func (f *fixture) announce(id uuid.UUID, size int) (int, map[string]any) {
	return f.call(http.MethodPost, "/receipts/upload-url", map[string]any{
		"id": id, "transaction_id": f.tx, "content_type": "image/jpeg", "size_bytes": size})
}

func errCode(body map[string]any) any {
	e, _ := body["error"].(map[string]any)
	return e["code"]
}

func TestUploadConfirmViewDelete(t *testing.T) {
	f := newFixture(t)
	id := uuid.New()
	key := receipts.Key(f.user, id, "image/jpeg")

	code, up := f.announce(id, 4)
	if code != http.StatusOK || up["method"] != "PUT" {
		t.Fatalf("upload-url: %d %v", code, up)
	}
	if h := up["headers"].(map[string]any); h["Content-Length"] != "4" || h["Content-Type"] != "image/jpeg" {
		t.Errorf("headers %v", h)
	}
	// Asking again for the same file is fine (e.g. after a timeout).
	if code, _ := f.announce(id, 4); code != http.StatusOK {
		t.Errorf("same announcement again: %d", code)
	}
	if code, body := f.announce(id, 5); code != http.StatusConflict || errCode(body) != "id_conflict" {
		t.Errorf("same id, other size: %d %v", code, body)
	}

	// Confirm before the file arrived: refused.
	if code, body := f.call(http.MethodPost, "/receipts/"+id.String()+"/confirm", nil); code != http.StatusConflict || errCode(body) != "not_uploaded" {
		t.Errorf("confirm too early: %d %v", code, body)
	}
	if code, _ := f.call(http.MethodGet, "/receipts/"+id.String()+"/url", nil); code != http.StatusNotFound {
		t.Errorf("view before confirm: %d", code)
	}
	// Not in the pull while pending.
	before, _ := f.sync.Pull(context.Background(), f.user, 0)
	for _, c := range before.Changes {
		if c.Entity == datasync.EntityReceipt {
			t.Error("pending receipt in pull")
		}
	}

	f.store.PutFile(key, "image/jpeg", []byte("jpeg"))
	if code, _ := f.call(http.MethodPost, "/receipts/"+id.String()+"/confirm", nil); code != http.StatusNoContent {
		t.Fatalf("confirm: %d", code)
	}
	if code, _ := f.call(http.MethodPost, "/receipts/"+id.String()+"/confirm", nil); code != http.StatusNoContent {
		t.Errorf("confirm twice: %d", code)
	}
	code, view := f.call(http.MethodGet, "/receipts/"+id.String()+"/url", nil)
	if code != http.StatusOK || view["url"] == "" {
		t.Errorf("view: %d %v", code, view)
	}
	pull, _ := f.sync.Pull(context.Background(), f.user, before.Cursor)
	if len(pull.Changes) != 1 || pull.Changes[0].Entity != datasync.EntityReceipt || pull.Changes[0].ID != id {
		t.Fatalf("pull after confirm: %+v", pull.Changes)
	}

	if code, _ := f.call(http.MethodDelete, "/receipts/"+id.String(), nil); code != http.StatusNoContent {
		t.Fatalf("delete: %d", code)
	}
	if f.store.Has(key) {
		t.Error("file still in the bucket after delete")
	}
	tomb, _ := f.sync.Pull(context.Background(), f.user, pull.Cursor)
	if len(tomb.Changes) != 1 || tomb.Changes[0].DeletedAt == nil {
		t.Errorf("tombstone: %+v", tomb.Changes)
	}
	if code, _ := f.call(http.MethodDelete, "/receipts/"+id.String(), nil); code != http.StatusNotFound {
		t.Errorf("delete twice: %d", code)
	}
}

func TestUploadLimits(t *testing.T) {
	f := newFixture(t)
	for _, c := range []struct {
		body map[string]any
		code string
	}{
		{map[string]any{"id": uuid.New(), "transaction_id": f.tx, "content_type": "image/gif", "size_bytes": 10}, "bad_type"},
		{map[string]any{"id": uuid.New(), "transaction_id": f.tx, "content_type": "image/png", "size_bytes": receipts.MaxBytes + 1}, "too_big"},
		{map[string]any{"id": uuid.New(), "transaction_id": f.tx, "content_type": "image/png", "size_bytes": 0}, "too_big"},
		{map[string]any{"id": uuid.New(), "transaction_id": uuid.New(), "content_type": "image/png", "size_bytes": 10}, "transaction_not_synced"},
	} {
		if _, body := f.call(http.MethodPost, "/receipts/upload-url", c.body); errCode(body) != c.code {
			t.Errorf("%v: got %v, want %s", c.body, body, c.code)
		}
	}
	for i := 0; i < receipts.MaxPerTransaction; i++ {
		if code, _ := f.announce(uuid.New(), 10); code != http.StatusOK {
			t.Fatalf("receipt %d: %d", i+1, code)
		}
	}
	if code, body := f.announce(uuid.New(), 10); code != http.StatusConflict || errCode(body) != "too_many" {
		t.Errorf("fourth receipt: %d %v", code, body)
	}

	// Another user cannot touch them.
	other := testdb.NewUser(t, testdb.Pool(t), "USD")
	req, _ := http.NewRequest(http.MethodPost, f.srv.URL+"/receipts/upload-url",
		bytes.NewReader([]byte(`{"id":"`+uuid.NewString()+`","transaction_id":"`+f.tx.String()+`","content_type":"image/png","size_bytes":10}`)))
	req.Header.Set("X-User", other.String())
	res, _ := http.DefaultClient.Do(req)
	res.Body.Close()
	if res.StatusCode != http.StatusConflict {
		t.Errorf("other user's transaction: %d", res.StatusCode)
	}
}

func TestCleanup(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()

	abandoned := uuid.New()
	f.announce(abandoned, 4)
	f.store.PutFile(receipts.Key(f.user, abandoned, "image/jpeg"), "image/jpeg", []byte("half"))

	kept := uuid.New()
	f.announce(kept, 4)
	f.store.PutFile(receipts.Key(f.user, kept, "image/jpeg"), "image/jpeg", []byte("jpeg"))
	if err := f.svc.Confirm(ctx, f.user, kept); err != nil {
		t.Fatal(err)
	}

	// Nothing is old enough yet.
	if r, err := f.svc.Cleanup(ctx); err != nil || r.Abandoned != 0 {
		t.Fatalf("too early: %+v %v", r, err)
	}
	later := receipts.NewService(testdb.Pool(t), f.store, quiet).WithClock(func() time.Time { return time.Now().Add(25 * time.Hour) })
	r, err := later.Cleanup(ctx)
	if err != nil || r.Abandoned != 1 {
		t.Fatalf("abandoned: %+v %v", r, err)
	}
	if f.store.Has(receipts.Key(f.user, abandoned, "image/jpeg")) || !f.store.Has(receipts.Key(f.user, kept, "image/jpeg")) {
		t.Errorf("bucket after clean-up: %v", f.store.Keys(""))
	}

	// Deleting the transaction (through sync) removes its receipts too.
	var acct, cat uuid.UUID
	_ = testdb.Pool(t).QueryRow(ctx, `SELECT account_id, category_id FROM transactions WHERE id = $1`, f.tx).Scan(&acct, &cat)
	now := time.Now()
	f.push(datasync.EntityTransaction, f.tx, f.txData(acct, cat), &now)
	r, err = f.svc.Cleanup(ctx)
	if err != nil || r.Orphaned != 1 || r.Purged != 1 {
		t.Fatalf("orphaned: %+v %v", r, err)
	}
	if len(f.store.Keys(receipts.UserPrefix(f.user))) != 0 {
		t.Errorf("files left: %v", f.store.Keys(""))
	}
}

func TestUnavailableWithoutStorage(t *testing.T) {
	r := chi.NewRouter()
	receipts.NewHandler(nil, allowAll{}, func(h http.Handler) http.Handler { return h },
		func(*http.Request) uuid.UUID { return uuid.Nil }, quiet).Routes(r)
	rec := httptest.NewRecorder()
	r.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/receipts/upload-url", nil))
	if rec.Code != http.StatusServiceUnavailable {
		t.Errorf("no R2: %d", rec.Code)
	}
}
