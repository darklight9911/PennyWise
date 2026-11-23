package datasync

// Integration tests on a real PostgreSQL (TEST_DATABASE_URL, see .env.example).
// Every test creates its own users, so nothing is truncated here.

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"os"
	gosync "sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"

	"pennywise/backend/internal/recurring"
	"pennywise/backend/migrations"
)

var (
	sharedPool *pgxpool.Pool
	poolOnce   gosync.Once
	poolErr    error
)

func testService(t *testing.T) *Service {
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
		if poolErr = goose.SetDialect("postgres"); poolErr != nil {
			return
		}
		if poolErr = goose.Up(sqlDB, "."); poolErr != nil {
			return
		}
		sharedPool, poolErr = pgxpool.New(context.Background(), url)
	})
	if poolErr != nil {
		t.Fatal(poolErr)
	}
	return NewService(sharedPool, slog.New(slog.NewTextHandler(io.Discard, nil)))
}

// newUser inserts a user directly (auth is tested elsewhere).
func newUser(t *testing.T, s *Service, base string) uuid.UUID {
	t.Helper()
	var id uuid.UUID
	err := s.pool.QueryRow(context.Background(),
		`INSERT INTO users (email, password_hash, base_currency) VALUES ($1, 'x', $2) RETURNING id`,
		fmt.Sprintf("sync-%s@example.com", uuid.NewString()), base).Scan(&id)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _, _ = s.pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, id) })
	return id
}

var t0 = time.Date(2026, 11, 15, 10, 0, 0, 0, time.UTC)

func ch(entity string, id uuid.UUID, updated time.Time, data any) Change {
	raw, _ := json.Marshal(data)
	return Change{Entity: entity, ID: id, UpdatedAt: updated, Data: raw}
}

func account(name, currency string) map[string]any {
	return map[string]any{"name": name, "type": "bank", "currency": currency, "opening_balance_minor": 10000}
}

func category(name, kind string) map[string]any {
	return map[string]any{"name": name, "kind": kind}
}

func expense(acct, cat uuid.UUID, amount int64, currency string) map[string]any {
	return map[string]any{
		"account_id": acct, "category_id": cat, "kind": "expense", "amount_minor": amount,
		"currency": currency, "occurred_at": t0, "local_date": "2026-11-15", "note": "lunch",
	}
}

