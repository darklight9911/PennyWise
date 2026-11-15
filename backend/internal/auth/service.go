// Package auth handles accounts and sessions: register, login, Google
// sign-in, rotating refresh tokens, email verification and password reset.
package auth

import (
	"context"
	"errors"
	"log/slog"
	"net/mail"
	"net/url"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"pennywise/backend/internal/db"
	pwmail "pennywise/backend/internal/mail"
	"pennywise/backend/internal/money"
)

// Errors the HTTP layer maps to responses.
var (
	ErrEmailTaken             = errors.New("auth: email already registered")
	ErrInvalidCredentials     = errors.New("auth: invalid email or password")
	ErrInvalidRefreshToken    = errors.New("auth: invalid refresh token")
	ErrInvalidEmailToken      = errors.New("auth: invalid or expired link")
	ErrGoogleNotConfigured    = errors.New("auth: Google sign-in is not configured")
	ErrGoogleEmailNotVerified = errors.New("auth: Google account email is not verified")
	ErrGoogleAccountConflict  = errors.New("auth: email is linked to a different Google account")
	ErrUserNotFound           = errors.New("auth: user not found")
)

// ValidationError reports a bad input field.
type ValidationError struct {
	Field   string
	Message string
}

func (e *ValidationError) Error() string { return e.Field + ": " + e.Message }

const (
	verifyEmailTTL   = 24 * time.Hour
	resetPasswordTTL = 1 * time.Hour

	purposeVerifyEmail   = "verify_email"
	purposeResetPassword = "reset_password"
)

// Config holds the service settings.
type Config struct {
	RefreshTTL time.Duration
	// LinkBase builds links in emails, e.g. "pennywise://" or "https://pennywise.app/".
	LinkBase string
}

// Service implements the account and session logic.
type Service struct {
	pool   *pgxpool.Pool
	q      *db.Queries
	jwt    *JWTIssuer
	google GoogleVerifier // nil when Google sign-in is not configured
	mailer pwmail.Mailer
	cfg    Config
	logger *slog.Logger
}

// NewService wires the service. google may be nil.
func NewService(pool *pgxpool.Pool, jwt *JWTIssuer, google GoogleVerifier, mailer pwmail.Mailer, cfg Config, logger *slog.Logger) *Service {
	return &Service{pool: pool, q: db.New(pool), jwt: jwt, google: google, mailer: mailer, cfg: cfg, logger: logger}
}

// Tokens is returned to the app after any successful login.
type Tokens struct {
	AccessToken      string    `json:"access_token"`
	AccessExpiresAt  time.Time `json:"access_expires_at"`
	RefreshToken     string    `json:"refresh_token"`
	RefreshExpiresAt time.Time `json:"refresh_expires_at"`
	TokenType        string    `json:"token_type"`
}

// Profile holds optional sign-up details from the app.
type Profile struct {
	Name         string
	BaseCurrency string
	Locale       string
	Timezone     string
}

// RegisterInput is the email + password sign-up request.
type RegisterInput struct {
	Email      string
	Password   string
	DeviceName string
	Profile
}

// Register creates an email + password account and logs it in.
// A verification email is sent; the account works before it is verified.
func (s *Service) Register(ctx context.Context, in RegisterInput) (db.User, Tokens, error) {
	email, err := normalizeEmail(in.Email)
	if err != nil {
		return db.User{}, Tokens{}, err
	}
	if err := ValidatePassword(in.Password); err != nil {
		return db.User{}, Tokens{}, &ValidationError{Field: "password", Message: err.Error()}
	}
	profile, err := normalizeProfile(in.Profile)
	if err != nil {
		return db.User{}, Tokens{}, err
	}
	hash, err := HashPassword(in.Password)
	if err != nil {
		return db.User{}, Tokens{}, err
	}

	var (
		user        db.User
		tokens      Tokens
		verifyToken string
	)
	err = s.inTx(ctx, func(q *db.Queries) error {
		user, err = q.CreateUser(ctx, db.CreateUserParams{
			Email:        email,
			PasswordHash: text(hash),
			Name:         profile.Name,
			BaseCurrency: profile.BaseCurrency,
			Locale:       profile.Locale,
			Timezone:     profile.Timezone,
		})
		if isUniqueViolation(err) {
			return ErrEmailTaken
		}
		if err != nil {
			return err
		}
		if verifyToken, err = s.newEmailToken(ctx, q, user.ID, purposeVerifyEmail, verifyEmailTTL); err != nil {
			return err
		}
		tokens, err = s.issueTokens(ctx, q, user.ID, uuid.New(), in.DeviceName)
		return err
	})
	if err != nil {
		return db.User{}, Tokens{}, err
	}
	s.sendVerifyEmail(ctx, user.Email, verifyToken)
	return user, tokens, nil
}

