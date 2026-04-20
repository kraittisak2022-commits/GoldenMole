-- ============================================
-- GoldenMole Construction Management App
-- Supabase Database Schema
-- ============================================

-- 1. Employees
CREATE TABLE IF NOT EXISTS employees (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    nickname TEXT NOT NULL,
    type TEXT NOT NULL CHECK (type IN ('Daily', 'Monthly')),
    base_wage NUMERIC NOT NULL DEFAULT 0,
    position TEXT,
    positions JSONB DEFAULT '[]'::jsonb,
    phone TEXT,
    start_date TEXT,
    salary_history JSONB DEFAULT '[]'::jsonb,
    kpi_history JSONB DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Transactions
CREATE TABLE IF NOT EXISTS transactions (
    id TEXT PRIMARY KEY,
    date TEXT NOT NULL,
    type TEXT NOT NULL,
    category TEXT NOT NULL,
    sub_category TEXT,
    description TEXT NOT NULL DEFAULT '',
    amount NUMERIC NOT NULL DEFAULT 0,
    employee_id TEXT,
    employee_ids JSONB DEFAULT '[]'::jsonb,
    driver_id TEXT,
    driver_wage NUMERIC,
    vehicle_wage NUMERIC,
    vehicle_id TEXT,
    quantity NUMERIC,
    unit TEXT,
    unit_price NUMERIC,
    project_id TEXT,
    mileage NUMERIC,
    image_url TEXT,
    location TEXT,
    labor_status TEXT,
    work_type TEXT,
    work_type_by_employee JSONB,
    work_assignments JSONB,
    custom_work_categories JSONB DEFAULT '[]'::jsonb,
    ot_amount NUMERIC,
    advance_amount NUMERIC,
    special_amount NUMERIC,
    ot_hours NUMERIC,
    ot_description TEXT,
    leave_reason TEXT,
    leave_days NUMERIC,
    note TEXT,
    work_details TEXT,
    fuel_type TEXT,
    fuel_movement TEXT,
    payroll_period JSONB,
    payroll_snapshot JSONB,
    machine_id TEXT,
    machine_hours NUMERIC,
    machine_work_type TEXT,
    sand_morning NUMERIC,
    sand_afternoon NUMERIC,
    sand_machine_type TEXT,
    sand_operators JSONB DEFAULT '[]'::jsonb,
    sand_transport NUMERIC,
    drums_obtained NUMERIC,
    drums_washed_at_home NUMERIC,
    sand_work_start TEXT,
    sand_morning_start TEXT,
    sand_afternoon_start TEXT,
    sand_evening_end TEXT,
    trip_count NUMERIC,
    trip_morning NUMERIC,
    trip_afternoon NUMERIC,
    cubic_per_trip NUMERIC,
    total_cubic NUMERIC,
    per_car_trips NUMERIC,
    per_car_cubic NUMERIC,
    event_type TEXT,
    event_priority TEXT,
    event_time TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Land Projects
CREATE TABLE IF NOT EXISTS land_projects (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    group_name TEXT,
    seller_name TEXT,
    title_deed TEXT,
    rai NUMERIC,
    ngan NUMERIC,
    sq_wah NUMERIC,
    full_price NUMERIC NOT NULL DEFAULT 0,
    deposit NUMERIC NOT NULL DEFAULT 0,
    purchase_date TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('Deposit', 'PaidFull', 'Transferred')),
    details TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. App Settings (singleton row)
CREATE TABLE IF NOT EXISTS app_settings (
    id TEXT PRIMARY KEY DEFAULT 'default',
    app_name TEXT NOT NULL DEFAULT 'Goldenmole Dashboard',
    app_subtext TEXT DEFAULT '',
    app_icon TEXT DEFAULT '',
    app_icon_dark TEXT DEFAULT '',
    cars JSONB DEFAULT '[]'::jsonb,
    job_descriptions JSONB DEFAULT '[]'::jsonb,
    income_types JSONB DEFAULT '[]'::jsonb,
    expense_types JSONB DEFAULT '[]'::jsonb,
    maintenance_types JSONB DEFAULT '[]'::jsonb,
    locations JSONB DEFAULT '[]'::jsonb,
    land_groups JSONB DEFAULT '[]'::jsonb,
    employee_positions JSONB DEFAULT '[]'::jsonb,
    fuel_opening_stock JSONB DEFAULT '{"Diesel":0,"Benzine":0}'::jsonb,
    org_profile JSONB DEFAULT '{}'::jsonb,
    app_defaults JSONB DEFAULT '{}'::jsonb,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- เพิ่มคอลัมน์สต็อกน้ำมันยกมา (ถ้ามีตาราง app_settings อยู่แล้วจากเวอร์ชันเก่า)
ALTER TABLE app_settings ADD COLUMN IF NOT EXISTS fuel_opening_stock JSONB DEFAULT '{"Diesel":0,"Benzine":0}'::jsonb;
ALTER TABLE app_settings ADD COLUMN IF NOT EXISTS employee_positions JSONB DEFAULT '[]'::jsonb;
ALTER TABLE app_settings ADD COLUMN IF NOT EXISTS org_profile JSONB DEFAULT '{}'::jsonb;
ALTER TABLE app_settings ADD COLUMN IF NOT EXISTS app_defaults JSONB DEFAULT '{}'::jsonb;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS position TEXT;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS positions JSONB DEFAULT '[]'::jsonb;

ALTER TABLE transactions ADD COLUMN IF NOT EXISTS fuel_movement TEXT;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS work_type_by_employee JSONB;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS work_assignments JSONB;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS custom_work_categories JSONB DEFAULT '[]'::jsonb;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS drums_obtained NUMERIC;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS drums_washed_at_home NUMERIC;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS sand_work_start TEXT;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS sand_morning_start TEXT;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS sand_afternoon_start TEXT;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS sand_evening_end TEXT;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS trip_count NUMERIC;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS trip_morning NUMERIC;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS trip_afternoon NUMERIC;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS cubic_per_trip NUMERIC;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS total_cubic NUMERIC;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS per_car_trips NUMERIC;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS per_car_cubic NUMERIC;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS event_type TEXT;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS event_priority TEXT;

-- 5. Admin Users
CREATE TABLE IF NOT EXISTS admin_users (
    id TEXT PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL,
    display_name TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('SuperAdmin', 'Admin')),
    created_at TEXT NOT NULL,
    last_login TEXT,
    avatar TEXT,
    must_change_password BOOLEAN NOT NULL DEFAULT FALSE,
    ui_theme TEXT DEFAULT 'system'
);

ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS must_change_password BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS ui_theme TEXT DEFAULT 'system';

-- 6. Admin Logs
CREATE TABLE IF NOT EXISTS admin_logs (
    id TEXT PRIMARY KEY,
    admin_id TEXT NOT NULL,
    admin_name TEXT NOT NULL,
    action TEXT NOT NULL,
    details TEXT NOT NULL DEFAULT '',
    timestamp TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- Row Level Security (RLS) - Allow all for anon key
-- (For production, you should configure proper RLS policies)
-- ============================================
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE land_projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_logs ENABLE ROW LEVEL SECURITY;

-- Allow full access for authenticated and anon users (DROP ก่อนเพื่อให้รันสคริปต์ซ้ำได้)
DROP POLICY IF EXISTS "Allow all on employees" ON employees;
DROP POLICY IF EXISTS "Allow all on transactions" ON transactions;
DROP POLICY IF EXISTS "Allow all on land_projects" ON land_projects;
DROP POLICY IF EXISTS "Allow all on app_settings" ON app_settings;
DROP POLICY IF EXISTS "Allow all on admin_users" ON admin_users;
DROP POLICY IF EXISTS "Allow all on admin_logs" ON admin_logs;

CREATE POLICY "Allow all on employees" ON employees FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on transactions" ON transactions FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on land_projects" ON land_projects FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on app_settings" ON app_settings FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on admin_users" ON admin_users FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on admin_logs" ON admin_logs FOR ALL USING (true) WITH CHECK (true);

-- Create indexes for common queries
CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions(date);
CREATE INDEX IF NOT EXISTS idx_transactions_category ON transactions(category);
CREATE INDEX IF NOT EXISTS idx_transactions_type ON transactions(type);
CREATE INDEX IF NOT EXISTS idx_admin_logs_admin_id ON admin_logs(admin_id);
