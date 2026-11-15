-- +goose Up
-- Needs PostgreSQL 18+ (built-in uuidv7()).

CREATE EXTENSION IF NOT EXISTS citext;

-- Keeps updated_at current on every UPDATE.
-- +goose StatementBegin
CREATE FUNCTION set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;
-- +goose StatementEnd

CREATE TABLE users (
    id                   uuid        PRIMARY KEY DEFAULT uuidv7(),
    email                citext      NOT NULL,
    password_hash        text,                       -- NULL for Google-only accounts
    google_sub           text,                       -- Google account id, NULL if not linked
    name                 text        NOT NULL DEFAULT '',
    base_currency        char(3)     NOT NULL DEFAULT 'USD'
                         CHECK (base_currency ~ '^[A-Z]{3}$'),
    base_currency_status text        NOT NULL DEFAULT 'ok'
                         CHECK (base_currency_status IN ('ok', 'recalculating')),
    locale               text        NOT NULL DEFAULT 'en',
    timezone             text        NOT NULL DEFAULT 'UTC',
    email_verified_at    timestamptz,
    -- Per-user sync counter. Bumped (row-locked) at the start of every sync push,
    -- so one user's versions always commit in order. See PLAN.md section 3.
    sync_version         bigint      NOT NULL DEFAULT 0,
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now(),
    deleted_at           timestamptz,

    CONSTRAINT users_login_method CHECK (password_hash IS NOT NULL OR google_sub IS NOT NULL)
);

-- One live account per email / Google id; deleted accounts free them up again.
CREATE UNIQUE INDEX users_email_key      ON users (email)      WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX users_google_sub_key ON users (google_sub) WHERE deleted_at IS NULL AND google_sub IS NOT NULL;

CREATE TRIGGER users_set_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- +goose Down
DROP TABLE users;
DROP FUNCTION set_updated_at();
