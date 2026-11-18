package ratelimit

import (
	"context"
	"log/slog"
	"net"
	"net/http"
	"strconv"
	"time"

	"pennywise/backend/internal/httpx"
)

// Allower is the part of Limiter that Middleware needs.
type Allower interface {
	Allow(ctx context.Context, rule Rule, key string) (bool, time.Duration, error)
}

// Middleware limits requests per key (e.g. the caller's IP or user id).
// If Redis is down it lets requests through and logs it: an outage of the
// limiter must not take the whole API down.
func Middleware(l Allower, rule Rule, key func(*http.Request) string, log *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			k := key(r)
			if k == "" {
				next.ServeHTTP(w, r)
				return
			}
			ok, retry, err := l.Allow(r.Context(), rule, k)
			if err != nil {
				log.ErrorContext(r.Context(), "rate limiter unavailable", "rule", rule.Name, "err", err)
				next.ServeHTTP(w, r)
				return
			}
			if !ok {
				w.Header().Set("Retry-After", strconv.Itoa(int(retry.Seconds())+1))
				httpx.WriteError(w, http.StatusTooManyRequests, "rate_limited", "too many requests, try again later")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// ClientIP is the caller's IP without the port (RealIP has already applied
// X-Forwarded-For from the reverse proxy).
func ClientIP(r *http.Request) string {
	if host, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
		return host
	}
	return r.RemoteAddr
}
