// Package money handles amounts as integer minor units (e.g. cents).
//
// Rule: amounts are never stored or computed as floats. $12.34 is 1234.
package money

import (
	"errors"
	"fmt"
	"math"
	"strings"
)

// Errors returned by Parse.
var (
	ErrUnknownCurrency = errors.New("money: unknown currency")
	ErrInvalidAmount   = errors.New("money: invalid amount")
	ErrTooPrecise      = errors.New("money: too many decimal places for currency")
	ErrOverflow        = errors.New("money: amount too large")
)

// minorUnits lists currencies whose number of decimals is not 2 (ISO 4217).
// Every other supported currency uses 2.
var minorUnits = map[string]int{
	// 0 decimals
	"BIF": 0, "CLP": 0, "DJF": 0, "GNF": 0, "ISK": 0, "JPY": 0, "KMF": 0,
	"KRW": 0, "PYG": 0, "RWF": 0, "UGX": 0, "UYI": 0, "VND": 0, "VUV": 0,
	"XAF": 0, "XOF": 0, "XPF": 0,
	// 3 decimals
	"BHD": 3, "IQD": 3, "JOD": 3, "KWD": 3, "LYD": 3, "OMR": 3, "TND": 3,
}

// Exponent returns how many decimal places a currency uses.
// code must be a 3-letter upper-case ISO 4217 code.
func Exponent(code string) (int, error) {
	if !isCurrencyCode(code) {
		return 0, fmt.Errorf("%w: %q", ErrUnknownCurrency, code)
	}
	if e, ok := minorUnits[code]; ok {
		return e, nil
	}
	return 2, nil
}

// Parse converts a decimal string such as "12.34" or "-5" into minor units.
// It rejects more decimals than the currency allows instead of rounding,
// so money is never lost silently.
func Parse(s, currency string) (int64, error) {
	exp, err := Exponent(currency)
	if err != nil {
		return 0, err
	}
	s = strings.TrimSpace(s)
	neg := false
	if strings.HasPrefix(s, "-") {
		neg, s = true, s[1:]
	}
	intPart, fracPart, hasDot := strings.Cut(s, ".")
	if intPart == "" || (hasDot && fracPart == "") || !allDigits(intPart) || !allDigits(fracPart) {
		return 0, fmt.Errorf("%w: %q", ErrInvalidAmount, s)
	}
	if len(fracPart) > exp {
		return 0, fmt.Errorf("%w: %q has %d, %s allows %d", ErrTooPrecise, s, len(fracPart), currency, exp)
	}
	fracPart += strings.Repeat("0", exp-len(fracPart))

	var v int64
	for _, c := range intPart + fracPart {
		d := int64(c - '0')
		if v > (math.MaxInt64-d)/10 {
			return 0, ErrOverflow
		}
		v = v*10 + d
	}
	if neg {
		v = -v
	}
	return v, nil
}

// Format turns minor units back into a plain decimal string, e.g. 1234 USD -> "12.34".
// Display formatting (symbols, grouping) is done by the app, not here.
func Format(minor int64, currency string) (string, error) {
	exp, err := Exponent(currency)
	if err != nil {
		return "", err
	}
	sign := ""
	u := uint64(minor)
	if minor < 0 {
		sign = "-"
		u = uint64(-(minor + 1)) + 1 // safe for math.MinInt64
	}
	digits := fmt.Sprintf("%d", u)
	if exp == 0 {
		return sign + digits, nil
	}
	if len(digits) <= exp {
		digits = strings.Repeat("0", exp-len(digits)+1) + digits
	}
	cut := len(digits) - exp
	return sign + digits[:cut] + "." + digits[cut:], nil
}

func isCurrencyCode(s string) bool {
	if len(s) != 3 {
		return false
	}
	for _, c := range s {
		if c < 'A' || c > 'Z' {
			return false
		}
	}
	return true
}

func allDigits(s string) bool {
	for _, c := range s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}
