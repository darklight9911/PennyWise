package auth

import (
	"context"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"pennywise/backend/internal/db"
	"pennywise/backend/internal/httpx"
	"pennywise/backend/internal/ratelimit"
)

// RateLimiter is the part of ratelimit.Limiter the handlers use.
type RateLimiter interface {
	Allow(ctx context.Context, rule ratelimit.Rule, key string) (bool, time.Duration, error)
}

// Limits on auth endpoints. Per-IP rules stop floods; the per-email login
// rule stops slow password guessing against one account from many IPs.
var (
	ruleRegister   = ratelimit.Rule{Name: "register", Limit: 5, Window: 10 * time.Minute}
	ruleLoginIP    = ratelimit.Rule{Name: "login-ip", Limit: 20, Window: time.Minute}
	ruleLoginEmail = ratelimit.Rule{Name: "login-email", Limit: 10, Window: 15 * time.Minute}
	ruleGoogle     = ratelimit.Rule{Name: "google", Limit: 20, Window: time.Minute}
	ruleRefresh    = ratelimit.Rule{Name: "refresh", Limit: 60, Window: time.Minute}
	ruleEmailLink  = ratelimit.Rule{Name: "email-link", Limit: 20, Window: 10 * time.Minute}
	ruleSendEmail  = ratelimit.Rule{Name: "send-email", Limit: 3, Window: time.Hour}
)

// Handler exposes the auth service over HTTP.
type Handler struct {
	svc     *Service
	limiter RateLimiter
	logger  *slog.Logger
}

// NewHandler creates the HTTP handler.
func NewHandler(svc *Service, limiter RateLimiter, logger *slog.Logger) *Handler {
	return &Handler{svc: svc, limiter: limiter, logger: logger}
}

// Routes mounts the auth endpoints under the given router (expected: /v1).
func (h *Handler) Routes(r chi.Router) {
	r.Route("/auth", func(r chi.Router) {
		r.Post("/register", h.register)
		r.Post("/login", h.login)
		r.Post("/google", h.googleLogin)
		r.Post("/refresh", h.refresh)
		r.Post("/logout", h.logout)
		r.Post("/verify-email", h.verifyEmail)
		r.Post("/forgot-password", h.forgotPassword)
		r.Post("/reset-password", h.resetPassword)
		r.With(h.RequireAuth).Post("/resend-verification", h.resendVerification)
	})
	r.With(h.RequireAuth).Get("/me", h.me)
}

// --- request / response shapes ---

type profileFields struct {
	Name         string `json:"name"`
	BaseCurrency string `json:"base_currency"`
	Locale       string `json:"locale"`
	Timezone     string `json:"timezone"`
}

func (p profileFields) toProfile() Profile {
	return Profile{Name: p.Name, BaseCurrency: p.BaseCurrency, Locale: p.Locale, Timezone: p.Timezone}
}

// UserResponse is the public view of a user. Never return db.User directly:
// it contains the password hash.
type UserResponse struct {
	ID                 uuid.UUID `json:"id"`
	Email              string    `json:"email"`
	Name               string    `json:"name"`
	BaseCurrency       string    `json:"base_currency"`
	BaseCurrencyStatus string    `json:"base_currency_status"`
	Locale             string    `json:"locale"`
	Timezone           string    `json:"timezone"`
	EmailVerified      bool      `json:"email_verified"`
	HasPassword        bool      `json:"has_password"`
	GoogleLinked       bool      `json:"google_linked"`
	CreatedAt          time.Time `json:"created_at"`
}

func toUserResponse(u db.User) UserResponse {
	return UserResponse{
		ID:                 u.ID,
		Email:              u.Email,
		Name:               u.Name,
		BaseCurrency:       u.BaseCurrency,
		BaseCurrencyStatus: u.BaseCurrencyStatus,
		Locale:             u.Locale,
		Timezone:           u.Timezone,
		EmailVerified:      u.EmailVerifiedAt.Valid,
		HasPassword:        u.PasswordHash.Valid,
		GoogleLinked:       u.GoogleSub.Valid,
		CreatedAt:          u.CreatedAt.Time.UTC(),
	}
}

type authResponse struct {
	User    UserResponse `json:"user"`
	Tokens  Tokens       `json:"tokens"`
	Created bool         `json:"created,omitempty"`
}

// --- handlers ---