// Login checks email + password. Every failure returns ErrInvalidCredentials
// and takes about the same time, so attackers cannot tell which part was wrong.
func (s *Service) Login(ctx context.Context, email, password, deviceName string) (db.User, Tokens, error) {
	email = strings.TrimSpace(email)
	user, err := s.q.GetUserByEmail(ctx, email)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return db.User{}, Tokens{}, err
	}
	hash := dummyHash
	if err == nil && user.PasswordHash.Valid {
		hash = user.PasswordHash.String
	}
	ok, checkErr := CheckPassword(password, hash)
	if checkErr != nil {
		return db.User{}, Tokens{}, checkErr
	}
	if err != nil || !user.PasswordHash.Valid || !ok {
		return db.User{}, Tokens{}, ErrInvalidCredentials
	}

	var tokens Tokens
	err = s.inTx(ctx, func(q *db.Queries) error {
		tokens, err = s.issueTokens(ctx, q, user.ID, uuid.New(), deviceName)
		return err
	})
	return user, tokens, err
}

// GoogleInput is a Google sign-in request.
type GoogleInput struct {
	IDToken    string
	DeviceName string
	Profile    // used only when a new account is created
}

// LoginWithGoogle signs in with a Google ID token. It logs in the linked
// account, links Google to an existing account with the same email, or
// creates a new account.
func (s *Service) LoginWithGoogle(ctx context.Context, in GoogleInput) (db.User, Tokens, bool, error) {
	if s.google == nil {
		return db.User{}, Tokens{}, false, ErrGoogleNotConfigured
	}
	id, err := s.google.Verify(ctx, in.IDToken)
	if err != nil {
		return db.User{}, Tokens{}, false, err
	}
	if !id.EmailVerified || id.Email == "" {
		return db.User{}, Tokens{}, false, ErrGoogleEmailNotVerified
	}
	email, err := normalizeEmail(id.Email)
	if err != nil {
		return db.User{}, Tokens{}, false, ErrInvalidGoogleToken
	}
	if in.Name == "" {
		in.Name = id.Name
	}
	profile, err := normalizeProfile(in.Profile)
	if err != nil {
		return db.User{}, Tokens{}, false, err
	}

	var (
		user    db.User
		tokens  Tokens
		created bool
	)
	err = s.inTx(ctx, func(q *db.Queries) error {
		user, err = q.GetUserByGoogleSub(ctx, text(id.Subject))
		switch {
		case err == nil:
			// Already linked: plain login.
		case errors.Is(err, pgx.ErrNoRows):
			user, err = q.GetUserByEmail(ctx, email)
			switch {
			case err == nil:
				if user.GoogleSub.Valid {
					return ErrGoogleAccountConflict
				}
				if user, err = q.LinkGoogleAccount(ctx, db.LinkGoogleAccountParams{ID: user.ID, GoogleSub: text(id.Subject)}); err != nil {
					return err
				}
			case errors.Is(err, pgx.ErrNoRows):
				user, err = q.CreateUser(ctx, db.CreateUserParams{
					Email:           email,
					GoogleSub:       text(id.Subject),
					Name:            profile.Name,
					BaseCurrency:    profile.BaseCurrency,
					Locale:          profile.Locale,
					Timezone:        profile.Timezone,
					EmailVerifiedAt: pgtype.Timestamptz{Time: time.Now(), Valid: true},
				})
				if isUniqueViolation(err) {
					return ErrEmailTaken // lost a race with a parallel sign-up; the app retries
				}
				if err != nil {
					return err
				}
				created = true
			default:
				return err
			}
		default:
			return err
		}
		tokens, err = s.issueTokens(ctx, q, user.ID, uuid.New(), in.DeviceName)
		return err
	})
	return user, tokens, created, err
}

