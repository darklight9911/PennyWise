package datasync

import (
	"errors"
	"log/slog"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"pennywise/backend/internal/httpx"
)

// maxPushBody allows a full batch of MaxPushChanges rows with long notes.
const maxPushBody = 4 << 20 // 4 MiB

// Handler exposes push and pull over HTTP.
type Handler struct {
	svc         *Service
	requireAuth func(http.Handler) http.Handler
	userID      func(*http.Request) uuid.UUID
	logger      *slog.Logger
}

// NewHandler wires the handler. requireAuth and userID come from the auth package.
func NewHandler(svc *Service, requireAuth func(http.Handler) http.Handler, userID func(*http.Request) uuid.UUID, logger *slog.Logger) *Handler {
	return &Handler{svc: svc, requireAuth: requireAuth, userID: userID, logger: logger}
}

// Routes mounts /sync/push and /sync/pull under the given router (expected: /v1).
func (h *Handler) Routes(r chi.Router) {
	r.Route("/sync", func(r chi.Router) {
		r.Use(h.requireAuth)
		r.Post("/push", h.push)
		r.Get("/pull", h.pull)
	})
}

func (h *Handler) push(w http.ResponseWriter, r *http.Request) {
	var req PushRequest
	if !httpx.DecodeJSONLimit(w, r, &req, maxPushBody) {
		return
	}
	resp, err := h.svc.Push(r.Context(), h.userID(r), req)
	switch {
	case errors.Is(err, ErrTooManyChanges):
		httpx.WriteError(w, http.StatusRequestEntityTooLarge, "too_many_changes", err.Error())
	case errors.Is(err, ErrUserNotFound):
		httpx.WriteError(w, http.StatusUnauthorized, "invalid_token", "account no longer exists")
	case err != nil:
		h.logger.ErrorContext(r.Context(), "sync push failed", "err", err)
		httpx.WriteError(w, http.StatusInternalServerError, "internal", "something went wrong")
	default:
		httpx.WriteJSON(w, http.StatusOK, resp)
	}
}

func (h *Handler) pull(w http.ResponseWriter, r *http.Request) {
	since := int64(0)
	if raw := r.URL.Query().Get("since"); raw != "" {
		v, err := strconv.ParseInt(raw, 10, 64)
		if err != nil || v < 0 {
			httpx.WriteError(w, http.StatusBadRequest, "invalid_cursor", "since must be a non-negative number")
			return
		}
		since = v
	}
	resp, err := h.svc.Pull(r.Context(), h.userID(r), since)
	switch {
	case errors.Is(err, ErrUserNotFound):
		httpx.WriteError(w, http.StatusUnauthorized, "invalid_token", "account no longer exists")
	case err != nil:
		h.logger.ErrorContext(r.Context(), "sync pull failed", "err", err)
		httpx.WriteError(w, http.StatusInternalServerError, "internal", "something went wrong")
	default:
		httpx.WriteJSON(w, http.StatusOK, resp)
	}
}
