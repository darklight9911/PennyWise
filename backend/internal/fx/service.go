package fx

import (
	"context"
	"fmt"
	"log/slog"
	"math/big"
	"time"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Task names.
const (
	// TaskRefresh downloads new rates, then fills missing base amounts.
	TaskRefresh = "fx:refresh"
	// TaskRebase recomputes a user's amounts after a base-currency change.
	TaskRebase = "fx:rebase"
)

// How many rows one sync version covers in the batch jobs.
const batchSize = 1000

// The ECB series starts here; nothing older can be fetched.
var ecbStart = time.Date(1999, 1, 4, 0, 0, 0, 0, time.UTC)

// Service keeps rates fresh and stored base amounts correct.
type Service struct {
	db    *pgxpool.Pool
	fetch Fetcher
	log   *slog.Logger
	now   func() time.Time
}

// NewService creates the service.
func NewService(db *pgxpool.Pool, fetch Fetcher, log *slog.Logger) *Service {
	return &Service{db: db, fetch: fetch, log: log, now: time.Now}
}

// WithClock sets the clock (tests).
func (s *Service) WithClock(now func() time.Time) *Service { s.now = now; return s }

// HandleRefresh is the asynq handler for TaskRefresh.
func (s *Service) HandleRefresh(ctx context.Context, _ *asynq.Task) error {
	if err := s.Refresh(ctx); err != nil {
		return err
	}
	n, err := s.FillMissing(ctx)
	if n > 0 {
		s.log.InfoContext(ctx, "fx: filled base amounts", "rows", n)
	}
	return err
}

// Refresh downloads the last 10 days of rates (covers weekends and missed
// runs) and, when older transactions need them, the days before the oldest
// stored rate, in chunks of 90 days.
func (s *Service) Refresh(ctx context.Context) error {
	today := day(s.now())
	if err := s.download(ctx, today.AddDate(0, 0, -10), today); err != nil {
		return err
	}

	var oldestRate, oldestNeed *time.Time
	if err := s.db.QueryRow(ctx,
		`SELECT min(date) FROM exchange_rates WHERE base = $1`, Anchor).Scan(&oldestRate); err != nil {
		return err
	}
	if err := s.db.QueryRow(ctx,
		`SELECT min(t.local_date) FROM transactions t JOIN users u ON u.id = t.user_id
		  WHERE t.currency <> u.base_currency AND t.deleted_at IS NULL`).Scan(&oldestNeed); err != nil {
		return err
	}
	if oldestRate == nil || oldestNeed == nil || !oldestNeed.Before(*oldestRate) {
		return nil
	}
	from := *oldestNeed
	if from.Before(ecbStart) {
		from = ecbStart
	}
	for end := oldestRate.AddDate(0, 0, -1); !end.Before(from); end = end.AddDate(0, 0, -90) {
		start := end.AddDate(0, 0, -89)
		if start.Before(from) {
			start = from
		}
		if err := s.download(ctx, start, end); err != nil {
			return err
		}
	}
	return nil
}

func (s *Service) download(ctx context.Context, from, to time.Time) error {
	days, err := s.fetch.Range(ctx, from, to)
	if err != nil {
		return err
	}
	return pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		for d, rates := range days {
			if err := SaveRates(ctx, tx, d, rates); err != nil {
				return err
			}
		}
		return nil
	})
}

// FillMissing gives automatic-rate transactions without a base amount one,
// now that rates may exist. Rows with a manual rate are left to the user.
// Each user's batch takes a new sync version so phones download the values.
func (s *Service) FillMissing(ctx context.Context) (int, error) {
	rows, err := s.db.Query(ctx, `
		SELECT DISTINCT user_id FROM transactions
		 WHERE amount_base_minor IS NULL AND deleted_at IS NULL
		   AND fx_rate_source IS DISTINCT FROM 'manual'`)
	if err != nil {
		return 0, err
	}
	users, err := pgx.CollectRows(rows, pgx.RowTo[uuid.UUID])
	if err != nil {
		return 0, err
	}
	total := 0
	for _, u := range users {
		n, err := s.fillUser(ctx, u)
		total += n
		if err != nil {
			return total, fmt.Errorf("fx: fill user %s: %w", u, err)
		}
	}
	return total, nil
}