// Refresh swaps a refresh token for a new access + refresh token pair.
// A refresh token works once. Presenting a used one means it was copied,
// so the whole session family is revoked.
func (s *Service) Refresh(ctx context.Context, plain string) (Tokens, error) {
	var (
		tokens Tokens
		reused bool
	)
	err := s.inTx(ctx, func(q *db.Queries) error {
		rt, err := q.GetRefreshTokenForUpdate(ctx, HashToken(plain))
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrInvalidRefreshToken
		}
		if err != nil {
			return err
		}
		if rt.RevokedAt.Valid || !rt.ExpiresAt.Time.After(time.Now()) {
			return ErrInvalidRefreshToken
		}
		if rt.UsedAt.Valid {
			reused = true
			return q.RevokeRefreshFamily(ctx, rt.FamilyID) // committed, then ErrInvalidRefreshToken below
		}
		if _, err := q.GetUserByID(ctx, rt.UserID); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrInvalidRefreshToken
			}
			return err
		}
		if err := q.MarkRefreshTokenUsed(ctx, rt.ID); err != nil {
			return err
		}
		tokens, err = s.issueTokens(ctx, q, rt.UserID, rt.FamilyID, rt.DeviceName)
		return err
	})
	if err != nil {
		return Tokens{}, err
	}
	if reused {
		s.logger.WarnContext(ctx, "refresh token reuse detected; session family revoked")
		return Tokens{}, ErrInvalidRefreshToken
	}
	return tokens, nil
}

// Logout ends the session (the token's whole family). Unknown tokens are ignored.
func (s *Service) Logout(ctx context.Context, plain string) error {
	rt, err := s.q.GetRefreshTokenForUpdate(ctx, HashToken(plain))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	return s.q.RevokeRefreshFamily(ctx, rt.FamilyID)
}

// VerifyEmail consumes a verification link token.
func (s *Service) VerifyEmail(ctx context.Context, plain string) error {
	return s.inTx(ctx, func(q *db.Queries) error {
		userID, err := q.ConsumeEmailToken(ctx, db.ConsumeEmailTokenParams{TokenHash: HashToken(plain), Purpose: purposeVerifyEmail})
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrInvalidEmailToken
		}
		if err != nil {
			return err
		}
		return q.MarkEmailVerified(ctx, userID)
	})
}

// ResendVerification sends a fresh verification link (old links stop working).
func (s *Service) ResendVerification(ctx context.Context, userID uuid.UUID) error {
	user, err := s.User(ctx, userID)
	if err != nil {
		return err
	}
	if user.EmailVerifiedAt.Valid {
		return nil
	}
	var token string
	err = s.inTx(ctx, func(q *db.Queries) error {
		token, err = s.newEmailToken(ctx, q, user.ID, purposeVerifyEmail, verifyEmailTTL)
		return err
	})
	if err != nil {
		return err
	}
	s.sendVerifyEmail(ctx, user.Email, token)
	return nil
}

// ForgotPassword emails a reset link if the account exists. It never says
// whether the email is registered.
func (s *Service) ForgotPassword(ctx context.Context, email string) error {
	user, err := s.q.GetUserByEmail(ctx, strings.TrimSpace(email))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	var token string
	err = s.inTx(ctx, func(q *db.Queries) error {
		token, err = s.newEmailToken(ctx, q, user.ID, purposeResetPassword, resetPasswordTTL)
		return err
	})
	if err != nil {
		return err
	}
	s.send(ctx, pwmail.Message{
		To:      user.Email,
		Subject: "Reset your pennyWise password",
		Text: "Someone asked to reset the password for your pennyWise account.\n\n" +
			"Open this link on your phone within 1 hour to choose a new password:\n" +
			s.link("reset-password", token) + "\n\n" +
			"If this was not you, ignore this email. Your password stays the same.",
	})
	return nil
}

// ResetPassword sets a new password from a reset link and logs out every device.
func (s *Service) ResetPassword(ctx context.Context, plain, newPassword string) error {
	if err := ValidatePassword(newPassword); err != nil {
		return &ValidationError{Field: "new_password", Message: err.Error()}
	}
	hash, err := HashPassword(newPassword)
	if err != nil {
		return err
	}
	return s.inTx(ctx, func(q *db.Queries) error {
		userID, err := q.ConsumeEmailToken(ctx, db.ConsumeEmailTokenParams{TokenHash: HashToken(plain), Purpose: purposeResetPassword})
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrInvalidEmailToken
		}
		if err != nil {
			return err
		}
		if err := q.SetPassword(ctx, db.SetPasswordParams{ID: userID, PasswordHash: text(hash)}); err != nil {
			return err
		}
		return q.RevokeAllUserRefreshTokens(ctx, userID)
	})
}

// User returns a live (not deleted) user.
func (s *Service) User(ctx context.Context, id uuid.UUID) (db.User, error) {
	u, err := s.q.GetUserByID(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) {
		return db.User{}, ErrUserNotFound
	}
	return u, err
}

// VerifyAccessToken checks an access token and returns the user ID.
func (s *Service) VerifyAccessToken(token string) (uuid.UUID, error) {
	return s.jwt.Verify(token)
}

// --- helpers ---

