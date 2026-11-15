package auth

import (
	"context"
	"errors"
	"slices"

	"github.com/coreos/go-oidc/v3/oidc"
)

// GoogleIdentity is what we trust from a verified Google ID token.
type GoogleIdentity struct {
	Subject       string // stable Google account id
	Email         string
	EmailVerified bool
	Name          string
}

// GoogleVerifier checks a Google ID token sent by the app.
type GoogleVerifier interface {
	Verify(ctx context.Context, idToken string) (GoogleIdentity, error)
}

// ErrInvalidGoogleToken is returned for any token Google did not issue to us.
var ErrInvalidGoogleToken = errors.New("auth: invalid Google ID token")

const googleCertsURL = "https://www.googleapis.com/oauth2/v3/certs"

// Google tokens use either issuer spelling.
var googleIssuers = []string{"https://accounts.google.com", "accounts.google.com"}

type oidcGoogleVerifier struct {
	verifier  *oidc.IDTokenVerifier
	clientIDs []string
}

// NewGoogleVerifier checks signature (Google's public keys, cached and
// refreshed automatically), expiry, issuer and that the token was issued to
// one of our OAuth client IDs. It makes no network call until first use.
func NewGoogleVerifier(clientIDs []string) GoogleVerifier {
	keys := oidc.NewRemoteKeySet(context.Background(), googleCertsURL)
	v := oidc.NewVerifier(googleIssuers[0], keys, &oidc.Config{
		// Checked by hand below: there are two issuer spellings and several client IDs.
		SkipClientIDCheck: true,
		SkipIssuerCheck:   true,
	})
	return &oidcGoogleVerifier{verifier: v, clientIDs: clientIDs}
}

func (g *oidcGoogleVerifier) Verify(ctx context.Context, raw string) (GoogleIdentity, error) {
	tok, err := g.verifier.Verify(ctx, raw)
	if err != nil {
		return GoogleIdentity{}, ErrInvalidGoogleToken
	}
	if !slices.Contains(googleIssuers, tok.Issuer) {
		return GoogleIdentity{}, ErrInvalidGoogleToken
	}
	if !slices.ContainsFunc(tok.Audience, func(a string) bool { return slices.Contains(g.clientIDs, a) }) {
		return GoogleIdentity{}, ErrInvalidGoogleToken
	}
	var c struct {
		Email         string `json:"email"`
		EmailVerified bool   `json:"email_verified"`
		Name          string `json:"name"`
	}
	if err := tok.Claims(&c); err != nil || tok.Subject == "" {
		return GoogleIdentity{}, ErrInvalidGoogleToken
	}
	return GoogleIdentity{Subject: tok.Subject, Email: c.Email, EmailVerified: c.EmailVerified, Name: c.Name}, nil
}
