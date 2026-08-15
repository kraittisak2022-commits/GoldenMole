-- Salary advance withdrawals (date, employee, amount)
CREATE TABLE IF NOT EXISTS fa_salary_advances (
  id TEXT PRIMARY KEY,
  advance_date TEXT NOT NULL,
  employee_id TEXT NOT NULL REFERENCES fa_employees(id),
  employee_name TEXT NOT NULL DEFAULT '',
  amount NUMERIC NOT NULL DEFAULT 0 CHECK (amount >= 0),
  notes TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_fa_salary_advances_date ON fa_salary_advances(advance_date);
CREATE INDEX IF NOT EXISTS idx_fa_salary_advances_emp ON fa_salary_advances(employee_id);

ALTER TABLE fa_salary_advances ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all on fa_salary_advances" ON fa_salary_advances;
CREATE POLICY "Allow all on fa_salary_advances" ON fa_salary_advances FOR ALL USING (true) WITH CHECK (true);
