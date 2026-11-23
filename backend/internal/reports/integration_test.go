package reports_test

// Integration tests on PostgreSQL (TEST_DATABASE_URL) and, for the cache,
// Redis (TEST_REDIS_URL). Data goes in through the real sync push.

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	goredis "github.com/redis/go-redis/v9"

	"pennywise/backend/internal/datasync"
	"pennywise/backend/internal/reports"
	"pennywise/backend/internal/testdb"
)

var quiet = slog.New(slog.NewTextHandler(io.Discard, nil))

type fixture struct {
	t            *testing.T
	sync         *datasync.Service
	user         uuid.UUID
	usd, xtz     uuid.UUID
	food, cafe   uuid.UUID
	rent, salary uuid.UUID
	at           time.Time
}

func newFixture(t *testing.T) *fixture {
	p := testdb.Pool(t)
	f := &fixture{t: t, sync: datasync.NewService(p, quiet), user: testdb.NewUser(t, p, "USD"), at: time.Now().Add(-time.Hour)}
	f.usd, f.xtz = uuid.New(), uuid.New()
	f.food, f.cafe, f.rent, f.salary = uuid.New(), uuid.New(), uuid.New(), uuid.New()
	f.push(datasync.EntityAccount, f.usd, map[string]any{"name": "Bank", "type": "bank", "currency": "USD"})
	f.push(datasync.EntityAccount, f.xtz, map[string]any{"name": "Odd", "type": "cash", "currency": "XTZ"}) // no rate
	f.push(datasync.EntityCategory, f.food, map[string]any{"name": "Food", "kind": "expense"})
	f.push(datasync.EntityCategory, f.cafe, map[string]any{"name": "Cafe", "kind": "expense", "parent_id": f.food})
	f.push(datasync.EntityCategory, f.rent, map[string]any{"name": "Rent", "kind": "expense"})
	f.push(datasync.EntityCategory, f.salary, map[string]any{"name": "Salary", "kind": "income"})

	f.tx(f.usd, f.salary, "income", 300000, "USD", "2026-01-31")
	f.tx(f.usd, f.rent, "expense", 120000, "USD", "2026-01-05")
	f.tx(f.usd, f.food, "expense", 2000, "USD", "2026-01-06")
	f.tx(f.usd, f.cafe, "expense", 500, "USD", "2026-01-07")
	f.tx(f.usd, f.cafe, "expense", 700, "USD", "2026-03-02")
	f.tx(f.xtz, f.food, "expense", 999, "XTZ", "2026-01-08")   // missing rate
	f.tx(f.usd, f.food, "expense", 50000, "USD", "2025-12-31") // outside
	gone := f.tx(f.usd, f.food, "expense", 7777, "USD", "2026-01-09")
	f.delete(gone, f.usd, f.food, "expense", 7777, "USD", "2026-01-09")
	// A transfer is neither income nor spending.
	other := uuid.New()
	f.push(datasync.EntityAccount, other, map[string]any{"name": "Savings", "type": "savings", "currency": "USD"})
	f.push(datasync.EntityTransaction, uuid.New(), map[string]any{
		"account_id": f.usd, "kind": "transfer", "amount_minor": 10000, "currency": "USD",
		"transfer_account_id": other, "transfer_amount_minor": 10000,
		"occurred_at": "2026-01-10T10:00:00Z", "local_date": "2026-01-10", "note": ""})
	// Loans move money but are neither income nor spending either.
	loan := uuid.New()
	f.push(datasync.EntityDue, loan, map[string]any{
		"direction": "owed_to_me", "kind": "loan", "person": "Sam", "amount_minor": 40000,
		"currency": "USD", "start_date": "2026-01-11"})
	for _, kind := range []string{"loan_out", "loan_in"} {
		f.push(datasync.EntityTransaction, uuid.New(), map[string]any{
			"account_id": f.usd, "kind": kind, "amount_minor": 40000, "currency": "USD", "due_id": loan,
			"occurred_at": "2026-01-11T10:00:00Z", "local_date": "2026-01-11", "note": ""})
	}
	return f
}

