package recurring

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"pennywise/backend/internal/money"
)

// TaskRunAll asks the worker to create due occurrences and send reminders
// for every user with an active rule. Scheduled every 15 minutes.
const TaskRunAll = "recurring:run_all"

// Message is a reminder to show on the user's phones.
type Message struct {
	Title, Body string
	Data        map[string]string
}

// NotifyFunc delivers a message to all phones of a user (the worker plugs
// in the push package; kept as a function so this package stays small).
type NotifyFunc func(ctx context.Context, userID uuid.UUID, m Message)

// Generator creates due occurrences on the server (for phones that are
// offline or not opened) and sends "due soon" reminders.
type Generator struct {
	pool   *pgxpool.Pool
	notify NotifyFunc
	logger *slog.Logger
	now    func() time.Time

	// OnCreated runs after occurrences were added for a user (e.g. queue a
	// budget check). Its error is logged.
	OnCreated func(ctx context.Context, userID uuid.UUID) error
}

// NewGenerator creates the generator.
func NewGenerator(pool *pgxpool.Pool, notify NotifyFunc, logger *slog.Logger) *Generator {
	return &Generator{pool: pool, notify: notify, logger: logger, now: time.Now}
}

type ruleRow struct {
	id, accountID, categoryID uuid.UUID
	kind, currency, note      string
	categoryName              string
	amount                    int64
	schedule                  Rule
	remindDays                int
}

// Result of one run for a user.
type Result struct {
	Created  int
	Reminded int
}

// WithClock replaces the clock (tests).
func (g *Generator) WithClock(now func() time.Time) *Generator {
	g.now = now
	return g
}

// HandleRunAll is the worker side of TaskRunAll.
func (g *Generator) HandleRunAll(ctx context.Context, _ *asynq.Task) error {
	rows, err := g.pool.Query(ctx,
		`SELECT DISTINCT user_id FROM recurring_rules WHERE active AND deleted_at IS NULL`)
	if err != nil {
		return err
	}
	users, err := pgx.CollectRows(rows, pgx.RowTo[uuid.UUID])
	if err != nil {
		return err
	}
	var failed int
	for _, u := range users {
		if _, err := g.RunUser(ctx, u); err != nil {
			failed++
			g.logger.ErrorContext(ctx, "recurring run failed for a user", "err", err)
		}
	}
	if failed > 0 {
		return fmt.Errorf("recurring run failed for %d of %d users", failed, len(users))
	}
	return nil
}

