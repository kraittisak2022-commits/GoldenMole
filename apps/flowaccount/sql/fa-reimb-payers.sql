-- Reimbursement payers + proof columns (apply on existing projects)
CREATE TABLE IF NOT EXISTS fa_reimb_payers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  share_token TEXT NOT NULL UNIQUE,
  inactive BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE fa_reimbursements
  ADD COLUMN IF NOT EXISTS payer_id TEXT REFERENCES fa_reimb_payers(id),
  ADD COLUMN IF NOT EXISTS receipt_url TEXT,
  ADD COLUMN IF NOT EXISTS repayment_proof_url TEXT,
  ADD COLUMN IF NOT EXISTS repaid_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS quantity NUMERIC NOT NULL DEFAULT 1;

ALTER TABLE fa_ledger_entries
  ADD COLUMN IF NOT EXISTS quantity NUMERIC NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS paid_by TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'fa_ledger_entries_paid_by_check'
  ) THEN
    ALTER TABLE fa_ledger_entries
      ADD CONSTRAINT fa_ledger_entries_paid_by_check
      CHECK (paid_by IS NULL OR paid_by IN ('A', 'B', 'AB'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_fa_reimb_payer ON fa_reimbursements(payer_id);
CREATE INDEX IF NOT EXISTS idx_fa_reimb_payers_token ON fa_reimb_payers(share_token);

ALTER TABLE fa_reimb_payers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all on fa_reimb_payers" ON fa_reimb_payers;
CREATE POLICY "Allow all on fa_reimb_payers" ON fa_reimb_payers FOR ALL USING (true) WITH CHECK (true);
