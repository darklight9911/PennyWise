package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/prometheus/client_golang/prometheus"
)

func newTestRouter(checks map[string]Pinger) http.Handler {
	return NewRouter(Deps{
		Logger:   slog.New(slog.NewTextHandler(io.Discard, nil)),
		Registry: prometheus.NewRegistry(),
		Checks:   checks,
	})
}

var (
	up   = PingFunc(func(context.Context) error { return nil })
	down = PingFunc(func(context.Context) error { return errors.New("boom") })
)

func TestHealthz(t *testing.T) {
	rec := httptest.NewRecorder()
	newTestRouter(nil).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", rec.Code)
	}
	if got := rec.Header().Get("Content-Type"); got != "application/json" {
		t.Errorf("content-type = %q", got)
	}
}

func TestReadyz(t *testing.T) {
	tests := []struct {
		name       string
		checks     map[string]Pinger
		wantStatus int
		wantDown   string
	}{
		{"all up", map[string]Pinger{"postgres": up, "redis": up}, http.StatusOK, ""},
		{"redis down", map[string]Pinger{"postgres": up, "redis": down}, http.StatusServiceUnavailable, "redis"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			newTestRouter(tt.checks).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/readyz", nil))

			if rec.Code != tt.wantStatus {
				t.Fatalf("status = %d, want %d", rec.Code, tt.wantStatus)
			}
			var body struct {
				Checks map[string]string `json:"checks"`
			}
			if err := json.NewDecoder(rec.Body).Decode(&body); err != nil {
				t.Fatal(err)
			}
			if tt.wantDown != "" && body.Checks[tt.wantDown] != "down" {
				t.Errorf("checks[%s] = %q, want down", tt.wantDown, body.Checks[tt.wantDown])
			}
		})
	}
}

func TestNotFoundUsesErrorShape(t *testing.T) {
	rec := httptest.NewRecorder()
	newTestRouter(nil).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/nope", nil))

	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), `"code":"not_found"`) {
		t.Errorf("body = %s", rec.Body.String())
	}
}

func TestMetricsEndpointCountsRequests(t *testing.T) {
	h := newTestRouter(nil)
	h.ServeHTTP(httptest.NewRecorder(), httptest.NewRequest(http.MethodGet, "/healthz", nil))

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/metrics", nil))
	want := `pennywise_http_requests_total{method="GET",route="/healthz",status="200"} 1`
	if !strings.Contains(rec.Body.String(), want) {
		t.Errorf("metrics output missing %q", want)
	}
}