func push(t *testing.T, s *Service, user uuid.UUID, changes ...Change) PushResponse {
	t.Helper()
	resp, err := s.Push(context.Background(), user, PushRequest{Changes: changes})
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

func pull(t *testing.T, s *Service, user uuid.UUID, since int64) PullResponse {
	t.Helper()
	resp, err := s.Pull(context.Background(), user, since)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

func statuses(r PushResponse) map[uuid.UUID]string {
	m := map[uuid.UUID]string{}
	for _, res := range r.Results {
		m[res.ID] = res.Status
	}
	return m
}

func errCodes(r PushResponse) map[uuid.UUID]string {
	m := map[uuid.UUID]string{}
	for _, res := range r.Results {
		if res.Error != nil {
			m[res.ID] = res.Error.Code
		}
	}
	return m
}

// --- tests ---

func TestPushThenPullRoundTrip(t *testing.T) {
	s := testService(t)
	u := newUser(t, s, "USD")
	acct, cat, txn := uuid.New(), uuid.New(), uuid.New()

	// Transaction first in the list: the server must still save its account
	// and category first.
	r := push(t, s, u,
		ch(EntityTransaction, txn, t0, expense(acct, cat, 1250, "USD")),
		ch(EntityAccount, acct, t0, account("Wallet", "USD")),
		ch(EntityCategory, cat, t0, category("Food", "expense")),
	)
	for id, st := range statuses(r) {
		if st != StatusApplied {
			t.Fatalf("%s: %s %v", id, st, errCodes(r))
		}
	}
	if r.Version == 0 {
		t.Fatal("no version returned")
	}

	p := pull(t, s, u, 0)
	if len(p.Changes) != 3 || p.HasMore || p.Cursor != r.Version {
		t.Fatalf("pull = %d changes, has_more=%v, cursor=%d (want 3, false, %d)", len(p.Changes), p.HasMore, p.Cursor, r.Version)
	}
	wantOrder := []string{EntityAccount, EntityCategory, EntityTransaction}
	for i, c := range p.Changes {
		if c.Entity != wantOrder[i] {
			t.Fatalf("change %d is %s, want %s (parents first)", i, c.Entity, wantOrder[i])
		}
	}
	var got map[string]any
	_ = json.Unmarshal(p.Changes[2].Data, &got)
	if got["amount_minor"] != float64(1250) || got["local_date"] != "2026-11-15" || got["note"] != "lunch" {
		t.Fatalf("transaction data = %v", got)
	}
	// Same currency as the user's base: converted at rate 1.
	if got["amount_base_minor"] != float64(1250) || got["fx_rate_to_base"] != "1.0000000000" {
		t.Fatalf("base amount = %v / %v", got["amount_base_minor"], got["fx_rate_to_base"])
	}

	if again := pull(t, s, u, p.Cursor); len(again.Changes) != 0 {
		t.Fatalf("pull after cursor returned %d changes", len(again.Changes))
	}
}

func TestPushIsIdempotent(t *testing.T) {
	s := testService(t)
	u := newUser(t, s, "USD")
	acct := uuid.New()
	c := ch(EntityAccount, acct, t0, account("Wallet", "USD"))

	first := push(t, s, u, c)
	again := push(t, s, u, c) // e.g. retried after a timeout
	if statuses(first)[acct] != StatusApplied || statuses(again)[acct] != StatusStale {
		t.Fatalf("first=%v again=%v", statuses(first), statuses(again))
	}
	if again.Version != 0 {
		t.Fatal("a push that changed nothing must not report a version")
	}
	if p := pull(t, s, u, first.Version); len(p.Changes) != 0 {
		t.Fatal("retry created new changes to pull")
	}
}

func TestNewerEditWins(t *testing.T) {
	s := testService(t)
	u := newUser(t, s, "USD")
	acct := uuid.New()
	push(t, s, u, ch(EntityAccount, acct, t0, account("Wallet", "USD")))

	newer := push(t, s, u, ch(EntityAccount, acct, t0.Add(time.Minute), account("Cash wallet", "USD")))
	older := push(t, s, u, ch(EntityAccount, acct, t0.Add(-time.Hour), account("Old name", "USD")))
	if statuses(newer)[acct] != StatusApplied || statuses(older)[acct] != StatusStale {
		t.Fatalf("newer=%v older=%v", statuses(newer), statuses(older))
	}
	var name string
	_ = s.pool.QueryRow(context.Background(), `SELECT name FROM accounts WHERE id = $1`, acct).Scan(&name)
	if name != "Cash wallet" {
		t.Fatalf("name = %q", name)
	}
}

func TestFutureClockIsClamped(t *testing.T) {
	s := testService(t)
	now := time.Now().UTC()
	s.now = func() time.Time { return now }
	u := newUser(t, s, "USD")
	acct := uuid.New()

	push(t, s, u, ch(EntityAccount, acct, now.Add(24*time.Hour), account("Future", "USD")))
	// A normal edit a minute later must still win.
	r := push(t, s, u, ch(EntityAccount, acct, now.Add(time.Minute), account("Present", "USD")))
	if statuses(r)[acct] != StatusApplied {
		t.Fatalf("edit after a future-dated one was %v", statuses(r))
	}
}

func TestOneBadChangeDoesNotBlockOthers(t *testing.T) {
	s := testService(t)
	u := newUser(t, s, "USD")
	good, bad := uuid.New(), uuid.New()
	r := push(t, s, u,
		ch(EntityAccount, bad, t0, map[string]any{"name": "", "type": "bank", "currency": "USD"}),
		ch(EntityAccount, good, t0, account("Good", "USD")),
	)
	if statuses(r)[good] != StatusApplied || statuses(r)[bad] != StatusRejected {
		t.Fatalf("statuses = %v", statuses(r))
	}
	if r.Results[0].Error.Field != "name" {
		t.Fatalf("error = %+v", r.Results[0].Error)
	}
}

func TestUsersAreIsolated(t *testing.T) {
	s := testService(t)
	ann, bo := newUser(t, s, "USD"), newUser(t, s, "USD")
	acct, cat := uuid.New(), uuid.New()
	push(t, s, ann, ch(EntityAccount, acct, t0, account("Ann's", "USD")), ch(EntityCategory, cat, t0, category("Food", "expense")))

	// Bo tries to overwrite Ann's account with a newer edit...
	r := push(t, s, bo, ch(EntityAccount, acct, t0.Add(time.Hour), account("Hijacked", "USD")))
	if errCodes(r)[acct] != "id_taken" {
		t.Fatalf("overwrite: %v %v", statuses(r), errCodes(r))
	}
	// ...or to book an expense on it.
	txn := uuid.New()
	r = push(t, s, bo, ch(EntityTransaction, txn, t0, expense(acct, cat, 100, "USD")))
	if errCodes(r)[txn] != "reference_not_found" {
		t.Fatalf("foreign account: %v", errCodes(r))
	}
	if p := pull(t, s, bo, 0); len(p.Changes) != 0 {
		t.Fatalf("Bo can pull %d of Ann's rows", len(p.Changes))
	}
}

func TestTransactionRules(t *testing.T) {
	s := testService(t)
	u := newUser(t, s, "USD")
	usd, usd2, eur := uuid.New(), uuid.New(), uuid.New()
	food, salary := uuid.New(), uuid.New()
	push(t, s, u,
		ch(EntityAccount, usd, t0, account("USD bank", "USD")),
		ch(EntityAccount, usd2, t0, account("USD cash", "USD")),
		ch(EntityAccount, eur, t0, account("EUR bank", "EUR")),
		ch(EntityCategory, food, t0, category("Food", "expense")),
		ch(EntityCategory, salary, t0, category("Salary", "income")),
	)

	transfer := func(from, to uuid.UUID, cur string, amount, received int64) map[string]any {
		return map[string]any{
			"account_id": from, "kind": "transfer", "amount_minor": amount, "currency": cur,
			"transfer_account_id": to, "transfer_amount_minor": received,
			"occurred_at": t0, "local_date": "2026-11-15",
		}
	}
	cases := []struct {
		name     string
		data     map[string]any
		wantCode string // "" = applied
	}{
		{"valid expense", expense(usd, food, 500, "USD"), ""},
		{"currency differs from account", expense(usd, food, 500, "EUR"), "invalid"},
		{"expense in an income category", expense(usd, salary, 500, "USD"), "invalid"},
		{"unknown category", expense(usd, uuid.New(), 500, "USD"), "reference_not_found"},
		{"zero amount", expense(usd, food, 0, "USD"), "invalid"},
		{"bad date", func() map[string]any { d := expense(usd, food, 1, "USD"); d["local_date"] = "15/11/2026"; return d }(), "invalid"},
		{"unknown field", func() map[string]any { d := expense(usd, food, 1, "USD"); d["is_admin"] = true; return d }(), "invalid"},
		{"same-currency transfer", transfer(usd, usd2, "USD", 700, 700), ""},
		{"same-currency transfer, different amount", transfer(usd, usd2, "USD", 700, 650), "invalid"},
		{"cross-currency transfer", transfer(usd, eur, "USD", 1000, 920), ""},
		{"transfer to itself", transfer(usd, usd, "USD", 100, 100), "invalid"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			id := uuid.New()
			r := push(t, s, u, ch(EntityTransaction, id, t0, tc.data))
			if got := errCodes(r)[id]; got != tc.wantCode {
				t.Fatalf("code = %q, want %q (%+v)", got, tc.wantCode, r.Results[0].Error)
			}
		})
	}

	// An EUR transaction for a USD user gets no base amount until FX (Milestone 6).
	id := uuid.New()
	push(t, s, u, ch(EntityTransaction, id, t0, map[string]any{
		"account_id": eur, "category_id": food, "kind": "expense", "amount_minor": 300,
		"currency": "EUR", "occurred_at": t0, "local_date": "2026-11-15",
	}))
	var base *int64
	_ = s.pool.QueryRow(context.Background(), `SELECT amount_base_minor FROM transactions WHERE id = $1`, id).Scan(&base)
	if base != nil {
		t.Fatalf("foreign-currency base amount = %d, want empty until Milestone 6", *base)
	}
}

func TestAccountCurrencyLockedOnceUsed(t *testing.T) {
	s := testService(t)
	u := newUser(t, s, "USD")
	acct, cat := uuid.New(), uuid.New()
	push(t, s, u, ch(EntityAccount, acct, t0, account("Bank", "USD")), ch(EntityCategory, cat, t0, category("Food", "expense")))

	// No transactions yet: changing the currency is fine.
	if r := push(t, s, u, ch(EntityAccount, acct, t0.Add(time.Minute), account("Bank", "EUR"))); statuses(r)[acct] != StatusApplied {
		t.Fatalf("change before use: %v", errCodes(r))
	}
	push(t, s, u, ch(EntityTransaction, uuid.New(), t0, expense(acct, cat, 100, "EUR")))
	r := push(t, s, u, ch(EntityAccount, acct, t0.Add(2*time.Minute), account("Bank", "GBP")))
	if errCodes(r)[acct] != "currency_locked" {
		t.Fatalf("change after use: %v", errCodes(r))
	}
}

func TestCategoryParentRules(t *testing.T) {
	s := testService(t)
	u := newUser(t, s, "USD")
	food, groceries, salary := uuid.New(), uuid.New(), uuid.New()
	push(t, s, u, ch(EntityCategory, food, t0, category("Food", "expense")), ch(EntityCategory, salary, t0, category("Salary", "income")))

	sub := func(name, kind string, parent uuid.UUID) map[string]any {
		return map[string]any{"name": name, "kind": kind, "parent_id": parent}
	}
	if r := push(t, s, u, ch(EntityCategory, groceries, t0, sub("Groceries", "expense", food))); statuses(r)[groceries] != StatusApplied {
		t.Fatalf("valid child: %v", errCodes(r))
	}
	tooDeep, wrongKind := uuid.New(), uuid.New()
	r := push(t, s, u,
		ch(EntityCategory, tooDeep, t0, sub("Fruit", "expense", groceries)),
		ch(EntityCategory, wrongKind, t0, sub("Bonus", "expense", salary)),
	)
	if errCodes(r)[tooDeep] != "invalid" || errCodes(r)[wrongKind] != "invalid" {
		t.Fatalf("codes = %v", errCodes(r))
	}
}

func TestDeletesAreSynced(t *testing.T) {
	s := testService(t)
	u := newUser(t, s, "USD")
	acct := uuid.New()
	first := push(t, s, u, ch(EntityAccount, acct, t0, account("Old", "USD")))

	del := ch(EntityAccount, acct, t0.Add(time.Minute), account("Old", "USD"))
	gone := t0.Add(time.Minute)
	del.DeletedAt = &gone
	push(t, s, u, del)

	p := pull(t, s, u, first.Version)
	if len(p.Changes) != 1 || p.Changes[0].DeletedAt == nil || !p.Changes[0].DeletedAt.Equal(gone) {
		t.Fatalf("pull = %+v", p.Changes)
	}
}

func TestPullPagesNeverSplitAPush(t *testing.T) {
	s := testService(t)
	u := newUser(t, s, "USD")
	// Five pushes of 300 rows. 300 does not divide the page size (1000), so
	// a page boundary falls inside a push unless the server trims it.
	const perPush = 300
	want := map[uuid.UUID]bool{}
	for range 5 {
		batch := make([]Change, 0, perPush)
		for i := range perPush {
			id := uuid.New()
			want[id] = true
			batch = append(batch, ch(EntityAccount, id, t0, account(fmt.Sprintf("A%d", i), "USD")))
		}
		push(t, s, u, batch...)
	}

	seen := map[uuid.UUID]bool{}
	cursor, pages := int64(0), 0
	for {
		p := pull(t, s, u, cursor)
		pages++
		groups := map[int64]int{}
		for _, c := range p.Changes {
			if seen[c.ID] {
				t.Fatalf("row %s pulled twice", c.ID)
			}
			seen[c.ID] = true
			groups[c.Version]++
		}
		for v, n := range groups {
			if n != perPush {
				t.Fatalf("page %d has %d of the %d rows of version %d (split)", pages, n, perPush, v)
			}
		}
		if p.Cursor <= cursor && p.HasMore {
			t.Fatal("cursor did not advance")
		}
		cursor = p.Cursor
		if !p.HasMore {
			break
		}
	}
	if len(seen) != len(want) || pages < 2 {
		t.Fatalf("pulled %d of %d rows in %d pages", len(seen), len(want), pages)
	}
}

func TestParallelPushesGetDistinctVersions(t *testing.T) {
	s := testService(t)
	u := newUser(t, s, "USD")
	const n = 8
	var wg gosync.WaitGroup
	versions := make(chan int64, n)
	for i := range n {
		wg.Add(1)
		go func() {
			defer wg.Done()
			r, err := s.Push(context.Background(), u, PushRequest{Changes: []Change{
				ch(EntityAccount, uuid.New(), t0, account(fmt.Sprintf("P%d", i), "USD")),
			}})
			if err != nil {
				t.Error(err)
				return
			}
			versions <- r.Version
		}()
	}
	wg.Wait()
	close(versions)
	seen := map[int64]bool{}
	for v := range versions {
		if seen[v] {
			t.Fatalf("version %d used twice", v)
		}
		seen[v] = true
	}
	if p := pull(t, s, u, 0); len(p.Changes) != n {
		t.Fatalf("pulled %d of %d", len(p.Changes), n)
	}
}

func TestTooManyChanges(t *testing.T) {
	s := testService(t)
	u := newUser(t, s, "USD")
	_, err := s.Push(context.Background(), u, PushRequest{Changes: make([]Change, MaxPushChanges+1)})
	if err != ErrTooManyChanges {
		t.Fatalf("err = %v", err)
	}
}

func TestSeedDefaultCategories(t *testing.T) {
	s := testService(t)
	u := newUser(t, s, "USD")
	ctx := context.Background()
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if err := SeedDefaultCategories(ctx, tx, u); err != nil {
		t.Fatal(err)
	}
	if err := tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}

	p := pull(t, s, u, 0)
	if len(p.Changes) != len(DefaultCategories) {
		t.Fatalf("pulled %d categories, want %d", len(p.Changes), len(DefaultCategories))
	}
	kinds := map[string]int{}
	for _, c := range p.Changes {
		var d CategoryData
		if err := json.Unmarshal(c.Data, &d); err != nil {
			t.Fatal(err)
		}
		if cerr := validateCategory(&d); cerr != nil {
			t.Fatalf("default %q is invalid: %v", d.Name, cerr)
		}
		kinds[d.Kind]++
	}
	if kinds["expense"] == 0 || kinds["income"] == 0 {
		t.Fatalf("kinds = %v", kinds)
	}
	// The phone can now book an expense in a default category.
	acct := uuid.New()
	var food uuid.UUID
	for _, c := range p.Changes {
		var d CategoryData
		_ = json.Unmarshal(c.Data, &d)
		if d.Kind == "expense" {
			food = c.ID
			break
		}
	}
	txn := uuid.New()
	r := push(t, s, u, ch(EntityAccount, acct, t0, account("Cash", "USD")), ch(EntityTransaction, txn, t0, expense(acct, food, 99, "USD")))
	if statuses(r)[txn] != StatusApplied {
		t.Fatalf("expense in default category: %v", errCodes(r))
	}
}

