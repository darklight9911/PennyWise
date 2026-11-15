package auth_test

// Integration tests: real PostgreSQL + Redis, full HTTP stack.
// They run when TEST_DATABASE_URL and TEST_REDIS_URL are set, e.g.:
//
//	TEST_DATABASE_URL=postgres://pennywise:pennywise_dev_password@localhost:5432/pennywise_test?sslmode=disable \
//	TEST_REDIS_URL=redis://localhost:6379/15 go test ./internal/auth/
//
// WARNING: they wipe the users table and the Redis DB they are given.

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"regexp"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"
	"github.com/prometheus/client_golang/prometheus"
	goredis "github.com/redis/go-redis/v9"

	"pennywise/backend/internal/auth"
	"pennywise/backend/internal/httpapi"
	"pennywise/backend/internal/mail"
	"pennywise/backend/internal/ratelimit"
	"pennywise/backend/migrations"
)

// --- fakes ---

type captureMailer struct {
	mu   sync.Mutex
	msgs []mail.Message
}

func (c *captureMailer) Send(_ context.Context, m mail.Message) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.msgs = append(c.msgs, m)
	return nil
}

var tokenRe = regexp.MustCompile(`token=([^\s]+)`)

// lastToken returns the token from the newest email to `to` whose subject contains subj.
func (c *captureMailer) lastToken(t *testing.T, to, subj string) string {
	t.Helper()
	c.mu.Lock()
	defer c.mu.Unlock()
	for i := len(c.msgs) - 1; i >= 0; i-- {
		m := c.msgs[i]
		if strings.EqualFold(m.To, to) && strings.Contains(m.Subject, subj) {
			tok, err := url.QueryUnescape(tokenRe.FindStringSubmatch(m.Text)[1])
			if err != nil {
				t.Fatal(err)
			}
			return tok
		}
	}
	t.Fatalf("no %q email to %s", subj, to)
	return ""
}

func (c *captureMailer) count() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	return len(c.msgs)
}

// fakeGoogle accepts tokens of the form "sub|email|verified".
type fakeGoogle struct{}

func (fakeGoogle) Verify(_ context.Context, raw string) (auth.GoogleIdentity, error) {
	p := strings.Split(raw, "|")
	if len(p) != 3 {
		return auth.GoogleIdentity{}, auth.ErrInvalidGoogleToken
	}
	return auth.GoogleIdentity{Subject: p[0], Email: p[1], EmailVerified: p[2] == "true", Name: "G User"}, nil
}

// --- harness ---

type env struct {
	t      *testing.T
	srv    *httptest.Server
	mailer *captureMailer
}

func setup(t *testing.T, google auth.GoogleVerifier) *env {
	t.Helper()
	dbURL, redisURL := os.Getenv("TEST_DATABASE_URL"), os.Getenv("TEST_REDIS_URL")
	if dbURL == "" || redisURL == "" {
		t.Skip("TEST_DATABASE_URL / TEST_REDIS_URL not set")
	}
	ctx := context.Background()

	sqlDB, err := sql.Open("pgx", dbURL)
	if err != nil {
		t.Fatal(err)
	}
	goose.SetBaseFS(migrations.FS)
	goose.SetLogger(goose.NopLogger())
	if err := goose.SetDialect("postgres"); err != nil {
		t.Fatal(err)
	}
	if err := goose.Up(sqlDB, "."); err != nil {
		t.Fatal(err)
	}
	if _, err := sqlDB.Exec("TRUNCATE users CASCADE"); err != nil {
		t.Fatal(err)
	}
	sqlDB.Close()

	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)

	opts, err := goredis.ParseURL(redisURL)
	if err != nil {
		t.Fatal(err)
	}
	rdb := goredis.NewClient(opts)
	t.Cleanup(func() { rdb.Close() })
	if err := rdb.FlushDB(ctx).Err(); err != nil {
		t.Fatal(err)
	}

	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	jwtIssuer, err := auth.NewJWTIssuer([]byte(strings.Repeat("s", 32)), 15*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	mailer := &captureMailer{}
	svc := auth.NewService(pool, jwtIssuer, google, mailer, auth.Config{RefreshTTL: time.Hour, LinkBase: "pennywise://"}, logger)
	h := auth.NewHandler(svc, ratelimit.New(rdb), logger)

	router := httpapi.NewRouter(httpapi.Deps{
		Logger: logger, Registry: prometheus.NewRegistry(), V1: []func(chi.Router){h.Routes},
	})
	srv := httptest.NewServer(router)
	t.Cleanup(srv.Close)
	return &env{t: t, srv: srv, mailer: mailer}
}

type resp struct {
	Status int
	Header http.Header
	Body   map[string]any
}

