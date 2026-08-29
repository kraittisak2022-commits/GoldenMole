-- Performance indexes for iOS / dashboard transaction queries.
-- Supports date-window fetches, category filters, and delta sync.

BEGIN;

CREATE INDEX IF NOT EXISTS transactions_date_idx
    ON transactions (date DESC);

CREATE INDEX IF NOT EXISTS transactions_date_category_idx
    ON transactions (date DESC, category);

-- updated_at index already exists as transactions_updated_at_idx (20260719130000)

COMMIT;