func (s *Service) issueTokens(ctx context.Context, q *db.Queries, userID, familyID uuid.UUID, device string) (Tokens, error) {
	refresh, hash, err := NewOpaqueToken()
	if err != nil {
		return Tokens{}, err
	}
	refreshExp := time.Now().Add(s.cfg.RefreshTTL)
	if err := q.InsertRefreshToken(ctx, db.InsertRefreshTokenParams{
		UserID:     userID,
		FamilyID:   familyID,
		TokenHash:  hash,
		DeviceName: truncate(strings.TrimSpace(device), 100),
		ExpiresAt:  pgtype.Timestamptz{Time: refreshExp, Valid: true},
	}); err != nil {
		return Tokens{}, err
	}
	access, accessExp, err := s.jwt.Issue(userID)
	if err != nil {
		return Tokens{}, err
	}
	return Tokens{
		AccessToken:      access,
		AccessExpiresAt:  accessExp.UTC(),
		RefreshToken:     refresh,
		RefreshExpiresAt: refreshExp.UTC(),
		TokenType:        "Bearer",
	}, nil
}

func (s *Service) newEmailToken(ctx context.Context, q *db.Queries, userID uuid.UUID, purpose string, ttl time.Duration) (string, error) {
	if err := q.InvalidateEmailTokens(ctx, db.InvalidateEmailTokensParams{UserID: userID, Purpose: purpose}); err != nil {
		return "", err
	}
	plain, hash, err := NewOpaqueToken()
	if err != nil {
		return "", err
	}
	err = q.InsertEmailToken(ctx, db.InsertEmailTokenParams{
		UserID:    userID,
		Purpose:   purpose,
		TokenHash: hash,
		ExpiresAt: pgtype.Timestamptz{Time: time.Now().Add(ttl), Valid: true},
	})
	return plain, err
}

func (s *Service) sendVerifyEmail(ctx context.Context, to, token string) {
	s.send(ctx, pwmail.Message{
		To:      to,
		Subject: "Confirm your pennyWise email",
		Text: "Welcome to pennyWise!\n\n" +
			"Open this link on your phone within 24 hours to confirm your email address:\n" +
			s.link("verify-email", token) + "\n\n" +
			"If you did not create an account, ignore this email.",
	})
}

// send delivers an email. A failure is logged, not returned: the account
// action already succeeded and the user can ask for a new link.
func (s *Service) send(ctx context.Context, m pwmail.Message) {
	if err := s.mailer.Send(ctx, m); err != nil {
		s.logger.ErrorContext(ctx, "sending email failed", "subject", m.Subject, "err", err)
	}
}

func (s *Service) link(path, token string) string {
	return s.cfg.LinkBase + path + "?token=" + url.QueryEscape(token)
}

func (s *Service) inTx(ctx context.Context, fn func(q *db.Queries) error) error {
	return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		return fn(s.q.WithTx(tx))
	})
}

func normalizeEmail(raw string) (string, error) {
	email := strings.TrimSpace(raw)
	addr, err := mail.ParseAddress(email)
	if err != nil || addr.Address != email || len(email) > 254 || !strings.Contains(email[strings.LastIndex(email, "@"):], ".") {
		return "", &ValidationError{Field: "email", Message: "enter a valid email address"}
	}
	return email, nil
}

func normalizeProfile(p Profile) (Profile, error) {
	p.Name = strings.TrimSpace(p.Name)
	if utf8.RuneCountInString(p.Name) > 100 {
		return Profile{}, &ValidationError{Field: "name", Message: "name must be at most 100 characters"}
	}
	if p.BaseCurrency == "" {
		p.BaseCurrency = "USD"
	}
	if _, err := money.Exponent(p.BaseCurrency); err != nil {
		return Profile{}, &ValidationError{Field: "base_currency", Message: "must be a 3-letter ISO 4217 code such as USD"}
	}
	if p.Locale == "" {
		p.Locale = "en"
	}
	if len(p.Locale) > 35 {
		return Profile{}, &ValidationError{Field: "locale", Message: "invalid locale"}
	}
	if p.Timezone == "" {
		p.Timezone = "UTC"
	}
	if _, err := time.LoadLocation(p.Timezone); err != nil || p.Timezone == "Local" {
		return Profile{}, &ValidationError{Field: "timezone", Message: "must be an IANA time zone such as Asia/Dhaka"}
	}
	return p, nil
}

func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}

func text(s string) pgtype.Text { return pgtype.Text{String: s, Valid: true} }

func truncate(s string, n int) string {
	if utf8.RuneCountInString(s) <= n {
		return s
	}
	return string([]rune(s)[:n])
}
