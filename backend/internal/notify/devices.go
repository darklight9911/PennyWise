package notify

import (
	"log/slog"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"pennywise/backend/internal/httpx"
)

// DevicesHandler lets the app register its push token (POST) and remove
// it at logout (DELETE). A token moved to another account (shared phone,
// new login) is re-assigned, so messages never reach the previous user.
type DevicesHandler struct {
	pool        *pgxpool.Pool
	requireAuth func(http.Handler) http.Handler
	userID      func(*http.Request) uuid.UUID
	logger      *slog.Logger
}

// NewDevicesHandler wires the handler.
func NewDevicesHandler(pool *pgxpool.Pool, requireAuth func(http.Handler) http.Handler, userID func(*http.Request) uuid.UUID, logger *slog.Logger) *DevicesHandler {
	return &DevicesHandler{pool: pool, requireAuth: requireAuth, userID: userID, logger: logger}
}

// Routes mounts /devices under the given router (expected: /v1).
func (h *DevicesHandler) Routes(r chi.Router) {
	r.With(h.requireAuth).Post("/devices", h.register)
	r.With(h.requireAuth).Delete("/devices", h.remove)
}

type deviceRequest struct {
	PushToken string `json:"push_token"`
	Platform  string `json:"platform"`
}

func (h *DevicesHandler) register(w http.ResponseWriter, r *http.Request) {
	var req deviceRequest
	if !httpx.DecodeJSON(w, r, &req) {
		return
	}
	req.PushToken = strings.TrimSpace(req.PushToken)
	if req.PushToken == "" || len(req.PushToken) > 4096 {
		httpx.WriteError(w, http.StatusUnprocessableEntity, "validation_failed", "push_token is required")
		return
	}
	if req.Platform != "android" && req.Platform != "ios" {
		httpx.WriteError(w, http.StatusUnprocessableEntity, "validation_failed", "platform must be android or ios")
		return
	}
	_, err := h.pool.Exec(r.Context(), `
		INSERT INTO devices (user_id, push_token, platform) VALUES ($1, $2, $3)
		ON CONFLICT (push_token) DO UPDATE
		   SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform, last_seen_at = now()`,
		h.userID(r), req.PushToken, req.Platform)
	if err != nil {
		h.logger.ErrorContext(r.Context(), "register device failed", "err", err)
		httpx.WriteError(w, http.StatusInternalServerError, "internal", "something went wrong")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *DevicesHandler) remove(w http.ResponseWriter, r *http.Request) {
	var req deviceRequest
	if !httpx.DecodeJSON(w, r, &req) {
		return
	}
	// Only the caller's own token can be removed.
	_, err := h.pool.Exec(r.Context(),
		`DELETE FROM devices WHERE push_token = $1 AND user_id = $2`, req.PushToken, h.userID(r))
	if err != nil {
		h.logger.ErrorContext(r.Context(), "remove device failed", "err", err)
		httpx.WriteError(w, http.StatusInternalServerError, "internal", "something went wrong")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
