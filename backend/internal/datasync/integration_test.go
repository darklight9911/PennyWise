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
