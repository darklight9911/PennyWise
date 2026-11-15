-- name: GetUserByID :one
SELECT * FROM users
WHERE id = $1 AND deleted_at IS NULL;

-- name: GetUserByEmail :one
SELECT * FROM users
WHERE email = $1 AND deleted_at IS NULL;

-- name: GetUserByGoogleSub :one
SELECT * FROM users
WHERE google_sub = $1 AND deleted_at IS NULL;

-- name: CreateUser :one
INSERT INTO users (email, password_hash, google_sub, name, base_currency, locale, timezone, email_verified_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
RETURNING *;

-- name: LinkGoogleAccount :one
-- Links Google to an existing account. Google has proven the email, so the
-- address is marked verified. If the email was NOT verified before, the old
-- password was set by someone who never proved they own the address
-- (possible account pre-hijacking), so it is removed.
UPDATE users
SET google_sub        = $2,
    password_hash     = CASE WHEN email_verified_at IS NULL THEN NULL ELSE password_hash END,
    email_verified_at = COALESCE(email_verified_at, now())
WHERE id = $1 AND deleted_at IS NULL
RETURNING *;

-- name: MarkEmailVerified :exec
UPDATE users
SET email_verified_at = COALESCE(email_verified_at, now())
WHERE id = $1;

-- name: SetPassword :exec
-- Used by password reset. Resetting through an emailed link also proves
-- the user owns the address.
UPDATE users
SET password_hash     = $2,
    email_verified_at = COALESCE(email_verified_at, now())
WHERE id = $1;
