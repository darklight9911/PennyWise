// Package datasync moves data between the phone and the server.
//
// The phone writes locally first and later pushes its changes; it pulls
// everything newer than its cursor. Sync is the ONLY way synced data is
// written (no separate CRUD endpoints). Rules (PLAN.md section 3):
//   - every push takes the user's next sync_version (row lock: one push per
//     user at a time, so versions always commit in order)
//   - the newer phone edit (updated_at) wins; equal = already applied
//   - updated_at more than 5 minutes in the future is clamped to now
//   - each change succeeds or fails on its own (savepoints)
package datasync

import (
	"encoding/json"
	"time"

	"github.com/google/uuid"
)

// Entity names on the wire, in the order the phone must apply them
// (parents before children).
const (
	EntityAccount     = "account"
	EntityCategory    = "category"
	EntityTransaction = "transaction"
)

var entityOrder = map[string]int{EntityAccount: 0, EntityCategory: 1, EntityTransaction: 2}

// Limits. PullLimit must be larger than MaxPushChanges so a page always
// holds at least one complete version group.
const (
	MaxPushChanges = 500
	PullLimit      = 1000
	maxClockSkew   = 5 * time.Minute
)

// Change is one row sent by the phone.
type Change struct {
	Entity    string          `json:"entity"`
	ID        uuid.UUID       `json:"id"`
	UpdatedAt time.Time       `json:"updated_at"`
	DeletedAt *time.Time      `json:"deleted_at"`
	Data      json.RawMessage `json:"data"`
}

// PushRequest is the body of POST /v1/sync/push.
type PushRequest struct {
	Changes []Change `json:"changes"`
}

// Result statuses.
const (
	StatusApplied  = "applied"  // saved
	StatusStale    = "stale"    // the server already has this edit or a newer one
	StatusRejected = "rejected" // invalid; the phone must not retry it as-is
)

// Result says what happened to one change.
type Result struct {
	Entity string       `json:"entity"`
	ID     uuid.UUID    `json:"id"`
	Status string       `json:"status"`
	Error  *ChangeError `json:"error,omitempty"`
}

// ChangeError explains a rejected change.
type ChangeError struct {
	Code    string `json:"code"`
	Field   string `json:"field,omitempty"`
	Message string `json:"message"`
}

func (e *ChangeError) Error() string { return e.Code + ": " + e.Message }

func reject(code, field, msg string) *ChangeError {
	return &ChangeError{Code: code, Field: field, Message: msg}
}

// PushResponse is the reply to a push.
type PushResponse struct {
	Results []Result `json:"results"`
	// Version given to the applied rows (0 if nothing was applied).
	Version int64 `json:"version"`
}

// PulledChange is one row sent to the phone.
type PulledChange struct {
	Entity    string          `json:"entity"`
	ID        uuid.UUID       `json:"id"`
	Version   int64           `json:"version"`
	UpdatedAt time.Time       `json:"updated_at"`
	DeletedAt *time.Time      `json:"deleted_at"`
	Data      json.RawMessage `json:"data"`
}

// PullResponse is the reply to GET /v1/sync/pull.
type PullResponse struct {
	Changes []PulledChange `json:"changes"`
	// Cursor to send as ?since= next time.
	Cursor  int64 `json:"cursor"`
	HasMore bool  `json:"has_more"`
}

// --- per-entity data ---

// AccountData is the editable part of an account.
type AccountData struct {
	Name                string `json:"name"`
	Type                string `json:"type"`
	Currency            string `json:"currency"`
	OpeningBalanceMinor int64  `json:"opening_balance_minor"`
	Icon                string `json:"icon"`
	Color               string `json:"color"`
	Archived            bool   `json:"archived"`
	SortOrder           int32  `json:"sort_order"`
}

// CategoryData is the editable part of a category.
type CategoryData struct {
	ParentID  *uuid.UUID `json:"parent_id"`
	Name      string     `json:"name"`
	Kind      string     `json:"kind"`
	Icon      string     `json:"icon"`
	Color     string     `json:"color"`
	SortOrder int32      `json:"sort_order"`
}

// TransactionData is the editable part of a transaction. The base-currency
// fields are computed by the server, never sent by the phone.
type TransactionData struct {
	AccountID           uuid.UUID  `json:"account_id"`
	CategoryID          *uuid.UUID `json:"category_id"`
	Kind                string     `json:"kind"`
	AmountMinor         int64      `json:"amount_minor"`
	Currency            string     `json:"currency"`
	TransferAccountID   *uuid.UUID `json:"transfer_account_id"`
	TransferAmountMinor *int64     `json:"transfer_amount_minor"`
	OccurredAt          time.Time  `json:"occurred_at"`
	LocalDate           string     `json:"local_date"` // YYYY-MM-DD in the user's time zone
	Note                string     `json:"note"`
}
