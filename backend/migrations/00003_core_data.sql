-- +goose Up
-- Accounts, categories and transactions: the first synced tables.
--
-- Rows are created on the phone (client-generated UUIDs) and arrive through
-- POST /v1/sync/push. Every row has:
--   version     the user's sync counter when the server last wrote the row;
--               the phone pulls rows with version > its cursor
--   updated_at  the phone's edit time; the newer edit wins a conflict
--   deleted_at  soft delete, so deletions sync too
--
-- Composite foreign keys (x_id, user_id) make the DATABASE refuse a row that
-- points at another user's account or category.

CREATE TABLE accounts (
    id                    uuid        PRIMARY KEY,
    user_id               uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    name                  text        NOT NULL CHECK (char_length(name) BETWEEN 1 AND 60),
    type                  text        NOT NULL CHECK (type IN ('cash', 'bank', 'card', 'ewallet', 'savings', 'other')),
    currency              char(3)     NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
    opening_balance_minor bigint      NOT NULL DEFAULT 0,
    icon                  text        NOT NULL DEFAULT '',
    color                 text        NOT NULL DEFAULT '' CHECK (color = '' OR color ~ '^#[0-9A-F]{6}$'),
    archived              boolean     NOT NULL DEFAULT false,
    sort_order            integer     NOT NULL DEFAULT 0,
    version               bigint      NOT NULL,
    updated_at            timestamptz NOT NULL,
    deleted_at            timestamptz,
    created_at            timestamptz NOT NULL DEFAULT now(),
    UNIQUE (id, user_id)
);
CREATE INDEX accounts_user_version_idx ON accounts (user_id, version);

CREATE TABLE categories (
    id          uuid        PRIMARY KEY,
    user_id     uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    parent_id   uuid,
    name        text        NOT NULL CHECK (char_length(name) BETWEEN 1 AND 40),
    kind        text        NOT NULL CHECK (kind IN ('income', 'expense')),
    icon        text        NOT NULL DEFAULT '',
    color       text        NOT NULL DEFAULT '' CHECK (color = '' OR color ~ '^#[0-9A-F]{6}$'),
    sort_order  integer     NOT NULL DEFAULT 0,
    version     bigint      NOT NULL,
    updated_at  timestamptz NOT NULL,
    deleted_at  timestamptz,
    created_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (id, user_id),
    CHECK (parent_id IS NULL OR parent_id <> id),
    FOREIGN KEY (parent_id, user_id) REFERENCES categories (id, user_id) ON DELETE CASCADE
);
CREATE INDEX categories_user_version_idx ON categories (user_id, version);

CREATE TABLE transactions (
    id                    uuid          PRIMARY KEY,
    user_id               uuid          NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    account_id            uuid          NOT NULL,
    category_id           uuid,
    kind                  text          NOT NULL CHECK (kind IN ('income', 'expense', 'transfer')),
    amount_minor          bigint        NOT NULL CHECK (amount_minor > 0),
    currency              char(3)       NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
    -- Filled when the amount is converted to the user's base currency
    -- (same currency now; other currencies from Milestone 6).
    fx_rate_to_base       numeric(20, 10),
    fx_rate_source        text          CHECK (fx_rate_source IN ('auto', 'manual')),
    amount_base_minor     bigint,
    transfer_account_id   uuid,
    transfer_amount_minor bigint        CHECK (transfer_amount_minor > 0),
    occurred_at           timestamptz   NOT NULL,
    local_date            date          NOT NULL,
    note                  text          NOT NULL DEFAULT '' CHECK (char_length(note) <= 500),
    recurring_id          uuid,
    occurrence_date       date,
    version               bigint        NOT NULL,
    updated_at            timestamptz   NOT NULL,
    deleted_at            timestamptz,
    created_at            timestamptz   NOT NULL DEFAULT now(),

    FOREIGN KEY (account_id, user_id) REFERENCES accounts (id, user_id) ON DELETE CASCADE,
    FOREIGN KEY (transfer_account_id, user_id) REFERENCES accounts (id, user_id) ON DELETE CASCADE,
    FOREIGN KEY (category_id, user_id) REFERENCES categories (id, user_id),

    -- A transfer moves money between two different accounts and has no category;
    -- income and expense always have a category.
    CONSTRAINT transactions_shape CHECK (
        (kind = 'transfer'
            AND transfer_account_id IS NOT NULL AND transfer_account_id <> account_id
            AND transfer_amount_minor IS NOT NULL AND category_id IS NULL)
        OR
        (kind <> 'transfer'
            AND transfer_account_id IS NULL AND transfer_amount_minor IS NULL
            AND category_id IS NOT NULL)
    ),
    CONSTRAINT transactions_fx_together CHECK (
        (fx_rate_to_base IS NULL) = (amount_base_minor IS NULL)
    )
);
CREATE INDEX transactions_user_version_idx  ON transactions (user_id, version);
CREATE INDEX transactions_user_date_idx     ON transactions (user_id, local_date DESC);
CREATE INDEX transactions_user_category_idx ON transactions (user_id, category_id, local_date);
CREATE INDEX transactions_account_idx       ON transactions (account_id);
CREATE INDEX transactions_transfer_idx      ON transactions (transfer_account_id) WHERE transfer_account_id IS NOT NULL;
-- Second guard against a recurring bill being created twice (see PLAN.md).
CREATE UNIQUE INDEX transactions_recurring_occurrence_key
    ON transactions (recurring_id, occurrence_date) WHERE recurring_id IS NOT NULL;

-- +goose Down
DROP TABLE transactions;
DROP TABLE categories;
DROP TABLE accounts;
