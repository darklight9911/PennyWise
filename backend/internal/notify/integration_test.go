package notify

// Integration tests on a real PostgreSQL (TEST_DATABASE_URL). Data is
// created through the real sync API, as the phone would.

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	gosync "sync"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"

	"pennywise/backend/internal/datasync"
	"pennywise/backend/migrations"
)

var (
	poolOnce   gosync.Once
	sharedPool *pgxpool.Pool
	poolErr    error
)

func testPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set")
	}
	poolOnce.Do(func() {
		sqlDB, err := sql.Open("pgx", url)
		if err != nil {
			poolErr = err
			return
		}
		defer sqlDB.Close()
		goose.SetBaseFS(migrations.FS)
		goose.SetLogger(goose.NopLogger())
		if poolErr = goose.SetDialect("postgres"); poolErr == nil {
			poolErr = goose.Up(sqlDB, ".")
		}
		if poolErr == nil {
			sharedPool, poolErr = pgxpool.New(context.Background(), url)
		}
	})
	if poolErr != nil {
		t.Fatal(poolErr)
	}
	return sharedPool
}

var quiet = slog.New(slog.NewTextHandler(io.Discard, nil))

type captured struct {
	mu   gosync.Mutex
	msgs []struct {
		token string
		m     Message
	}
}

func (c *captured) Send(_ context.Context, token string, m Message) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.msgs = append(c.msgs, struct {
		token string
		m     Message
	}{token, m})
	return nil
}

type world struct {
	t       *testing.T
	pool    *pgxpool.Pool
	sync    *datasync.Service
	user    uuid.UUID
	account uuid.UUID
	clock   time.Time
}

func newWorld(t *testing.T, tz string) *world {
	t.Helper()
	pool := testPool(t)
	w := &world{t: t, pool: pool, sync: datasync.NewService(pool, quiet)}
	err := pool.QueryRow(context.Background(),
		`INSERT INTO users (email, password_hash, base_currency, timezone) VALUES ($1, 'x', 'USD', $2) RETURNING id`,
		fmt.Sprintf("notify-%s@example.com", uuid.NewString()), tz).Scan(&w.user)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _, _ = pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, w.user) })
	w.clock = time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC)
	w.account = uuid.New()
	w.push(datasync.EntityAccount, w.account, map[string]any{"name": "Bank", "type": "bank", "currency": "USD"})
	return w
}

func (w *world) push(entity string, id uuid.UUID, data map[string]any) {
	w.t.Helper()
	raw, _ := json.Marshal(data)
	w.clock = w.clock.Add(time.Second)
	resp, err := w.sync.Push(context.Background(), w.user, datasync.PushRequest{Changes: []datasync.Change{
		{Entity: entity, ID: id, UpdatedAt: w.clock, Data: raw},
	}})
	if err != nil {
		w.t.Fatal(err)
	}
	if r := resp.Results[0]; r.Status != datasync.StatusApplied {
		w.t.Fatalf("%s %s: %s %+v", entity, id, r.Status, r.Error)
	}
}

func (w *world) category(name string, parent *uuid.UUID) uuid.UUID {
	id := uuid.New()
	d := map[string]any{"name": name, "kind": "expense"}
	if parent != nil {
		d["parent_id"] = *parent
	}
	w.push(datasync.EntityCategory, id, d)
	return id
}

func (w *world) spend(cat uuid.UUID, amount int64, localDate string) uuid.UUID {
	id := uuid.New()
	w.push(datasync.EntityTransaction, id, map[string]any{
		"account_id": w.account, "category_id": cat, "kind": "expense", "amount_minor": amount,
		"currency": "USD", "occurred_at": w.clock, "local_date": localDate,
	})
	return id
}

func (w *world) budget(cat *uuid.UUID, amount int64, period string) uuid.UUID {
	id := uuid.New()
	d := map[string]any{"amount_minor": amount, "period": period}
	if cat != nil {
		d["category_id"] = *cat
	}
	w.push(datasync.EntityBudget, id, d)
	return id
}

func checker(pool *pgxpool.Pool, sender Sender, now time.Time) *BudgetChecker {
	b := NewBudgetChecker(pool, sender, quiet)
	b.now = func() time.Time { return now }
	return b
}

func levels(alerts []Alert) []int32 {
	out := []int32{}
	for _, a := range alerts {
		out = append(out, a.Threshold)
	}
	return out
}

// --- tests ---

