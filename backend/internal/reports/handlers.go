package reports

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	goredis "github.com/redis/go-redis/v9"

	"pennywise/backend/internal/httpx"
)

// CacheTTL is how long a report answer is kept. The cache key holds the
// user's sync version, so any change (a push, a base-currency job) makes
// old entries unused at once; the TTL only frees memory.
const CacheTTL = 10 * time.Minute

// Handler serves /v1/reports.
type Handler struct {
	svc         *Service
	db          *pgxpool.Pool
	cache       *goredis.Client // nil: no cache
	requireAuth func(http.Handler) http.Handler
	userID      func(*http.Request) uuid.UUID
	log         *slog.Logger
}

// NewHandler creates the handler. cache may be nil.
func NewHandler(db *pgxpool.Pool, cache *goredis.Client, requireAuth func(http.Handler) http.Handler,
	userID func(*http.Request) uuid.UUID, log *slog.Logger) *Handler {
	return &Handler{svc: NewService(db), db: db, cache: cache, requireAuth: requireAuth, userID: userID, log: log}
}

// Routes mounts the routes.
func (h *Handler) Routes(r chi.Router) {
	r.Route("/reports", func(r chi.Router) {
		r.Use(h.requireAuth)
		r.Get("/summary", h.summary)
		r.Get("/by-category", h.byCategory)
		r.Get("/trend", h.trend)
	})
}

func (h *Handler) summary(w http.ResponseWriter, r *http.Request) {
	h.serve(w, r, "summary", func(ctx context.Context, u uuid.UUID, rg Range) (any, error) {
		return h.svc.Summary(ctx, u, rg)
	})
}

func (h *Handler) byCategory(w http.ResponseWriter, r *http.Request) {
	kind := r.URL.Query().Get("kind")
	if kind == "" {
		kind = "expense"
	}
	if kind != "expense" && kind != "income" {
		httpx.WriteError(w, http.StatusBadRequest, "bad_kind", "kind must be expense or income")
		return
	}
	h.serve(w, r, "by-category:"+kind, func(ctx context.Context, u uuid.UUID, rg Range) (any, error) {
		return h.svc.ByCategory(ctx, u, rg, kind)
	})
}

func (h *Handler) trend(w http.ResponseWriter, r *http.Request) {
	interval := r.URL.Query().Get("interval")
	if interval == "" {
		interval = "month"
	}
	h.serve(w, r, "trend:"+interval, func(ctx context.Context, u uuid.UUID, rg Range) (any, error) {
		return h.svc.Trend(ctx, u, rg, interval)
	})
}

// serve parses the range, answers from the cache when it can, and stores
// fresh answers.
func (h *Handler) serve(w http.ResponseWriter, r *http.Request, name string, run func(context.Context, uuid.UUID, Range) (any, error)) {
	q := r.URL.Query()
	rg, err := ParseRange(q.Get("from"), q.Get("to"))
	if err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "bad_range", "from and to must be YYYY-MM-DD dates, from <= to, at most 5 years apart")
		return
	}
	ctx, user := r.Context(), h.userID(r)
	key := ""
	if h.cache != nil {
		var version int64
		if err := h.db.QueryRow(ctx, `SELECT sync_version FROM users WHERE id = $1`, user).Scan(&version); err == nil {
			key = fmt.Sprintf("rep:%s:%d:%s:%s:%s", user, version, name, q.Get("from"), q.Get("to"))
			if b, err := h.cache.Get(ctx, key).Bytes(); err == nil {
				w.Header().Set("Content-Type", "application/json")
				w.Header().Set("X-Cache", "hit")
				_, _ = w.Write(b)
				return
			}
		}
	}
	out, err := run(ctx, user, rg)
	if errors.Is(err, ErrBadInterval) {
		httpx.WriteError(w, http.StatusBadRequest, "bad_interval", "interval must be day, week or month, with at most 400, 300 or 120 periods")
		return
	}
	if err != nil {
		h.log.ErrorContext(ctx, "report failed", "report", name, "err", err)
		httpx.WriteError(w, http.StatusInternalServerError, "internal", "something went wrong")
		return
	}
	// Do not cache numbers that are about to change.
	if key != "" && !recalculating(out) {
		if b, err := json.Marshal(out); err == nil {
			if err := h.cache.Set(ctx, key, b, CacheTTL).Err(); err != nil {
				h.log.WarnContext(ctx, "report cache write failed", "err", err)
			}
		}
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}

func recalculating(v any) bool {
	switch x := v.(type) {
	case Summary:
		return x.Status != "ok"
	case ByCategory:
		return x.Status != "ok"
	case Trend:
		return x.Status != "ok"
	}
	return false
}
