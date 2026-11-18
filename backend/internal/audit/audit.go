// Package audit records security events (who did what, when, from where)
// in the audit_log table. Recording never fails a request: an error is
// only logged.
package audit

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"log/slog"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Actions.
const (
	Register       = "auth.register"
	Login          = "auth.login"
	LoginFailed    = "auth.login_failed"
	GoogleLogin    = "auth.google_login"
	GoogleRegister = "auth.google_register"
	PasswordReset  = "auth.password_reset"
	ProfileUpdate  = "profile.update"
	ExportCreate   = "export.create"
	AccountDelete  = "account.delete"
)

// Retention is how long events are kept.
const Retention = 180 * 24 * time.Hour

// TaskPrune deletes events older than Retention.
const TaskPrune = "audit:prune"

// Event is one thing that happened.
type Event struct {
	UserID   uuid.UUID // uuid.Nil when not known (failed login)
	Action   string
	Entity   string
	EntityID uuid.UUID
	Detail   map[string]any
}

// Log writes events. A nil *Log records nothing (tests, tools).
type Log struct {
	db  *pgxpool.Pool
	log *slog.Logger
}

// New creates the log.
func New(db *pgxpool.Pool, log *slog.Logger) *Log { return &Log{db: db, log: log} }

// Record stores e with the request's IP and user agent.
func (l *Log) Record(r *http.Request, e Event) {
	if l == nil {
		return
	}
	detail, _ := json.Marshal(e.Detail)
	if e.Detail == nil {
		detail = []byte("{}")
	}
	ua := r.UserAgent()
	if len(ua) > 200 {
		ua = ua[:200]
	}
	// Use a fresh context: the event must be stored even if the client
	// hung up after the work was done.
	ctx, cancel := context.WithTimeout(context.WithoutCancel(r.Context()), 3*time.Second)
	defer cancel()
	if _, err := l.db.Exec(ctx, `
		INSERT INTO audit_log (user_id, action, entity, entity_id, ip, user_agent, detail)
		VALUES ($1, $2, $3, $4, $5, $6, $7)`,
		nullUUID(e.UserID), e.Action, e.Entity, nullUUID(e.EntityID), ip(r), ua, detail); err != nil {
		l.log.ErrorContext(ctx, "audit write failed", "action", e.Action, "err", err)
	}
}

// HandlePrune is the asynq handler for TaskPrune.
func (l *Log) HandlePrune(ctx context.Context, _ *asynq.Task) error {
	tag, err := l.db.Exec(ctx, `DELETE FROM audit_log WHERE at < $1`, time.Now().Add(-Retention))
	if err == nil {
		l.log.InfoContext(ctx, "audit: pruned", "rows", tag.RowsAffected())
	}
	return err
}

// EmailHash lets failed logins for one address be grouped without storing
// the address itself.
func EmailHash(email string) string {
	sum := sha256.Sum256([]byte(strings.ToLower(strings.TrimSpace(email))))
	return hex.EncodeToString(sum[:8])
}

func ip(r *http.Request) any {
	host := r.RemoteAddr
	if h, _, err := net.SplitHostPort(host); err == nil {
		host = h
	}
	if net.ParseIP(host) == nil {
		return nil
	}
	return host
}

func nullUUID(id uuid.UUID) any {
	if id == uuid.Nil {
		return nil
	}
	return id
}
