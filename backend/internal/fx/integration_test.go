package fx_test

// Integration tests on PostgreSQL (TEST_DATABASE_URL). They use made-up
// currency codes (XTA, XTB, XTC) so they never clash with real rates.

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
	"github.com/jackc/pgx/v5/pgxpool"

	"pennywise/backend/internal/datasync"
	"pennywise/backend/internal/fx"
	"pennywise/backend/internal/testdb"
)

var quiet = slog.New(slog.NewTextHandler(io.Discard, nil))

// rates: date -> code -> EUR rate. Cleaned up after the test.
func seedRates(t *testing.T, p *pgxpool.Pool, rates map[string]map[string]string) {
	t.Helper()
	ctx := context.Background()
	for d, m := range rates {
		if err := fx.SaveRates(ctx, p, d, m); err != nil {
			t.Fatal(err)
		}
	}
	t.Cleanup(func() {
		_, _ = p.Exec(ctx, `DELETE FROM exchange_rates WHERE quote IN ('XTA', 'XTB', 'XTC')`)
	})
}

func d(s string) time.Time { t, _ := time.Parse(time.DateOnly, s); return t }

func TestRateUsesLatestDayOnOrBefore(t *testing.T) {
	p := testdb.Pool(t)
	seedRates(t, p, map[string]map[string]string{
		"2026-03-05": {"XTA": "2", "XTB": "10"}, // Thursday
		"2026-03-06": {"XTA": "4", "XTB": "10"}, // Friday
	})
	ctx := context.Background()
	for _, c := range []struct {
		day  string
		want string
	}{
		{"2026-03-06", "2.5"}, // 1 XTA = 10/4 XTB
		{"2026-03-08", "2.5"}, // Sunday: Friday's rate
		{"2026-03-05", "5"},   // Thursday
		{"2026-01-01", "5"},   // before all data: the earliest rate
	} {
		r, ok, err := fx.Rate(ctx, p, "XTA", "XTB", d(c.day))
		if err != nil || !ok {
			t.Fatalf("%s: ok=%v err=%v", c.day, ok, err)
		}
		if got := fx.Format(r); got != c.want {
			t.Errorf("%s: rate %s, want %s", c.day, got, c.want)
		}
	}
	if r, _, _ := fx.Rate(ctx, p, "XTA", "EUR", d("2026-03-06")); fx.Format(r) != "0.25" {
		t.Errorf("XTA->EUR = %s", fx.Format(r))
	}
	if _, ok, _ := fx.Rate(ctx, p, "XTA", "XTC", d("2026-03-06")); ok {
		t.Error("XTC has no rate, want ok=false")
	}
}

type fixture struct {
	t    *testing.T
	p    *pgxpool.Pool
	sync *datasync.Service
	user uuid.UUID
	cat  uuid.UUID
	at   time.Time
}

func newFixture(t *testing.T, base string) *fixture {
	p := testdb.Pool(t)
	f := &fixture{t: t, p: p, sync: datasync.NewService(p, quiet), user: testdb.NewUser(t, p, base),
		cat: uuid.New(), at: time.Now().Add(-time.Hour)}
	f.push(datasync.EntityCategory, f.cat, map[string]any{"name": "Food", "kind": "expense"})
	return f
}

func (f *fixture) push(entity string, id uuid.UUID, data map[string]any) {
	f.t.Helper()
	raw, _ := json.Marshal(data)
	f.at = f.at.Add(time.Second)
	r, err := f.sync.Push(context.Background(), f.user, datasync.PushRequest{Changes: []datasync.Change{
		{Entity: entity, ID: id, UpdatedAt: f.at, Data: raw},
	}})
	if err != nil {
		f.t.Fatal(err)
	}
	if r.Results[0].Status != datasync.StatusApplied {
		f.t.Fatalf("%s: %s %+v", entity, r.Results[0].Status, r.Results[0].Error)
	}
}

func (f *fixture) account(currency string) uuid.UUID {
	id := uuid.New()
	f.push(datasync.EntityAccount, id, map[string]any{"name": currency, "type": "bank", "currency": currency})
	return id
}

func (f *fixture) expense(acct uuid.UUID, currency string, amount int64, day string, extra map[string]any) uuid.UUID {
	id := uuid.New()
	data := map[string]any{
		"account_id": acct, "category_id": f.cat, "kind": "expense", "amount_minor": amount,
		"currency": currency, "occurred_at": day + "T12:00:00Z", "local_date": day, "note": "",
	}
	for k, v := range extra {
		data[k] = v
	}
	f.push(datasync.EntityTransaction, id, data)
	return id
}

