-- +goose Up
-- Budgets (synced like accounts), phones for push messages, and a log of
-- alerts already sent so each one goes out once per budget period.

CREATE TABLE budgets (
    id               uuid        PRIMARY KEY,
    user_id          uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    -- NULL = an overall budget for all spending.
    category_id      uuid,
    -- In the user's base currency (PLAN.md: budgets compare base amounts).
    amount_minor     bigint      NOT NULL CHECK (amount_minor > 0),
    period           text        NOT NULL CHECK (period IN ('weekly', 'monthly')),
    -- Percentages of the amount that trigger an alert, e.g. {80,100}.
    alert_thresholds integer[]   NOT NULL DEFAULT '{80,100}'
                     CHECK (cardinality(alert_thresholds) <= 5
                            AND 1 <= ALL (alert_thresholds)
                            AND 200 >= ALL (alert_thresholds)),
    version          bigint      NOT NULL,
    updated_at       timestamptz NOT NULL,
    deleted_at       timestamptz,
    created_at       timestamptz NOT NULL DEFAULT now(),
    UNIQUE (id, user_id),
    FOREIGN KEY (category_id, user_id) REFERENCES categories (id, user_id)
);
CREATE INDEX budgets_user_version_idx ON budgets (user_id, version);
CREATE INDEX budgets_live_idx ON budgets (user_id) WHERE deleted_at IS NULL;

-- One row per phone that can receive push messages (FCM token).
CREATE TABLE devices (
    id           uuid        PRIMARY KEY DEFAULT uuidv7(),
    user_id      uuid        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    push_token   text        NOT NULL UNIQUE CHECK (char_length(push_token) BETWEEN 1 AND 4096),
    platform     text        NOT NULL CHECK (platform IN ('android', 'ios')),
    created_at   timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX devices_user_idx ON devices (user_id);

-- An alert is sent once per budget, period and threshold. The primary key
-- makes a second send impossible even if two workers race.
CREATE TABLE budget_alerts (
    budget_id    uuid        NOT NULL REFERENCES budgets (id) ON DELETE CASCADE,
    period_start date        NOT NULL,
    threshold    integer     NOT NULL,
    spent_minor  bigint      NOT NULL,
    sent_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (budget_id, period_start, threshold)
);

-- +goose Down
DROP TABLE budget_alerts;
DROP TABLE devices;
DROP TABLE budgets;
