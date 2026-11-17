package recurring_test

// Integration tests on PostgreSQL (TEST_DATABASE_URL). Rules and accounts
// are created through the real sync API, as the phone would.

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

	"pennywise/backend/internal/datasync"
	"pennywise/backend/internal/recurring"
	"pennywise/backend/migrations"
)

var (
	once  gosync.Once
	pool  *pgxpool.Pool
	dbErr error
	quiet = slog.New(slog.NewTextHandler(io.Discard, nil))
)

func testPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL not set")
	}
	once.Do(func() {
		sqlDB, err := sql.Open("pgx", url)
		if err != nil {
			dbErr = err
			return
		}
		defer sqlDB.Close()
		goose.SetBaseFS(migrations.FS)
		goose.SetLogger(goose.NopLogger())
		if dbErr = goose.SetDialect("postgres"); dbErr == nil {
			dbErr = goose.Up(sqlDB, ".")
		}
		if dbErr == nil {
			pool, dbErr = pgxpool.New(context.Background(), url)
		}
	})
	if dbErr != nil {
		t.Fatal(dbErr)
	}
	return pool
}

type fixture struct {
	t        *testing.T
	pool     *pgxpool.Pool
	sync     *datasync.Service
	user     uuid.UUID
	acct     uuid.UUID
	rent     uuid.UUID
	clock    time.Time
	messages []recurring.Message
}

func newFixture(t *testing.T) *fixture {
	t.Helper()
	p := testPool(t)
	f := &fixture{t: t, pool: p, sync: datasync.NewService(p, quiet), clock: time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)}
	if err := p.QueryRow(context.Background(),
		`INSERT INTO users (email, password_hash, base_currency, timezone) VALUES ($1, 'x', 'USD', 'Asia/Dhaka') RETURNING id`,
		fmt.Sprintf("rec-%s@example.com", uuid.NewString())).Scan(&f.user); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _, _ = p.Exec(context.Background(), `DELETE FROM users WHERE id = $1`, f.user) })
	f.acct, f.rent = uuid.New(), uuid.New()
	f.push(datasync.EntityAccount, f.acct, map[string]any{"name": "Bank", "type": "bank", "currency": "USD"})
	f.push(datasync.EntityCategory, f.rent, map[string]any{"name": "Rent", "kind": "expense"})
	return f
}

func (f *fixture) push(entity string, id uuid.UUID, data map[string]any) {
	f.t.Helper()
	raw, _ := json.Marshal(data)
	f.clock = f.clock.Add(time.Second)
	r, err := f.sync.Push(context.Background(), f.user, datasync.PushRequest{Changes: []datasync.Change{
		{Entity: entity, ID: id, UpdatedAt: f.clock, Data: raw},
	}})
	if err != nil {
		f.t.Fatal(err)
	}
	if r.Results[0].Status != datasync.StatusApplied {
		f.t.Fatalf("%s: %s %+v", entity, r.Results[0].Status, r.Results[0].Error)
	}
}

func (f *fixture) rule(mod func(map[string]any)) uuid.UUID {
	id := uuid.New()
	d := map[string]any{
		"kind": "expense", "account_id": f.acct, "category_id": f.rent, "amount_minor": 120000,
		"currency": "USD", "note": "Rent", "frequency": "monthly", "every": 1,
		"start_date": "2026-09-30", "remind_days_before": 2, "active": true,
	}
	if mod != nil {
		mod(d)
	}
	f.push(datasync.EntityRecurring, id, d)
	return id
}

func (f *fixture) gen(now time.Time) *recurring.Generator {
	return recurring.NewGenerator(f.pool, func(_ context.Context, _ uuid.UUID, m recurring.Message) {
		f.messages = append(f.messages, m)
	}, quiet).WithClock(func() time.Time { return now })
}

func (f *fixture) occurrenceDates(rule uuid.UUID) []string {
	rows, _ := f.pool.Query(context.Background(),
		`SELECT to_char(occurrence_date, 'YYYY-MM-DD') FROM transactions
		  WHERE recurring_id = $1 AND deleted_at IS NULL ORDER BY occurrence_date`, rule)
	var out []string
	for rows.Next() {
		var s string
		_ = rows.Scan(&s)
		out = append(out, s)
	}
	return out
}

