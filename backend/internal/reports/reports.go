// Package reports answers the report screens: totals, spending by
// category and trends over time, all in the user's base currency and by
// the user's local date (PLAN.md section 3). Transfers are not income or
// spending, so they are left out.
package reports

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// MaxSpan is the longest range a report covers.
const MaxSpan = 5 * 366 * 24 * time.Hour

// ErrBadRange is returned for a missing, reversed or too long range.
var ErrBadRange = errors.New("reports: bad date range")

// Range is a span of local dates, both ends included.
type Range struct{ From, To time.Time }

// ParseRange reads YYYY-MM-DD dates.
func ParseRange(from, to string) (Range, error) {
	f, err1 := time.Parse(time.DateOnly, from)
	t, err2 := time.Parse(time.DateOnly, to)
	if err1 != nil || err2 != nil || t.Before(f) || t.Sub(f) > MaxSpan {
		return Range{}, ErrBadRange
	}
	return Range{From: f, To: t}, nil
}

// Days is how many days the range covers.
func (r Range) Days() int { return int(r.To.Sub(r.From).Hours()/24) + 1 }

// Summary is the income and spending in a range.
type Summary struct {
	Currency     string `json:"currency"`
	Status       string `json:"status"` // ok, or recalculating after a base change
	IncomeMinor  int64  `json:"income_minor"`
	ExpenseMinor int64  `json:"expense_minor"`
	NetMinor     int64  `json:"net_minor"`
	Count        int64  `json:"count"`
	// MissingRate counts transactions left out because their currency has no
	// rate yet (the user can type one).
	MissingRate int64 `json:"missing_rate"`
}

// Service runs the report queries.
type Service struct{ db *pgxpool.Pool }

// NewService creates the service.
func NewService(db *pgxpool.Pool) *Service { return &Service{db: db} }

func (s *Service) user(ctx context.Context, id uuid.UUID) (currency, status string, err error) {
	err = s.db.QueryRow(ctx, `SELECT base_currency, base_currency_status FROM users WHERE id = $1`, id).Scan(&currency, &status)
	return
}

// Summary totals the range.
func (s *Service) Summary(ctx context.Context, userID uuid.UUID, r Range) (Summary, error) {
	out := Summary{}
	var err error
	if out.Currency, out.Status, err = s.user(ctx, userID); err != nil {
		return out, err
	}
	err = s.db.QueryRow(ctx, `
		SELECT COALESCE(sum(amount_base_minor) FILTER (WHERE kind = 'income'), 0),
		       COALESCE(sum(amount_base_minor) FILTER (WHERE kind = 'expense'), 0),
		       count(*) FILTER (WHERE amount_base_minor IS NOT NULL),
		       count(*) FILTER (WHERE amount_base_minor IS NULL)
		  FROM transactions
		 WHERE user_id = $1 AND deleted_at IS NULL AND kind <> 'transfer'
		   AND local_date BETWEEN $2 AND $3`, userID, r.From, r.To).
		Scan(&out.IncomeMinor, &out.ExpenseMinor, &out.Count, &out.MissingRate)
	out.NetMinor = out.IncomeMinor - out.ExpenseMinor
	return out, err
}

// CategoryTotal is one top-level category with its sub-categories.
type CategoryTotal struct {
	CategoryID uuid.UUID       `json:"category_id"`
	Name       string          `json:"name"`
	Color      string          `json:"color"`
	TotalMinor int64           `json:"total_minor"` // including sub-categories
	Count      int64           `json:"count"`
	Children   []CategoryTotal `json:"children,omitempty"`
}

// ByCategory is spending (or income) per category, biggest first.
type ByCategory struct {
	Currency   string          `json:"currency"`
	Status     string          `json:"status"`
	Kind       string          `json:"kind"`
	TotalMinor int64           `json:"total_minor"`
	Categories []CategoryTotal `json:"categories"`
}

// ByCategory groups the range by category; sub-categories are added to
// their parent and also listed under it.
func (s *Service) ByCategory(ctx context.Context, userID uuid.UUID, r Range, kind string) (ByCategory, error) {
	out := ByCategory{Kind: kind, Categories: []CategoryTotal{}}
	var err error
	if out.Currency, out.Status, err = s.user(ctx, userID); err != nil {
		return out, err
	}
	rows, err := s.db.Query(ctx, `
		SELECT c.id, c.parent_id, c.name, c.color, sum(t.amount_base_minor), count(*)
		  FROM transactions t JOIN categories c ON c.id = t.category_id
		 WHERE t.user_id = $1 AND t.deleted_at IS NULL AND t.kind = $4
		   AND t.amount_base_minor IS NOT NULL AND t.local_date BETWEEN $2 AND $3
		 GROUP BY c.id, c.parent_id, c.name, c.color`, userID, r.From, r.To, kind)
	if err != nil {
		return out, err
	}
	type row struct {
		id     uuid.UUID
		parent *uuid.UUID
		name   string
		color  string
		total  int64
		count  int64
	}
	list, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (row, error) {
		var x row
		return x, r.Scan(&x.id, &x.parent, &x.name, &x.color, &x.total, &x.count)
	})
	if err != nil {
		return out, err
	}
	top := map[uuid.UUID]*CategoryTotal{}
	var order []uuid.UUID
	get := func(id uuid.UUID) *CategoryTotal {
		if c, ok := top[id]; ok {
			return c
		}
		c := &CategoryTotal{CategoryID: id}
		top[id] = c
		order = append(order, id)
		return c
	}
	var children []row
	for _, x := range list {
		if x.parent != nil {
			children = append(children, x)
			continue
		}
		c := get(x.id)
		c.Name, c.Color = x.name, x.color
		c.TotalMinor += x.total
		c.Count += x.count
	}
	for _, x := range children {
		p := get(*x.parent)
		p.TotalMinor += x.total
		p.Count += x.count
		p.Children = append(p.Children, CategoryTotal{CategoryID: x.id, Name: x.name, Color: x.color, TotalMinor: x.total, Count: x.count})
	}
	// A parent that only has spending through its children still needs its name.
	for _, id := range order {
		if c := top[id]; c.Name == "" {
			_ = s.db.QueryRow(ctx, `SELECT name, color FROM categories WHERE id = $1`, id).Scan(&c.Name, &c.Color)
		}
	}
	for _, id := range order {
		c := top[id]
		sortTotals(c.Children)
		out.Categories = append(out.Categories, *c)
		out.TotalMinor += c.TotalMinor
	}
	sortTotals(out.Categories)
	return out, nil
}