func (f *fixture) push(entity string, id uuid.UUID, data map[string]any) {
	f.pushAt(entity, id, data, nil)
}

func (f *fixture) pushAt(entity string, id uuid.UUID, data map[string]any, deleted *time.Time) {
	f.t.Helper()
	raw, _ := json.Marshal(data)
	f.at = f.at.Add(time.Second)
	r, err := f.sync.Push(context.Background(), f.user, datasync.PushRequest{Changes: []datasync.Change{
		{Entity: entity, ID: id, UpdatedAt: f.at, DeletedAt: deleted, Data: raw}}})
	if err != nil || r.Results[0].Status != datasync.StatusApplied {
		f.t.Fatalf("push %s: %v %+v", entity, err, r)
	}
}

func txData(acct, cat uuid.UUID, kind string, amount int64, cur, day string) map[string]any {
	return map[string]any{"account_id": acct, "category_id": cat, "kind": kind, "amount_minor": amount,
		"currency": cur, "occurred_at": day + "T12:00:00Z", "local_date": day, "note": ""}
}

func (f *fixture) tx(acct, cat uuid.UUID, kind string, amount int64, cur, day string) uuid.UUID {
	id := uuid.New()
	f.push(datasync.EntityTransaction, id, txData(acct, cat, kind, amount, cur, day))
	return id
}

func (f *fixture) delete(id, acct, cat uuid.UUID, kind string, amount int64, cur, day string) {
	now := time.Now()
	f.pushAt(datasync.EntityTransaction, id, txData(acct, cat, kind, amount, cur, day), &now)
}

func rng(t *testing.T, from, to string) reports.Range {
	r, err := reports.ParseRange(from, to)
	if err != nil {
		t.Fatal(err)
	}
	return r
}

func TestSummaryAndCategories(t *testing.T) {
	f := newFixture(t)
	svc := reports.NewService(testdb.Pool(t))
	ctx := context.Background()

	s, err := svc.Summary(ctx, f.user, rng(t, "2026-01-01", "2026-03-31"))
	if err != nil {
		t.Fatal(err)
	}
	want := reports.Summary{Currency: "USD", Status: "ok", IncomeMinor: 300000, ExpenseMinor: 123200,
		NetMinor: 176800, Count: 5, MissingRate: 1}
	if s != want {
		t.Errorf("summary\n got %+v\nwant %+v", s, want)
	}

	c, err := svc.ByCategory(ctx, f.user, rng(t, "2026-01-01", "2026-03-31"), "expense")
	if err != nil {
		t.Fatal(err)
	}
	if c.TotalMinor != 123200 || len(c.Categories) != 2 {
		t.Fatalf("by category: %+v", c)
	}
	rent, food := c.Categories[0], c.Categories[1]
	if rent.Name != "Rent" || rent.TotalMinor != 120000 {
		t.Errorf("first: %+v", rent)
	}
	if food.Name != "Food" || food.TotalMinor != 3200 || food.Count != 3 ||
		len(food.Children) != 1 || food.Children[0].Name != "Cafe" || food.Children[0].TotalMinor != 1200 {
		t.Errorf("food with cafe: %+v", food)
	}

	// Only sub-category spending: the parent still gets its name.
	only, _ := svc.ByCategory(ctx, f.user, rng(t, "2026-03-01", "2026-03-31"), "expense")
	if len(only.Categories) != 1 || only.Categories[0].Name != "Food" || only.Categories[0].TotalMinor != 700 {
		t.Errorf("March: %+v", only)
	}
}

