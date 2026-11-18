// Package httpapi wires the HTTP routes and middleware of the API.
package httpapi

import (
	"context"
	"log/slog"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"pennywise/backend/internal/httpx"
)

// Pinger is anything that can tell whether a dependency is reachable.
type Pinger interface {
	Ping(ctx context.Context) error
}

// PingFunc adapts a function to the Pinger interface.
type PingFunc func(ctx context.Context) error

// Ping calls f.
func (f PingFunc) Ping(ctx context.Context) error { return f(ctx) }

// Deps are the dependencies the router needs.
type Deps struct {
	Logger   *slog.Logger
	Registry *prometheus.Registry
	// Checks are run by /readyz. The key is the dependency name.
	Checks map[string]Pinger
	// V1 mounts the feature routes (auth, sync, ...) under /v1.
	V1 []func(r chi.Router)
	// V1Middleware runs before every /v1 route (e.g. a per-IP rate limit).
	V1Middleware []func(http.Handler) http.Handler
}

// NewRouter builds the HTTP handler for the API.
func NewRouter(d Deps) http.Handler {
	m := newMetrics(d.Registry)

	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	// The API always runs behind Caddy, which sets X-Forwarded-For.
	r.Use(middleware.RealIP)
	r.Use(requestLogger(d.Logger))
	r.Use(m.middleware)
	r.Use(middleware.Recoverer)
	r.Use(middleware.Timeout(30 * time.Second))

	r.Get("/healthz", healthz)
	r.Get("/readyz", readyz(d.Checks))
	r.Handle("/metrics", promhttp.HandlerFor(d.Registry, promhttp.HandlerOpts{}))

	r.Route("/v1", func(r chi.Router) {
		r.Use(d.V1Middleware...)
		for _, mount := range d.V1 {
			mount(r)
		}
	})

	r.NotFound(func(w http.ResponseWriter, _ *http.Request) {
		httpx.WriteError(w, http.StatusNotFound, "not_found", "route not found")
	})
	return r
}

// healthz says the process is alive. It does not check dependencies.
func healthz(w http.ResponseWriter, _ *http.Request) {
	httpx.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// readyz says whether the API can serve traffic (database and Redis reachable).
func readyz(checks map[string]Pinger) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()

		results := make(map[string]string, len(checks))
		status := http.StatusOK
		for name, c := range checks {
			if err := c.Ping(ctx); err != nil {
				results[name] = "down"
				status = http.StatusServiceUnavailable
				continue
			}
			results[name] = "up"
		}
		overall := "ok"
		if status != http.StatusOK {
			overall = "unavailable"
		}
		httpx.WriteJSON(w, status, map[string]any{"status": overall, "checks": results})
	}
}
