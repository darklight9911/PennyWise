package datasync

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"slices"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Errors for the whole request (single changes fail with a Result instead).
var (
	ErrTooManyChanges = fmt.Errorf("datasync: at most %d changes per push", MaxPushChanges)
	ErrUserNotFound   = errors.New("datasync: user not found")
)

// Service implements push and pull.
type Service struct {
	pool   *pgxpool.Pool
	logger *slog.Logger
	now    func() time.Time
}

// NewService creates the sync service.
func NewService(pool *pgxpool.Pool, logger *slog.Logger) *Service {
	return &Service{pool: pool, logger: logger, now: time.Now}
}

// Push saves the phone's changes. Each change gets its own Result.
func (s *Service) Push(ctx context.Context, userID uuid.UUID, req PushRequest) (PushResponse, error) {
	if len(req.Changes) > MaxPushChanges {
		return PushResponse{}, ErrTooManyChanges
	}
	resp := PushResponse{Results: make([]Result, 0, len(req.Changes))}
	if len(req.Changes) == 0 {
		return resp, nil
	}

	// Parents before children, so a new account and its first transaction
	// can arrive in the same push. Stable: keeps the phone's order otherwise.
	changes := slices.Clone(req.Changes)
	slices.SortStableFunc(changes, func(a, b Change) int { return order(a.Entity) - order(b.Entity) })

	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var (
			version int64
			base    string
		)
		// Row lock on the user: pushes of one user run one after another,
		// so their versions commit in order (PLAN.md section 3).
		err := tx.QueryRow(ctx,
			`UPDATE users SET sync_version = sync_version + 1
			 WHERE id = $1 AND deleted_at IS NULL
			 RETURNING sync_version, base_currency`, userID).Scan(&version, &base)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrUserNotFound
		}
		if err != nil {
			return err
		}

		applied := false
		for _, ch := range changes {
			res := Result{Entity: ch.Entity, ID: ch.ID}
			status, cerr, err := s.applyOne(ctx, tx, userID, version, base, ch)
			if err != nil {
				return err
			}
			res.Status, res.Error = status, cerr
			applied = applied || status == StatusApplied
			resp.Results = append(resp.Results, res)
		}
		if applied {
			resp.Version = version
		}
		return nil
	})
	if err != nil {
		return PushResponse{}, err
	}
	return resp, nil
}

func order(entity string) int {
	if o, ok := entityOrder[entity]; ok {
		return o
	}
	return len(entityOrder)
}

// applyOne saves one change inside its own savepoint. It returns an
// internal error only for real failures (the whole push then fails).
func (s *Service) applyOne(ctx context.Context, tx pgx.Tx, userID uuid.UUID, version int64, base string, ch Change) (string, *ChangeError, error) {
	if ch.ID == uuid.Nil {
		return StatusRejected, reject("invalid", "id", "id is required"), nil
	}
	if ch.UpdatedAt.IsZero() {
		return StatusRejected, reject("invalid", "updated_at", "updated_at is required"), nil
	}
	now := s.now()
	// A phone with its clock far in the future would win every conflict.
	updatedAt := clamp(ch.UpdatedAt, now)
	var deletedAt *time.Time
	if ch.DeletedAt != nil {
		d := clamp(*ch.DeletedAt, now)
		deletedAt = &d
	}

	sp, err := tx.Begin(ctx) // savepoint
	if err != nil {
		return "", nil, err
	}
	row := rowMeta{userID: userID, id: ch.ID, version: version, updatedAt: updatedAt, deletedAt: deletedAt}

	var (
		ok   bool
		cerr *ChangeError
	)
	switch ch.Entity {
	case EntityAccount:
		ok, cerr, err = upsertAccount(ctx, sp, row, ch.Data)
	case EntityCategory:
		ok, cerr, err = upsertCategory(ctx, sp, row, ch.Data)
	case EntityTransaction:
		ok, cerr, err = upsertTransaction(ctx, sp, row, base, ch.Data)
	case EntityBudget:
		ok, cerr, err = upsertBudget(ctx, sp, row, ch.Data)
	default:
		cerr = reject("invalid", "entity", "entity must be account, category, transaction or budget")
	}

	if err != nil {
		_ = sp.Rollback(ctx)
		if mapped := dbErrorToChangeError(err); mapped != nil {
			return StatusRejected, mapped, nil
		}
		return "", nil, err
	}
	if cerr != nil {
		_ = sp.Rollback(ctx)
		return StatusRejected, cerr, nil
	}
	if !ok {
		// Nothing written: either the server's copy is newer/equal, or the
		// id belongs to another user (never overwrite someone else's row).
		_ = sp.Rollback(ctx)
		mine, err := ownedByUser(ctx, tx, ch.Entity, ch.ID, userID)
		if err != nil {
			return "", nil, err
		}
		if !mine {
			return StatusRejected, reject("id_taken", "id", "this id is already used"), nil
		}
		return StatusStale, nil, nil
	}
	if err := sp.Commit(ctx); err != nil {
		return "", nil, err
	}
	return StatusApplied, nil, nil
}

