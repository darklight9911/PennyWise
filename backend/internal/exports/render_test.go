package exports

import (
	"bytes"
	"encoding/csv"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
	"testing"
	"time"

	"pennywise/backend/internal/reports"
)

func p[T any](v T) *T { return &v }

func sampleRows() []row {
	d := func(s string) time.Time { t, _ := time.Parse(time.DateOnly, s); return t }
	return []row{
		{Date: d("2026-01-31"), Kind: "income", Account: "Bank", Category: "Salary", AmountMinor: 300000, Currency: "USD",
			BaseMinor: p(int64(300000)), Rate: p("1"), RateSource: p("auto")},
		{Date: d("2026-02-02"), Kind: "expense", Account: "Wallet", Category: "Food › Café", Note: "=HYPERLINK(\"x\")",
			AmountMinor: 1234, Currency: "EUR", BaseMinor: p(int64(1350)), Rate: p("1.094"), RateSource: p("auto")},
		{Date: d("2026-02-03"), Kind: "transfer", Account: "Bank", AmountMinor: 5000, Currency: "USD",
			BaseMinor: p(int64(5000)), ToAccount: p("Savings"), ToCurrency: p("USD"), ToAmount: p(int64(5000))},
		{Date: d("2026-02-04"), Kind: "expense", Account: "Cash", Category: "Food", AmountMinor: 900, Currency: "BDT"},
		{Date: d("2026-02-05"), Kind: "loan_out", Account: "Bank", AmountMinor: 20000, Currency: "USD",
			BaseMinor: p(int64(20000)), Rate: p("1"), RateSource: p("auto"), Person: p("Sam")},
		{Date: d("2026-02-06"), Kind: "loan_in", Account: "Bank", AmountMinor: 5000, Currency: "USD",
			BaseMinor: p(int64(5000)), Rate: p("1"), RateSource: p("auto"), Person: p("=Sam")},
	}
}

func TestCSV(t *testing.T) {
	b, err := buildCSV(sampleRows(), "USD")
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.HasPrefix(b, []byte("\uFEFF")) {
		t.Error("no UTF-8 BOM")
	}
	recs, err := csv.NewReader(bytes.NewReader(bytes.TrimPrefix(b, []byte("\uFEFF")))).ReadAll()
	if err != nil {
		t.Fatal(err)
	}
	if strings.Join(recs[0], ",") != "date,type,account,category,note,amount,currency,amount_usd,rate_to_usd,rate_source,to_account,to_amount,to_currency" {
		t.Errorf("header %v", recs[0])
	}
	want := [][]string{
		{"2026-01-31", "income", "Bank", "Salary", "", "3000.00", "USD", "3000.00", "1", "auto", "", "", ""},
		{"2026-02-02", "expense", "Wallet", "Food › Café", `'=HYPERLINK("x")`, "-12.34", "EUR", "-13.50", "1.094", "auto", "", "", ""},
		{"2026-02-03", "transfer", "Bank", "", "", "-50.00", "USD", "-50.00", "", "", "Savings", "50.00", "USD"},
		{"2026-02-04", "expense", "Cash", "Food", "", "-9.00", "BDT", "", "", "", "", "", ""},
		{"2026-02-05", "loan_out", "Bank", "Loan · Sam", "", "-200.00", "USD", "-200.00", "1", "auto", "", "", ""},
		{"2026-02-06", "loan_in", "Bank", "Loan · =Sam", "", "50.00", "USD", "50.00", "1", "auto", "", "", ""},
	}
	for i, w := range want {
		if strings.Join(recs[i+1], "|") != strings.Join(w, "|") {
			t.Errorf("row %d\n got %q\nwant %q", i+1, recs[i+1], w)
		}
	}
}

func TestPretty(t *testing.T) {
	for _, c := range []struct {
		v    int64
		cur  string
		want string
	}{{123456789, "USD", "1,234,567.89"}, {-100000, "USD", "−1,000.00"}, {5, "USD", "0.05"}, {1234567, "JPY", "1,234,567"}, {999, "USD", "9.99"}} {
		if got := pretty(c.v, c.cur); got != c.want {
			t.Errorf("pretty(%d %s) = %s, want %s", c.v, c.cur, got, c.want)
		}
	}
}