func TestPeriodStart(t *testing.T) {
	day := func(s string) time.Time { d, _ := time.Parse(time.DateOnly, s); return d }
	cases := []struct{ period, today, want string }{
		{"monthly", "2026-11-18", "2026-11-01"},
		{"monthly", "2026-11-01", "2026-11-01"},
		{"weekly", "2026-11-18", "2026-11-16"}, // Wednesday -> Monday
		{"weekly", "2026-11-16", "2026-11-16"}, // Monday
		{"weekly", "2026-11-22", "2026-11-16"}, // Sunday belongs to the week before
	}
	for _, c := range cases {
		if got := PeriodStart(c.period, day(c.today)).Format(time.DateOnly); got != c.want {
			t.Errorf("%s %s: got %s, want %s", c.period, c.today, got, c.want)
		}
	}
	if got := PeriodEnd("monthly", day("2026-12-01")).Format(time.DateOnly); got != "2027-01-01" {
		t.Errorf("month end over a year: %s", got)
	}
}

func TestAlertsFireOncePerLevelAndPeriod(t *testing.T) {
	w := newWorld(t, "UTC")
	food := w.category("Food", nil)
	w.budget(&food, 10000, "monthly") // 100.00, alerts at 80 % and 100 %
	if _, err := w.pool.Exec(context.Background(),
		`INSERT INTO devices (user_id, push_token, platform) VALUES ($1, $2, 'android')`,
		w.user, "token-"+uuid.NewString()); err != nil {
		t.Fatal(err)
	}
	sender := &captured{}
	c := checker(w.pool, sender, time.Date(2026, 11, 18, 12, 0, 0, 0, time.UTC))
	ctx := context.Background()

	w.spend(food, 7900, "2026-11-10")
	if a, _ := c.Check(ctx, w.user); len(a) != 0 {
		t.Fatalf("79 %%: alerts %v", levels(a))
	}
	w.spend(food, 100, "2026-11-11") // exactly 80 %
	a, err := c.Check(ctx, w.user)
	if err != nil || fmt.Sprint(levels(a)) != "[80]" {
		t.Fatalf("80 %%: %v %v", levels(a), err)
	}
	if again, _ := c.Check(ctx, w.user); len(again) != 0 {
		t.Fatal("80 % alert sent twice")
	}
	w.spend(food, 2500, "2026-11-12") // 105 %
	if a, _ := c.Check(ctx, w.user); fmt.Sprint(levels(a)) != "[100]" {
		t.Fatalf("105 %%: %v", levels(a))
	}

	if len(sender.msgs) != 2 {
		t.Fatalf("sent %d pushes, want 2", len(sender.msgs))
	}
	if got := sender.msgs[1].m.Title; got != "Food: budget reached" {
		t.Errorf("title = %q", got)
	}
	if got := sender.msgs[0].m.Body; got != "You have spent 80.00 of 100.00 USD this month." {
		t.Errorf("body = %q", got)
	}

	// Next month starts fresh.
	next := checker(w.pool, sender, time.Date(2026, 12, 2, 12, 0, 0, 0, time.UTC))
	w.spend(food, 9000, "2026-12-01")
	if a, _ := next.Check(ctx, w.user); fmt.Sprint(levels(a)) != "[80]" {
		t.Fatalf("new month: %v", levels(a))
	}
}

func TestWhatCountsTowardsABudget(t *testing.T) {
	w := newWorld(t, "UTC")
	food := w.category("Food", nil)
	snacks := w.category("Snacks", &food)
	fun := w.category("Fun", nil)
	w.budget(&food, 10000, "monthly")
	ctx := context.Background()
	c := checker(w.pool, &captured{}, time.Date(2026, 11, 18, 12, 0, 0, 0, time.UTC))

	w.spend(snacks, 4000, "2026-11-05")                      // sub-category: counts
	w.spend(fun, 9000, "2026-11-05")                         // other category: not counted
	w.spend(food, 9000, "2026-10-31")                        // last month: not counted
	gone := w.spend(food, 9000, "2026-11-06")                // deleted below: not counted
	w.push(datasync.EntityTransaction, gone, map[string]any{ // soft delete
		"account_id": w.account, "category_id": food, "kind": "expense", "amount_minor": 9000,
		"currency": "USD", "occurred_at": w.clock, "local_date": "2026-11-06",
	})
	_, _ = w.pool.Exec(ctx, `UPDATE transactions SET deleted_at = now() WHERE id = $1`, gone)

	if a, _ := c.Check(ctx, w.user); len(a) != 0 {
		t.Fatalf("40 %% counted wrongly: %v", levels(a))
	}
	w.spend(food, 4000, "2026-11-07") // now 80 %
	if a, _ := c.Check(ctx, w.user); fmt.Sprint(levels(a)) != "[80]" {
		t.Fatalf("children + own: %v", levels(a))
	}

	overall := newWorld(t, "UTC")
	any1 := overall.category("A", nil)
	any2 := overall.category("B", nil)
	overall.budget(nil, 10000, "monthly")
	overall.spend(any1, 5000, "2026-11-01")
	overall.spend(any2, 5000, "2026-11-02")
	if a, _ := checker(overall.pool, &captured{}, time.Date(2026, 11, 3, 0, 0, 0, 0, time.UTC)).Check(ctx, overall.user); fmt.Sprint(levels(a)) != "[80 100]" {
		t.Fatalf("overall budget: %v", levels(a))
	}
}

