-- Adds transactions.updated_at (auto-maintained) for delta sync, and ensures the
-- table is part of the realtime publication so the app receives WebSocket changes.
BEGIN;

CREATE EXTENSION IF NOT EXISTS moddatetime SCHEMA extensions;

ALTER TABLE transactions
    ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- Auto-update updated_at on every UPDATE regardless of the writer (web/app).
DROP TRIGGER IF EXISTS set_transactions_updated_at ON transactions;
CREATE TRIGGER set_transactions_updated_at
    BEFORE UPDATE ON transactions
    FOR EACH ROW
    EXECUTE PROCEDURE extensions.moddatetime(updated_at);

CREATE INDEX IF NOT EXISTS transactions_updated_at_idx
    ON transactions (updated_at DESC);

COMMIT;

-- Ensure realtime broadcasts changes for transactions (safe if already added).
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE transactions;
EXCEPTION
    WHEN duplicate_object THEN NULL;   -- already in publication
    WHEN undefined_object THEN
        RAISE NOTICE 'publication supabase_realtime not found; enable Realtime in the dashboard.';
END $$;