// RunUser creates the user's missing occurrences up to today (in the
// user's time zone) and sends due reminders. Safe to run any number of
// times: occurrence IDs are fixed and reminders are recorded.
func (g *Generator) RunUser(ctx context.Context, userID uuid.UUID) (Result, error) {
	var tzName, base string
	err := g.pool.QueryRow(ctx,
		`SELECT timezone, base_currency FROM users WHERE id = $1 AND deleted_at IS NULL`,
		userID).Scan(&tzName, &base)
	if errors.Is(err, pgx.ErrNoRows) {
		return Result{}, nil
	}
	if err != nil {
		return Result{}, err
	}
	loc, err := time.LoadLocation(tzName)
	if err != nil {
		loc = time.UTC
	}
	now := g.now().In(loc)
	today := day(now)

	rules, err := g.rules(ctx, userID)
	if err != nil {
		return Result{}, err
	}

	type pending struct {
		rule ruleRow
		date time.Time
	}
	var missing []pending
	for _, r := range rules {
		existing, err := g.existingDates(ctx, r.id)
		if err != nil {
			return Result{}, err
		}
		for _, d := range Dates(r.schedule, r.schedule.Start, today) {
			if !existing[d.Format(time.DateOnly)] {
				missing = append(missing, pending{r, d})
			}
		}
	}

	var res Result
	if len(missing) > 0 {
		err := pgx.BeginFunc(ctx, g.pool, func(tx pgx.Tx) error {
			var version int64
			// Same lock and counter as a sync push: phones pull these rows.
			if err := tx.QueryRow(ctx,
				`UPDATE users SET sync_version = sync_version + 1 WHERE id = $1 RETURNING sync_version`,
				userID).Scan(&version); err != nil {
				return err
			}
			for _, p := range missing {
				n, err := g.insertOccurrence(ctx, tx, userID, base, loc, version, p.rule, p.date)
				if err != nil {
					return err
				}
				res.Created += n
			}
			return nil
		})
		if err != nil {
			return Result{}, err
		}
		if res.Created > 0 && g.OnCreated != nil {
			if err := g.OnCreated(ctx, userID); err != nil {
				g.logger.WarnContext(ctx, "after-create hook failed", "err", err)
			}
		}
	}

	for _, r := range rules {
		if r.remindDays == 0 {
			continue
		}
		for _, d := range Dates(r.schedule, today.AddDate(0, 0, 1), today.AddDate(0, 0, r.remindDays)) {
			tag, err := g.pool.Exec(ctx,
				`INSERT INTO recurring_reminders (rule_id, occurrence_date) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
				r.id, d)
			if err != nil {
				return res, err
			}
			if tag.RowsAffected() == 0 {
				continue // already reminded
			}
			res.Reminded++
			g.notify(ctx, userID, reminder(r, d, today))
		}
	}
	return res, nil
}

func reminder(r ruleRow, due, today time.Time) Message {
	amount, _ := money.Format(r.amount, r.currency)
	days := int(due.Sub(today).Hours() / 24)
	when := fmt.Sprintf("in %d days", days)
	if days == 1 {
		when = "tomorrow"
	}
	what := r.categoryName
	if r.note != "" {
		what = r.note
	}
	verb := "is due"
	if r.kind == "income" {
		verb = "is expected"
	}
	return Message{
		Title: fmt.Sprintf("%s %s %s", what, verb, when),
		Body:  fmt.Sprintf("%s %s on %s.", amount, r.currency, due.Format("Mon 2 Jan")),
		Data:  map[string]string{"type": "recurring_reminder", "rule_id": r.id.String(), "date": due.Format(time.DateOnly)},
	}
}

// rules returns the user's active rules whose account still exists.
func (g *Generator) rules(ctx context.Context, userID uuid.UUID) ([]ruleRow, error) {
	rows, err := g.pool.Query(ctx, `
		SELECT r.id, r.kind, r.account_id, r.category_id, COALESCE(c.name, ''), r.amount_minor,
		       r.currency, r.note, r.frequency, r.every, r.start_date, r.end_date, r.remind_days_before
		  FROM recurring_rules r
		  JOIN accounts a ON a.id = r.account_id AND a.deleted_at IS NULL
		  LEFT JOIN categories c ON c.id = r.category_id
		 WHERE r.user_id = $1 AND r.active AND r.deleted_at IS NULL`, userID)
	if err != nil {
		return nil, err
	}
	return pgx.CollectRows(rows, func(row pgx.CollectableRow) (ruleRow, error) {
		var (
			r     ruleRow
			every int32
			start time.Time
			end   *time.Time
			days  int32
		)
		err := row.Scan(&r.id, &r.kind, &r.accountID, &r.categoryID, &r.categoryName, &r.amount,
			&r.currency, &r.note, &r.schedule.Frequency, &every, &start, &end, &days)
		r.schedule.Every, r.schedule.Start, r.schedule.End, r.remindDays = int(every), start, end, int(days)
		return r, err
	})
}

// existingDates are the occurrence dates the rule already has, deleted
// ones included: a deleted occurrence must never come back.
func (g *Generator) existingDates(ctx context.Context, ruleID uuid.UUID) (map[string]bool, error) {
	rows, err := g.pool.Query(ctx,
		`SELECT to_char(occurrence_date, 'YYYY-MM-DD') FROM transactions WHERE recurring_id = $1`, ruleID)
	if err != nil {
		return nil, err
	}
	dates, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		return nil, err
	}
	set := make(map[string]bool, len(dates))
	for _, d := range dates {
		set[d] = true
	}
	return set, nil
}

const insertOccurrenceSQL = `
INSERT INTO transactions (id, user_id, account_id, category_id, kind, amount_minor, currency,
                          fx_rate_to_base, fx_rate_source, amount_base_minor,
                          occurred_at, local_date, note, recurring_id, occurrence_date,
                          version, updated_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)
ON CONFLICT DO NOTHING`

func (g *Generator) insertOccurrence(ctx context.Context, tx pgx.Tx, userID uuid.UUID, base string,
	loc *time.Location, version int64, r ruleRow, date time.Time) (int, error) {
	var (
		rate, source *string
		baseAmount   *int64
	)
	if r.currency == base {
		one, auto := "1", "auto"
		rate, source, baseAmount = &one, &auto, &r.amount
	}
	// Noon on the due day, in the user's time zone.
	occurredAt := time.Date(date.Year(), date.Month(), date.Day(), 12, 0, 0, 0, loc)
	tag, err := tx.Exec(ctx, insertOccurrenceSQL,
		OccurrenceID(r.id, date), userID, r.accountID, r.categoryID, r.kind, r.amount, r.currency,
		rate, source, baseAmount, occurredAt, date, r.note, r.id, date, version, g.now())
	if err != nil {
		return 0, err
	}
	return int(tag.RowsAffected()), nil
}
