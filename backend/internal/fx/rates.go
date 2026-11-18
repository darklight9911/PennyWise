// Package fx converts money between currencies with daily reference rates
// (ECB data through Frankfurter), keeps those rates fresh, and recomputes
// stored base-currency amounts when rates arrive or the base changes.
//
// Rates are exact decimals (math/big), never floats.
package fx

import (
	"context"
	"errors"
	"fmt"
	"math"
	"math/big"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"pennywise/backend/internal/money"
)

// Anchor is the currency every stored rate is quoted against.
const Anchor = "EUR"

// RateDecimals is how many decimals a stored rate keeps (numeric(20,10)).
const RateDecimals = 10

// Querier is what this package needs from a pool or a transaction.
type Querier interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

// ErrOverflow means a converted amount does not fit in int64.
var ErrOverflow = errors.New("fx: converted amount too large")

// Rate returns how much of `to` one unit of `from` buys on day, rounded to
// RateDecimals. It uses the latest published rate on or before day (none
// are published on weekends), or the earliest known one if day is older
// than all data. ok is false when either currency has no rate at all.
func Rate(ctx context.Context, q Querier, from, to string, day time.Time) (*big.Rat, bool, error) {
	if from == to {
		return big.NewRat(1, 1), true, nil
	}
	f, ok, err := anchorRate(ctx, q, from, day)
	if err != nil || !ok {
		return nil, false, err
	}
	t, ok, err := anchorRate(ctx, q, to, day)
	if err != nil || !ok {
		return nil, false, err
	}
	return Round(new(big.Rat).Quo(t, f)), true, nil
}

// anchorRate is 1 EUR in currency c.
func anchorRate(ctx context.Context, q Querier, c string, day time.Time) (*big.Rat, bool, error) {
	if c == Anchor {
		return big.NewRat(1, 1), true, nil
	}
	var s string
	err := q.QueryRow(ctx, `
		SELECT rate::text FROM (
		    (SELECT rate, 0 AS pref FROM exchange_rates
		      WHERE base = $1 AND quote = $2 AND date <= $3 ORDER BY date DESC LIMIT 1)
		    UNION ALL
		    (SELECT rate, 1 FROM exchange_rates
		      WHERE base = $1 AND quote = $2 ORDER BY date LIMIT 1)
		) r ORDER BY pref LIMIT 1`, Anchor, c, day.Format(time.DateOnly)).Scan(&s)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, err
	}
	r, ok := new(big.Rat).SetString(s)
	if !ok {
		return nil, false, fmt.Errorf("fx: bad stored rate %q", s)
	}
	return r, true, nil
}

// Round rounds r to RateDecimals (halves away from zero), so the rate that
// is stored is exactly the rate that was used.
func Round(r *big.Rat) *big.Rat {
	out, _ := new(big.Rat).SetString(r.FloatString(RateDecimals))
	return out
}

// Format writes a rate as a plain decimal without trailing zeros: "1.0989".
func Format(r *big.Rat) string {
	s := r.FloatString(RateDecimals)
	for len(s) > 1 && s[len(s)-1] == '0' {
		s = s[:len(s)-1]
	}
	if s[len(s)-1] == '.' {
		s = s[:len(s)-1]
	}
	return s
}

// ParseRate reads a positive decimal rate with at most RateDecimals decimals
// and at most 10 digits before the point (what numeric(20,10) holds).
func ParseRate(s string) (*big.Rat, bool) {
	if len(s) == 0 || len(s) > 21 {
		return nil, false
	}
	dot := -1
	for i, c := range s {
		switch {
		case c == '.' && dot < 0 && i > 0 && i < len(s)-1:
			dot = i
		case c < '0' || c > '9':
			return nil, false
		}
	}
	intDigits := len(s)
	if dot >= 0 {
		intDigits = dot
		if len(s)-dot-1 > RateDecimals {
			return nil, false
		}
	}
	if intDigits > 10 {
		return nil, false
	}
	r, ok := new(big.Rat).SetString(s)
	if !ok || r.Sign() <= 0 {
		return nil, false
	}
	return r, true
}

// Convert turns amountMinor in currency from into minor units of to, at
// rate (how much `to` one `from` buys). Halves round away from zero.
func Convert(amountMinor int64, from, to string, rate *big.Rat) (int64, error) {
	ef, err := money.Exponent(from)
	if err != nil {
		return 0, err
	}
	et, err := money.Exponent(to)
	if err != nil {
		return 0, err
	}
	v := new(big.Rat).Mul(new(big.Rat).SetInt64(amountMinor), rate)
	scale := new(big.Rat).SetInt(new(big.Int).Exp(big.NewInt(10), big.NewInt(int64(abs(et-ef))), nil))
	if et > ef {
		v.Mul(v, scale)
	} else {
		v.Quo(v, scale)
	}
	return roundHalfAway(v)
}

func roundHalfAway(v *big.Rat) (int64, error) {
	num, den := new(big.Int).Abs(v.Num()), v.Denom()
	q, rem := new(big.Int).QuoRem(num, den, new(big.Int))
	if new(big.Int).Mul(rem, big.NewInt(2)).Cmp(den) >= 0 {
		q.Add(q, big.NewInt(1))
	}
	if !q.IsInt64() || q.Int64() == math.MinInt64 {
		return 0, ErrOverflow
	}
	if v.Sign() < 0 {
		return -q.Int64(), nil
	}
	return q.Int64(), nil
}

func abs(n int) int {
	if n < 0 {
		return -n
	}
	return n
}

// SaveRates stores one day's EUR rates (quote -> decimal string). Existing
// rows are replaced, so a corrected rate wins.
func SaveRates(ctx context.Context, q Querier, day string, rates map[string]string) error {
	for quote, rate := range rates {
		if _, ok := ParseRate(rate); !ok || quote == Anchor {
			continue
		}
		if _, err := q.Exec(ctx, `
			INSERT INTO exchange_rates (base, quote, date, rate) VALUES ($1, $2, $3, $4::numeric)
			ON CONFLICT (base, quote, date) DO UPDATE SET rate = EXCLUDED.rate`,
			Anchor, quote, day, rate); err != nil {
			return fmt.Errorf("fx: save %s %s: %w", quote, day, err)
		}
	}
	return nil
}
