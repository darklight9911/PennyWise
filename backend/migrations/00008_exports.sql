-- +goose Up

-- CSV and PDF exports. A worker job builds the file into R2; the phone
-- polls GET /v1/exports/{id} and downloads through a short-lived link.
CREATE TABLE exports (
    id          uuid        PRIMARY KEY DEFAULT uuidv7(),
    user_id     uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    format      text        NOT NULL CHECK (format IN ('csv', 'pdf')),
    from_date   date        NOT NULL,
    to_date     date        NOT NULL CHECK (to_date >= from_date),
    status      text        NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'ready', 'failed')),
    object_key  text,
    size_bytes  bigint,
    error       text        NOT NULL DEFAULT '',
    created_at  timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz,
    expires_at  timestamptz            -- the file is deleted after this
);
CREATE INDEX exports_user_idx    ON exports (user_id, created_at DESC);
CREATE INDEX exports_cleanup_idx ON exports (created_at);

-- +goose Down
DROP TABLE exports;