type stored struct {
	rate    *string
	source  *string
	amount  *int64
	version int64
}

func (f *fixture) tx(id uuid.UUID) stored {
	f.t.Helper()
	var s stored
	if err := f.p.QueryRow(context.Background(),
		`SELECT fx_rate_to_base::text, fx_rate_source, amount_base_minor, version FROM transactions WHERE id = $1`,
		id).Scan(&s.rate, &s.source, &s.amount, &s.version); err != nil {
		f.t.Fatal(err)
	}
	return s
}

func val[T any](p *T) any {
	if p == nil {
		return nil
	}
	return *p
}

func TestPushConvertsWithTheRateOfItsDate(t *testing.T) {
	f := newFixture(t, "XTB")
	seedRates(t, f.p, map[string]map[string]string{
		"2026-03-05": {"XTA": "2", "XTB": "10"},
		"2026-03-06": {"XTA": "4", "XTB": "10"},
	})
	a := f.account("XTA")
	thu := f.tx(f.expense(a, "XTA", 1000, "2026-03-05", nil))
	sun := f.tx(f.expense(a, "XTA", 1000, "2026-03-08", nil))
	if val(thu.amount) != int64(5000) || *thu.rate != "5.0000000000" || *thu.source != "auto" {
		t.Errorf("Thursday: %v %v %v", val(thu.rate), val(thu.source), val(thu.amount))
	}
	if val(sun.amount) != int64(2500) {
		t.Errorf("Sunday uses Friday's rate: amount %v", val(sun.amount))
	}

	manual := f.tx(f.expense(a, "XTA", 1000, "2026-03-05", map[string]any{"manual_fx_rate": "3.5"}))
	if val(manual.amount) != int64(3500) || *manual.source != "manual" {
		t.Errorf("manual rate: %v %v", val(manual.source), val(manual.amount))
	}

	same := f.tx(f.expense(f.account("XTB"), "XTB", 777, "2026-03-05", map[string]any{"manual_fx_rate": "9"}))
	if val(same.amount) != int64(777) || *same.rate != "1.0000000000" || *same.source != "auto" {
		t.Errorf("base currency ignores a typed rate: %v %v %v", val(same.rate), val(same.source), val(same.amount))
	}

	raw, _ := json.Marshal(map[string]any{
		"account_id": a, "category_id": f.cat, "kind": "expense", "amount_minor": 1,
		"currency": "XTA", "occurred_at": "2026-03-05T12:00:00Z", "local_date": "2026-03-05",
		"note": "", "manual_fx_rate": "-2",
	})
	r, err := f.sync.Push(context.Background(), f.user, datasync.PushRequest{Changes: []datasync.Change{
		{Entity: datasync.EntityTransaction, ID: uuid.New(), UpdatedAt: time.Now(), Data: raw},
	}})
	if err != nil || r.Results[0].Status != datasync.StatusRejected || r.Results[0].Error.Field != "manual_fx_rate" {
		t.Errorf("bad typed rate: %+v %v", r.Results, err)
	}
}

type fakeFetcher struct {
	days  map[string]map[string]string
	calls [][2]string
}

func (f *fakeFetcher) Range(_ context.Context, from, to time.Time) (map[string]map[string]string, error) {
	f.calls = append(f.calls, [2]string{from.Format(time.DateOnly), to.Format(time.DateOnly)})
	out := map[string]map[string]string{}
	for day, m := range f.days {
		if t := d(day); !t.Before(from) && !t.After(to) {
			out[day] = m
		}
	}
	return out, nil
}

