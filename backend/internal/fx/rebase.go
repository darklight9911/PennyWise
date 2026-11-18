package fx

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"time"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
	"github.com/jackc/pgx/v5"
)

// ErrRecalculating means a base-currency change is still being applied.
var ErrRecalculating = errors.New("fx: base currency change still in progress")

// RebasePayload is the TaskRebase job data.
type RebasePayload struct {
	UserID  uuid.UUID `json:"user_id"`
	OldBase string    `json:"old_base"`
}

// Enqueuer queues TaskRebase jobs.
type Enqueuer interface {
	EnqueueContext(ctx context.Context, task *asynq.Task, opts ...asynq.Option) (*asynq.TaskInfo, error)
}

// ChangeBase switches the user's base currency and queues the job that
// recomputes every stored base amount. Until it finishes the user's
// base_currency_status is "recalculating" and phones show that instead of
// totals. A second change while one runs gets ErrRecalculating.
func ChangeBase(ctx context.Context, q Querier, queue Enqueuer, userID uuid.UUID, newBase string) error {
	var oldBase string
	err := q.QueryRow(ctx, `
		WITH old AS (SELECT base_currency FROM users WHERE id = $1 AND base_currency_status = 'ok' FOR UPDATE)
		UPDATE users u SET base_currency = $2, base_currency_status = 'recalculating'
		  FROM old WHERE u.id = $1 AND old.base_currency <> $2
		RETURNING old.base_currency`, userID, newBase).Scan(&oldBase)
	if errors.Is(err, pgx.ErrNoRows) {
		// Same currency (nothing to do) or a change already running.
		var status, cur string
		if err := q.QueryRow(ctx, `SELECT base_currency_status, base_currency FROM users WHERE id = $1`, userID).Scan(&status, &cur); err != nil {
			return err
		}
		if status != "ok" {
			return ErrRecalculating
		}
		return nil
	}
	if err != nil {
		return err
	}
	payload, _ := json.Marshal(RebasePayload{UserID: userID, OldBase: oldBase})
	_, err = queue.EnqueueContext(ctx, asynq.NewTask(TaskRebase, payload),
		asynq.MaxRetry(20), asynq.Timeout(30*time.Minute), asynq.Queue("critical"))
	return err
}

// HandleRebase is the asynq handler for TaskRebase. It is safe to run again
// after a crash: every row is recomputed from its own currency and date.
func (s *Service) HandleRebase(ctx context.Context, t *asynq.Task) error {
	var p RebasePayload
	if err := json.Unmarshal(t.Payload(), &p); err != nil {
		return fmt.Errorf("fx: rebase payload: %w: %w", err, asynq.SkipRetry)
	}
	return s.Rebase(ctx, p.UserID, p.OldBase)
}

// Rebase recomputes the user's transactions (rate on each one's date;
// manual rates go through the old base so the typed rate is kept) and
// converts budgets and goals at today's rate. Then the status is "ok".
func (s *Service) Rebase(ctx context.Context, userID uuid.UUID, oldBase string) error {
	var after uuid.UUID
	for {
		last, more, err := s.rebaseBatch(ctx, userID, oldBase, after)
		if err != nil {
			return err
		}
		if !more {
			break
		}
		after = last
	}
	return pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		version, base, err := bumpVersion(ctx, tx, userID)
		if err != nil {
			return err
		}
		if base != oldBase {
			rate, ok, err := Rate(ctx, tx, oldBase, base, s.now())
			if err != nil {
				return err
			}
			if ok {
				for _, t := range []struct{ table, col string }{
					{"budgets", "amount_minor"}, {"goals", "target_minor"}, {"goal_contributions", "amount_minor"},
				} {
					if err := convertColumn(ctx, tx, t.table, t.col, userID, oldBase, base, rate, version); err != nil {
						return err
					}
				}
			} else {
				s.log.WarnContext(ctx, "fx: no rate to convert budgets and goals", "from", oldBase, "to", base)
			}
		}
		_, err = tx.Exec(ctx, `UPDATE users SET base_currency_status = 'ok' WHERE id = $1`, userID)
		return err
	})
}

