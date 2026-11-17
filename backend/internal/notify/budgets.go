package notify

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"pennywise/backend/internal/money"
)

// BudgetChecker sends an alert when spending in a budget's current period
// reaches one of its levels. Each alert goes out once per period: the
// budget_alerts primary key makes a second send impossible.
type BudgetChecker struct {
	pool   *pgxpool.Pool
	sender Sender
	logger *slog.Logger
	now    func() time.Time
}

// NewBudgetChecker creates the checker.
func NewBudgetChecker(pool *pgxpool.Pool, sender Sender, logger *slog.Logger) *BudgetChecker {
	return &BudgetChecker{pool: pool, sender: sender, logger: logger, now: time.Now}
}

// Alert is one newly reached budget level (returned for tests and logs).
type Alert struct {
	BudgetID    uuid.UUID
	PeriodStart time.Time
	Threshold   int32
	SpentMinor  int64
	AmountMinor int64
}

// PeriodStart is the first day of the budget period containing localToday:
// the 1st of the month, or the Monday of the week.
func PeriodStart(period string, localToday time.Time) time.Time {
	d := time.Date(localToday.Year(), localToday.Month(), localToday.Day(), 0, 0, 0, 0, time.UTC)
	if period == "weekly" {
		offset := (int(d.Weekday()) + 6) % 7 // Monday = 0
		return d.AddDate(0, 0, -offset)
	}
	return time.Date(d.Year(), d.Month(), 1, 0, 0, 0, 0, time.UTC)
}

// PeriodEnd is the first day after the period.
func PeriodEnd(period string, start time.Time) time.Time {
	if period == "weekly" {
		return start.AddDate(0, 0, 7)
	}
	return start.AddDate(0, 1, 0)
}

type budgetRow struct {
	id         uuid.UUID
	categoryID *uuid.UUID
	category   string
	amount     int64
	period     string
	thresholds []int32
}

// spentSQL sums expenses in the base currency for one budget period, by
// the user's local date. A category budget includes its sub-categories.
// Transactions without a base amount (foreign currency before Milestone 6)
// are not counted.
const spentSQL = `
SELECT COALESCE(SUM(t.amount_base_minor), 0)
  FROM transactions t
  LEFT JOIN categories c ON c.id = t.category_id
 WHERE t.user_id = $1
   AND t.kind = 'expense'
   AND t.deleted_at IS NULL
   AND t.amount_base_minor IS NOT NULL
   AND t.local_date >= $2 AND t.local_date < $3
   AND ($4::uuid IS NULL OR t.category_id = $4 OR c.parent_id = $4)`

// Check looks at every live budget of the user and sends the alerts that
// are newly reached. It is safe to run any number of times.
func (b *BudgetChecker) Check(ctx context.Context, userID uuid.UUID) ([]Alert, error) {
	var (
		tzName, currency string
	)
	err := b.pool.QueryRow(ctx,
		`SELECT timezone, base_currency FROM users WHERE id = $1 AND deleted_at IS NULL`,
		userID).Scan(&tzName, &currency)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	loc, err := time.LoadLocation(tzName)
	if err != nil {
		loc = time.UTC
	}
	today := b.now().In(loc)

	rows, err := b.pool.Query(ctx, `
		SELECT bu.id, bu.category_id, COALESCE(c.name, ''), bu.amount_minor, bu.period, bu.alert_thresholds
		  FROM budgets bu
		  LEFT JOIN categories c ON c.id = bu.category_id
		 WHERE bu.user_id = $1 AND bu.deleted_at IS NULL`, userID)
	if err != nil {
		return nil, err
	}
	budgets, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (budgetRow, error) {
		var x budgetRow
		err := r.Scan(&x.id, &x.categoryID, &x.category, &x.amount, &x.period, &x.thresholds)
		return x, err
	})
	if err != nil {
		return nil, err
	}

	var alerts []Alert
	for _, bu := range budgets {
		start := PeriodStart(bu.period, today)
		end := PeriodEnd(bu.period, start)
		var spent int64
		if err := b.pool.QueryRow(ctx, spentSQL, userID, start, end, bu.categoryID).Scan(&spent); err != nil {
			return nil, err
		}
		for _, level := range bu.thresholds {
			// Integer maths: spent/amount >= level/100.
			if spent*100 < int64(level)*bu.amount {
				continue
			}
			tag, err := b.pool.Exec(ctx,
				`INSERT INTO budget_alerts (budget_id, period_start, threshold, spent_minor)
				 VALUES ($1, $2, $3, $4) ON CONFLICT DO NOTHING`,
				bu.id, start, level, spent)
			if err != nil {
				return nil, err
			}
			if tag.RowsAffected() == 0 {
				continue // already sent this period
			}
			a := Alert{BudgetID: bu.id, PeriodStart: start, Threshold: level, SpentMinor: spent, AmountMinor: bu.amount}
			alerts = append(alerts, a)
			b.send(ctx, userID, bu, a, currency)
		}
	}
	return alerts, nil
}

func (b *BudgetChecker) send(ctx context.Context, userID uuid.UUID, bu budgetRow, a Alert, currency string) {
	name := bu.category
	if bu.categoryID == nil {
		name = "Total spending"
	}
	spent, _ := money.Format(a.SpentMinor, currency)
	limit, _ := money.Format(a.AmountMinor, currency)
	when := "this month"
	if bu.period == "weekly" {
		when = "this week"
	}
	m := Message{
		Title: fmt.Sprintf("%s: %d%% of your budget used", name, a.Threshold),
		Body:  fmt.Sprintf("You have spent %s of %s %s %s.", spent, limit, currency, when),
		Data:  map[string]string{"type": "budget_alert", "budget_id": bu.id.String()},
	}
	if a.Threshold >= 100 {
		m.Title = fmt.Sprintf("%s: budget reached", name)
	}

	SendToUser(ctx, b.pool, b.sender, b.logger, userID, m)
}