type rowMeta struct {
	userID    uuid.UUID
	id        uuid.UUID
	version   int64
	updatedAt time.Time
	deletedAt *time.Time
}

func clamp(t, now time.Time) time.Time {
	if t.After(now.Add(maxClockSkew)) {
		return now
	}
	return t
}

// --- accounts ---

const upsertAccountSQL = `
INSERT INTO accounts (id, user_id, name, type, currency, opening_balance_minor,
                      icon, color, archived, sort_order, version, updated_at, deleted_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name, type = EXCLUDED.type, currency = EXCLUDED.currency,
    opening_balance_minor = EXCLUDED.opening_balance_minor, icon = EXCLUDED.icon,
    color = EXCLUDED.color, archived = EXCLUDED.archived, sort_order = EXCLUDED.sort_order,
    version = EXCLUDED.version, updated_at = EXCLUDED.updated_at, deleted_at = EXCLUDED.deleted_at
WHERE accounts.user_id = EXCLUDED.user_id AND accounts.updated_at < EXCLUDED.updated_at
RETURNING id`

func upsertAccount(ctx context.Context, tx pgx.Tx, r rowMeta, data []byte) (bool, *ChangeError, error) {
	var d AccountData
	if cerr := decodeStrict(data, &d); cerr != nil {
		return false, cerr, nil
	}
	if cerr := validateAccount(&d); cerr != nil {
		return false, cerr, nil
	}
	// The currency of an account with transactions cannot change: every
	// amount in it would silently mean something else.
	var current string
	err := tx.QueryRow(ctx, `SELECT currency FROM accounts WHERE id = $1 AND user_id = $2`, r.id, r.userID).Scan(&current)
	switch {
	case errors.Is(err, pgx.ErrNoRows):
	case err != nil:
		return false, nil, err
	case current != d.Currency:
		var used bool
		if err := tx.QueryRow(ctx,
			`SELECT EXISTS (SELECT 1 FROM transactions
			  WHERE (account_id = $1 OR transfer_account_id = $1) AND deleted_at IS NULL)`, r.id).Scan(&used); err != nil {
			return false, nil, err
		}
		if used {
			return false, reject("currency_locked", "currency", "an account with transactions cannot change its currency"), nil
		}
	}
	return execUpsert(ctx, tx, upsertAccountSQL, r.id, r.userID, d.Name, d.Type, d.Currency,
		d.OpeningBalanceMinor, d.Icon, d.Color, d.Archived, d.SortOrder, r.version, r.updatedAt, r.deletedAt)
}

// --- categories ---

const upsertCategorySQL = `
INSERT INTO categories (id, user_id, parent_id, name, kind, icon, color, sort_order,
                        version, updated_at, deleted_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
ON CONFLICT (id) DO UPDATE SET
    parent_id = EXCLUDED.parent_id, name = EXCLUDED.name, kind = EXCLUDED.kind,
    icon = EXCLUDED.icon, color = EXCLUDED.color, sort_order = EXCLUDED.sort_order,
    version = EXCLUDED.version, updated_at = EXCLUDED.updated_at, deleted_at = EXCLUDED.deleted_at
WHERE categories.user_id = EXCLUDED.user_id AND categories.updated_at < EXCLUDED.updated_at
RETURNING id`

