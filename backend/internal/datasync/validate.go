package datasync

import (
	"bytes"
	"encoding/json"
	"slices"
	"strings"
	"time"
	"unicode/utf8"

	"pennywise/backend/internal/money"
)

// maxAmountMinor keeps amounts far from int64 overflow when summed
// (10^15 minor units = 10 trillion dollars).
const maxAmountMinor = 1_000_000_000_000_000

var (
	accountTypes     = map[string]bool{"cash": true, "bank": true, "card": true, "ewallet": true, "savings": true, "other": true}
	categoryKinds    = map[string]bool{"income": true, "expense": true}
	transferKind     = "transfer"
	transactionKinds = map[string]bool{"income": true, "expense": true, transferKind: true}
)

// decodeStrict parses data into dst, rejecting unknown fields
// (a typo must not be silently dropped).
func decodeStrict(data json.RawMessage, dst any) *ChangeError {
	if len(data) == 0 {
		return reject("invalid", "data", "data is required")
	}
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		return reject("invalid", "data", "data is not valid: "+err.Error())
	}
	return nil
}

func validateAccount(d *AccountData) *ChangeError {
	d.Name = strings.TrimSpace(d.Name)
	if n := utf8.RuneCountInString(d.Name); n < 1 || n > 60 {
		return reject("invalid", "name", "name must be 1 to 60 characters")
	}
	if !accountTypes[d.Type] {
		return reject("invalid", "type", "type must be cash, bank, card, ewallet, savings or other")
	}
	if _, err := money.Exponent(d.Currency); err != nil {
		return reject("invalid", "currency", "currency must be a 3-letter ISO 4217 code")
	}
	if d.OpeningBalanceMinor > maxAmountMinor || d.OpeningBalanceMinor < -maxAmountMinor {
		return reject("invalid", "opening_balance_minor", "opening balance is too large")
	}
	return validateLook(&d.Icon, &d.Color)
}

func validateCategory(d *CategoryData) *ChangeError {
	d.Name = strings.TrimSpace(d.Name)
	if n := utf8.RuneCountInString(d.Name); n < 1 || n > 40 {
		return reject("invalid", "name", "name must be 1 to 40 characters")
	}
	if !categoryKinds[d.Kind] {
		return reject("invalid", "kind", "kind must be income or expense")
	}
	return validateLook(&d.Icon, &d.Color)
}

func validateTransaction(d *TransactionData) *ChangeError {
	if !transactionKinds[d.Kind] {
		return reject("invalid", "kind", "kind must be income, expense or transfer")
	}
	if d.AmountMinor <= 0 || d.AmountMinor > maxAmountMinor {
		return reject("invalid", "amount_minor", "amount must be positive (the kind says in or out)")
	}
	if _, err := money.Exponent(d.Currency); err != nil {
		return reject("invalid", "currency", "currency must be a 3-letter ISO 4217 code")
	}
	if d.OccurredAt.IsZero() {
		return reject("invalid", "occurred_at", "occurred_at is required")
	}
	if _, err := time.Parse(time.DateOnly, d.LocalDate); err != nil {
		return reject("invalid", "local_date", "local_date must be YYYY-MM-DD")
	}
	if utf8.RuneCountInString(d.Note) > 500 {
		return reject("invalid", "note", "note must be at most 500 characters")
	}
	if d.Kind == transferKind {
		if d.TransferAccountID == nil || d.TransferAmountMinor == nil {
			return reject("invalid", "transfer_account_id", "a transfer needs a target account and amount")
		}
		if *d.TransferAccountID == d.AccountID {
			return reject("invalid", "transfer_account_id", "a transfer needs two different accounts")
		}
		if *d.TransferAmountMinor <= 0 || *d.TransferAmountMinor > maxAmountMinor {
			return reject("invalid", "transfer_amount_minor", "transfer amount must be positive")
		}
		if d.CategoryID != nil {
			return reject("invalid", "category_id", "a transfer has no category")
		}
		return nil
	}
	if d.CategoryID == nil {
		return reject("invalid", "category_id", "income and expenses need a category")
	}
	if d.TransferAccountID != nil || d.TransferAmountMinor != nil {
		return reject("invalid", "transfer_account_id", "only transfers have a target account")
	}
	return nil
}

func validateLook(icon, color *string) *ChangeError {
	if utf8.RuneCountInString(*icon) > 40 {
		return reject("invalid", "icon", "icon name is too long")
	}
	*color = strings.ToUpper(strings.TrimSpace(*color))
	if *color != "" && !isHexColor(*color) {
		return reject("invalid", "color", "color must look like #2C706E")
	}
	return nil
}

func isHexColor(s string) bool {
	if len(s) != 7 || s[0] != '#' {
		return false
	}
	for _, c := range s[1:] {
		if !(c >= '0' && c <= '9' || c >= 'A' && c <= 'F') {
			return false
		}
	}
	return true
}

var budgetPeriods = map[string]bool{"weekly": true, "monthly": true}

func validateBudget(d *BudgetData) *ChangeError {
	if d.AmountMinor <= 0 || d.AmountMinor > maxAmountMinor {
		return reject("invalid", "amount_minor", "budget amount must be positive")
	}
	if !budgetPeriods[d.Period] {
		return reject("invalid", "period", "period must be weekly or monthly")
	}
	if d.AlertThresholds == nil {
		d.AlertThresholds = []int32{80, 100}
	}
	if len(d.AlertThresholds) > 5 {
		return reject("invalid", "alert_thresholds", "at most 5 alert levels")
	}
	seen := map[int32]bool{}
	clean := make([]int32, 0, len(d.AlertThresholds))
	for _, t := range d.AlertThresholds {
		if t < 1 || t > 200 {
			return reject("invalid", "alert_thresholds", "alert levels must be 1 to 200 percent")
		}
		if !seen[t] {
			seen[t] = true
			clean = append(clean, t)
		}
	}
	slices.Sort(clean)
	d.AlertThresholds = clean
	return nil
}
