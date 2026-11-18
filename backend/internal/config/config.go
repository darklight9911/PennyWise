// Package config loads application settings from environment variables.
package config

import (
	"errors"
	"fmt"
	"os"
	"strings"
	"time"
)

// Minimum JWT secret length in bytes (HS256 needs 256 bits).
const minJWTSecretLen = 32

// Config holds every setting the API and worker need.
type Config struct {
	Env             string
	HTTPAddr        string
	DatabaseURL     string
	RedisURL        string
	ShutdownTimeout time.Duration

	// Auth
	JWTSecret       []byte
	AccessTokenTTL  time.Duration
	RefreshTokenTTL time.Duration
	// GoogleClientIDs are the OAuth client IDs whose ID tokens we accept.
	// Empty means Google sign-in is switched off.
	GoogleClientIDs []string
	// LinkBase starts links in emails, e.g. "pennywise://" (app deep link).
	LinkBase string
	// Mailer selects the email sender. Only "log" exists so far (dev only).
	Mailer string
	// FXAPIURL is the Frankfurter API base (daily exchange rates).
	FXAPIURL string
	// R2 is the private bucket for receipts and exports. Empty Bucket means
	// not configured: receipt upload and export are switched off.
	R2 R2
}

// R2 holds the Cloudflare R2 (S3 API) settings.
type R2 struct {
	AccountID       string
	AccessKeyID     string
	SecretAccessKey string
	Bucket          string
	Endpoint        string // optional, e.g. a local MinIO
}

// Configured reports whether a bucket is set up.
func (r R2) Configured() bool { return r.Bucket != "" }

// Load reads the configuration from the environment and validates it.
// The API needs everything; the worker calls LoadWorker.
func Load() (Config, error) {
	cfg := base()
	errs := cfg.requireCore()

	cfg.JWTSecret = []byte(os.Getenv("JWT_SECRET"))
	if len(cfg.JWTSecret) < minJWTSecretLen {
		errs = append(errs, fmt.Errorf("JWT_SECRET must be at least %d bytes (generate with: openssl rand -base64 48)", minJWTSecretLen))
	}
	if cfg.IsProduction() && cfg.Mailer == "log" {
		errs = append(errs, errors.New("MAILER=log is for development only; configure a real email provider for production"))
	}
	if cfg.Mailer != "log" {
		errs = append(errs, fmt.Errorf("MAILER=%q is not supported (only \"log\" so far)", cfg.Mailer))
	}
	return cfg, join(errs)
}

// LoadWorker reads only what the background worker needs.
func LoadWorker() (Config, error) {
	cfg := base()
	return cfg, join(cfg.requireCore())
}

func base() Config {
	return Config{
		Env:             getenv("APP_ENV", "development"),
		HTTPAddr:        getenv("HTTP_ADDR", ":8080"),
		DatabaseURL:     os.Getenv("DATABASE_URL"),
		RedisURL:        os.Getenv("REDIS_URL"),
		ShutdownTimeout: 15 * time.Second,
		AccessTokenTTL:  15 * time.Minute,
		RefreshTokenTTL: 30 * 24 * time.Hour,
		GoogleClientIDs: splitList(os.Getenv("GOOGLE_CLIENT_IDS")),
		LinkBase:        getenv("LINK_BASE", "pennywise://"),
		Mailer:          getenv("MAILER", "log"),
		FXAPIURL:        getenv("FX_API_URL", "https://api.frankfurter.dev/v1"),
		R2: R2{
			AccountID:       os.Getenv("R2_ACCOUNT_ID"),
			AccessKeyID:     os.Getenv("R2_ACCESS_KEY_ID"),
			SecretAccessKey: os.Getenv("R2_SECRET_ACCESS_KEY"),
			Bucket:          os.Getenv("R2_BUCKET"),
			Endpoint:        os.Getenv("R2_ENDPOINT"),
		},
	}
}

func (c Config) requireCore() []error {
	var errs []error
	if c.DatabaseURL == "" {
		errs = append(errs, errors.New("DATABASE_URL is required"))
	}
	if c.RedisURL == "" {
		errs = append(errs, errors.New("REDIS_URL is required"))
	}
	r := c.R2
	if r.Configured() && (r.AccessKeyID == "" || r.SecretAccessKey == "" || (r.AccountID == "" && r.Endpoint == "")) {
		errs = append(errs, errors.New("R2_BUCKET is set: R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY and R2_ACCOUNT_ID (or R2_ENDPOINT) are required too"))
	}
	return errs
}

// IsProduction reports whether the app runs in production.
func (c Config) IsProduction() bool { return c.Env == "production" }

func join(errs []error) error {
	if len(errs) == 0 {
		return nil
	}
	return fmt.Errorf("config: %w", errors.Join(errs...))
}

func getenv(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return fallback
}

func splitList(s string) []string {
	var out []string
	for _, p := range strings.Split(s, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}
