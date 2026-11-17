package recurring

import "time"

// Rule is the schedule part of a recurring rule.
type Rule struct {
	Frequency string // daily, weekly, monthly, yearly
	Every     int    // every N days/weeks/months/years (>= 1)
	Start     time.Time
	End       *time.Time // inclusive; nil = no end
}

// maxSteps bounds one call (e.g. daily for ~27 years).
const maxSteps = 10000

// Dates returns the occurrence dates of r within [from, to] (both
// inclusive), oldest first. Dates are calendar days (time.UTC midnight).
//
// Monthly and yearly rules keep the start's day of month: a rule starting
// on the 31st falls on the last day of shorter months (Feb 28/29, Apr 30)
// and back on the 31st when the month has one; 29 Feb falls on 28 Feb in
// other years.
func Dates(r Rule, from, to time.Time) []time.Time {
	start := day(r.Start)
	from, to = day(from), day(to)
	if r.End != nil && day(*r.End).Before(to) {
		to = day(*r.End)
	}
	every := max(r.Every, 1)
	var out []time.Time
	for k := 0; k < maxSteps; k++ {
		d := nth(r.Frequency, start, k*every)
		if d.After(to) {
			break
		}
		if !d.Before(from) {
			out = append(out, d)
		}
	}
	return out
}

// Next returns the first occurrence on or after from, if any.
func Next(r Rule, from time.Time) (time.Time, bool) {
	limit := day(from).AddDate(5, 0, 0) // no rule waits more than 365 years; 5 is plenty for "next"
	if r.Frequency == "yearly" {
		limit = day(from).AddDate(365, 0, 0)
	}
	ds := Dates(r, from, limit)
	if len(ds) == 0 {
		return time.Time{}, false
	}
	return ds[0], true
}

// nth is the n-th step after start (n in days/weeks/months/years).
func nth(freq string, start time.Time, n int) time.Time {
	switch freq {
	case "daily":
		return start.AddDate(0, 0, n)
	case "weekly":
		return start.AddDate(0, 0, 7*n)
	case "yearly":
		return clampDay(start.Year()+n, start.Month(), start.Day())
	default: // monthly
		total := int(start.Month()) - 1 + n
		return clampDay(start.Year()+total/12, time.Month(total%12+1), start.Day())
	}
}

// clampDay builds year-month-day, using the month's last day when the day
// does not exist (31 April -> 30 April).
func clampDay(y int, m time.Month, d int) time.Time {
	last := time.Date(y, m+1, 0, 0, 0, 0, 0, time.UTC).Day()
	return time.Date(y, m, min(d, last), 0, 0, 0, 0, time.UTC)
}

func day(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
}
