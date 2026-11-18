package datasync

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// One query over all synced tables, ordered by version, then parents before
// children. Only rows with version <= the user's COMMITTED sync_version are
// read: a push still in progress holds a higher version and is not visible
// yet, so a phone can never skip a row (PLAN.md section 3).
const pullSQL = `
SELECT entity, id, version, updated_at, deleted_at, data FROM (
    SELECT 'account' AS entity, 0 AS ord, id, version, updated_at, deleted_at,
           jsonb_build_object(
               'name', name, 'type', type, 'currency', currency,
               'opening_balance_minor', opening_balance_minor, 'icon', icon, 'color', color,
               'archived', archived, 'sort_order', sort_order) AS data
      FROM accounts WHERE user_id = $1 AND version > $2 AND version <= $3
    UNION ALL
    SELECT 'category', 1, id, version, updated_at, deleted_at,
           jsonb_build_object(
               'parent_id', parent_id, 'name', name, 'kind', kind, 'icon', icon,
               'color', color, 'sort_order', sort_order)
      FROM categories WHERE user_id = $1 AND version > $2 AND version <= $3
    UNION ALL
    SELECT 'transaction', 3, id, version, updated_at, deleted_at,
           jsonb_build_object(
               'account_id', account_id, 'category_id', category_id, 'kind', kind,
               'amount_minor', amount_minor, 'currency', currency,
               'fx_rate_to_base', fx_rate_to_base::text, 'fx_rate_source', fx_rate_source,
               'amount_base_minor', amount_base_minor,
               'transfer_account_id', transfer_account_id,
               'transfer_amount_minor', transfer_amount_minor,
               'occurred_at', occurred_at, 'local_date', to_char(local_date, 'YYYY-MM-DD'),
               'note', note, 'recurring_id', recurring_id,
               'occurrence_date', to_char(occurrence_date, 'YYYY-MM-DD'))
      FROM transactions WHERE user_id = $1 AND version > $2 AND version <= $3
    UNION ALL
    SELECT 'budget', 4, id, version, updated_at, deleted_at,
           jsonb_build_object(
               'category_id', category_id, 'amount_minor', amount_minor,
               'period', period, 'alert_thresholds', alert_thresholds)
      FROM budgets WHERE user_id = $1 AND version > $2 AND version <= $3
    UNION ALL
    SELECT 'recurring_rule', 2, id, version, updated_at, deleted_at,
           jsonb_build_object(
               'kind', kind, 'account_id', account_id, 'category_id', category_id,
               'amount_minor', amount_minor, 'currency', currency, 'note', note,
               'frequency', frequency, 'every', every,
               'start_date', to_char(start_date, 'YYYY-MM-DD'),
               'end_date', to_char(end_date, 'YYYY-MM-DD'),
               'remind_days_before', remind_days_before, 'active', active)
      FROM recurring_rules WHERE user_id = $1 AND version > $2 AND version <= $3
    UNION ALL
    SELECT 'goal', 5, id, version, updated_at, deleted_at,
           jsonb_build_object(
               'name', name, 'target_minor', target_minor,
               'deadline', to_char(deadline, 'YYYY-MM-DD'),
               'icon', icon, 'color', color, 'archived', archived)
      FROM goals WHERE user_id = $1 AND version > $2 AND version <= $3
    UNION ALL
    SELECT 'goal_contribution', 6, id, version, updated_at, deleted_at,
           jsonb_build_object(
               'goal_id', goal_id, 'amount_minor', amount_minor,
               'local_date', to_char(local_date, 'YYYY-MM-DD'), 'note', note)
      FROM goal_contributions WHERE user_id = $1 AND version > $2 AND version <= $3
    UNION ALL
    -- Read-only for phones (the receipts API writes them). Only files the
    -- API has seen in storage, and tombstones.
    SELECT 'receipt', 7, id, version, updated_at, deleted_at,
           jsonb_build_object(
               'transaction_id', transaction_id, 'content_type', content_type,
               'size_bytes', size_bytes)
      FROM receipts WHERE user_id = $1 AND version > $2 AND version <= $3
                      AND (status = 'uploaded' OR deleted_at IS NOT NULL)
) rows
ORDER BY version, ord, id
LIMIT $4`

// Pull returns the user's rows changed after version `since`.
func (s *Service) Pull(ctx context.Context, userID uuid.UUID, since int64) (PullResponse, error) {
	if since < 0 {
		since = 0
	}
	var upTo int64
	err := s.pool.QueryRow(ctx, `SELECT sync_version FROM users WHERE id = $1 AND deleted_at IS NULL`, userID).Scan(&upTo)
	if errors.Is(err, pgx.ErrNoRows) {
		return PullResponse{}, ErrUserNotFound
	}
	if err != nil {
		return PullResponse{}, err
	}

	changes, err := s.query(ctx, userID, since, upTo, PullLimit+1)
	if err != nil {
		return PullResponse{}, err
	}
	resp := PullResponse{Changes: changes, Cursor: upTo}
	if len(changes) <= PullLimit {
		return resp, nil // everything up to upTo
	}

	// More than one page. Rows of one push share a version, and a page must
	// not stop in the middle of one: drop the last (maybe partial) group.
	resp.HasMore = true
	last := changes[PullLimit].Version
	cut := len(changes)
	for cut > 0 && changes[cut-1].Version == last {
		cut--
	}
	if cut == 0 {
		// One group bigger than a page (cannot happen while PullLimit >
		// MaxPushChanges, but never return a broken page): send it whole.
		group, err := s.query(ctx, userID, last-1, last, 1<<31-1)
		if err != nil {
			return PullResponse{}, err
		}
		resp.Changes, resp.Cursor = group, last
		resp.HasMore = last < upTo
		return resp, nil
	}
	resp.Changes = changes[:cut]
	resp.Cursor = changes[cut-1].Version
	return resp, nil
}

func (s *Service) query(ctx context.Context, userID uuid.UUID, since, upTo int64, limit int) ([]PulledChange, error) {
	rows, err := s.pool.Query(ctx, pullSQL, userID, since, upTo, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	changes := []PulledChange{}
	for rows.Next() {
		var (
			c       PulledChange
			deleted *time.Time
			data    []byte
		)
		if err := rows.Scan(&c.Entity, &c.ID, &c.Version, &c.UpdatedAt, &deleted, &data); err != nil {
			return nil, err
		}
		c.UpdatedAt = c.UpdatedAt.UTC()
		if deleted != nil {
			d := deleted.UTC()
			c.DeletedAt = &d
		}
		c.Data = json.RawMessage(data)
		changes = append(changes, c)
	}
	return changes, rows.Err()
}
