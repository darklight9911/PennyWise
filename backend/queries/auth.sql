-- name: InsertRefreshToken :exec
INSERT INTO refresh_tokens (user_id, family_id, token_hash, device_name, expires_at)
VALUES ($1, $2, $3, $4, $5);

-- name: GetRefreshTokenForUpdate :one
-- Row lock: two parallel refreshes with the same token cannot both succeed.
SELECT * FROM refresh_tokens
WHERE token_hash = $1
FOR UPDATE;

-- name: MarkRefreshTokenUsed :exec
UPDATE refresh_tokens SET used_at = now() WHERE id = $1;

-- name: RevokeRefreshFamily :exec
UPDATE refresh_tokens SET revoked_at = now()
WHERE family_id = $1 AND revoked_at IS NULL;

-- name: RevokeAllUserRefreshTokens :exec
UPDATE refresh_tokens SET revoked_at = now()
WHERE user_id = $1 AND revoked_at IS NULL;

-- name: InsertEmailToken :exec
INSERT INTO email_tokens (user_id, purpose, token_hash, expires_at)
VALUES ($1, $2, $3, $4);

-- name: InvalidateEmailTokens :exec
-- Only the newest link of each kind should work.
UPDATE email_tokens SET used_at = now()
WHERE user_id = $1 AND purpose = $2 AND used_at IS NULL;

-- name: ConsumeEmailToken :one
-- Atomic: a token can be used once, and only before it expires.
UPDATE email_tokens SET used_at = now()
WHERE token_hash = $1
  AND purpose = $2
  AND used_at IS NULL
  AND expires_at > now()
RETURNING user_id;
