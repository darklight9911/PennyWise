package exports

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"pennywise/backend/internal/httpx"
	"pennywise/backend/internal/ratelimit"
	"pennywise/backend/internal/reports"
)

// RateLimiter is the part of ratelimit.Limiter the handlers use.
type RateLimiter interface {
	Allow(ctx context.Context, rule ratelimit.Rule, key string) (bool, time.Duration, error)
}

var ruleExport = ratelimit.Rule{Name: "export", Limit: 20, Window: time.Hour}

// Handler serves /v1/exports. svc is nil when R2 is not configured.
type Handler struct {
	svc         *Service
	limiter     RateLimiter
	requireAuth func(http.Handler) http.Handler
	userID      func(*http.Request) uuid.UUID
	log         *slog.Logger
}

// NewHandler creates the handler.
func NewHandler(svc *Service, limiter RateLimiter, requireAuth func(http.Handler) http.Handler,
	userID func(*http.Request) uuid.UUID, log *slog.Logger) *Handler {
	return &Handler{svc: svc, limiter: limiter, requireAuth: requireAuth, userID: userID, log: log}
}

// Routes mounts the routes.
func (h *Handler) Routes(r chi.Router) {
	r.Route("/exports", func(r chi.Router) {
		r.Use(h.requireAuth, h.available)
		r.Post("/", h.create)
		r.Get("/{id}", h.get)
	})
}

func (h *Handler) available(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if h.svc == nil {
			httpx.WriteError(w, http.StatusServiceUnavailable, "exports_unavailable", "export is not set up on this server")
			return
		}
		next.ServeHTTP(w, r)
	})
}

type createRequest struct {
	Format string `json:"format"`
	From   string `json:"from"`
	To     string `json:"to"`
}

func (h *Handler) create(w http.ResponseWriter, r *http.Request) {
	user := h.userID(r)
	ok, retry, err := h.limiter.Allow(r.Context(), ruleExport, user.String())
	if err != nil {
		h.fail(w, r, err)
		return
	}
	if !ok {
		w.Header().Set("Retry-After", strconv.Itoa(int(retry.Seconds())+1))
		httpx.WriteError(w, http.StatusTooManyRequests, "rate_limited", "too many exports, try again later")
		return
	}
	var req createRequest
	if !httpx.DecodeJSON(w, r, &req) {
		return
	}
	rg, err := reports.ParseRange(req.From, req.To)
	if err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_range", "from and to must be YYYY-MM-DD dates, from <= to, at most 5 years apart")
		return
	}
	e, err := h.svc.Create(r.Context(), user, req.Format, rg)
	switch {
	case errors.Is(err, ErrBadFormat):
		httpx.WriteError(w, http.StatusBadRequest, "bad_format", "format must be csv or pdf")
	case errors.Is(err, ErrTooMany):
		httpx.WriteError(w, http.StatusConflict, "too_many", "wait for your other exports to finish")
	case err != nil:
		h.fail(w, r, err)
	default:
		httpx.WriteJSON(w, http.StatusAccepted, map[string]Export{"export": e})
	}
}

func (h *Handler) get(w http.ResponseWriter, r *http.Request) {
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		httpx.WriteError(w, http.StatusNotFound, "not_found", "export not found")
		return
	}
	e, err := h.svc.Get(r.Context(), h.userID(r), id)
	if errors.Is(err, ErrNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "not_found", "export not found")
		return
	}
	if err != nil {
		h.fail(w, r, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]Export{"export": e})
}

func (h *Handler) fail(w http.ResponseWriter, r *http.Request, err error) {
	h.log.ErrorContext(r.Context(), "exports request failed", "path", r.URL.Path, "err", err)
	httpx.WriteError(w, http.StatusInternalServerError, "internal", "something went wrong")
}