func TestFillMissingAfterRatesArrive(t *testing.T) {
	f := newFixture(t, "XTB")
	a := f.account("XTC")
	id := f.expense(a, "XTC", 1000, "2026-03-05", nil)
	before := f.tx(id)
	if before.amount != nil || before.rate != nil || before.source != nil {
		t.Fatalf("no rate yet: want empty, got %v %v %v", val(before.rate), val(before.source), val(before.amount))
	}
	manual := f.expense(a, "XTC", 1000, "2026-03-05", map[string]any{"manual_fx_rate": "7"})

	t.Cleanup(func() {
		_, _ = f.p.Exec(context.Background(), `DELETE FROM exchange_rates WHERE quote IN ('XTB', 'XTC')`)
	})
	fetch := &fakeFetcher{days: map[string]map[string]string{"2026-03-05": {"XTB": "10", "XTC": "5"}}}
	svc := fx.NewService(f.p, fetch, quiet).WithClock(func() time.Time { return d("2026-03-09") })
	if err := svc.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.FillMissing(context.Background()); err != nil {
		t.Fatal(err)
	}
	after := f.tx(id)
	if val(after.amount) != int64(2000) || *after.source != "auto" {
		t.Errorf("filled: %v %v %v", val(after.rate), val(after.source), val(after.amount))
	}
	if after.version <= before.version {
		t.Errorf("version not bumped: %d -> %d", before.version, after.version)
	}
	if m := f.tx(manual); val(m.amount) != int64(7000) {
		t.Errorf("manual row changed: %v", val(m.amount))
	}
	// The pull sends the filled value to phones.
	pull, err := f.sync.Pull(context.Background(), f.user, before.version)
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, c := range pull.Changes {
		if c.ID == id {
			found = true
		}
	}
	if !found {
		t.Error("filled row is not in the next pull")
	}
}

type fakeQueue struct{ tasks []*asynq.Task }

func (q *fakeQueue) EnqueueContext(_ context.Context, t *asynq.Task, _ ...asynq.Option) (*asynq.TaskInfo, error) {
	q.tasks = append(q.tasks, t)
	return &asynq.TaskInfo{}, nil
}

func TestChangeBaseRecomputesEverything(t *testing.T) {
	f := newFixture(t, "XTA")
	seedRates(t, f.p, map[string]map[string]string{
		"2026-03-05": {"XTA": "2", "XTB": "10", "XTC": "4"},
	})
	ctx := context.Background()
	xta, xtc := f.account("XTA"), f.account("XTC")
	own := f.expense(xta, "XTA", 1000, "2026-03-05", nil)
	auto := f.expense(xtc, "XTC", 1000, "2026-03-05", nil)                                      // 1 XTC = 0.5 XTA
	typed := f.expense(xtc, "XTC", 1000, "2026-03-05", map[string]any{"manual_fx_rate": "0.6"}) // user says 0.6 XTA
	budget := uuid.New()
	f.push(datasync.EntityBudget, budget, map[string]any{"category_id": nil, "amount_minor": 30000, "period": "monthly", "alert_thresholds": []int{80, 100}})

	q := &fakeQueue{}
	if err := fx.ChangeBase(ctx, f.p, q, f.user, "XTB"); err != nil {
		t.Fatal(err)
	}
	var status string
	_ = f.p.QueryRow(ctx, `SELECT base_currency_status FROM users WHERE id = $1`, f.user).Scan(&status)
	if status != "recalculating" || len(q.tasks) != 1 {
		t.Fatalf("status %q, %d jobs", status, len(q.tasks))
	}
	if err := fx.ChangeBase(ctx, f.p, q, f.user, "XTC"); err != fx.ErrRecalculating {
		t.Errorf("second change while running: %v", err)
	}

	svc := fx.NewService(f.p, &fakeFetcher{}, quiet).WithClock(func() time.Time { return d("2026-03-06") })
	if err := svc.HandleRebase(ctx, q.tasks[0]); err != nil {
		t.Fatal(err)
	}
	_ = f.p.QueryRow(ctx, `SELECT base_currency_status FROM users WHERE id = $1`, f.user).Scan(&status)
	if status != "ok" {
		t.Errorf("status after job: %q", status)
	}
	// 1 XTA = 5 XTB; 1 XTC = 2.5 XTB; typed 0.6 XTA = 3 XTB.
	for name, c := range map[string]struct {
		id     uuid.UUID
		amount int64
		source string
	}{
		"own":   {own, 5000, "auto"},
		"auto":  {auto, 2500, "auto"},
		"typed": {typed, 3000, "manual"},
	} {
		s := f.tx(c.id)
		if val(s.amount) != c.amount || val(s.source) != c.source {
			t.Errorf("%s: amount %v source %v, want %d %s", name, val(s.amount), val(s.source), c.amount, c.source)
		}
	}
	var limit int64
	_ = f.p.QueryRow(ctx, `SELECT amount_minor FROM budgets WHERE id = $1`, budget).Scan(&limit)
	if limit != 150000 {
		t.Errorf("budget limit %d, want 150000 (300.00 XTA = 1500.00 XTB)", limit)
	}

	if err := fx.ChangeBase(ctx, f.p, q, f.user, "XTB"); err != nil || len(q.tasks) != 1 {
		t.Errorf("same base again: err %v, jobs %d", err, len(q.tasks))
	}
}
