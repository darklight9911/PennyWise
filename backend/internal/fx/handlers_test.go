package fx_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/go-chi/chi/v5"

	"pennywise/backend/internal/fx"
	"pennywise/backend/internal/testdb"
)

func TestRatesEndpoint(t *testing.T) {
	p := testdb.Pool(t)
	// A far-future day, so it is the latest one whatever else is stored.
	seedRates(t, p, map[string]map[string]string{"2099-01-02": {"XTA": "2", "XTB": "10"}})
	r := chi.NewRouter()
	fx.NewHandler(p, func(h http.Handler) http.Handler { return h }, quiet).Routes(r)

	get := func(q string) (int, fx.RatesResponse) {
		rec := httptest.NewRecorder()
		r.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/fx/rates"+q, nil))
		var out fx.RatesResponse
		_ = json.Unmarshal(rec.Body.Bytes(), &out)
		return rec.Code, out
	}
	code, out := get("?base=xta")
	if code != http.StatusOK || out.Date != "2099-01-02" || out.Base != "XTA" {
		t.Fatalf("%d %+v", code, out)
	}
	if out.Rates["XTB"] != "5" || out.Rates["EUR"] != "0.5" || len(out.Rates) != 2 {
		t.Errorf("rates %v", out.Rates)
	}
	if code, _ := get("?base=XTC"); code != http.StatusNotFound {
		t.Errorf("unknown currency: %d", code)
	}
	if code, _ := get("?base=12"); code != http.StatusBadRequest {
		t.Errorf("bad code: %d", code)
	}
}