func TestBudgetsSync(t *testing.T) {
	s := testService(t)
	u := newUser(t, s, "USD")
	food, salary := uuid.New(), uuid.New()
	push(t, s, u, ch(EntityCategory, food, t0, category("Food", "expense")), ch(EntityCategory, salary, t0, category("Salary", "income")))

	overall, foodBudget, bad1, bad2, bad3 := uuid.New(), uuid.New(), uuid.New(), uuid.New(), uuid.New()
	r := push(t, s, u,
		// Budgets first in the list: the server still saves categories first.
		ch(EntityBudget, overall, t0, map[string]any{"amount_minor": 200000, "period": "monthly"}),
		ch(EntityBudget, foodBudget, t0, map[string]any{
			"category_id": food, "amount_minor": 30000, "period": "weekly", "alert_thresholds": []int{100, 50, 100},
		}),
		ch(EntityBudget, bad1, t0, map[string]any{"category_id": salary, "amount_minor": 1, "period": "monthly"}),
		ch(EntityBudget, bad2, t0, map[string]any{"amount_minor": 1, "period": "daily"}),
		ch(EntityBudget, bad3, t0, map[string]any{"amount_minor": 1, "period": "monthly", "alert_thresholds": []int{0}}),
	)
	st, codes := statuses(r), errCodes(r)
	if st[overall] != StatusApplied || st[foodBudget] != StatusApplied {
		t.Fatalf("valid budgets: %v %v", st, codes)
	}
	for _, id := range []uuid.UUID{bad1, bad2, bad3} {
		if codes[id] != "invalid" {
			t.Errorf("budget %s: code %q, want invalid", id, codes[id])
		}
	}

	p := pull(t, s, u, 0)
	var budgets []map[string]any
	for _, c := range p.Changes {
		if c.Entity == EntityBudget {
			var d map[string]any
			_ = json.Unmarshal(c.Data, &d)
			d["id"] = c.ID.String()
			budgets = append(budgets, d)
		}
	}
	if len(budgets) != 2 {
		t.Fatalf("pulled %d budgets", len(budgets))
	}
	for _, b := range budgets {
		switch b["id"] {
		case overall.String():
			if b["category_id"] != nil || fmt.Sprint(b["alert_thresholds"]) != "[80 100]" {
				t.Errorf("overall budget = %v (want no category, default levels)", b)
			}
		case foodBudget.String():
			if fmt.Sprint(b["alert_thresholds"]) != "[50 100]" {
				t.Errorf("levels = %v, want sorted and unique [50 100]", b["alert_thresholds"])
			}
		}
	}
	if p.Changes[len(p.Changes)-1].Entity != EntityBudget {
		t.Error("budgets must come after categories in a pull")
	}
}

