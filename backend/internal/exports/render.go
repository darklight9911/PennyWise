package exports

import (
	"bytes"
	"context"
	"encoding/csv"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"pennywise/backend/internal/fx"
	"pennywise/backend/internal/money"
	"pennywise/backend/internal/reports"
)

// Row limits per file. A bigger range should be split (or use CSV).
const (
	MaxCSVRows = 200000
	MaxPDFRows = 20000
)

// row is one transaction with its names, as exported.
type row struct {
	Date        time.Time
	Kind        string
	Account     string
	Category    string // "Food › Cafe" for sub-categories
	Note        string
	AmountMinor int64
	Currency    string
	BaseMinor   *int64
	Rate        *string
	RateSource  *string
	ToAccount   *string
	ToCurrency  *string
	ToAmount    *int64
	Person      *string // the due's person, for loan payments
}

func loadRows(ctx context.Context, q fx.Querier, userID uuid.UUID, r reports.Range, limit int) ([]row, error) {
	rows, err := q.Query(ctx, `
		SELECT t.local_date, t.kind, a.name, COALESCE(pc.name || ' › ' || c.name, c.name, ''), t.note,
		       t.amount_minor, t.currency, t.amount_base_minor, t.fx_rate_to_base::text, t.fx_rate_source,
		       ta.name, ta.currency, t.transfer_amount_minor, d.person
		  FROM transactions t
		  JOIN accounts a ON a.id = t.account_id
		  LEFT JOIN categories c ON c.id = t.category_id
		  LEFT JOIN categories pc ON pc.id = c.parent_id
		  LEFT JOIN accounts ta ON ta.id = t.transfer_account_id
		  LEFT JOIN dues d ON d.id = t.due_id
		 WHERE t.user_id = $1 AND t.deleted_at IS NULL AND t.local_date BETWEEN $2 AND $3
		 ORDER BY t.local_date, t.occurred_at, t.id
		 LIMIT $4`, userID, r.From, r.To, limit+1)
	if err != nil {
		return nil, err
	}
	list, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (row, error) {
		var x row
		return x, r.Scan(&x.Date, &x.Kind, &x.Account, &x.Category, &x.Note, &x.AmountMinor, &x.Currency,
			&x.BaseMinor, &x.Rate, &x.RateSource, &x.ToAccount, &x.ToCurrency, &x.ToAmount, &x.Person)
	})
	if err != nil {
		return nil, err
	}
	for i := range list {
		if r := list[i].Rate; r != nil && strings.Contains(*r, ".") {
			t := strings.TrimRight(strings.TrimRight(*r, "0"), ".")
			list[i].Rate = &t
		}
	}
	if len(list) > limit {
		return nil, fmt.Errorf("%w: more than %d transactions", ErrTooLarge, limit)
	}
	return list, nil
}

// buildCSV writes one line per transaction. Amounts are plain decimals
// (12.34) so spreadsheets read them as numbers; spending is negative.
func buildCSV(list []row, base string) ([]byte, error) {
	var buf bytes.Buffer
	buf.WriteString("\uFEFF") // BOM: Excel then reads the file as UTF-8
	w := csv.NewWriter(&buf)
	_ = w.Write([]string{"date", "type", "account", "category", "note", "amount", "currency",
		"amount_" + strings.ToLower(base), "rate_to_" + strings.ToLower(base), "rate_source",
		"to_account", "to_amount", "to_currency"})
	for _, x := range list {
		rec := []string{
			x.Date.Format(time.DateOnly), x.Kind, safeCell(x.Account), safeCell(categoryLabel(x)), safeCell(x.Note),
			amount(signed(x.Kind, x.AmountMinor), x.Currency), x.Currency,
			"", deref(x.Rate), deref(x.RateSource), "", "", "",
		}
		if x.BaseMinor != nil {
			rec[7] = amount(signed(x.Kind, *x.BaseMinor), base)
		}
		if x.ToAccount != nil && x.ToAmount != nil && x.ToCurrency != nil {
			rec[10], rec[11], rec[12] = safeCell(*x.ToAccount), amount(*x.ToAmount, *x.ToCurrency), *x.ToCurrency
		}
		if err := w.Write(rec); err != nil {
			return nil, err
		}
	}
	w.Flush()
	return buf.Bytes(), w.Error()
}