func (s *Service) rebaseBatch(ctx context.Context, userID uuid.UUID, oldBase string, after uuid.UUID) (last uuid.UUID, more bool, err error) {
	err = pgx.BeginFunc(ctx, s.db, func(tx pgx.Tx) error {
		version, base, err := bumpVersion(ctx, tx, userID)
		if err != nil {
			return err
		}
		rows, err := tx.Query(ctx, `
			SELECT id, amount_minor, currency, local_date, fx_rate_to_base::text, fx_rate_source
			  FROM transactions
			 WHERE user_id = $1 AND id > $2 AND deleted_at IS NULL
			 ORDER BY id LIMIT $3 FOR UPDATE`, userID, after, batchSize)
		if err != nil {
			return err
		}
		type row struct {
			id       uuid.UUID
			amount   int64
			currency string
			date     time.Time
			rate     *string
			source   *string
		}
		list, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (row, error) {
			var x row
			return x, r.Scan(&x.id, &x.amount, &x.currency, &x.date, &x.rate, &x.source)
		})
		if err != nil {
			return err
		}
		more = len(list) == batchSize
		for _, x := range list {
			last = x.id
			var manual *big.Rat
			if x.source != nil && *x.source == "manual" && x.currency != base {
				manual, err = s.carryManual(ctx, tx, x.rate, oldBase, base, x.date)
				if err != nil {
					return err
				}
				if manual == nil {
					// Typed rate cannot be carried over: ask the user again.
					if _, err := tx.Exec(ctx, `
						UPDATE transactions SET fx_rate_to_base = NULL, amount_base_minor = NULL,
						       fx_rate_source = 'manual', version = $2 WHERE id = $1`, x.id, version); err != nil {
						return err
					}
					continue
				}
			}
			rate, src, amt, err := BaseAmount(ctx, tx, x.amount, x.currency, base, x.date, manual)
			if err != nil {
				return err
			}
			if _, err := tx.Exec(ctx, `
				UPDATE transactions SET fx_rate_to_base = $2::numeric, fx_rate_source = $3,
				       amount_base_minor = $4, version = $5 WHERE id = $1`,
				x.id, rate, src, amt, version); err != nil {
				return err
			}
		}
		return nil
	})
	return last, more, err
}

// carryManual turns a typed rate (currency -> old base) into currency ->
// new base through the old base. nil when that is not possible.
func (s *Service) carryManual(ctx context.Context, q Querier, typed *string, oldBase, newBase string, day time.Time) (*big.Rat, error) {
	if typed == nil {
		return nil, nil
	}
	r, ok := new(big.Rat).SetString(*typed)
	if !ok {
		return nil, nil
	}
	via, ok, err := Rate(ctx, q, oldBase, newBase, day)
	if err != nil || !ok {
		return nil, err
	}
	return new(big.Rat).Mul(r, via), nil
}

// convertColumn converts one base-currency amount column of the user's rows.
// table and col are constants from Rebase, never user input.
func convertColumn(ctx context.Context, tx pgx.Tx, table, col string, userID uuid.UUID, from, to string, rate *big.Rat, version int64) error {
	rows, err := tx.Query(ctx, fmt.Sprintf(
		`SELECT id, %s FROM %s WHERE user_id = $1 AND deleted_at IS NULL FOR UPDATE`, col, table), userID)
	if err != nil {
		return err
	}
	type row struct {
		id  uuid.UUID
		amt int64
	}
	list, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (row, error) {
		var x row
		return x, r.Scan(&x.id, &x.amt)
	})
	if err != nil {
		return err
	}
	for _, x := range list {
		v, err := Convert(x.amt, from, to, rate)
		if err != nil {
			return err
		}
		if v == 0 { // the tables reject zero; keep the smallest amount instead
			v = 1
			if x.amt < 0 {
				v = -1
			}
		}
		if _, err := tx.Exec(ctx, fmt.Sprintf(
			`UPDATE %s SET %s = $2, version = $3 WHERE id = $1`, table, col), x.id, v, version); err != nil {
			return err
		}
	}
	return nil
}