func TestGoalsAndContributions(t *testing.T) {
	s := testService(t)
	ann, bo := newUser(t, s, "USD"), newUser(t, s, "USD")
	goal, c1, c2 := uuid.New(), uuid.New(), uuid.New()
	r := push(t, s, ann,
		ch(EntityGoalContrib, c1, t0, map[string]any{"goal_id": goal, "amount_minor": 5000, "local_date": "2026-11-01"}),
		ch(EntityGoal, goal, t0, map[string]any{"name": " Laptop ", "target_minor": 150000, "deadline": "2027-06-30", "color": "#2c706e"}),
		ch(EntityGoalContrib, c2, t0, map[string]any{"goal_id": goal, "amount_minor": -1000, "local_date": "2026-11-05", "note": "oops"}),
	)
	for id, st := range statuses(r) {
		if st != StatusApplied {
			t.Fatalf("%s: %s %v", id, st, errCodes(r))
		}
	}
	var name, color string
	_ = s.pool.QueryRow(context.Background(), `SELECT name, color FROM goals WHERE id = $1`, goal).Scan(&name, &color)
	if name != "Laptop" || color != "#2C706E" {
		t.Fatalf("goal stored as %q %q (want trimmed name, upper-case colour)", name, color)
	}

	// Bo cannot add money to Ann's goal.
	steal := uuid.New()
	r = push(t, s, bo, ch(EntityGoalContrib, steal, t0, map[string]any{"goal_id": goal, "amount_minor": 1, "local_date": "2026-11-01"}))
	if errCodes(r)[steal] != "reference_not_found" {
		t.Fatalf("contribution to another user's goal: %v", errCodes(r))
	}
	zero := uuid.New()
	r = push(t, s, ann, ch(EntityGoalContrib, zero, t0, map[string]any{"goal_id": goal, "amount_minor": 0, "local_date": "2026-11-01"}))
	if errCodes(r)[zero] != "invalid" {
		t.Fatalf("zero contribution: %v", errCodes(r))
	}

	p := pull(t, s, ann, 0)
	order := []string{}
	for _, c := range p.Changes {
		order = append(order, c.Entity)
	}
	if fmt.Sprint(order) != "[goal goal_contribution goal_contribution]" {
		t.Fatalf("pull order = %v (goal before its contributions)", order)
	}
}

