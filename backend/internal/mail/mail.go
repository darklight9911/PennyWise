// Package mail sends transactional emails (verification, password reset).
package mail

import (
	"context"
	"log/slog"
)

// Message is a plain-text email.
type Message struct {
	To      string
	Subject string
	Text    string
}

// Mailer sends emails. A real provider is plugged in before production;
// until then only LogMailer exists (see PLAN.md: email provider not chosen yet).
type Mailer interface {
	Send(ctx context.Context, m Message) error
}

// LogMailer writes emails to the log instead of sending them.
// For development only: the log would contain one-time tokens.
// config.Load refuses it when APP_ENV=production.
type LogMailer struct {
	Logger *slog.Logger
}

// Send logs the message.
func (l LogMailer) Send(ctx context.Context, m Message) error {
	l.Logger.InfoContext(ctx, "email (dev log mailer, not sent)",
		"to", m.To, "subject", m.Subject, "text", m.Text)
	return nil
}
