package receipts

import (
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"pennywise/backend/internal/httpx"
	"pennywise/backend/internal/ratelimit"
)

// RateLimiter is the part of ratelimit.Limiter the handlers use.
type RateLimiter = ratelimit.Allower

var ruleUpload = ratelimit.Rule{Name: "receipt-upload", Limit: 60, Window: time.Hour}

// Handler serves /v1/receipts. svc is nil when R2 is not configured; the
// routes then answer 503 so the phone keeps receipts on the device.
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
	r.Route("/receipts", func(r chi.Router) {
		r.Use(h.requireAuth, h.available)
		r.With(ratelimit.Middleware(h.limiter, ruleUpload, func(r *http.Request) string {
			return h.userID(r).String()
		}, h.log)).Post("/upload-url", h.uploadURL)
		r.Post("/{id}/confirm", h.confirm)
		r.Get("/{id}/url", h.viewURL)
		r.Delete("/{id}", h.remove)
	})
}

func (h *Handler) available(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if h.svc == nil {
			httpx.WriteError(w, http.StatusServiceUnavailable, "receipts_unavailable", "receipt upload is not set up on this server")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (h *Handler) uploadURL(w http.ResponseWriter, r *http.Request) {
	user := h.userID(r)
	var req UploadRequest
	if !httpx.DecodeJSON(w, r, &req) {
		return
	}
	up, err := h.svc.UploadURL(r.Context(), user, req)
	if err != nil {
		h.writeErr(w, r, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, up)
}

func (h *Handler) confirm(w http.ResponseWriter, r *http.Request) {
	id, ok := h.id(w, r)
	if !ok {
		return
	}
	if err := h.svc.Confirm(r.Context(), h.userID(r), id); err != nil {
		h.writeErr(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) viewURL(w http.ResponseWriter, r *http.Request) {
	id, ok := h.id(w, r)
	if !ok {
		return
	}
	url, exp, err := h.svc.ViewURL(r.Context(), h.userID(r), id)
	if err != nil {
		h.writeErr(w, r, err)
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"url": url, "expires_at": exp})
}

func (h *Handler) remove(w http.ResponseWriter, r *http.Request) {
	id, ok := h.id(w, r)
	if !ok {
		return
	}
	if err := h.svc.Delete(r.Context(), h.userID(r), id); err != nil {
		h.writeErr(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) id(w http.ResponseWriter, r *http.Request) (uuid.UUID, bool) {
	id, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		httpx.WriteError(w, http.StatusNotFound, "not_found", "receipt not found")
		return uuid.Nil, false
	}
	return id, true
}

func (h *Handler) writeErr(w http.ResponseWriter, r *http.Request, err error) {
	switch {
	case errors.Is(err, ErrNotFound):
		httpx.WriteError(w, http.StatusNotFound, "not_found", "receipt not found")
	case errors.Is(err, ErrBadType):
		httpx.WriteError(w, http.StatusUnprocessableEntity, "bad_type", "receipts must be JPEG or PNG")
	case errors.Is(err, ErrTooBig):
		httpx.WriteError(w, http.StatusUnprocessableEntity, "too_big", "receipts must be at most 2 MB")
	case errors.Is(err, ErrTooMany):
		httpx.WriteError(w, http.StatusConflict, "too_many", "a transaction can have at most 3 receipts")
	case errors.Is(err, ErrNoTransaction):
		httpx.WriteError(w, http.StatusConflict, "transaction_not_synced", "sync the transaction first")
	case errors.Is(err, ErrNotUploaded):
		httpx.WriteError(w, http.StatusConflict, "not_uploaded", "the file has not arrived yet")
	case errors.Is(err, ErrMismatch):
		httpx.WriteError(w, http.StatusUnprocessableEntity, "mismatch", "the uploaded file is not the announced one")
	case errors.Is(err, ErrConflict):
		httpx.WriteError(w, http.StatusConflict, "id_conflict", "this receipt id is already used")
	default:
		h.fail(w, r, err)
	}
}

func (h *Handler) fail(w http.ResponseWriter, r *http.Request, err error) {
	h.log.ErrorContext(r.Context(), "receipts request failed", "path", r.URL.Path, "err", err)
	httpx.WriteError(w, http.StatusInternalServerError, "internal", "something went wrong")
}
