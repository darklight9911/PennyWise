-- +goose Up

-- Long-lived login sessions. Only a SHA-256 hash of each token is stored,
-- so a database leak does not leak usable tokens.
--
-- Rotation: every refresh issues a new token in the same family and marks the
-- old one used. If a used token is presented again, it was stolen (or replayed),
-- so the whole family is revoked and that device must log in again.
CREATE TABLE refresh_tokens (
    id          uuid        PRIMARY KEY DEFAULT uuidv7(),
    user_id     uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    family_id   uuid        NOT NULL,
    token_hash  bytea       NOT NULL UNIQUE,
    device_name text        NOT NULL DEFAULT '',
    expires_at  timestamptz NOT NULL,
    used_at     timestamptz,
    revoked_at  timestamptz,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX refresh_tokens_user_idx   ON refresh_tokens (user_id);
CREATE INDEX refresh_tokens_family_idx ON refresh_tokens (family_id);

-- One-time tokens sent by email (verify address, reset password). Hashed too.
CREATE TABLE email_tokens (
    id          uuid        PRIMARY KEY DEFAULT uuidv7(),
    user_id     uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    purpose     text        NOT NULL CHECK (purpose IN ('verify_email', 'reset_password')),
    token_hash  bytea       NOT NULL UNIQUE,
    expires_at  timestamptz NOT NULL,
    used_at     timestamptz,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX email_tokens_user_purpose_idx ON email_tokens (user_id, purpose);

-- +goose Down
DROP TABLE email_tokens;
DROP TABLE refresh_tokens;