func TestRecurringRulesAndOccurrences(t *testing.T) {
	s := testService(t)
	u := newUser(t, s, "USD")
	bank, eur, rent, salary := uuid.New(), uuid.New(), uuid.New(), uuid.New()
	push(t, s, u,
		ch(EntityAccount, bank, t0, account("Bank", "USD")),
		ch(EntityAccount, eur, t0, account("Euro", "EUR")),
		ch(EntityCategory, rent, t0, category("Rent", "expense")),
		ch(EntityCategory, salary, t0, category("Salary", "income")),
	)
	rule := func(mod func(map[string]any)) map[string]any {
		d := map[string]any{
			"kind": "expense", "account_id": bank, "category_id": rent, "amount_minor": 120000,
			"currency": "USD", "frequency": "monthly", "every": 1, "start_date": "2026-01-31",
			"remind_days_before": 2, "active": true,
		}
		if mod != nil {
			mod(d)
		}
		return d
	}
	ok := uuid.New()
	bad := map[string]map[string]any{
		"currency":     rule(func(d map[string]any) { d["account_id"] = eur }),
		"category":     rule(func(d map[string]any) { d["category_id"] = salary }),
		"end":          rule(func(d map[string]any) { d["end_date"] = "2025-12-31" }),
		"frequency":    rule(func(d map[string]any) { d["frequency"] = "hourly" }),
		"remind":       rule(func(d map[string]any) { d["remind_days_before"] = 31 }),
		"transferKind": rule(func(d map[string]any) { d["kind"] = "transfer" }),
	}
	changes := []Change{ch(EntityRecurring, ok, t0, rule(nil))}
	ids := map[string]uuid.UUID{}
	for name, d := range bad {
		ids[name] = uuid.New()
		changes = append(changes, ch(EntityRecurring, ids[name], t0, d))
	}
	r := push(t, s, u, changes...)
	if statuses(r)[ok] != StatusApplied {
		t.Fatalf("valid rule: %v", errCodes(r))
	}
	for name, id := range ids {
		if statuses(r)[id] != StatusRejected {
			t.Errorf("rule %s accepted", name)
		}
	}

	occ := func(id uuid.UUID, date string, rule uuid.UUID) Change {
		return ch(EntityTransaction, id, t0, map[string]any{
			"account_id": bank, "category_id": rent, "kind": "expense", "amount_minor": 120000,
			"currency": "USD", "occurred_at": t0, "local_date": date,
			"recurring_id": rule, "occurrence_date": date,
		})
	}
	feb := time.Date(2026, 2, 28, 0, 0, 0, 0, time.UTC)
	good := recurring.OccurrenceID(ok, feb)
	wrong, unknownRule := uuid.New(), uuid.New()
	r = push(t, s, u,
		occ(good, "2026-02-28", ok),
		occ(wrong, "2026-03-31", ok),
		occ(recurring.OccurrenceID(unknownRule, feb), "2026-02-28", unknownRule),
	)
	if statuses(r)[good] != StatusApplied {
		t.Fatalf("occurrence with the right id: %v", errCodes(r))
	}
	if errCodes(r)[wrong] != "invalid" {
		t.Fatalf("occurrence with a random id: %v", errCodes(r))
	}
	if errCodes(r)[recurring.OccurrenceID(unknownRule, feb)] != "reference_not_found" {
		t.Fatalf("occurrence of an unknown rule: %v", errCodes(r))
	}

	// The server's worker and the phone create the same occurrence: one row.
	again := push(t, s, u, occ(good, "2026-02-28", ok))
	if statuses(again)[good] != StatusStale {
		t.Fatalf("second copy of the occurrence: %v", statuses(again))
	}
	var n int
	_ = s.pool.QueryRow(context.Background(), `SELECT count(*) FROM transactions WHERE recurring_id = $1`, ok).Scan(&n)
	if n != 1 {
		t.Fatalf("%d occurrence rows, want 1", n)
	}

	p := pull(t, s, u, 0)
	for _, c := range p.Changes {
		if c.ID == good {
			var d map[string]any
			_ = json.Unmarshal(c.Data, &d)
			if d["recurring_id"] != ok.String() || d["occurrence_date"] != "2026-02-28" {
				t.Fatalf("pulled occurrence = %v", d)
			}
		}
	}
}