func TestWeeklyBudgetUsesTheUsersTimeZone(t *testing.T) {
	// 2026-11-15 23:30 in New York is already Monday 2026-11-16 in UTC.
	// The user's week has not started yet.
	w := newWorld(t, "America/New_York")
	food := w.category("Food", nil)
	w.budget(&food, 10000, "weekly")
	w.spend(food, 9000, "2026-11-15")                     // Sunday, previous week
	now := time.Date(2026, 11, 16, 4, 30, 0, 0, time.UTC) // Sun 23:30 in NY
	if a, _ := checker(w.pool, &captured{}, now).Check(context.Background(), w.user); fmt.Sprint(levels(a)) != "[80]" {
		t.Fatalf("still Sunday for the user, so the week of 9-15 Nov counts: %v", levels(a))
	}
	later := time.Date(2026, 11, 17, 12, 0, 0, 0, time.UTC) // Tuesday
	if a, _ := checker(w.pool, &captured{}, later).Check(context.Background(), w.user); len(a) != 0 {
		t.Fatalf("new week: %v", levels(a))
	}
}

func TestDevicesEndpoint(t *testing.T) {
	pool := testPool(t)
	ann, bo := newWorld(t, "UTC").user, newWorld(t, "UTC").user
	h := NewDevicesHandler(pool,
		func(next http.Handler) http.Handler { return next },
		func(r *http.Request) uuid.UUID { return uuid.MustParse(r.Header.Get("X-User")) },
		quiet)
	r := chi.NewRouter()
	h.Routes(r)
	call := func(method string, user uuid.UUID, body map[string]string) int {
		b, _ := json.Marshal(body)
		req := httptest.NewRequest(method, "/devices", bytes.NewReader(b))
		req.Header.Set("X-User", user.String())
		rec := httptest.NewRecorder()
		r.ServeHTTP(rec, req)
		return rec.Code
	}
	owner := func(token string) uuid.UUID {
		var u uuid.UUID
		_ = pool.QueryRow(context.Background(), `SELECT user_id FROM devices WHERE push_token = $1`, token).Scan(&u)
		return u
	}
	token := "tok-" + uuid.NewString()

	if code := call(http.MethodPost, ann, map[string]string{"push_token": token, "platform": "android"}); code != http.StatusNoContent {
		t.Fatalf("register: %d", code)
	}
	if code := call(http.MethodPost, ann, map[string]string{"push_token": token, "platform": "web"}); code != http.StatusUnprocessableEntity {
		t.Fatalf("bad platform: %d", code)
	}
	// Bo logs in on the same phone: the token moves to Bo.
	call(http.MethodPost, bo, map[string]string{"push_token": token, "platform": "android"})
	if owner(token) != bo {
		t.Fatal("token was not re-assigned to the new user")
	}
	// Ann cannot remove Bo's token.
	call(http.MethodDelete, ann, map[string]string{"push_token": token})
	if owner(token) != bo {
		t.Fatal("another user removed the token")
	}
	call(http.MethodDelete, bo, map[string]string{"push_token": token})
	if owner(token) != uuid.Nil {
		t.Fatal("token not removed")
	}
}

func TestPushHookRunsOnlyWhenSomethingWasSaved(t *testing.T) {
	w := newWorld(t, "UTC")
	var calls int
	w.sync.OnApplied = func(context.Context, uuid.UUID) error { calls++; return nil }
	acct := uuid.New()
	w.push(datasync.EntityAccount, acct, map[string]any{"name": "X", "type": "cash", "currency": "USD"})
	raw, _ := json.Marshal(map[string]any{"name": "X", "type": "cash", "currency": "USD"})
	_, _ = w.sync.Push(context.Background(), w.user, datasync.PushRequest{Changes: []datasync.Change{
		{Entity: datasync.EntityAccount, ID: acct, UpdatedAt: w.clock, Data: raw}, // same edit again: stale
	}})
	if calls != 1 {
		t.Fatalf("hook ran %d times, want 1 (not for a push that saved nothing)", calls)
	}
}
