package datasync

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

type defaultCategory struct {
	name, kind, icon, color string
}

// DefaultCategories every new user starts with. Users can rename, recolour,
// delete or add to them. Icons are Material icon names the app maps to glyphs.
var DefaultCategories = []defaultCategory{
	{"Food & dining", "expense", "restaurant", "#E07A5F"},
	{"Groceries", "expense", "local_grocery_store", "#81B29A"},
	{"Transport", "expense", "directions_bus", "#3D5A80"},
	{"Housing", "expense", "home", "#9C6644"},
	{"Bills & utilities", "expense", "receipt_long", "#5C6B69"},
	{"Shopping", "expense", "shopping_bag", "#C77DFF"},
	{"Health", "expense", "medical_services", "#D62828"},
	{"Entertainment", "expense", "movie", "#F2A541"},
	{"Education", "expense", "school", "#4361EE"},
	{"Travel", "expense", "flight", "#2A9D8F"},
	{"Personal care", "expense", "spa", "#E5989B"},
	{"Gifts & donations", "expense", "card_giftcard", "#B5838D"},
	{"Other", "expense", "more_horiz", "#8D99AE"},
	{"Salary", "income", "payments", "#2F7734"},
	{"Business", "income", "storefront", "#2C706E"},
	{"Freelance", "income", "work", "#729D99"},
	{"Gifts", "income", "redeem", "#B5838D"},
	{"Interest", "income", "savings", "#3D5A80"},
	{"Other income", "income", "attach_money", "#8D99AE"},
}

// SeedDefaultCategories gives a brand-new user the default categories, in
// the same transaction that creates the user. The rows get a sync version,
// so the phone downloads them with its first pull.
func SeedDefaultCategories(ctx context.Context, tx pgx.Tx, userID uuid.UUID) error {
	var version int64
	if err := tx.QueryRow(ctx,
		`UPDATE users SET sync_version = sync_version + 1 WHERE id = $1 RETURNING sync_version`,
		userID).Scan(&version); err != nil {
		return err
	}
	now := time.Now()
	batch := &pgx.Batch{}
	for i, c := range DefaultCategories {
		batch.Queue(
			`INSERT INTO categories (id, user_id, name, kind, icon, color, sort_order, version, updated_at)
			 VALUES (uuidv7(), $1, $2, $3, $4, $5, $6, $7, $8)`,
			userID, c.name, c.kind, c.icon, c.color, i, version, now)
	}
	return tx.SendBatch(ctx, batch).Close()
}