func TestDuesAndLoanPayments(t *testing.T) {
	s := testService(t)
	ann, bo := newUser(t, s, "USD"), newUser(t, s, "USD")
	bank, eur, rent, salary := uuid.New(), uuid.New(), uuid.New(), uuid.New()
	push(t, s, ann,
		ch(EntityAccount, bank, t0, account("Bank", "USD")),
		ch(EntityAccount, eur, t0, account("Euro", "EUR")),
		ch(EntityCategory, rent, t0, category("Rent", "expense")),
		ch(EntityCategory, salary, t0, category("Salary", "income")),
	)
	due := func(mod func(map[string]any)) map[string]any {
		d := map[string]any{
			"direction": "owed_to_me", "kind": "loan", "person": " Sam ", "amount_minor": 50000,
			"currency": "USD", "account_id": bank, "category_id": nil, "start_date": "2026-11-01",
			"due_date": "2026-12-01", "remind_days_before": 0, "note": "", "closed_at": nil,
		}
		if mod != nil {
			mod(d)
		}
		return d
	}
	loanPay := func(kind string, dueID any) map[string]any {
		return map[string]any{
			"account_id": bank, "kind": kind, "amount_minor": 20000, "currency": "USD",
			"occurred_at": t0, "local_date": "2026-11-15", "due_id": dueID,
		}
	}

	// A loan and its first payment in one push, child sent first: the
	// server applies the due before the transaction.
	loan, lent := uuid.New(), uuid.New()
	r := push(t, s, ann,
		ch(EntityTransaction, lent, t0, loanPay("loan_out", loan)),
		ch(EntityDue, loan, t0, due(nil)),
	)
	for id, st := range statuses(r) {
		if st != StatusApplied {
			t.Fatalf("%s: %s %v", id, st, r.Results)
		}
	}
	if r.Results[0].Entity != EntityDue {
		t.Fatalf("results order = %v, want the due first", r.Results)
	}

	bill := uuid.New()
	bad := map[string]map[string]any{
		"direction":        due(func(d map[string]any) { d["direction"] = "maybe" }),
		"kind":             due(func(d map[string]any) { d["kind"] = "gift" }),
		"empty person":     due(func(d map[string]any) { d["person"] = "  " }),
		"zero amount":      due(func(d map[string]any) { d["amount_minor"] = 0 }),
		"account currency": due(func(d map[string]any) { d["account_id"] = eur }),
		"loan category":    due(func(d map[string]any) { d["category_id"] = rent }),
		"bill wrong kind":  due(func(d map[string]any) { d["kind"] = "bill"; d["category_id"] = rent }),
		"remind 31":        due(func(d map[string]any) { d["remind_days_before"] = 31 }),
		"bad due date":     due(func(d map[string]any) { d["due_date"] = "1/12/2026" }),
		"long note":        due(func(d map[string]any) { d["note"] = string(make([]byte, 501)) }),
	}
	changes := []Change{ch(EntityDue, bill, t0, due(func(d map[string]any) {
		d["direction"], d["kind"], d["category_id"], d["remind_days_before"] = "i_owe", "bill", rent, nil
	}))}
	ids := map[string]uuid.UUID{}
	for name, d := range bad {
		ids[name] = uuid.New()
		changes = append(changes, ch(EntityDue, ids[name], t0, d))
	}
	r = push(t, s, ann, changes...)
	if statuses(r)[bill] != StatusApplied {
		t.Fatalf("valid bill: %v", r.Results)
	}
	for name, id := range ids {
		if statuses(r)[id] != StatusRejected {
			t.Errorf("due %s accepted", name)
		}
	}

	// Transactions that point at dues.
	billPay := expense(bank, rent, 30000, "USD")
	billPay["due_id"] = bill
	cases := []struct {
		name     string
		data     map[string]any
		wantCode string
	}{
		{"repayment received", loanPay("loan_in", loan), ""},
		{"bill payment", billPay, ""},
		{"loan without due", loanPay("loan_in", nil), "invalid"},
		{"loan with category", func() map[string]any { d := loanPay("loan_in", loan); d["category_id"] = salary; return d }(), "invalid"},
		{"loan with transfer", func() map[string]any {
			d := loanPay("loan_out", loan)
			d["transfer_account_id"], d["transfer_amount_minor"] = eur, 100
			return d
		}(), "invalid"},
		{"unknown due", loanPay("loan_in", uuid.New()), "reference_not_found"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			id := uuid.New()
			r := push(t, s, ann, ch(EntityTransaction, id, t0, tc.data))
			if got := errCodes(r)[id]; got != tc.wantCode {
				t.Fatalf("code = %q, want %q (%+v)", got, tc.wantCode, r.Results[0].Error)
			}
		})
	}

	// Bo cannot see or pay into Ann's due, nor overwrite it.
	boBank := uuid.New()
	push(t, s, bo, ch(EntityAccount, boBank, t0, account("Bank", "USD")))
	steal := uuid.New()
	pay := loanPay("loan_in", loan)
	pay["account_id"] = boBank
	r = push(t, s, bo, ch(EntityTransaction, steal, t0, pay), ch(EntityDue, loan, t0.Add(time.Hour), due(func(d map[string]any) { d["account_id"] = nil })))
	if errCodes(r)[steal] != "reference_not_found" || errCodes(r)[loan] != "id_taken" {
		t.Fatalf("Bo's push: %v", errCodes(r))
	}

	// Forgive the rest: closed_at round-trips.
	closed := time.Date(2026, 11, 20, 8, 30, 0, 0, time.UTC)
	r = push(t, s, ann, ch(EntityDue, loan, t0.Add(time.Hour), due(func(d map[string]any) { d["closed_at"] = closed })))
	if statuses(r)[loan] != StatusApplied {
		t.Fatalf("close loan: %v", r.Results)
	}

	p := pull(t, s, ann, 0)
	for _, c := range p.Changes {
		var d map[string]any
		_ = json.Unmarshal(c.Data, &d)
		switch c.ID {
		case loan:
			at, err := time.Parse(time.RFC3339, fmt.Sprint(d["closed_at"]))
			if d["person"] != "Sam" || d["due_date"] != "2026-12-01" || d["remind_days_before"] != 0.0 ||
				d["category_id"] != nil || err != nil || !at.Equal(closed) {
				t.Fatalf("pulled loan = %v", d)
			}
		case bill:
			if d["remind_days_before"] != nil || d["category_id"] != rent.String() || d["closed_at"] != nil {
				t.Fatalf("pulled bill = %v", d)
			}
		case lent:
			if d["kind"] != "loan_out" || d["due_id"] != loan.String() || d["category_id"] != nil {
				t.Fatalf("pulled loan payment = %v", d)
			}
		}
	}
	// Within one push, a due is pulled before its payment.
	due2, pay2 := uuid.New(), uuid.New()
	r = push(t, s, ann, ch(EntityTransaction, pay2, t0, loanPay("loan_in", due2)), ch(EntityDue, due2, t0, due(nil)))
	p = pull(t, s, ann, r.Version-1)
	got := []string{}
	for _, c := range p.Changes {
		got = append(got, c.Entity)
	}
	if fmt.Sprint(got) != "[due transaction]" {
		t.Fatalf("pull order = %v (due before its payments)", got)
	}

	// Deleting the user removes dues and loan payments together.
	if _, err := s.pool.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, ann); err != nil {
		t.Fatalf("delete user with dues: %v", err)
	}
}
