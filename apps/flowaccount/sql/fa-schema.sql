-- FlowAccount schema (prefix fa_) — separate from GoldenMole ops tables

CREATE TABLE IF NOT EXISTS fa_categories (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('income', 'expense', 'both')),
  archived BOOLEAN NOT NULL DEFAULT FALSE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fa_employees (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('monthly', 'daily', 'daily_driver')),
  base_pay NUMERIC NOT NULL DEFAULT 0,
  inactive BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fa_fleet_assets (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  daily_rate NUMERIC NOT NULL DEFAULT 0,
  inactive BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fa_ledger_entries (
  id TEXT PRIMARY KEY,
  date TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  category_id TEXT NOT NULL REFERENCES fa_categories(id),
  entry_type TEXT NOT NULL CHECK (entry_type IN ('income', 'expense')),
  quantity NUMERIC NOT NULL DEFAULT 1 CHECK (quantity > 0),
  amount NUMERIC NOT NULL DEFAULT 0 CHECK (amount >= 0),
  paid_by TEXT CHECK (paid_by IS NULL OR paid_by IN ('A', 'B', 'AB')),
  source TEXT NOT NULL DEFAULT 'manual'
    CHECK (source IN ('manual', 'reimbursement', 'payroll', 'fleet')),
  source_id TEXT,
  created_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fa_reimbursements (
  id TEXT PRIMARY KEY,
  date TEXT NOT NULL,
  payer_name TEXT NOT NULL,
  payer_id TEXT,
  description TEXT NOT NULL DEFAULT '',
  quantity NUMERIC NOT NULL DEFAULT 1 CHECK (quantity > 0),
  amount NUMERIC NOT NULL DEFAULT 0 CHECK (amount >= 0),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected')),
  approved_category_id TEXT REFERENCES fa_categories(id),
  ledger_entry_id TEXT REFERENCES fa_ledger_entries(id),
  approved_by TEXT,
  approved_at TIMESTAMPTZ,
  receipt_url TEXT,
  repayment_proof_url TEXT,
  repaid_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fa_reimb_payers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  share_token TEXT NOT NULL UNIQUE,
  inactive BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE fa_reimbursements
  DROP CONSTRAINT IF EXISTS fa_reimbursements_payer_id_fkey;
ALTER TABLE fa_reimbursements
  ADD CONSTRAINT fa_reimbursements_payer_id_fkey
  FOREIGN KEY (payer_id) REFERENCES fa_reimb_payers(id);

CREATE TABLE IF NOT EXISTS fa_payroll_slips (
  id TEXT PRIMARY KEY,
  pay_date TEXT NOT NULL,
  employee_id TEXT NOT NULL REFERENCES fa_employees(id),
  employee_name TEXT NOT NULL,
  employee_type TEXT NOT NULL CHECK (employee_type IN ('monthly', 'daily', 'daily_driver')),
  base_pay NUMERIC NOT NULL DEFAULT 0,
  work_days NUMERIC NOT NULL DEFAULT 0,
  ot_amount NUMERIC NOT NULL DEFAULT 0,
  special_amount NUMERIC NOT NULL DEFAULT 0,
  total NUMERIC NOT NULL DEFAULT 0,
  ledger_entry_id TEXT REFERENCES fa_ledger_entries(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS fa_fleet_logs (
  id TEXT PRIMARY KEY,
  work_date TEXT NOT NULL,
  asset_id TEXT NOT NULL REFERENCES fa_fleet_assets(id),
  driver_name TEXT NOT NULL DEFAULT '',
  work_days NUMERIC NOT NULL DEFAULT 0,
  ot_amount NUMERIC NOT NULL DEFAULT 0,
  income_amount NUMERIC NOT NULL DEFAULT 0,
  total_cost NUMERIC NOT NULL DEFAULT 0,
  daily_rate_snapshot NUMERIC NOT NULL DEFAULT 0,
  asset_name_snapshot TEXT NOT NULL DEFAULT '',
  ledger_entry_id TEXT REFERENCES fa_ledger_entries(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_fa_ledger_date ON fa_ledger_entries(date);
CREATE INDEX IF NOT EXISTS idx_fa_ledger_category ON fa_ledger_entries(category_id);
CREATE INDEX IF NOT EXISTS idx_fa_reimb_status ON fa_reimbursements(status);
CREATE INDEX IF NOT EXISTS idx_fa_reimb_payer ON fa_reimbursements(payer_id);
CREATE INDEX IF NOT EXISTS idx_fa_reimb_payers_token ON fa_reimb_payers(share_token);
CREATE INDEX IF NOT EXISTS idx_fa_payroll_date ON fa_payroll_slips(pay_date);
CREATE INDEX IF NOT EXISTS idx_fa_fleet_date ON fa_fleet_logs(work_date);

ALTER TABLE fa_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE fa_employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE fa_fleet_assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE fa_ledger_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE fa_reimbursements ENABLE ROW LEVEL SECURITY;
ALTER TABLE fa_reimb_payers ENABLE ROW LEVEL SECURITY;
ALTER TABLE fa_payroll_slips ENABLE ROW LEVEL SECURITY;
ALTER TABLE fa_fleet_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow all on fa_categories" ON fa_categories;
DROP POLICY IF EXISTS "Allow all on fa_employees" ON fa_employees;
DROP POLICY IF EXISTS "Allow all on fa_fleet_assets" ON fa_fleet_assets;
DROP POLICY IF EXISTS "Allow all on fa_ledger_entries" ON fa_ledger_entries;
DROP POLICY IF EXISTS "Allow all on fa_reimbursements" ON fa_reimbursements;
DROP POLICY IF EXISTS "Allow all on fa_reimb_payers" ON fa_reimb_payers;
DROP POLICY IF EXISTS "Allow all on fa_payroll_slips" ON fa_payroll_slips;
DROP POLICY IF EXISTS "Allow all on fa_fleet_logs" ON fa_fleet_logs;

CREATE POLICY "Allow all on fa_categories" ON fa_categories FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on fa_employees" ON fa_employees FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on fa_fleet_assets" ON fa_fleet_assets FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on fa_ledger_entries" ON fa_ledger_entries FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on fa_reimbursements" ON fa_reimbursements FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on fa_reimb_payers" ON fa_reimb_payers FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on fa_payroll_slips" ON fa_payroll_slips FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on fa_fleet_logs" ON fa_fleet_logs FOR ALL USING (true) WITH CHECK (true);

-- Seed mock data (idempotent upserts)
INSERT INTO fa_categories (id, name, kind, archived, sort_order) VALUES
  ('cat-fuel', 'น้ำมันรถ', 'expense', false, 10),
  ('cat-repair', 'ซ่อมบำรุงเครื่องจักร', 'expense', false, 20),
  ('cat-supplies', 'ของใช้ทั่วไป', 'expense', false, 30),
  ('cat-salary', 'เงินเดือน', 'expense', false, 40),
  ('cat-reimburse', 'สำรองจ่าย', 'expense', false, 50),
  ('cat-income-job', 'รายรับจากบัญชีบริษัท', 'income', false, 5),
  ('cat-income-other', 'รายรับจากการขาย', 'income', false, 6)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  kind = EXCLUDED.kind,
  sort_order = EXCLUDED.sort_order;

INSERT INTO fa_employees (id, name, type, base_pay, inactive) VALUES
  ('emp-monthly-1', 'สมชาย ใจดี', 'monthly', 18000, false),
  ('emp-daily-1', 'วิชัย ขยัน', 'daily', 500, false),
  ('emp-driver-1', 'ประเสริฐ ขับดี', 'daily_driver', 650, false)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  type = EXCLUDED.type,
  base_pay = EXCLUDED.base_pay;

INSERT INTO fa_fleet_assets (id, name, daily_rate, inactive) VALUES
  ('fleet-backhoe-01', 'รถแบคโฮ 01', 3500, false),
  ('fleet-truck-10w', 'รถสิบล้อ', 2800, false)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  daily_rate = EXCLUDED.daily_rate;

INSERT INTO fa_ledger_entries (id, date, description, category_id, entry_type, amount, source, created_by) VALUES
  ('led-1', '2026-08-01', 'เติมน้ำมันรถสิบล้อ', 'cat-fuel', 'expense', 3200, 'manual', 'seed'),
  ('led-2', '2026-08-03', 'รับเงินงานขนทราย', 'cat-income-job', 'income', 25000, 'manual', 'seed'),
  ('led-3', '2026-08-05', 'ซื้อของใช้สำนักงาน', 'cat-supplies', 'expense', 890, 'manual', 'seed')
ON CONFLICT (id) DO NOTHING;

INSERT INTO fa_reimbursements (id, date, payer_name, description, amount, status) VALUES
  ('reimb-1', '2026-08-08', 'สมชาย ใจดี', 'สำรองจ่ายค่าซ่อมยางรถแบคโฮ', 1500, 'pending'),
  ('reimb-2', '2026-08-10', 'วิชัย ขยัน', 'สำรองจ่ายค่าอาหารพนักงานไซต์', 780, 'pending')
ON CONFLICT (id) DO NOTHING;

INSERT INTO fa_payroll_slips (
  id, pay_date, employee_id, employee_name, employee_type,
  base_pay, work_days, ot_amount, special_amount, total
) VALUES
  ('pay-1', '2026-08-15', 'emp-daily-1', 'วิชัย ขยัน', 'daily', 500, 12, 500, 200, 6700)
ON CONFLICT (id) DO NOTHING;

INSERT INTO fa_fleet_logs (
  id, work_date, asset_id, driver_name, work_days, ot_amount,
  income_amount, total_cost, daily_rate_snapshot, asset_name_snapshot
) VALUES
  ('flog-1', '2026-08-12', 'fleet-backhoe-01', 'ประเสริฐ ขับดี', 5, 1000, 22000, 18500, 3500, 'รถแบคโฮ 01')
ON CONFLICT (id) DO NOTHING;