func (s *Service) fillUser(ctx context.Context, userID uuid.UUID) (int, error) {
	var after uuid.UUID // keyset cursor
	total := 0
	for {
		n, last, more, err := s.fillBatch(ctx, userID, after)
		total += n
		if err != nil || !more {
			return total, err
		}
		after = last
	}
}

func (s *Service) fillBatch(ctx context.Context, userID, after uuid.UUID) (n int, last uuid.UUID, more bool, err error) {
	err = pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		version, base, err := bumpVersion(ctx, tx, userID)
		if err != nil {
			return err
		}
		rows, err := tx.Query(ctx, `
			SELECT id, amount_minor, currency, local_date FROM transactions
			 WHERE user_id = $1 AND id > $2 AND amount_base_minor IS NULL AND deleted_at IS NULL
			   AND fx_rate_source IS DISTINCT FROM 'manual'
			 ORDER BY id LIMIT $3 FOR UPDATE`, userID, after, batchSize)
		if err != nil {
			return err
		}
		type row struct {
			id       uuid.UUID
			amount   int64
			currency string
			date     time.Time
		}
		list, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (row, error) {
			var x row
			return x, r.Scan(&x.id, &x.amount, &x.currency, &x.date)
		})
		if err != nil {
			return err
		}
		more = len(list) == batchSize
		for _, x := range list {
			last = x.id
			rate, ok, err := Rate(ctx, tx, x.currency, base, x.date)
			if err != nil {
				return err
			}
			if !ok {
				continue
			}
			amt, err := Convert(x.amount, x.currency, base, rate)
			if err != nil {
				continue // leave it empty rather than fail the whole job
			}
			if _, err := tx.Exec(ctx, `
				UPDATE transactions SET fx_rate_to_base = $2::numeric, fx_rate_source = 'auto',
				       amount_base_minor = $3, version = $4
				 WHERE id = $1`, x.id, Format(rate), amt, version); err != nil {
				return err
			}
			n++
		}
		return nil
	})
	return n, last, more, err
}

// bumpVersion takes the user's next sync version under the user's row lock,
// like a sync push, so pulls never skip these changes.
func bumpVersion(ctx context.Context, tx pgx.Tx, userID uuid.UUID) (int64, string, error) {
	var (
		v    int64
		base string
	)
	err := tx.QueryRow(ctx, `
		UPDATE users SET sync_version = sync_version + 1
		 WHERE id = $1 RETURNING sync_version, base_currency`, userID).Scan(&v, &base)
	return v, base, err
}

// BaseAmount works out a new transaction's base-currency amount at push
// time. manualRate is the user's typed rate (nil = automatic). It returns
// nils when no rate is known yet; FillMissing fills those later.
func BaseAmount(ctx context.Context, q Querier, amountMinor int64, currency, base string, day time.Time, manualRate *big.Rat) (rate *string, source *string, amount *int64, err error) {
	src := "auto"
	var r *big.Rat
	switch {
	case currency == base:
		r = big.NewRat(1, 1)
	case manualRate != nil:
		src, r = "manual", Round(manualRate)
	default:
		var ok bool
		r, ok, err = Rate(ctx, q, currency, base, day)
		if err != nil || !ok {
			return nil, nil, nil, err
		}
	}
	a, err := Convert(amountMinor, currency, base, r)
	if err != nil {
		return nil, nil, nil, err
	}
	f := Format(r)
	return &f, &src, &a, nil
}

func day(t time.Time) time.Time {
	t = t.UTC()
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
}
