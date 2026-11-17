// Package notify sends push messages: registering phones and budget alerts.
package notify

import (
	"context"
	"log/slog"
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