func (e *env) do(method, path, bearer string, body any) resp {
	e.t.Helper()
	var r io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		r = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(method, e.srv.URL+path, r)
	req.Header.Set("Content-Type", "application/json")
	if bearer != "" {
		req.Header.Set("Authorization", "Bearer "+bearer)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		e.t.Fatal(err)
	}
	defer res.Body.Close()
	out := resp{Status: res.StatusCode, Header: res.Header}
	raw, _ := io.ReadAll(res.Body)
	if len(raw) > 0 {
		if err := json.Unmarshal(raw, &out.Body); err != nil {
			e.t.Fatalf("%s %s: bad JSON %q", method, path, raw)
		}
	}
	return out
}

func (e *env) post(path string, body any) resp { return e.do(http.MethodPost, path, "", body) }

func expectStatus(t *testing.T, r resp, want int) {
	t.Helper()
	if r.Status != want {
		t.Fatalf("status = %d, want %d; body = %v", r.Status, want, r.Body)
	}
}

func errCode(r resp) string {
	e, _ := r.Body["error"].(map[string]any)
	s, _ := e["code"].(string)
	return s
}

func tokens(r resp) (access, refresh string) {
	tk := r.Body["tokens"].(map[string]any)
	return tk["access_token"].(string), tk["refresh_token"].(string)
}

func user(r resp) map[string]any { return r.Body["user"].(map[string]any) }

const pw = "a-strong-password"

func (e *env) register(email string) resp {
	e.t.Helper()
	r := e.post("/v1/auth/register", map[string]any{
		"email": email, "password": pw, "name": "Ann", "base_currency": "EUR",
		"timezone": "Asia/Dhaka", "device_name": "Pixel 9",
	})
	expectStatus(e.t, r, http.StatusCreated)
	return r
}

// --- tests ---

func TestRegisterVerifyAndMe(t *testing.T) {
	e := setup(t, nil)
	r := e.register("ann@example.com")
	u := user(r)
	if u["email_verified"] != false || u["base_currency"] != "EUR" || u["timezone"] != "Asia/Dhaka" || u["has_password"] != true {
		t.Fatalf("unexpected user: %v", u)
	}
	if _, ok := u["password_hash"]; ok {
		t.Fatal("password hash leaked in response")
	}
	access, _ := tokens(r)

	me := e.do(http.MethodGet, "/v1/me", access, nil)
	expectStatus(t, me, http.StatusOK)

	tok := e.mailer.lastToken(t, "ann@example.com", "Confirm")
	expectStatus(t, e.post("/v1/auth/verify-email", map[string]string{"token": tok}), http.StatusNoContent)
	if user(e.do(http.MethodGet, "/v1/me", access, nil))["email_verified"] != true {
		t.Fatal("email not verified after link")
	}
	// A link works once.
	again := e.post("/v1/auth/verify-email", map[string]string{"token": tok})
	expectStatus(t, again, http.StatusBadRequest)
	if errCode(again) != "invalid_link" {
		t.Fatalf("code = %s", errCode(again))
	}
}

func TestResendVerificationInvalidatesOldLink(t *testing.T) {
	e := setup(t, nil)
	access, _ := tokens(e.register("bo@example.com"))
	first := e.mailer.lastToken(t, "bo@example.com", "Confirm")
	expectStatus(t, e.do(http.MethodPost, "/v1/auth/resend-verification", access, nil), http.StatusAccepted)
	second := e.mailer.lastToken(t, "bo@example.com", "Confirm")
	if first == second {
		t.Fatal("resend returned the same token")
	}
	expectStatus(t, e.post("/v1/auth/verify-email", map[string]string{"token": first}), http.StatusBadRequest)
	expectStatus(t, e.post("/v1/auth/verify-email", map[string]string{"token": second}), http.StatusNoContent)
}

func TestRegisterDuplicateEmailIgnoresCase(t *testing.T) {
	e := setup(t, nil)
	e.register("cy@example.com")
	r := e.post("/v1/auth/register", map[string]any{"email": "CY@Example.com", "password": pw})
	expectStatus(t, r, http.StatusConflict)
	if errCode(r) != "email_taken" {
		t.Fatalf("code = %s", errCode(r))
	}
}

func TestRegisterValidation(t *testing.T) {
	e := setup(t, nil)
	cases := map[string]map[string]any{
		"email":         {"email": "not-an-email", "password": pw},
		"password":      {"email": "d@example.com", "password": "short"},
		"base_currency": {"email": "d@example.com", "password": pw, "base_currency": "dollars"},
		"timezone":      {"email": "d@example.com", "password": pw, "timezone": "Mars/Base"},
	}
	for field, body := range cases {
		r := e.post("/v1/auth/register", body)
		expectStatus(t, r, http.StatusUnprocessableEntity)
		if got := r.Body["error"].(map[string]any)["field"]; got != field {
			t.Errorf("field = %v, want %s", got, field)
		}
	}
	// Unknown JSON fields are rejected, not silently ignored.
	expectStatus(t, e.post("/v1/auth/register", map[string]any{"email": "d@example.com", "password": pw, "is_admin": true}), http.StatusBadRequest)
}

