// Package notify sends push messages: registering phones and budget alerts.
package notify

import (
	"context"
	"log/slog"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Message is one push notification.
type Message struct {
	Title string
	Body  string
	// Data is delivered to the app silently (e.g. which screen to open).
	Data map[string]string
}

// Sender delivers a message to one phone (push token).
type Sender interface {
	Send(ctx context.Context, token string, m Message) error
}

// LogSender writes push messages to the log instead of sending them.
// Used until Firebase Cloud Messaging is configured (it needs a Firebase
// project and a service account, which only the project owner can create).
type LogSender struct {
	Logger *slog.Logger
}

// Send logs the message. The token is shortened: it identifies a phone.
func (l LogSender) Send(ctx context.Context, token string, m Message) error {
	short := token
	if len(short) > 8 {
		short = short[:8] + "…"
	}
	l.Logger.InfoContext(ctx, "push (log sender, not sent)",
		"token", short, "title", m.Title, "body", m.Body, "data", m.Data)
	return nil
}

// SendToUser sends m to every phone of the user. Failures are logged, not
// returned: a message that reached some phones must not be repeated on them.
func SendToUser(ctx context.Context, pool *pgxpool.Pool, sender Sender, logger *slog.Logger, userID uuid.UUID, m Message) {
	rows, err := pool.Query(ctx, `SELECT push_token FROM devices WHERE user_id = $1`, userID)
	if err != nil {
		logger.ErrorContext(ctx, "listing devices failed", "err", err)
		return
	}
	tokens, err := pgx.CollectRows(rows, pgx.RowTo[string])
	if err != nil {
		logger.ErrorContext(ctx, "listing devices failed", "err", err)
		return
	}
	for _, t := range tokens {
		if err := sender.Send(ctx, t, m); err != nil {
			logger.WarnContext(ctx, "push failed", "err", err)
		}
	}
}