func TestCreatesDueOccurrencesOnceInTheUsersTimeZone(t *testing.T) {
	f := newFixture(t)
	rule := f.rule(nil)
	ctx := context.Background()

	// 20:00 UTC on 17 Nov is already 02:00 on 18 Nov in Dhaka.
	g := f.gen(time.Date(2026, 11, 17, 20, 0, 0, 0, time.UTC))
	res, err := g.RunUser(ctx, f.user)
	if err != nil {
		t.Fatal(err)
	}
	if res.Created != 2 || fmt.Sprint(f.occurrenceDates(rule)) != "[2026-09-30 2026-10-30]" {
		t.Fatalf("created %d: %v", res.Created, f.occurrenceDates(rule))
	}
	if again, _ := g.RunUser(ctx, f.user); again.Created != 0 {
		t.Fatalf("second run created %d", again.Created)
	}

	// The rows carry the fixed IDs and reach phones through pull.
	p, err := f.sync.Pull(ctx, f.user, 0)
	if err != nil {
		t.Fatal(err)
	}
	want := recurring.OccurrenceID(rule, time.Date(2026, 10, 30, 0, 0, 0, 0, time.UTC))
	found := false
	for _, c := range p.Changes {
		if c.ID == want {
			found = true
			var d map[string]any
			_ = json.Unmarshal(c.Data, &d)
			if d["amount_base_minor"] != float64(120000) || d["local_date"] != "2026-10-30" {
				t.Fatalf("occurrence data %v", d)
			}
		}
	}
	if !found {
		t.Fatal("generated occurrence not in pull")
	}
}

func TestDeletedOccurrenceNeverComesBack(t *testing.T) {
	f := newFixture(t)
	rule := f.rule(nil)
	ctx := context.Background()
	g := f.gen(time.Date(2026, 11, 18, 6, 0, 0, 0, time.UTC))
	_, _ = g.RunUser(ctx, f.user)
	sep := recurring.OccurrenceID(rule, time.Date(2026, 9, 30, 0, 0, 0, 0, time.UTC))
	if _, err := f.pool.Exec(ctx, `UPDATE transactions SET deleted_at = now() WHERE id = $1`, sep); err != nil {
		t.Fatal(err)
	}
	if res, _ := g.RunUser(ctx, f.user); res.Created != 0 {
		t.Fatal("deleted occurrence was created again")
	}
	if fmt.Sprint(f.occurrenceDates(rule)) != "[2026-10-30]" {
		t.Fatalf("dates = %v", f.occurrenceDates(rule))
	}
}

func TestPhoneMadeOccurrenceIsNotDuplicated(t *testing.T) {
	f := newFixture(t)
	rule := f.rule(nil)
	sep := time.Date(2026, 9, 30, 0, 0, 0, 0, time.UTC)
	// The phone created September's occurrence while offline, then synced.
	f.push(datasync.EntityTransaction, recurring.OccurrenceID(rule, sep), map[string]any{
		"account_id": f.acct, "category_id": f.rent, "kind": "expense", "amount_minor": 120000,
		"currency": "USD", "occurred_at": f.clock, "local_date": "2026-09-30",
		"recurring_id": rule, "occurrence_date": "2026-09-30",
	})
	res, err := f.gen(time.Date(2026, 11, 18, 6, 0, 0, 0, time.UTC)).RunUser(context.Background(), f.user)
	if err != nil || res.Created != 1 {
		t.Fatalf("created %d (want only October) %v", res.Created, err)
	}
}

func TestPausedOrEndedRulesCreateNothing(t *testing.T) {
	f := newFixture(t)
	paused := f.rule(func(d map[string]any) { d["active"] = false })
	ended := f.rule(func(d map[string]any) { d["end_date"] = "2026-10-15" })
	res, _ := f.gen(time.Date(2026, 11, 18, 6, 0, 0, 0, time.UTC)).RunUser(context.Background(), f.user)
	if len(f.occurrenceDates(paused)) != 0 {
		t.Fatal("paused rule created occurrences")
	}
	if fmt.Sprint(f.occurrenceDates(ended)) != "[2026-09-30]" {
		t.Fatalf("ended rule: %v", f.occurrenceDates(ended))
	}
	if res.Created != 1 {
		t.Fatalf("created %d", res.Created)
	}
}

func TestRemindersComeOnceBeforeTheDueDate(t *testing.T) {
	f := newFixture(t)
	f.rule(nil) // due on the 30th, remind 2 days before
	ctx := context.Background()

	if res, _ := f.gen(time.Date(2026, 11, 26, 6, 0, 0, 0, time.UTC)).RunUser(ctx, f.user); res.Reminded != 0 {
		t.Fatal("reminded 4 days early")
	}
	g := f.gen(time.Date(2026, 11, 28, 6, 0, 0, 0, time.UTC)) // 28 Nov in Dhaka
	res, _ := g.RunUser(ctx, f.user)
	if res.Reminded != 1 || len(f.messages) != 1 {
		t.Fatalf("reminded %d, messages %d", res.Reminded, len(f.messages))
	}
	if m := f.messages[0]; m.Title != "Rent is due in 2 days" || m.Body != "1200.00 USD on Mon 30 Nov." {
		t.Fatalf("message = %+v", m)
	}
	if again, _ := g.RunUser(ctx, f.user); again.Reminded != 0 {
		t.Fatal("reminder sent twice")
	}
	if res, _ := f.gen(time.Date(2026, 11, 29, 6, 0, 0, 0, time.UTC)).RunUser(ctx, f.user); res.Reminded != 0 {
		t.Fatal("reminded again the next day")
	}
}
