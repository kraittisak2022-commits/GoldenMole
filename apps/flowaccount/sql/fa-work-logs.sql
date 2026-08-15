-- Daily wage cells + per-period summary (paid / special / advance / notes)
ALTER TABLE fa_work_logs
  ADD COLUMN IF NOT EXISTS amount NUMERIC NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS fa_work_period_summaries (
  id TEXT PRIMARY KEY,
  period_key TEXT NOT NULL,
  employee_id TEXT NOT NULL REFERENCES fa_employees(id),
  paid BOOLEAN NOT NULL DEFAULT FALSE,
  special_amount NUMERIC NOT NULL DEFAULT 0,
  advance_amount NUMERIC NOT NULL DEFAULT 0,
  notes TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (period_key, employee_id)
);

CREATE INDEX IF NOT EXISTS idx_fa_work_period_key ON fa_work_period_summaries(period_key);

ALTER TABLE fa_work_period_summaries ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all on fa_work_period_summaries" ON fa_work_period_summaries;
CREATE POLICY "Allow all on fa_work_period_summaries" ON fa_work_period_summaries FOR ALL USING (true) WITH CHECK (true);