func upsertCategory(ctx context.Context, tx pgx.Tx, r rowMeta, data []byte) (bool, *ChangeError, error) {
	var d CategoryData
	if cerr := decodeStrict(data, &d); cerr != nil {
		return false, cerr, nil
	}
	if cerr := validateCategory(&d); cerr != nil {
		return false, cerr, nil
	}
	if d.ParentID != nil {
		if *d.ParentID == r.id {
			return false, reject("invalid", "parent_id", "a category cannot be its own parent"), nil
		}
		// One level only: a parent must be a top-level category of the same kind.
		var (
			kind        string
			grandparent *uuid.UUID
		)
		err := tx.QueryRow(ctx, `SELECT kind, parent_id FROM categories WHERE id = $1 AND user_id = $2`,
			*d.ParentID, r.userID).Scan(&kind, &grandparent)
		if errors.Is(err, pgx.ErrNoRows) {
			return false, reject("reference_not_found", "parent_id", "parent category not found"), nil
		}
		if err != nil {
			return false, nil, err
		}
		if grandparent != nil {
			return false, reject("invalid", "parent_id", "sub-categories can only be one level deep"), nil
		}
		if kind != d.Kind {
			return false, reject("invalid", "parent_id", "parent must have the same kind (income or expense)"), nil
		}
	}
	return execUpsert(ctx, tx, upsertCategorySQL, r.id, r.userID, d.ParentID, d.Name, d.Kind,
		d.Icon, d.Color, d.SortOrder, r.version, r.updatedAt, r.deletedAt)
}

// --- transactions ---

const upsertTransactionSQL = `
INSERT INTO transactions (id, user_id, account_id, category_id, kind, amount_minor, currency,
                          fx_rate_to_base, fx_rate_source, amount_base_minor,
                          transfer_account_id, transfer_amount_minor, occurred_at, local_date,
                          note, version, updated_at, deleted_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)
ON CONFLICT (id) DO UPDATE SET
    account_id = EXCLUDED.account_id, category_id = EXCLUDED.category_id, kind = EXCLUDED.kind,
    amount_minor = EXCLUDED.amount_minor, currency = EXCLUDED.currency,
    fx_rate_to_base = EXCLUDED.fx_rate_to_base, fx_rate_source = EXCLUDED.fx_rate_source,
    amount_base_minor = EXCLUDED.amount_base_minor,
    transfer_account_id = EXCLUDED.transfer_account_id,
    transfer_amount_minor = EXCLUDED.transfer_amount_minor,
    occurred_at = EXCLUDED.occurred_at, local_date = EXCLUDED.local_date, note = EXCLUDED.note,
    version = EXCLUDED.version, updated_at = EXCLUDED.updated_at, deleted_at = EXCLUDED.deleted_at
WHERE transactions.user_id = EXCLUDED.user_id AND transactions.updated_at < EXCLUDED.updated_at
RETURNING id`

func upsertTransaction(ctx context.Context, tx pgx.Tx, r rowMeta, base string, data []byte) (bool, *ChangeError, error) {
	var d TransactionData
	if cerr := decodeStrict(data, &d); cerr != nil {
		return false, cerr, nil
	}
	if cerr := validateTransaction(&d); cerr != nil {
		return false, cerr, nil
	}

	acctCurrency, found, err := accountCurrency(ctx, tx, d.AccountID, r.userID)
	if err != nil {
		return false, nil, err
	}
	if !found {
		return false, reject("reference_not_found", "account_id", "account not found"), nil
	}
	if acctCurrency != d.Currency {
		return false, reject("invalid", "currency", "currency must match the account's currency ("+acctCurrency+")"), nil
	}

	if d.Kind == transferKind {
		targetCurrency, found, err := accountCurrency(ctx, tx, *d.TransferAccountID, r.userID)
		if err != nil {
			return false, nil, err
		}
		if !found {
			return false, reject("reference_not_found", "transfer_account_id", "target account not found"), nil
		}
		if targetCurrency == d.Currency && *d.TransferAmountMinor != d.AmountMinor {
			return false, reject("invalid", "transfer_amount_minor", "same-currency transfers must receive the amount sent"), nil
		}
	} else {
		var kind string
		err := tx.QueryRow(ctx, `SELECT kind FROM categories WHERE id = $1 AND user_id = $2`, *d.CategoryID, r.userID).Scan(&kind)
		if errors.Is(err, pgx.ErrNoRows) {
			return false, reject("reference_not_found", "category_id", "category not found"), nil
		}
		if err != nil {
			return false, nil, err
		}
		if kind != d.Kind {
			return false, reject("invalid", "category_id", "category kind must match ("+d.Kind+")"), nil
		}
	}

	// Amount in the user's base currency. Same currency: rate 1.
	// Other currencies get rates in Milestone 6 (left empty until then).
	var (
		rate, source *string
		baseAmount   *int64
	)
	if d.Currency == base {
		one, auto := "1", "auto"
		rate, source, baseAmount = &one, &auto, &d.AmountMinor
	}

	return execUpsert(ctx, tx, upsertTransactionSQL, r.id, r.userID, d.AccountID, d.CategoryID, d.Kind,
		d.AmountMinor, d.Currency, rate, source, baseAmount, d.TransferAccountID, d.TransferAmountMinor,
		d.OccurredAt, d.LocalDate, d.Note, r.version, r.updatedAt, r.deletedAt)
}

