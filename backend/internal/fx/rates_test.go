package fx

import (
	"math/big"
	"testing"
)

func rat(s string) *big.Rat {
	r, ok := new(big.Rat).SetString(s)
	if !ok {
		panic(s)
	}
	return r
}

func TestConvert(t *testing.T) {
	cases := []struct {
		amount   int64
		from, to string
		rate     string
		want     int64
	}{
		{1000, "USD", "EUR", "0.91", 910},       // $10.00 -> €9.10
		{1234, "USD", "JPY", "150.5", 1857},     // $12.34 -> ¥1857.17 -> ¥1857
		{1857, "JPY", "USD", "0.0066445", 1234}, // ¥1857 -> $12.3388... -> $12.34
		{1000, "USD", "KWD", "0.3075", 3075},    // $10.00 -> 3.075 KWD (3 decimals)
		{5, "USD", "EUR", "0.5", 3},             // 2.5 cents rounds away from zero
		{-5, "USD", "EUR", "0.5", -3},           // and so do refunds
		{100, "EUR", "EUR", "1", 100},           //
		{999999, "IDR", "USD", "0.0000613", 61}, // Rp9,999.99 -> $0.613 -> 61 cents
	}
	for _, c := range cases {
		got, err := Convert(c.amount, c.from, c.to, rat(c.rate))
		if err != nil {
			t.Fatal(err)
		}
		if got != c.want {
			t.Errorf("Convert(%d %s->%s at %s) = %d, want %d", c.amount, c.from, c.to, c.rate, got, c.want)
		}
	}
	if _, err := Convert(1<<62, "USD", "JPY", rat("1000")); err != ErrOverflow {
		t.Errorf("overflow: got %v", err)
	}
}

func TestRoundAndFormat(t *testing.T) {
	r := Round(new(big.Rat).Quo(rat("175.05"), rat("1.0989")))
	if got := Format(r); got != "159.2956592957" {
		t.Errorf("cross rate = %s", got)
	}
	for in, want := range map[string]string{"1.5000": "1.5", "2": "2", "0.0000000001": "0.0000000001"} {
		if got := Format(rat(in)); got != want {
			t.Errorf("Format(%s) = %s, want %s", in, got, want)
		}
	}
}

func TestParseRate(t *testing.T) {
	for _, ok := range []string{"1", "0.5", "117.25", "0.0000000001", "9999999999.9999999999"} {
		if _, good := ParseRate(ok); !good {
			t.Errorf("ParseRate(%q) rejected", ok)
		}
	}
	for _, bad := range []string{"", "0", "0.0", "-1", "1.", ".5", "1e5", "1.00000000001", "12345678901", "abc", "1.2.3"} {
		if _, good := ParseRate(bad); good {
			t.Errorf("ParseRate(%q) accepted", bad)
		}
	}
}
