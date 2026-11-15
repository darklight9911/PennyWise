package money

import (
	"errors"
	"math"
	"testing"
)

func TestParse(t *testing.T) {
	tests := []struct {
		in, cur string
		want    int64
		wantErr error
	}{
		{"12.34", "USD", 1234, nil},
		{"12.3", "USD", 1230, nil},
		{"12", "USD", 1200, nil},
		{"-0.05", "EUR", -5, nil},
		{" 7.5 ", "GBP", 750, nil},
		{"1500", "JPY", 1500, nil},
		{"1.234", "KWD", 1234, nil},
		{"1.2", "KWD", 1200, nil},
		{"12.345", "USD", 0, ErrTooPrecise},
		{"1.5", "JPY", 0, ErrTooPrecise},
		{"abc", "USD", 0, ErrInvalidAmount},
		{"1.", "USD", 0, ErrInvalidAmount},
		{".5", "USD", 0, ErrInvalidAmount},
		{"1,000", "USD", 0, ErrInvalidAmount},
		{"", "USD", 0, ErrInvalidAmount},
		{"1", "usd", 0, ErrUnknownCurrency},
		{"1", "US", 0, ErrUnknownCurrency},
		{"99999999999999999999", "USD", 0, ErrOverflow},
	}
	for _, tt := range tests {
		got, err := Parse(tt.in, tt.cur)
		if !errors.Is(err, tt.wantErr) {
			t.Errorf("Parse(%q, %s) error = %v, want %v", tt.in, tt.cur, err, tt.wantErr)
			continue
		}
		if got != tt.want {
			t.Errorf("Parse(%q, %s) = %d, want %d", tt.in, tt.cur, got, tt.want)
		}
	}
}

func TestFormat(t *testing.T) {
	tests := []struct {
		minor int64
		cur   string
		want  string
	}{
		{1234, "USD", "12.34"},
		{5, "USD", "0.05"},
		{-5, "USD", "-0.05"},
		{0, "USD", "0.00"},
		{1500, "JPY", "1500"},
		{1234, "KWD", "1.234"},
		{7, "KWD", "0.007"},
		{math.MinInt64, "USD", "-92233720368547758.08"},
	}
	for _, tt := range tests {
		got, err := Format(tt.minor, tt.cur)
		if err != nil {
			t.Fatalf("Format(%d, %s): %v", tt.minor, tt.cur, err)
		}
		if got != tt.want {
			t.Errorf("Format(%d, %s) = %q, want %q", tt.minor, tt.cur, got, tt.want)
		}
	}
}

func TestRoundTrip(t *testing.T) {
	for _, cur := range []string{"USD", "JPY", "KWD"} {
		for _, v := range []int64{0, 1, -1, 99, 100, 123456789, -987654321} {
			s, err := Format(v, cur)
			if err != nil {
				t.Fatal(err)
			}
			back, err := Parse(s, cur)
			if err != nil || back != v {
				t.Errorf("%s: %d -> %q -> %d (%v)", cur, v, s, back, err)
			}
		}
	}
}