// sortTotals puts the biggest first; ties by name so the order is stable.
func sortTotals(list []CategoryTotal) {
	sort.Slice(list, func(i, j int) bool {
		if list[i].TotalMinor != list[j].TotalMinor {
			return list[i].TotalMinor > list[j].TotalMinor
		}
		return list[i].Name < list[j].Name
	})
}

// Bucket is one period of a trend.
type Bucket struct {
	Start        string `json:"start"` // first day, YYYY-MM-DD
	IncomeMinor  int64  `json:"income_minor"`
	ExpenseMinor int64  `json:"expense_minor"`
	NetMinor     int64  `json:"net_minor"`
}

// Trend is income and spending per day, week or month.
type Trend struct {
	Currency string   `json:"currency"`
	Status   string   `json:"status"`
	Interval string   `json:"interval"`
	Buckets  []Bucket `json:"buckets"`
}

// Intervals and how many buckets each may produce.
var intervals = map[string]int{"day": 400, "week": 300, "month": 120}

// ErrBadInterval is returned for an unknown interval or too many buckets.
var ErrBadInterval = errors.New("reports: bad interval")

// Trend splits the range into periods (weeks start on Monday); empty
// periods are included with zeros so charts have no gaps.
func (s *Service) Trend(ctx context.Context, userID uuid.UUID, r Range, interval string) (Trend, error) {
	limit, ok := intervals[interval]
	if !ok {
		return Trend{}, ErrBadInterval
	}
	starts := bucketStarts(r, interval)
	if len(starts) > limit {
		return Trend{}, fmt.Errorf("%w: %d %ss is too many (max %d)", ErrBadInterval, len(starts), interval, limit)
	}
	out := Trend{Interval: interval, Buckets: make([]Bucket, 0, len(starts))}
	var err error
	if out.Currency, out.Status, err = s.user(ctx, userID); err != nil {
		return out, err
	}
	rows, err := s.db.Query(ctx, `
		SELECT to_char(date_trunc($4, local_date::timestamp), 'YYYY-MM-DD'),
		       COALESCE(sum(amount_base_minor) FILTER (WHERE kind = 'income'), 0),
		       COALESCE(sum(amount_base_minor) FILTER (WHERE kind = 'expense'), 0)
		  FROM transactions
		 WHERE user_id = $1 AND deleted_at IS NULL AND kind <> 'transfer'
		   AND amount_base_minor IS NOT NULL AND local_date BETWEEN $2 AND $3
		 GROUP BY 1`, userID, r.From, r.To, interval)
	if err != nil {
		return out, err
	}
	sums := map[string][2]int64{}
	var (
		start         string
		income, spent int64
	)
	if _, err := pgx.ForEachRow(rows, []any{&start, &income, &spent}, func() error {
		sums[start] = [2]int64{income, spent}
		return nil
	}); err != nil {
		return out, err
	}
	for _, st := range starts {
		v := sums[st]
		out.Buckets = append(out.Buckets, Bucket{Start: st, IncomeMinor: v[0], ExpenseMinor: v[1], NetMinor: v[0] - v[1]})
	}
	return out, nil
}

// bucketStarts lists the first day of every period touching the range,
// matching Postgres date_trunc (ISO weeks start on Monday).
func bucketStarts(r Range, interval string) []string {
	var cur time.Time
	switch interval {
	case "day":
		cur = r.From
	case "week":
		cur = r.From.AddDate(0, 0, -((int(r.From.Weekday()) + 6) % 7))
	default:
		cur = time.Date(r.From.Year(), r.From.Month(), 1, 0, 0, 0, 0, time.UTC)
	}
	var out []string
	for !cur.After(r.To) && len(out) <= intervals[interval] {
		out = append(out, cur.Format(time.DateOnly))
		switch interval {
		case "day":
			cur = cur.AddDate(0, 0, 1)
		case "week":
			cur = cur.AddDate(0, 0, 7)
		default:
			cur = cur.AddDate(0, 1, 0)
		}
	}
	return out
}
