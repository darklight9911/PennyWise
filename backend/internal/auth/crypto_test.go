package auth

import (
	"strings"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

func TestPasswordHashAndCheck(t *testing.T) {
	hash, err := HashPassword("correct horse battery")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(hash, "$argon2id$v=19$m=65536,t=2,p=2$") {
		t.Errorf("unexpected hash format: %s", hash)
	}
	if ok, err := CheckPassword("correct horse battery", hash); err != nil || !ok {
		t.Errorf("right password rejected: ok=%v err=%v", ok, err)
	}
	if ok, _ := CheckPassword("wrong horse battery", hash); ok {
		t.Error("wrong password accepted")
	}
	other, _ := HashPassword("correct horse battery")
	if other == hash {
		t.Error("two hashes of the same password are equal: salt not random")
	}
}

func TestCheckPasswordRejectsMalformed(t *testing.T) {
	for _, h := range []string{"", "plain", "$argon2i$v=19$m=1,t=1,p=1$c2FsdA$aGFzaA", "$argon2id$v=19$m=x$a$b", "$argon2id$v=19$m=65536,t=2,p=2$!!$aGFzaA"} {
		if ok, err := CheckPassword("pw", h); ok || err == nil {
			t.Errorf("CheckPassword(%q) = %v, %v; want false, error", h, ok, err)
		}
	}
}

func TestValidatePassword(t *testing.T) {
	if err := ValidatePassword("short"); err == nil {
		t.Error("short password accepted")
	}
	if err := ValidatePassword(strings.Repeat("é", 10)); err != nil {
		t.Errorf("10 characters (20 bytes) rejected: %v", err)
	}
	if err := ValidatePassword(strings.Repeat("a", 129)); err == nil {
		t.Error("129-character password accepted")
	}
}

func TestOpaqueTokens(t *testing.T) {
	a, ha, err := NewOpaqueToken()
	if err != nil {
		t.Fatal(err)
	}
	b, _, _ := NewOpaqueToken()
	if a == b {
		t.Fatal("tokens repeat")
	}
	if len(a) != 43 {
		t.Errorf("token length = %d, want 43 (32 bytes base64url)", len(a))
	}
	if string(HashToken(a)) != string(ha) {
		t.Error("HashToken does not match the returned hash")
	}
}

func newIssuer(t *testing.T) *JWTIssuer {
	t.Helper()
	j, err := NewJWTIssuer([]byte(strings.Repeat("k", 32)), 15*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	return j
}

func TestJWTRoundTrip(t *testing.T) {
	j := newIssuer(t)
	id := uuid.New()
	tok, exp, err := j.Issue(id)
	if err != nil {
		t.Fatal(err)
	}
	if d := time.Until(exp); d < 14*time.Minute || d > 15*time.Minute {
		t.Errorf("expiry in %v, want ~15m", d)
	}
	got, err := j.Verify(tok)
	if err != nil || got != id {
		t.Fatalf("Verify = %v, %v", got, err)
	}
}

func TestJWTRejects(t *testing.T) {
	j := newIssuer(t)
	id := uuid.New()
	good, _, _ := j.Issue(id)

	// Expired: issued 20 minutes ago with a 15-minute lifetime.
	old := newIssuer(t)
	old.now = func() time.Time { return time.Now().Add(-20 * time.Minute) }
	expired, _, _ := old.Issue(id)

	// Signed with another secret.
	other, _ := NewJWTIssuer([]byte(strings.Repeat("x", 32)), time.Minute)
	foreign, _, _ := other.Issue(id)

	// "alg: none" token with valid-looking claims.
	none, _ := jwt.NewWithClaims(jwt.SigningMethodNone, jwt.RegisteredClaims{
		Issuer: jwtIssuer, Audience: jwt.ClaimStrings{jwtAudience}, Subject: id.String(),
		ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour)),
	}).SignedString(jwt.UnsafeAllowNoneSignatureType)

	// Right key, wrong audience.
	wrongAud, _ := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.RegisteredClaims{
		Issuer: jwtIssuer, Audience: jwt.ClaimStrings{"someone-else"}, Subject: id.String(),
		ExpiresAt: jwt.NewNumericDate(time.Now().Add(time.Hour)),
	}).SignedString([]byte(strings.Repeat("k", 32)))

	tampered := good[:len(good)-2] + "xx"

	for name, tok := range map[string]string{
		"expired": expired, "foreign key": foreign, "alg none": none,
		"wrong audience": wrongAud, "tampered": tampered, "garbage": "abc", "empty": "",
	} {
		if _, err := j.Verify(tok); err == nil {
			t.Errorf("%s token accepted", name)
		}
	}
}

func TestJWTSecretTooShort(t *testing.T) {
	if _, err := NewJWTIssuer([]byte("short"), time.Minute); err == nil {
		t.Error("short secret accepted")
	}
}
