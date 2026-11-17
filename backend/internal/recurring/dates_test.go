package recurring

import (
	"strings"
	"testing"
	"time"
)

func d(s string) time.Time {
	t, err := time.Parse(time.DateOnly, s)
	if err != nil {
		panic(err)
	}
	return t
}

func fmtDates(ds []time.Time) string {
	parts := make([]string, len(ds))
	for i, x := range ds {
		parts[i] = x.Format(time.DateOnly)
	}
	return strings.Join(parts, " ")
}

func TestDates(t *testing.T) {
	end := d("2026-06-30")
	cases := []struct {
		name     string
		rule     Rule
		from, to string
		want     string
	}{
		{"daily", Rule{Frequency: "daily", Every: 1, Start: d("2026-01-30")}, "2026-01-01", "2026-02-02",
			"2026-01-30 2026-01-31 2026-02-01 2026-02-02"},
		{"every 3 days from the middle", Rule{Frequency: "daily", Every: 3, Start: d("2026-01-01")}, "2026-01-05", "2026-01-12",
			"2026-01-07 2026-01-10"},
		{"weekly", Rule{Frequency: "weekly", Every: 1, Start: d("2026-11-02")}, "2026-11-01", "2026-11-30",
			"2026-11-02 2026-11-09 2026-11-16 2026-11-23 2026-11-30"},
		{"every 2 weeks", Rule{Frequency: "weekly", Every: 2, Start: d("2026-11-02")}, "2026-11-01", "2026-11-30",
			"2026-11-02 2026-11-16 2026-11-30"},
		{"monthly on the 31st", Rule{Frequency: "monthly", Every: 1, Start: d("2026-01-31")}, "2026-01-01", "2026-05-31",
			"2026-01-31 2026-02-28 2026-03-31 2026-04-30 2026-05-31"},
		{"monthly in a leap year", Rule{Frequency: "monthly", Every: 1, Start: d("2028-01-31")}, "2028-02-01", "2028-02-29",
			"2028-02-29"},
		{"every 3 months over a year end", Rule{Frequency: "monthly", Every: 3, Start: d("2026-11-15")}, "2026-01-01", "2027-12-31",
			"2026-11-15 2027-02-15 2027-05-15 2027-08-15 2027-11-15"},
		{"yearly on 29 Feb", Rule{Frequency: "yearly", Every: 1, Start: d("2028-02-29")}, "2028-01-01", "2032-12-31",
			"2028-02-29 2029-02-28 2030-02-28 2031-02-28 2032-02-29"},
		{"ends", Rule{Frequency: "monthly", Every: 1, Start: d("2026-04-01"), End: &end}, "2026-01-01", "2026-12-31",
			"2026-04-01 2026-05-01 2026-06-01"},
		{"not started yet", Rule{Frequency: "daily", Every: 1, Start: d("2027-01-01")}, "2026-01-01", "2026-12-31", ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := fmtDates(Dates(c.rule, d(c.from), d(c.to))); got != c.want {
				t.Fatalf("got  %s\nwant %s", got, c.want)
			}
		})
	}
}

func TestNext(t *testing.T) {
	r := Rule{Frequency: "monthly", Every: 1, Start: d("2026-01-31")}
	if n, ok := Next(r, d("2026-02-01")); !ok || n.Format(time.DateOnly) != "2026-02-28" {
		t.Fatalf("next = %v %v", n, ok)
	}
	end := d("2026-03-01")
	r.End = &end
	if _, ok := Next(r, d("2026-03-02")); ok {
		t.Fatal("an ended rule has no next date")
	}
}