func TestLogin(t *testing.T) {
	e := setup(t, nil)
	e.register("di@example.com")

	ok := e.post("/v1/auth/login", map[string]string{"email": "DI@example.com", "password": pw})
	expectStatus(t, ok, http.StatusOK)

	wrongPw := e.post("/v1/auth/login", map[string]string{"email": "di@example.com", "password": "wrong-password"})
	noUser := e.post("/v1/auth/login", map[string]string{"email": "nobody@example.com", "password": pw})
	for _, r := range []resp{wrongPw, noUser} {
		expectStatus(t, r, http.StatusUnauthorized)
		if errCode(r) != "invalid_credentials" {
			t.Fatalf("code = %s", errCode(r))
		}
	}
	if wrongPw.Body["error"].(map[string]any)["message"] != noUser.Body["error"].(map[string]any)["message"] {
		t.Fatal("wrong password and unknown user give different messages (user enumeration)")
	}
}

func TestRefreshRotationAndReuseDetection(t *testing.T) {
	e := setup(t, nil)
	_, r1 := tokens(e.register("ed@example.com"))

	res := e.post("/v1/auth/refresh", map[string]string{"refresh_token": r1})
	expectStatus(t, res, http.StatusOK)
	a2, r2 := tokens(res)
	if r2 == r1 {
		t.Fatal("refresh token not rotated")
	}
	expectStatus(t, e.do(http.MethodGet, "/v1/me", a2, nil), http.StatusOK)

	// Replaying the used token is treated as theft: it fails AND kills r2.
	expectStatus(t, e.post("/v1/auth/refresh", map[string]string{"refresh_token": r1}), http.StatusUnauthorized)
	expectStatus(t, e.post("/v1/auth/refresh", map[string]string{"refresh_token": r2}), http.StatusUnauthorized)
}

func TestParallelRefreshOnlyOneWins(t *testing.T) {
	e := setup(t, nil)
	_, r1 := tokens(e.register("fi@example.com"))

	const n = 5
	var wg sync.WaitGroup
	statuses := make(chan int, n)
	for range n {
		wg.Add(1)
		go func() {
			defer wg.Done()
			statuses <- e.post("/v1/auth/refresh", map[string]string{"refresh_token": r1}).Status
		}()
	}
	wg.Wait()
	close(statuses)
	wins := 0
	for s := range statuses {
		if s == http.StatusOK {
			wins++
		}
	}
	if wins != 1 {
		t.Fatalf("%d parallel refreshes succeeded, want exactly 1", wins)
	}
}

func TestLogout(t *testing.T) {
	e := setup(t, nil)
	_, r1 := tokens(e.register("gu@example.com"))
	expectStatus(t, e.post("/v1/auth/logout", map[string]string{"refresh_token": r1}), http.StatusNoContent)
	expectStatus(t, e.post("/v1/auth/refresh", map[string]string{"refresh_token": r1}), http.StatusUnauthorized)
	// Unknown token: still 204, nothing to reveal.
	expectStatus(t, e.post("/v1/auth/logout", map[string]string{"refresh_token": "nope"}), http.StatusNoContent)
}

func TestForgotAndResetPassword(t *testing.T) {
	e := setup(t, nil)
	_, oldRefresh := tokens(e.register("hu@example.com"))

	before := e.mailer.count()
	expectStatus(t, e.post("/v1/auth/forgot-password", map[string]string{"email": "nobody@example.com"}), http.StatusAccepted)
	if e.mailer.count() != before {
		t.Fatal("email sent for unknown address")
	}
	expectStatus(t, e.post("/v1/auth/forgot-password", map[string]string{"email": "hu@example.com"}), http.StatusAccepted)
	tok := e.mailer.lastToken(t, "hu@example.com", "Reset")

	expectStatus(t, e.post("/v1/auth/reset-password", map[string]string{"token": tok, "new_password": "short"}), http.StatusUnprocessableEntity)
	expectStatus(t, e.post("/v1/auth/reset-password", map[string]string{"token": tok, "new_password": "brand-new-password"}), http.StatusNoContent)
	expectStatus(t, e.post("/v1/auth/reset-password", map[string]string{"token": tok, "new_password": "another-password"}), http.StatusBadRequest)

	// Every device is logged out; only the new password works; the email counts as verified.
	expectStatus(t, e.post("/v1/auth/refresh", map[string]string{"refresh_token": oldRefresh}), http.StatusUnauthorized)
	expectStatus(t, e.post("/v1/auth/login", map[string]string{"email": "hu@example.com", "password": pw}), http.StatusUnauthorized)
	ok := e.post("/v1/auth/login", map[string]string{"email": "hu@example.com", "password": "brand-new-password"})
	expectStatus(t, ok, http.StatusOK)
	if user(ok)["email_verified"] != true {
		t.Fatal("reset did not mark email verified")
	}
}

