-- +goose Up

-- Daily reference rates (ECB data through Frankfurter). Stored as given:
-- 1 base = rate quote, with base always EUR. Cross rates are worked out
-- from two EUR rates. No row on weekends and holidays: look up the latest
-- date on or before the day you need.
CREATE TABLE exchange_rates (
    base   char(3)        NOT NULL CHECK (base ~ '^[A-Z]{3}$'),
    quote  char(3)        NOT NULL CHECK (quote ~ '^[A-Z]{3}$'),
    date   date           NOT NULL,
    rate   numeric(20, 10) NOT NULL CHECK (rate > 0),
    PRIMARY KEY (base, quote, date)
);

-- Transactions whose base amount still waits for a rate (a currency with
-- no rate yet). The fill job finds them here.
CREATE INDEX transactions_missing_fx ON transactions (user_id)
    WHERE amount_base_minor IS NULL AND deleted_at IS NULL;

-- +goose Down
DROP INDEX transactions_missing_fx;
DROP TABLE exchange_rates;
