package config

import (
	"strings"
	"testing"
)

func setValid(t *testing.T) {
	t.Setenv("DATABASE_URL", "postgres://x")
	t.Setenv("REDIS_URL", "redis://x")
	t.Setenv("JWT_SECRET", strings.Repeat("a", 32))
	t.Setenv("APP_ENV", "development")
	t.Setenv("MAILER", "")
	t.Setenv("GOOGLE_CLIENT_IDS", "")
	for _, k := range []string{"R2_ACCOUNT_ID", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY", "R2_BUCKET", "R2_ENDPOINT"} {
		t.Setenv(k, "")
	}
}

func TestLoadValid(t *testing.T) {
	setValid(t)
	t.Setenv("GOOGLE_CLIENT_IDS", " a.apps.googleusercontent.com , ,b ")
	cfg, err := Load()
	if err != nil {
		t.Fatal(err)
	}
	if got := cfg.GoogleClientIDs; len(got) != 2 || got[0] != "a.apps.googleusercontent.com" || got[1] != "b" {
		t.Errorf("GoogleClientIDs = %q", got)
	}
	if cfg.Mailer != "log" || cfg.LinkBase != "pennywise://" {
		t.Errorf("defaults wrong: %+v", cfg)
	}
}

func TestLoadRejectsBadConfig(t *testing.T) {
	tests := []struct {
		name, key, value, wantErr string
	}{
		{"short JWT secret", "JWT_SECRET", "short", "JWT_SECRET"},
		{"missing DB", "DATABASE_URL", "", "DATABASE_URL"},
		{"unknown mailer", "MAILER", "smtp", "not supported"},
		{"log mailer in production", "APP_ENV", "production", "development only"},
		{"bucket without keys", "R2_BUCKET", "pennywise", "R2_ACCESS_KEY_ID"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			setValid(t)
			t.Setenv(tt.key, tt.value)
			_, err := Load()
			if err == nil || !strings.Contains(err.Error(), tt.wantErr) {
				t.Fatalf("err = %v, want containing %q", err, tt.wantErr)
			}
		})
	}
}

func TestLoadWorkerNeedsNoJWTSecret(t *testing.T) {
	setValid(t)
	t.Setenv("JWT_SECRET", "")
	if _, err := LoadWorker(); err != nil {
		t.Fatal(err)
	}
}

func TestR2Settings(t *testing.T) {
	setValid(t)
	cfg, err := Load()
	if err != nil || cfg.R2.Configured() {
		t.Fatalf("no bucket: configured=%v err=%v", cfg.R2.Configured(), err)
	}
	t.Setenv("R2_BUCKET", "pennywise")
	t.Setenv("R2_ACCESS_KEY_ID", "id")
	t.Setenv("R2_SECRET_ACCESS_KEY", "secret")
	t.Setenv("R2_ACCOUNT_ID", "acct")
	cfg, err = Load()
	if err != nil || !cfg.R2.Configured() || cfg.R2.AccountID != "acct" {
		t.Fatalf("bucket set: %+v %v", cfg.R2, err)
	}
}
