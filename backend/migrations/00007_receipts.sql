-- +goose Up

-- Lets child tables reference a transaction together with its owner.
ALTER TABLE transactions ADD CONSTRAINT transactions_id_user_key UNIQUE (id, user_id);

-- Receipt photos. The file lives in R2 at object_key; this row tracks it.
-- pending: upload URL handed out; uploaded: the API saw the file (HEAD).
-- Phones download only uploaded and deleted rows through sync.
CREATE TABLE receipts (
    id             uuid        PRIMARY KEY,   -- made by the phone
    user_id        uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    transaction_id uuid        NOT NULL,
    object_key     text        NOT NULL UNIQUE,
    content_type   text        NOT NULL CHECK (content_type IN ('image/jpeg', 'image/png')),
    size_bytes     integer     NOT NULL CHECK (size_bytes BETWEEN 1 AND 2097152),
    status         text        NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'uploaded')),
    version        bigint      NOT NULL DEFAULT 0,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    deleted_at     timestamptz,
    purged_at      timestamptz,               -- file removed from R2 after delete

    FOREIGN KEY (transaction_id, user_id) REFERENCES transactions (id, user_id) ON DELETE CASCADE
);
CREATE INDEX receipts_user_version_idx ON receipts (user_id, version);
CREATE INDEX receipts_transaction_idx  ON receipts (transaction_id) WHERE deleted_at IS NULL;
CREATE INDEX receipts_pending_idx      ON receipts (created_at) WHERE status = 'pending';
CREATE INDEX receipts_unpurged_idx     ON receipts (deleted_at) WHERE deleted_at IS NOT NULL AND purged_at IS NULL;

-- +goose Down
DROP TABLE receipts;
ALTER TABLE transactions DROP CONSTRAINT transactions_id_user_key;