func TestTrend(t *testing.T) {
	f := newFixture(t)
	svc := reports.NewService(testdb.Pool(t))
	ctx := context.Background()

	m, err := svc.Trend(ctx, f.user, rng(t, "2026-01-15", "2026-03-10"), "month")
	if err != nil {
		t.Fatal(err)
	}
	got := []reports.Bucket{}
	got = append(got, m.Buckets...)
	want := []reports.Bucket{
		{Start: "2026-01-01", IncomeMinor: 300000, NetMinor: 300000}, // only from the 15th
		{Start: "2026-02-01"},
		{Start: "2026-03-01", ExpenseMinor: 700, NetMinor: -700},
	}
	if len(got) != len(want) {
		t.Fatalf("months %+v", got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("month %d: %+v, want %+v", i, got[i], want[i])
		}
	}

	// 2026-01-05 is a Monday; the 4th (Sunday) belongs to the week before.
	w, err := svc.Trend(ctx, f.user, rng(t, "2026-01-04", "2026-01-11"), "week")
	if err != nil {
		t.Fatal(err)
	}
	if len(w.Buckets) != 2 || w.Buckets[0].Start != "2025-12-29" || w.Buckets[1].Start != "2026-01-05" ||
		w.Buckets[1].ExpenseMinor != 122500 {
		t.Errorf("weeks %+v", w.Buckets)
	}

	if _, err := svc.Trend(ctx, f.user, rng(t, "2020-01-01", "2024-12-31"), "day"); err == nil {
		t.Error("five years of days: want an error")
	}
	if _, err := svc.Trend(ctx, f.user, rng(t, "2026-01-01", "2026-01-31"), "hour"); err == nil {
		t.Error("unknown interval: want an error")
	}
}

func TestParseRange(t *testing.T) {
	for _, bad := range [][2]string{{"", ""}, {"2026-02-01", "2026-01-01"}, {"2020-01-01", "2026-01-01"}, {"2026-1-1", "2026-01-02"}} {
		if _, err := reports.ParseRange(bad[0], bad[1]); err == nil {
			t.Errorf("%v accepted", bad)
		}
	}
}

func TestHandlerCachesUntilDataChanges(t *testing.T) {
	url := os.Getenv("TEST_REDIS_URL")
	if url == "" {
		t.Skip("TEST_REDIS_URL not set")
	}
	opts, _ := goredis.ParseURL(url)
	rdb := goredis.NewClient(opts)
	t.Cleanup(func() { rdb.Close() })

	f := newFixture(t)
	r := chi.NewRouter()
	reports.NewHandler(testdb.Pool(t), rdb, func(h http.Handler) http.Handler { return h },
		func(*http.Request) uuid.UUID { return f.user }, quiet).Routes(r)
	get := func(path string) (*httptest.ResponseRecorder, reports.Summary) {
		rec := httptest.NewRecorder()
		r.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
		var s reports.Summary
		_ = json.Unmarshal(rec.Body.Bytes(), &s)
		return rec, s
	}
	const path = "/reports/summary?from=2026-01-01&to=2026-01-31"
	first, s1 := get(path)
	second, s2 := get(path)
	if first.Code != 200 || first.Header().Get("X-Cache") != "" || second.Header().Get("X-Cache") != "hit" || s1 != s2 {
		t.Fatalf("cache: %d %q %q", first.Code, first.Header().Get("X-Cache"), second.Header().Get("X-Cache"))
	}
	f.tx(f.usd, f.food, "expense", 100, "USD", "2026-01-20")
	third, s3 := get(path)
	if third.Header().Get("X-Cache") == "hit" || s3.ExpenseMinor != s1.ExpenseMinor+100 {
		t.Errorf("after a push: cache %q, expense %d -> %d", third.Header().Get("X-Cache"), s1.ExpenseMinor, s3.ExpenseMinor)
	}
	if rec, _ := get("/reports/summary?from=2026-02-01&to=2026-01-01"); rec.Code != http.StatusBadRequest {
		t.Errorf("bad range: %d", rec.Code)
	}
	if rec, _ := get("/reports/by-category?from=2026-01-01&to=2026-01-31&kind=transfer"); rec.Code != http.StatusBadRequest {
		t.Errorf("bad kind: %d", rec.Code)
	}
}