// safeCell stops spreadsheet formula injection: a note like "=HYPERLINK(...)"
// would otherwise run when the file is opened.
func safeCell(s string) string {
	if s != "" && strings.ContainsRune("=+-@\t\r", rune(s[0])) {
		return "'" + s
	}
	return s
}

// signed makes money going out negative: spending, transfers out and
// loan_out (money lent, or a loan paid back).
func signed(kind string, v int64) int64 {
	if moneyIn(kind) {
		return v
	}
	return -v
}

// moneyIn is true for kinds that add to the account: income and loan_in
// (money borrowed, or a loan repaid to the user).
func moneyIn(kind string) bool { return kind == "income" || kind == "loan_in" }

// categoryLabel is the category, or for a loan payment "Loan · person"
// (loans have no category).
func categoryLabel(x row) string {
	if x.Kind == "loan_in" || x.Kind == "loan_out" {
		if x.Person != nil {
			return "Loan · " + *x.Person
		}
		return "Loan"
	}
	return x.Category
}

// amount formats minor units as a plain decimal. Codes were validated on
// the way in, so an error can only mean a broken row: show the raw number.
func amount(minor int64, currency string) string {
	s, err := money.Format(minor, currency)
	if err != nil {
		return fmt.Sprint(minor)
	}
	return s
}

func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

// pretty formats minor units with thousands separators: 1234567 -> "12,345.67".
func pretty(minor int64, currency string) string {
	s := amount(minor, currency)
	neg := strings.HasPrefix(s, "-")
	s = strings.TrimPrefix(s, "-")
	intPart, frac, hasFrac := strings.Cut(s, ".")
	var b strings.Builder
	for i, c := range intPart {
		if i > 0 && (len(intPart)-i)%3 == 0 {
			b.WriteByte(',')
		}
		b.WriteRune(c)
	}
	out := b.String()
	if hasFrac {
		out += "." + frac
	}
	if neg {
		return "−" + out
	}
	return out
}

func signedPretty(kind string, minor int64, currency string) string {
	switch kind {
	case "income", "loan_in":
		return "+" + pretty(minor, currency)
	case "expense", "loan_out":
		return "−" + pretty(minor, currency)
	}
	return pretty(minor, currency)
}

// statement is what the PDF shows.
type statement struct {
	Range     reports.Range
	Base      string
	Generated time.Time
	Summary   reports.Summary
	ByCat     reports.ByCategory
	Rows      []row
}

func dayLabel(t time.Time) string { return t.Format("2 Jan 2006") }