func TestWinAnsiAndFit(t *testing.T) {
	if got := winAnsi("Café €5 – ok\n日本"); got != "Caf\xe9 \x805 \x96 ok ??" {
		t.Errorf("winAnsi = %q", got)
	}
	if got := escape(`a(b)\c`); got != `a\(b\)\\c` {
		t.Errorf("escape = %s", got)
	}
	long := strings.Repeat("Groceries ", 10)
	f := fit(long, 80, 9, false)
	if textWidth(f, 9, false) > 80 || !strings.HasSuffix(f, "…") {
		t.Errorf("fit = %q (%.1f)", f, textWidth(f, 9, false))
	}
	if fit("Rent", 80, 9, false) != "Rent" {
		t.Error("short text changed")
	}
}

func statementFor(rows []row) statement {
	d := func(s string) time.Time { t, _ := time.Parse(time.DateOnly, s); return t }
	return statement{
		Range: reports.Range{From: d("2026-01-01"), To: d("2026-03-31")}, Base: "USD",
		Generated: d("2026-04-01"),
		Summary:   reports.Summary{Currency: "USD", IncomeMinor: 300000, ExpenseMinor: 1350, NetMinor: 298650, MissingRate: 1},
		ByCat: reports.ByCategory{TotalMinor: 1350, Categories: []reports.CategoryTotal{
			{Name: "Food", TotalMinor: 1350}}},
		Rows: rows,
	}
}

// The cross-reference table must point at every object, or readers have to
// repair the file.
func checkXref(t *testing.T, b []byte) {
	t.Helper()
	m := regexp.MustCompile(`startxref\n(\d+)\n%%EOF\n$`).FindSubmatch(b)
	if m == nil {
		t.Fatal("no startxref")
	}
	at, _ := strconv.Atoi(string(m[1]))
	if !bytes.HasPrefix(b[at:], []byte("xref\n")) {
		t.Fatal("startxref does not point at the xref table")
	}
	lines := strings.Split(string(b[at:]), "\n")
	n, _ := strconv.Atoi(strings.Fields(lines[1])[1])
	for i := 1; i < n; i++ {
		off, _ := strconv.Atoi(strings.Fields(lines[2+i])[0])
		if !bytes.HasPrefix(b[off:], []byte(fmt.Sprintf("%d 0 obj", i))) {
			t.Fatalf("object %d: offset %d is wrong", i, off)
		}
	}
}

func TestPDFStructureAndText(t *testing.T) {
	rows := sampleRows()
	for i := 0; i < 120; i++ { // enough for several pages
		r := rows[1]
		r.Note = fmt.Sprintf("Lunch %d", i)
		rows = append(rows, r)
	}
	b := buildPDF(statementFor(rows))
	if !bytes.HasPrefix(b, []byte("%PDF-1.4")) {
		t.Fatal("not a PDF")
	}
	checkXref(t, b)
	pages := bytes.Count(b, []byte("/Type /Page "))
	if pages < 3 {
		t.Errorf("pages: %d, want at least 3", pages)
	}
	if out := os.Getenv("PDF_SAMPLE"); out != "" { // for looking at it: PDF_SAMPLE=/tmp/x.pdf
		_ = os.WriteFile(out, b, 0o600)
	}
	if _, err := exec.LookPath("pdftotext"); err != nil {
		t.Skip("pdftotext not installed: text not checked")
	}
	f := t.TempDir() + "/s.pdf"
	_ = os.WriteFile(f, b, 0o600)
	txt, err := exec.Command("pdftotext", "-layout", f, "-").CombinedOutput()
	if err != nil {
		t.Fatalf("pdftotext: %v %s", err, txt)
	}
	for _, want := range []string{"pennyWise", "1 Jan 2026 – 31 Mar 2026", "+3,000.00 USD", "Food › Café", "Transfer to Savings",
		"Loan · Sam", "200.00 USD", "+50.00 USD", "no rate", fmt.Sprintf("Page 1 of %d", pages), fmt.Sprintf("Page %d of %d", pages, pages), "Lunch 119", "not in the totals yet"} {
		if !strings.Contains(string(txt), want) {
			t.Errorf("PDF text has no %q", want)
		}
	}
}

func TestEmptyPDF(t *testing.T) {
	b := buildPDF(statementFor(nil))
	checkXref(t, b)
}
