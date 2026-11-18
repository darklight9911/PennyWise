package fx

import (
	"context"
	"encoding/json"
	"fmt"
	"math/big"
	"net/http"
	"time"
)

// DefaultAPI is Frankfurter's public endpoint (free, no key).
const DefaultAPI = "https://api.frankfurter.dev/v1"

// Fetcher downloads daily EUR rates for a date range:
// date (YYYY-MM-DD) -> quote -> rate as a decimal string.
type Fetcher interface {
	Range(ctx context.Context, from, to time.Time) (map[string]map[string]string, error)
}

// Frankfurter is the HTTP client for the Frankfurter API.
type Frankfurter struct {
	BaseURL string
	HTTP    *http.Client
}

// NewFrankfurter returns a client with a 20-second timeout.
func NewFrankfurter(baseURL string) *Frankfurter {
	if baseURL == "" {
		baseURL = DefaultAPI
	}
	return &Frankfurter{BaseURL: baseURL, HTTP: &http.Client{Timeout: 20 * time.Second}}
}

// Range implements Fetcher.
func (f *Frankfurter) Range(ctx context.Context, from, to time.Time) (map[string]map[string]string, error) {
	url := fmt.Sprintf("%s/%s..%s?base=%s", f.BaseURL, from.Format(time.DateOnly), to.Format(time.DateOnly), Anchor)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "pennywise-backend")
	res, err := f.HTTP.Do(req)
	if err != nil {
		return nil, fmt.Errorf("fx: fetch: %w", err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("fx: fetch: status %d", res.StatusCode)
	}
	var body struct {
		Base  string                            `json:"base"`
		Rates map[string]map[string]json.Number `json:"rates"`
	}
	dec := json.NewDecoder(http.MaxBytesReader(nil, res.Body, 8<<20))
	dec.UseNumber()
	if err := dec.Decode(&body); err != nil {
		return nil, fmt.Errorf("fx: decode: %w", err)
	}
	if body.Base != Anchor {
		return nil, fmt.Errorf("fx: unexpected base %q", body.Base)
	}
	out := make(map[string]map[string]string, len(body.Rates))
	for day, quotes := range body.Rates {
		m := make(map[string]string, len(quotes))
		for q, n := range quotes {
			// Normalise (the API may write tiny rates as 1e-05).
			if r, ok := new(big.Rat).SetString(n.String()); ok && r.Sign() > 0 {
				m[q] = Format(Round(r))
			}
		}
		out[day] = m
	}
	return out, nil
}