// buildPDF lays out the statement: a header, totals, the top spending
// categories, then every transaction in a table that continues over pages.
func buildPDF(s statement) []byte {
	const (
		left   = 42.0
		right  = pageW - 42.0
		top    = 50.0
		bottom = pageH - 50.0
	)
	d := &pdfDoc{}
	d.addPage()
	y := top

	d.text(left, y+14, 20, true, primary, "pennyWise")
	d.textRight(right, y+6, 9, false, muted, "Statement")
	d.textRight(right, y+18, 9, false, muted, "Made "+dayLabel(s.Generated))
	y += 34
	d.text(left, y+12, 13, true, black, dayLabel(s.Range.From)+" – "+dayLabel(s.Range.To))
	d.text(left, y+27, 9, false, muted, "All totals in "+s.Base+", converted at the rate of each transaction's date.")
	y += 44

	// Totals: three boxes side by side.
	boxW := (right - left - 2*12) / 3
	for i, t := range []struct {
		label string
		value string
		c     rgb
	}{
		{"Income", "+" + pretty(s.Summary.IncomeMinor, s.Base), income},
		{"Spending", "−" + pretty(s.Summary.ExpenseMinor, s.Base), expense},
		{"Net", signedNet(s.Summary.NetMinor, s.Base), black},
	} {
		x := left + float64(i)*(boxW+12)
		d.box(x, y, boxW, 48, shade)
		d.text(x+12, y+17, 9, false, muted, t.label)
		d.text(x+12, y+36, 14, true, t.c, fit(t.value+" "+s.Base, boxW-24, 14, true))
	}
	y += 62
	if s.Summary.MissingRate > 0 {
		d.text(left, y+8, 8.5, false, muted, fmt.Sprintf(
			"%d transaction(s) are not in the totals yet: their currency has no rate. Add a rate in the app.", s.Summary.MissingRate))
		y += 18
	}

	// Top spending categories.
	if len(s.ByCat.Categories) > 0 {
		y += 8
		d.text(left, y+10, 11, true, black, "Spending by category")
		y += 20
		max := 8
		for i, c := range s.ByCat.Categories {
			if i == max {
				break
			}
			share := 0.0
			if s.ByCat.TotalMinor > 0 {
				share = float64(c.TotalMinor) / float64(s.ByCat.TotalMinor)
			}
			d.text(left, y+10, 9.5, false, black, fit(c.Name, 150, 9.5, false))
			barX, barW := left+160, right-left-160-150
			d.box(barX, y+3, barW, 8, shade)
			d.box(barX, y+3, barW*share, 8, primary)
			d.textRight(right-46, y+10, 9.5, false, black, pretty(c.TotalMinor, s.Base))
			d.textRight(right, y+10, 9.5, false, muted, fmt.Sprintf("%.0f%%", share*100))
			y += 17
		}
		y += 8
	}

	// Transactions table.
	cols := []struct {
		title string
		x, w  float64
		right bool
	}{
		{"Date", left, 62, false},
		{"Category", left + 66, 110, false},
		{"Account", left + 180, 80, false},
		{"Note", left + 264, 101, false},
		{"Amount", right - 84, 110, true},
		{s.Base, right, 80, true},
	}
	header := func() {
		d.box(left, y, right-left, 20, shade)
		for _, c := range cols {
			if c.right {
				d.textRight(c.x, y+13.5, 8.5, true, muted, c.title)
			} else {
				d.text(c.x+4, y+13.5, 8.5, true, muted, c.title)
			}
		}
		y += 20
	}
	y += 6
	d.text(left, y+10, 11, true, black, fmt.Sprintf("Transactions (%d)", len(s.Rows)))
	y += 20
	header()
	if len(s.Rows) == 0 {
		d.text(left+4, y+14, 9.5, false, muted, "No transactions in this period.")
	}
	const rowH = 17.0
	for i, x := range s.Rows {
		if y+rowH > bottom {
			d.addPage()
			y = top
			header()
		}
		if i%2 == 1 {
			d.box(left, y, right-left, rowH, rgb{0.985, 0.98, 0.97})
		}
		ty := y + 11.5
		category := categoryLabel(x)
		if x.Kind == "transfer" && x.ToAccount != nil {
			category = "Transfer to " + *x.ToAccount
		}
		d.text(cols[0].x+4, ty, 8.5, false, black, x.Date.Format("02 Jan 2006"))
		d.text(cols[1].x+4, ty, 8.5, false, black, fit(category, cols[1].w-8, 8.5, false))
		d.text(cols[2].x+4, ty, 8.5, false, black, fit(x.Account, cols[2].w-8, 8.5, false))
		d.text(cols[3].x+4, ty, 8.5, false, muted, fit(x.Note, cols[3].w-8, 8.5, false))
		c := black
		switch x.Kind {
		case "income":
			c = income
		case "expense":
			c = expense
		}
		d.textRight(cols[4].x, ty, 8.5, false, c, signedPretty(x.Kind, x.AmountMinor, x.Currency)+" "+x.Currency)
		base := "no rate"
		if x.BaseMinor != nil {
			base = signedPretty(x.Kind, *x.BaseMinor, s.Base)
		}
		d.textRight(cols[5].x, ty, 8.5, false, muted, base)
		d.line(left, y+rowH, right, y+rowH, 0.4, rule)
		y += rowH
	}

	// Footer with page numbers on every page.
	for i, p := range d.pages {
		d.cur = p
		d.line(left, pageH-36, right, pageH-36, 0.4, rule)
		d.text(left, pageH-24, 8, false, muted, "pennyWise · "+dayLabel(s.Range.From)+" – "+dayLabel(s.Range.To))
		d.textRight(right, pageH-24, 8, false, muted, fmt.Sprintf("Page %d of %d", i+1, len(d.pages)))
	}
	return d.bytes()
}

func signedNet(v int64, base string) string {
	if v >= 0 {
		return "+" + pretty(v, base)
	}
	return pretty(v, base)
}