func (h *Handler) register(w http.ResponseWriter, r *http.Request) {
	if !h.allow(w, r, ruleRegister, clientIP(r)) {
		return
	}
	var req struct {
		Email      string `json:"email"`
		Password   string `json:"password"`
		DeviceName string `json:"device_name"`
		profileFields
	}
	if !httpx.DecodeJSON(w, r, &req) {
		return
	}
	user, tokens, err := h.svc.Register(r.Context(), RegisterInput{
		Email: req.Email, Password: req.Password, DeviceName: req.DeviceName, Profile: req.toProfile(),
	})
	if err != nil {
		h.writeErr(w, r, err)
		return
	}
	httpx.WriteJSON(w, http.StatusCreated, authResponse{User: toUserResponse(user), Tokens: tokens, Created: true})
}

func (h *Handler) login(w http.ResponseWriter, r *http.Request) {
	if !h.allow(w, r, ruleLoginIP, clientIP(r)) {
		return
	}
	var req struct {
		Email      string `json:"email"`
		Password   string `json:"password"`
		DeviceName string `json:"device_name"`
	}
	if !httpx.DecodeJSON(w, r, &req) {
		return
	}
	if !h.allow(w, r, ruleLoginEmail, strings.ToLower(strings.TrimSpace(req.Email))) {
		return
	}
	user, tokens, err := h.svc.Login(r.Context(), req.Email, req.Password, req.DeviceName)
	if err != nil {
		h.writeErr(w, r, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, authResponse{User: toUserResponse(user), Tokens: tokens})
}

func (h *Handler) googleLogin(w http.ResponseWriter, r *http.Request) {
	if !h.allow(w, r, ruleGoogle, clientIP(r)) {
		return
	}
	var req struct {
		IDToken    string `json:"id_token"`
		DeviceName string `json:"device_name"`
		profileFields
	}
	if !httpx.DecodeJSON(w, r, &req) {
		return
	}
	user, tokens, created, err := h.svc.LoginWithGoogle(r.Context(), GoogleInput{
		IDToken: req.IDToken, DeviceName: req.DeviceName, Profile: req.toProfile(),
	})
	if err != nil {
		h.writeErr(w, r, err)
		return
	}
	status := http.StatusOK
	if created {
		status = http.StatusCreated
	}
	httpx.WriteJSON(w, status, authResponse{User: toUserResponse(user), Tokens: tokens, Created: created})
}

func (h *Handler) refresh(w http.ResponseWriter, r *http.Request) {
	if !h.allow(w, r, ruleRefresh, clientIP(r)) {
		return
	}
	var req struct {
		RefreshToken string `json:"refresh_token"`
	}
	if !httpx.DecodeJSON(w, r, &req) {
		return
	}
	tokens, err := h.svc.Refresh(r.Context(), req.RefreshToken)
	if err != nil {
		h.writeErr(w, r, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]Tokens{"tokens": tokens})
}

func (h *Handler) logout(w http.ResponseWriter, r *http.Request) {
	var req struct {
		RefreshToken string `json:"refresh_token"`
	}
	if !httpx.DecodeJSON(w, r, &req) {
		return
	}
	if err := h.svc.Logout(r.Context(), req.RefreshToken); err != nil {
		h.writeErr(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) verifyEmail(w http.ResponseWriter, r *http.Request) {
	if !h.allow(w, r, ruleEmailLink, clientIP(r)) {
		return
	}
	var req struct {
		Token string `json:"token"`
	}
	if !httpx.DecodeJSON(w, r, &req) {
		return
	}
	if err := h.svc.VerifyEmail(r.Context(), req.Token); err != nil {
		h.writeErr(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) resendVerification(w http.ResponseWriter, r *http.Request) {
	userID := UserID(r.Context())
	if !h.allow(w, r, ruleSendEmail, "user:"+userID.String()) {
		return
	}
	if err := h.svc.ResendVerification(r.Context(), userID); err != nil {
		h.writeErr(w, r, err)
		return
	}
	w.WriteHeader(http.StatusAccepted)
}

func (h *Handler) forgotPassword(w http.ResponseWriter, r *http.Request) {
	if !h.allow(w, r, ruleSendEmail, clientIP(r)) {
		return
	}
	var req struct {
		Email string `json:"email"`
	}
	if !httpx.DecodeJSON(w, r, &req) {
		return
	}
	if err := h.svc.ForgotPassword(r.Context(), req.Email); err != nil {
		h.writeErr(w, r, err)
		return
	}
	// Same answer whether or not the email exists.
	w.WriteHeader(http.StatusAccepted)
}

func (h *Handler) resetPassword(w http.ResponseWriter, r *http.Request) {
	if !h.allow(w, r, ruleEmailLink, clientIP(r)) {
		return
	}
	var req struct {
		Token       string `json:"token"`
		NewPassword string `json:"new_password"`
	}
	if !httpx.DecodeJSON(w, r, &req) {
		return
	}
	if err := h.svc.ResetPassword(r.Context(), req.Token, req.NewPassword); err != nil {
		h.writeErr(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) me(w http.ResponseWriter, r *http.Request) {
	user, err := h.svc.User(r.Context(), UserID(r.Context()))
	if err != nil {
		h.writeErr(w, r, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]UserResponse{"user": toUserResponse(user)})
}

// --- auth middleware ---

type ctxKey struct{}

// RequireAuth rejects requests without a valid "Authorization: Bearer <access token>".
func (h *Handler) RequireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		if !ok || raw == "" {
			w.Header().Set("WWW-Authenticate", `Bearer`)
			httpx.WriteError(w, http.StatusUnauthorized, "unauthorized", "missing access token")
			return
		}
		userID, err := h.svc.VerifyAccessToken(strings.TrimSpace(raw))
		if err != nil {
			w.Header().Set("WWW-Authenticate", `Bearer error="invalid_token"`)
			httpx.WriteError(w, http.StatusUnauthorized, "invalid_token", "access token is invalid or expired")
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), ctxKey{}, userID)))
	})
}

// UserID returns the logged-in user's ID set by RequireAuth.
func UserID(ctx context.Context) uuid.UUID {
	id, _ := ctx.Value(ctxKey{}).(uuid.UUID)
	return id
}

// --- helpers ---

// allow applies a rate-limit rule. If Redis is down it lets the request
// through (and logs), so an outage does not lock everyone out.
func (h *Handler) allow(w http.ResponseWriter, r *http.Request, rule ratelimit.Rule, key string) bool {
	ok, retry, err := h.limiter.Allow(r.Context(), rule, key)
	if err != nil {
		h.logger.ErrorContext(r.Context(), "rate limiter unavailable", "rule", rule.Name, "err", err)
		return true
	}
	if !ok {
		w.Header().Set("Retry-After", strconv.Itoa(int(retry.Seconds())+1))
		httpx.WriteError(w, http.StatusTooManyRequests, "rate_limited", "too many attempts, try again later")
		return false
	}
	return true
}

func (h *Handler) writeErr(w http.ResponseWriter, r *http.Request, err error) {
	var ve *ValidationError
	switch {
	case errors.As(err, &ve):
		httpx.WriteJSON(w, http.StatusUnprocessableEntity, map[string]any{
			"error": map[string]string{"code": "validation_failed", "field": ve.Field, "message": ve.Message},
		})
	case errors.Is(err, ErrEmailTaken):
		httpx.WriteError(w, http.StatusConflict, "email_taken", "an account with this email already exists")
	case errors.Is(err, ErrInvalidCredentials):
		httpx.WriteError(w, http.StatusUnauthorized, "invalid_credentials", "email or password is wrong")
	case errors.Is(err, ErrInvalidRefreshToken):
		httpx.WriteError(w, http.StatusUnauthorized, "invalid_refresh_token", "session expired, please log in again")
	case errors.Is(err, ErrInvalidEmailToken):
		httpx.WriteError(w, http.StatusBadRequest, "invalid_link", "this link is invalid or has expired")
	case errors.Is(err, ErrInvalidGoogleToken):
		httpx.WriteError(w, http.StatusUnauthorized, "invalid_google_token", "Google sign-in failed")
	case errors.Is(err, ErrGoogleEmailNotVerified):
		httpx.WriteError(w, http.StatusForbidden, "google_email_unverified", "your Google account email is not verified")
	case errors.Is(err, ErrGoogleAccountConflict):
		httpx.WriteError(w, http.StatusConflict, "google_account_conflict", "this email is linked to a different Google account")
	case errors.Is(err, ErrGoogleNotConfigured):
		httpx.WriteError(w, http.StatusServiceUnavailable, "google_not_configured", "Google sign-in is not available yet")
	case errors.Is(err, ErrUserNotFound):
		httpx.WriteError(w, http.StatusUnauthorized, "invalid_token", "account no longer exists")
	default:
		h.logger.ErrorContext(r.Context(), "auth request failed", "path", r.URL.Path, "err", err)
		httpx.WriteError(w, http.StatusInternalServerError, "internal", "something went wrong")
	}
}

// clientIP returns the caller's IP without the port. chi's RealIP middleware
// has already replaced RemoteAddr with X-Forwarded-For from Caddy.
func clientIP(r *http.Request) string {
	if host, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
		return host
	}
	return r.RemoteAddr
}
