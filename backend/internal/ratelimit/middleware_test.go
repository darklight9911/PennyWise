package ratelimit

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

type fakeAllower struct {
	allow bool
	err   error
	keys  []string
}

func (f *fakeAllower) Allow(_ context.Context, _ Rule, key string) (bool, time.Duration, error) {
	f.keys = append(f.keys, key)
	return f.allow, 30 * time.Second, f.err
}

func TestMiddleware(t *testing.T) {
	quiet := slog.New(slog.NewTextHandler(io.Discard, nil))
	ok := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusTeapot) })
	run := func(f *fakeAllower, key string) *httptest.ResponseRecorder {
		h := Middleware(f, Rule{Name: "t", Limit: 1, Window: time.Minute}, func(*http.Request) string { return key }, quiet)(ok)
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodGet, "/", nil)
		req.RemoteAddr = "203.0.113.9:4444"
		h.ServeHTTP(rec, req)
		return rec
	}
	if rec := run(&fakeAllower{allow: true}, "k"); rec.Code != http.StatusTeapot {
		t.Errorf("allowed: %d", rec.Code)
	}
	rec := run(&fakeAllower{allow: false}, "k")
	if rec.Code != http.StatusTooManyRequests || rec.Header().Get("Retry-After") != "31" {
		t.Errorf("blocked: %d retry %q", rec.Code, rec.Header().Get("Retry-After"))
	}
	if rec := run(&fakeAllower{err: errors.New("redis down")}, "k"); rec.Code != http.StatusTeapot {
		t.Errorf("limiter down must not block: %d", rec.Code)
	}
	f := &fakeAllower{}
	if rec := run(f, ""); rec.Code != http.StatusTeapot || len(f.keys) != 0 {
		t.Errorf("no key: %d %v", rec.Code, f.keys)
	}

	req := httptest.NewRequest(http.MethodGet, "/", nil)
	req.RemoteAddr = "[2001:db8::1]:443"
	if ClientIP(req) != "2001:db8::1" {
		t.Errorf("ClientIP = %s", ClientIP(req))
	}
}
