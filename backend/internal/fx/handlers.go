package fx

import (
	"log/slog"
	"math/big"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"pennywise/backend/internal/httpx"
	"pennywise/backend/internal/money"
)

// Handler serves GET /v1/fx/rates.
type Handler struct {
	db          *pgxpool.Pool
	requireAuth func(http.Handler) http.Handler
	log         *slog.Logger
}

// NewHandler creates the handler.
func NewHandler(db *pgxpool.Pool, requireAuth func(http.Handler) http.Handler, log *slog.Logger) *Handler {
	return &Handler{db: db, requireAuth: requireAuth, log: log}
}

// Routes mounts the routes.
func (h *Handler) Routes(r chi.Router) {
	r.With(h.requireAuth).Get("/fx/rates", h.rates)
}

// RatesResponse lists what one unit of Base buys, on the latest day known.
type RatesResponse struct {
	Base  string            `json:"base"`
	Date  string            `json:"date"`
	Rates map[string]string `json:"rates"`
}

func (h *Handler) rates(w http.ResponseWriter, r *http.Request) {
	base := strings.ToUpper(r.URL.Query().Get("base"))
	if base == "" {
		base = Anchor
	}
	if _, err := money.Exponent(base); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_base", "base must be a 3-letter currency code")
		return
	}
	ctx := r.Context()
	rows, err := h.db.Query(ctx, `
		SELECT quote, rate::text, date FROM exchange_rates
		 WHERE base = $1 AND date = (SELECT max(date) FROM exchange_rates WHERE base = $1)`, Anchor)
	if err != nil {
		h.fail(w, r, err)
		return
	}
	type row struct {
		quote, rate string
		date        time.Time
	}
	list, err := pgx.CollectRows(rows, func(r pgx.CollectableRow) (row, error) {
		var x row
		return x, r.Scan(&x.quote, &x.rate, &x.date)
	})
	if err != nil {
		h.fail(w, r, err)
		return
	}
	eur := map[string]*big.Rat{Anchor: big.NewRat(1, 1)}
	out := RatesResponse{Base: base, Rates: map[string]string{}}
	for _, x := range list {
		if v, ok := new(big.Rat).SetString(x.rate); ok {
			eur[x.quote] = v
		}
		out.Date = x.date.Format(time.DateOnly)
	}
	b, ok := eur[base]
	if !ok || len(list) == 0 {
		httpx.WriteError(w, http.StatusNotFound, "no_rates", "no daily rate for this currency; type the rate on the transaction")
		return
	}
	for q, v := range eur {
		if q != base {
			out.Rates[q] = Format(Round(new(big.Rat).Quo(v, b)))
		}
	}
	httpx.WriteJSON(w, http.StatusOK, out)
}

func (h *Handler) fail(w http.ResponseWriter, r *http.Request, err error) {
	h.log.ErrorContext(r.Context(), "fx request failed", "err", err)
	httpx.WriteError(w, http.StatusInternalServerError, "internal", "something went wrong")
}
