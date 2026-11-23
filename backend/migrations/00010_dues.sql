-- +goose Up
-- Dues: money the user owes or is owed (loans and bills), with part payments.
-- Synced like goals (client UUIDs, version, LWW, soft delete).
--
-- Payments are ordinary transactions linked by transactions.due_id:
--   bill payments are income/expense with a category (they count in totals);
--   loan payments use the kinds loan_in / loan_out, which move money between
--   the user and someone else without being income or expense.

CREATE TABLE dues (
    id                 uuid        PRIMARY KEY,
    user_id            uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    direction          text        NOT NULL CHECK (direction IN ('i_owe', 'owed_to_me')),
    kind               text        NOT NULL CHECK (kind IN ('loan', 'bill')),
    person             text        NOT NULL CHECK (char_length(person) BETWEEN 1 AND 60),
    amount_minor       bigint      NOT NULL CHECK (amount_minor > 0),
    currency           char(3)     NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
    -- Default account for payments (optional).
    account_id         uuid,
    -- Bills only: expense category for i_owe, income for owed_to_me.
    category_id        uuid,
    start_date         date        NOT NULL,
    due_date           date,
    -- NULL = no reminder, 0 = on the due date.
    remind_days_before integer     CHECK (remind_days_before BETWEEN 0 AND 30),
    note               text        NOT NULL DEFAULT '' CHECK (char_length(note) <= 500),
    -- Set when the rest is forgiven; cleared on reopen.
    closed_at          timestamptz,
    version            bigint      NOT NULL,
    updated_at         timestamptz NOT NULL,
    deleted_at         timestamptz,
    created_at         timestamptz NOT NULL DEFAULT now(),
    UNIQUE (id, user_id),
    FOREIGN KEY (account_id, user_id) REFERENCES accounts (id, user_id) ON DELETE SET NULL (account_id),
    FOREIGN KEY (category_id, user_id) REFERENCES categories (id, user_id) ON DELETE SET NULL (category_id),
    CONSTRAINT dues_loan_no_category CHECK (kind = 'bill' OR category_id IS NULL)
);
CREATE INDEX dues_user_version_idx ON dues (user_id, version);

ALTER TABLE transactions ADD COLUMN due_id uuid;
ALTER TABLE transactions ADD CONSTRAINT transactions_due_fkey
    FOREIGN KEY (due_id, user_id) REFERENCES dues (id, user_id) ON DELETE SET NULL (due_id);
CREATE INDEX transactions_due_idx ON transactions (due_id) WHERE due_id IS NOT NULL;

ALTER TABLE transactions DROP CONSTRAINT transactions_kind_check;
ALTER TABLE transactions ADD CONSTRAINT transactions_kind_check
    CHECK (kind IN ('income', 'expense', 'transfer', 'loan_in', 'loan_out'));

-- Loan payments need their due, and have no category or transfer fields.
ALTER TABLE transactions DROP CONSTRAINT transactions_shape;
ALTER TABLE transactions ADD CONSTRAINT transactions_shape CHECK (
    (kind = 'transfer'
        AND transfer_account_id IS NOT NULL AND transfer_account_id <> account_id
        AND transfer_amount_minor IS NOT NULL AND category_id IS NULL)
    OR
    (kind IN ('income', 'expense')
        AND transfer_account_id IS NULL AND transfer_amount_minor IS NULL
        AND category_id IS NOT NULL)
    OR
    (kind IN ('loan_in', 'loan_out')
        AND transfer_account_id IS NULL AND transfer_amount_minor IS NULL
        AND category_id IS NULL AND due_id IS NOT NULL)
);

-- +goose Down
DELETE FROM transactions WHERE kind IN ('loan_in', 'loan_out');
ALTER TABLE transactions DROP CONSTRAINT transactions_shape;
ALTER TABLE transactions ADD CONSTRAINT transactions_shape CHECK (
    (kind = 'transfer'
        AND transfer_account_id IS NOT NULL AND transfer_account_id <> account_id
        AND transfer_amount_minor IS NOT NULL AND category_id IS NULL)
    OR
    (kind <> 'transfer'
        AND transfer_account_id IS NULL AND transfer_amount_minor IS NULL
        AND category_id IS NOT NULL)
);
ALTER TABLE transactions DROP CONSTRAINT transactions_kind_check;
ALTER TABLE transactions ADD CONSTRAINT transactions_kind_check
    CHECK (kind IN ('income', 'expense', 'transfer'));
DROP INDEX transactions_due_idx;
ALTER TABLE transactions DROP CONSTRAINT transactions_due_fkey;
ALTER TABLE transactions DROP COLUMN due_id;
DROP TABLE dues;
