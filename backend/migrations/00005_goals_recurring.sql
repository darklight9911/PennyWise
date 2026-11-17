-- +goose Up
-- Savings goals, their contributions, and recurring income/expense rules.
-- All three are synced like accounts (client UUIDs, version, LWW, soft delete).

CREATE TABLE goals (
    id           uuid        PRIMARY KEY,
    user_id      uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    name         text        NOT NULL CHECK (char_length(name) BETWEEN 1 AND 60),
    -- In the user's base currency.
    target_minor bigint      NOT NULL CHECK (target_minor > 0),
    deadline     date,
    icon         text        NOT NULL DEFAULT '',
    color        text        NOT NULL DEFAULT '' CHECK (color = '' OR color ~ '^#[0-9A-F]{6}$'),
    archived     boolean     NOT NULL DEFAULT false,
    version      bigint      NOT NULL,
    updated_at   timestamptz NOT NULL,
    deleted_at   timestamptz,
    created_at   timestamptz NOT NULL DEFAULT now(),
    UNIQUE (id, user_id)
);
CREATE INDEX goals_user_version_idx ON goals (user_id, version);

-- Money put into (positive) or taken out of (negative) a goal.
CREATE TABLE goal_contributions (
    id           uuid        PRIMARY KEY,
    user_id      uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    goal_id      uuid        NOT NULL,
    amount_minor bigint      NOT NULL CHECK (amount_minor <> 0),
    local_date   date        NOT NULL,
    note         text        NOT NULL DEFAULT '' CHECK (char_length(note) <= 500),
    version      bigint      NOT NULL,
    updated_at   timestamptz NOT NULL,
    deleted_at   timestamptz,
    created_at   timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (goal_id, user_id) REFERENCES goals (id, user_id) ON DELETE CASCADE
);
CREATE INDEX goal_contributions_user_version_idx ON goal_contributions (user_id, version);
CREATE INDEX goal_contributions_goal_idx ON goal_contributions (goal_id);

-- A repeating income or expense. Occurrences are ordinary transactions with
-- recurring_id + occurrence_date and the ID UUIDv5(rule id + ":" + date),
-- so the phone and the server can both create them without duplicates.
CREATE TABLE recurring_rules (
    id                 uuid        PRIMARY KEY,
    user_id            uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    kind               text        NOT NULL CHECK (kind IN ('income', 'expense')),
    account_id         uuid        NOT NULL,
    category_id        uuid        NOT NULL,
    amount_minor       bigint      NOT NULL CHECK (amount_minor > 0),
    currency           char(3)     NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
    note               text        NOT NULL DEFAULT '' CHECK (char_length(note) <= 500),
    frequency          text        NOT NULL CHECK (frequency IN ('daily', 'weekly', 'monthly', 'yearly')),
    every              integer     NOT NULL DEFAULT 1 CHECK (every BETWEEN 1 AND 365),
    start_date         date        NOT NULL,
    end_date           date        CHECK (end_date IS NULL OR end_date >= start_date),
    remind_days_before integer     NOT NULL DEFAULT 0 CHECK (remind_days_before BETWEEN 0 AND 30),
    active             boolean     NOT NULL DEFAULT true,
    version            bigint      NOT NULL,
    updated_at         timestamptz NOT NULL,
    deleted_at         timestamptz,
    created_at         timestamptz NOT NULL DEFAULT now(),
    UNIQUE (id, user_id),
    FOREIGN KEY (account_id, user_id) REFERENCES accounts (id, user_id) ON DELETE CASCADE,
    FOREIGN KEY (category_id, user_id) REFERENCES categories (id, user_id)
);
CREATE INDEX recurring_rules_user_version_idx ON recurring_rules (user_id, version);
CREATE INDEX recurring_rules_active_idx ON recurring_rules (user_id) WHERE active AND deleted_at IS NULL;

-- Reminders already sent (one per rule and occurrence date).
CREATE TABLE recurring_reminders (
    rule_id         uuid        NOT NULL REFERENCES recurring_rules (id) ON DELETE CASCADE,
    occurrence_date date        NOT NULL,
    sent_at         timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (rule_id, occurrence_date)
);

-- +goose Down
DROP TABLE recurring_reminders;
DROP TABLE recurring_rules;
DROP TABLE goal_contributions;
DROP TABLE goals;
