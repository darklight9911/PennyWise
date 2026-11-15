package auth

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"
	"unicode/utf8"

	"golang.org/x/crypto/argon2"
)

// Password rules follow NIST SP 800-63B: a length minimum, a generous maximum,
// and no forced symbol/digit mixes (they lead to weaker, predictable passwords).
const (
	MinPasswordLen = 10
	MaxPasswordLen = 128
)

// argon2id parameters (RFC 9106 style, sized for a small 2 vCPU / 4 GB server).
const (
	argonTime    = 2
	argonMemory  = 64 * 1024 // KiB = 64 MiB
	argonThreads = 2
	argonKeyLen  = 32
	argonSaltLen = 16
)

var errMalformedHash = errors.New("auth: malformed password hash")

// ValidatePassword checks the length rules. Length is counted in characters.
func ValidatePassword(pw string) error {
	n := utf8.RuneCountInString(pw)
	if n < MinPasswordLen {
		return fmt.Errorf("password must be at least %d characters", MinPasswordLen)
	}
	if n > MaxPasswordLen {
		return fmt.Errorf("password must be at most %d characters", MaxPasswordLen)
	}
	return nil
}

// HashPassword returns an argon2id hash in the standard PHC string format:
// $argon2id$v=19$m=65536,t=2,p=2$<salt>$<hash>
func HashPassword(pw string) (string, error) {
	salt := make([]byte, argonSaltLen)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	key := argon2.IDKey([]byte(pw), salt, argonTime, argonMemory, argonThreads, argonKeyLen)
	b64 := base64.RawStdEncoding
	return fmt.Sprintf("$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
		argon2.Version, argonMemory, argonTime, argonThreads,
		b64.EncodeToString(salt), b64.EncodeToString(key)), nil
}

// CheckPassword reports whether pw matches the PHC-encoded hash.
// It reads the parameters from the hash, so old hashes keep working
// after the defaults above are raised.
func CheckPassword(pw, encoded string) (bool, error) {
	parts := strings.Split(encoded, "$")
	if len(parts) != 6 || parts[1] != "argon2id" {
		return false, errMalformedHash
	}
	var version int
	if _, err := fmt.Sscanf(parts[2], "v=%d", &version); err != nil || version != argon2.Version {
		return false, errMalformedHash
	}
	var mem, t uint32
	var p uint8
	if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &mem, &t, &p); err != nil {
		return false, errMalformedHash
	}
	b64 := base64.RawStdEncoding
	salt, err := b64.DecodeString(parts[4])
	if err != nil {
		return false, errMalformedHash
	}
	want, err := b64.DecodeString(parts[5])
	if err != nil || len(want) == 0 {
		return false, errMalformedHash
	}
	got := argon2.IDKey([]byte(pw), salt, t, mem, p, uint32(len(want)))
	return subtle.ConstantTimeCompare(got, want) == 1, nil
}

// dummyHash is compared against when a login email does not exist, so that
// "no such user" takes as long as "wrong password" (no user enumeration by timing).
var dummyHash = func() string {
	h, err := HashPassword("pennywise-dummy-password")
	if err != nil {
		panic(err)
	}
	return h
}()
