-- +goose Up

-- Security events (sign-ups, logins, failed logins, password resets,
-- base-currency changes, exports, account deletion). Kept 180 days, and
-- deleted with the account.
CREATE TABLE audit_log (
    id         bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id    uuid        REFERENCES users (id) ON DELETE CASCADE,
    action     text        NOT NULL,
    entity     text        NOT NULL DEFAULT '',
    entity_id  uuid,
    ip         inet,
    user_agent text        NOT NULL DEFAULT '',
    detail     jsonb       NOT NULL DEFAULT '{}',
    at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_log_user_idx ON audit_log (user_id, at DESC);
CREATE INDEX audit_log_at_idx   ON audit_log (at);

-- +goose Down
DROP TABLE audit_log;
