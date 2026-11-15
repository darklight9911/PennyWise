package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

// NewOpaqueToken returns a random URL-safe token (256 bits) and its SHA-256
// hash. Only the hash is stored; the plain token goes to the client once.
func NewOpaqueToken() (plain string, hash []byte, err error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", nil, err
	}
	plain = base64.RawURLEncoding.EncodeToString(b)
	return plain, HashToken(plain), nil
}

// HashToken hashes an opaque token for storage or lookup. Tokens are random
// and long, so a fast hash is enough (no salt or argon2 needed).
func HashToken(plain string) []byte {
	sum := sha256.Sum256([]byte(plain))
	return sum[:]
}

const (
	jwtIssuer   = "pennywise-api"
	jwtAudience = "pennywise-app"
)

// MinJWTSecretLen is the shortest HS256 secret accepted (32 bytes = 256 bits).
const MinJWTSecretLen = 32

// ErrInvalidAccessToken is returned for any bad, expired or tampered token.
var ErrInvalidAccessToken = errors.New("auth: invalid access token")

// JWTIssuer signs and checks short-lived access tokens.
type JWTIssuer struct {
	secret []byte
	ttl    time.Duration
	now    func() time.Time
}

// NewJWTIssuer creates an issuer. secret must be at least MinJWTSecretLen bytes.
func NewJWTIssuer(secret []byte, ttl time.Duration) (*JWTIssuer, error) {
	if len(secret) < MinJWTSecretLen {
		return nil, fmt.Errorf("auth: JWT secret must be at least %d bytes", MinJWTSecretLen)
	}
	return &JWTIssuer{secret: secret, ttl: ttl, now: time.Now}, nil
}

// Issue returns a signed access token for userID and its expiry time.
func (j *JWTIssuer) Issue(userID uuid.UUID) (string, time.Time, error) {
	now := j.now()
	exp := now.Add(j.ttl)
	claims := jwt.RegisteredClaims{
		Issuer:    jwtIssuer,
		Audience:  jwt.ClaimStrings{jwtAudience},
		Subject:   userID.String(),
		IssuedAt:  jwt.NewNumericDate(now),
		NotBefore: jwt.NewNumericDate(now),
		ExpiresAt: jwt.NewNumericDate(exp),
	}
	signed, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(j.secret)
	return signed, exp, err
}

// Verify checks the signature, algorithm, issuer, audience and expiry,
// and returns the user ID.
func (j *JWTIssuer) Verify(token string) (uuid.UUID, error) {
	var claims jwt.RegisteredClaims
	_, err := jwt.ParseWithClaims(token, &claims,
		func(*jwt.Token) (any, error) { return j.secret, nil },
		// Pinning the algorithm blocks "alg: none" and algorithm-confusion attacks.
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithIssuer(jwtIssuer),
		jwt.WithAudience(jwtAudience),
		jwt.WithExpirationRequired(),
		jwt.WithTimeFunc(j.now),
		jwt.WithLeeway(30*time.Second),
	)
	if err != nil {
		return uuid.Nil, ErrInvalidAccessToken
	}
	id, err := uuid.Parse(claims.Subject)
	if err != nil {
		return uuid.Nil, ErrInvalidAccessToken
	}
	return id, nil
}