func TestGoogleSignIn(t *testing.T) {
	e := setup(t, fakeGoogle{})

	first := e.post("/v1/auth/google", map[string]any{"id_token": "g-1|ivy@example.com|true", "base_currency": "GBP"})
	expectStatus(t, first, http.StatusCreated)
	u := user(first)
	if u["email_verified"] != true || u["has_password"] != false || u["google_linked"] != true || u["base_currency"] != "GBP" {
		t.Fatalf("unexpected user: %v", u)
	}
	again := e.post("/v1/auth/google", map[string]any{"id_token": "g-1|ivy@example.com|true"})
	expectStatus(t, again, http.StatusOK)
	if user(again)["id"] != u["id"] {
		t.Fatal("second Google login created another account")
	}

	expectStatus(t, e.post("/v1/auth/google", map[string]any{"id_token": "g-2|jo@example.com|false"}), http.StatusForbidden)
	expectStatus(t, e.post("/v1/auth/google", map[string]any{"id_token": "garbage"}), http.StatusUnauthorized)
	// Same email, different Google account.
	expectStatus(t, e.post("/v1/auth/google", map[string]any{"id_token": "g-9|ivy@example.com|true"}), http.StatusConflict)
}

// An attacker registers the victim's email with a password before the victim
// ever signs up. When the victim signs in with Google, the attacker's password
// must stop working.
func TestGoogleLinkRemovesUnverifiedPassword(t *testing.T) {
	e := setup(t, fakeGoogle{})
	e.register("kim@example.com") // unverified, password set by "attacker"

	r := e.post("/v1/auth/google", map[string]any{"id_token": "g-3|kim@example.com|true"})
	expectStatus(t, r, http.StatusOK)
	if u := user(r); u["has_password"] != false || u["email_verified"] != true {
		t.Fatalf("unexpected user after link: %v", u)
	}
	expectStatus(t, e.post("/v1/auth/login", map[string]string{"email": "kim@example.com", "password": pw}), http.StatusUnauthorized)
}

func TestGoogleLinkKeepsVerifiedPassword(t *testing.T) {
	e := setup(t, fakeGoogle{})
	e.register("lu@example.com")
	tok := e.mailer.lastToken(t, "lu@example.com", "Confirm")
	expectStatus(t, e.post("/v1/auth/verify-email", map[string]string{"token": tok}), http.StatusNoContent)

	r := e.post("/v1/auth/google", map[string]any{"id_token": "g-4|lu@example.com|true"})
	expectStatus(t, r, http.StatusOK)
	if user(r)["has_password"] != true {
		t.Fatal("verified user's password was removed")
	}
	expectStatus(t, e.post("/v1/auth/login", map[string]string{"email": "lu@example.com", "password": pw}), http.StatusOK)
}

func TestGoogleNotConfigured(t *testing.T) {
	e := setup(t, nil)
	r := e.post("/v1/auth/google", map[string]any{"id_token": "x|y@example.com|true"})
	expectStatus(t, r, http.StatusServiceUnavailable)
}

func TestRequireAuth(t *testing.T) {
	e := setup(t, nil)
	for _, bearer := range []string{"", "garbage"} {
		r := e.do(http.MethodGet, "/v1/me", bearer, nil)
		expectStatus(t, r, http.StatusUnauthorized)
		if r.Header.Get("WWW-Authenticate") == "" {
			t.Error("missing WWW-Authenticate header")
		}
	}
}

func TestRegisterRateLimited(t *testing.T) {
	e := setup(t, nil)
	var last resp
	for i := range 6 {
		last = e.post("/v1/auth/register", map[string]any{"email": "rl" + string(rune('a'+i)) + "@example.com", "password": pw})
	}
	expectStatus(t, last, http.StatusTooManyRequests)
	if last.Header.Get("Retry-After") == "" {
		t.Fatal("missing Retry-After")
	}
}

func TestLoginRateLimitedPerEmail(t *testing.T) {
	e := setup(t, nil)
	e.register("mo@example.com")
	var last resp
	for range 11 {
		last = e.post("/v1/auth/login", map[string]string{"email": "mo@example.com", "password": "wrong-password"})
	}
	expectStatus(t, last, http.StatusTooManyRequests)
}