func accountCurrency(ctx context.Context, tx pgx.Tx, id, userID uuid.UUID) (string, bool, error) {
	var c string
	err := tx.QueryRow(ctx, `SELECT currency FROM accounts WHERE id = $1 AND user_id = $2`, id, userID).Scan(&c)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", false, nil
	}
	return c, err == nil, err
}

// --- budgets ---

const upsertBudgetSQL = `
INSERT INTO budgets (id, user_id, category_id, amount_minor, period, alert_thresholds,
                     version, updated_at, deleted_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
ON CONFLICT (id) DO UPDATE SET
    category_id = EXCLUDED.category_id, amount_minor = EXCLUDED.amount_minor,
    period = EXCLUDED.period, alert_thresholds = EXCLUDED.alert_thresholds,
    version = EXCLUDED.version, updated_at = EXCLUDED.updated_at, deleted_at = EXCLUDED.deleted_at
WHERE budgets.user_id = EXCLUDED.user_id AND budgets.updated_at < EXCLUDED.updated_at
RETURNING id`

func upsertBudget(ctx context.Context, tx pgx.Tx, r rowMeta, data []byte) (bool, *ChangeError, error) {
	var d BudgetData
	if cerr := decodeStrict(data, &d); cerr != nil {
		return false, cerr, nil
	}
	if cerr := validateBudget(&d); cerr != nil {
		return false, cerr, nil
	}
	if d.CategoryID != nil {
		var kind string
		err := tx.QueryRow(ctx, `SELECT kind FROM categories WHERE id = $1 AND user_id = $2`, *d.CategoryID, r.userID).Scan(&kind)
		if errors.Is(err, pgx.ErrNoRows) {
			return false, reject("reference_not_found", "category_id", "category not found"), nil
		}
		if err != nil {
			return false, nil, err
		}
		if kind != "expense" {
			return false, reject("invalid", "category_id", "budgets are for expense categories"), nil
		}
	}
	return execUpsert(ctx, tx, upsertBudgetSQL, r.id, r.userID, d.CategoryID, d.AmountMinor,
		d.Period, d.AlertThresholds, r.version, r.updatedAt, r.deletedAt)
}

// --- helpers ---

// execUpsert runs an INSERT ... ON CONFLICT ... RETURNING id. It reports
// false when the conflict rule skipped the row (stale or someone else's).
func execUpsert(ctx context.Context, tx pgx.Tx, sql string, args ...any) (bool, *ChangeError, error) {
	var id uuid.UUID
	err := tx.QueryRow(ctx, sql, args...).Scan(&id)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil, nil
	}
	if err != nil {
		return false, nil, err
	}
	return true, nil, nil
}

var tables = map[string]string{
	EntityAccount: "accounts", EntityCategory: "categories", EntityTransaction: "transactions",
	EntityBudget: "budgets",
}

func ownedByUser(ctx context.Context, tx pgx.Tx, entity string, id, userID uuid.UUID) (bool, error) {
	table, ok := tables[entity]
	if !ok {
		return false, nil
	}
	var owner uuid.UUID
	err := tx.QueryRow(ctx, `SELECT user_id FROM `+table+` WHERE id = $1`, id).Scan(&owner)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return owner == userID, nil
}

// dbErrorToChangeError turns constraint violations into a rejection of
// that one change. Anything else is a real error.
func dbErrorToChangeError(err error) *ChangeError {
	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) {
		return nil
	}
	switch pgErr.Code {
	case "23503": // foreign_key_violation
		return reject("reference_not_found", "", "a referenced row does not exist")
	case "23514": // check_violation
		return reject("invalid", "", "the row breaks a rule ("+pgErr.ConstraintName+")")
	case "23505": // unique_violation
		return reject("duplicate", "", "a row like this already exists")
	case "22007", "22008", "22P02": // bad date/time or text representation
		return reject("invalid", "", "a value has the wrong format")
	}
	return nil
}
