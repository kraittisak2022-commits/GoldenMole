-- Fix for current app architecture (client-side with Supabase anon key)
-- Symptom: data in DB does not appear on web UI.
-- Cause: restrictive RLS policies require JWT role claims that anon client does not have.
--
-- Run this in Supabase SQL Editor.
-- This keeps behavior aligned with `supabase-schema.sql` (allow all) for now.
-- You can re-harden later after migrating to real Supabase Auth sessions.

BEGIN;

ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE land_projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_logs ENABLE ROW LEVEL SECURITY;

-- Drop strict policies from hardening template (if present)
DROP POLICY IF EXISTS employees_read_logged_in ON employees;
DROP POLICY IF EXISTS employees_write_admin ON employees;
DROP POLICY IF EXISTS transactions_read_logged_in ON transactions;
DROP POLICY IF EXISTS transactions_write_not_assistant ON transactions;
DROP POLICY IF EXISTS transactions_update_not_assistant ON transactions;
DROP POLICY IF EXISTS transactions_delete_superadmin ON transactions;
DROP POLICY IF EXISTS land_projects_read_logged_in ON land_projects;
DROP POLICY IF EXISTS land_projects_write_admin ON land_projects;
DROP POLICY IF EXISTS app_settings_read_logged_in ON app_settings;
DROP POLICY IF EXISTS app_settings_write_superadmin ON app_settings;
DROP POLICY IF EXISTS work_plans_read_logged_in ON work_plans;
DROP POLICY IF EXISTS work_plans_write_admin ON work_plans;
DROP POLICY IF EXISTS admin_logs_read_admins ON admin_logs;
DROP POLICY IF EXISTS admin_logs_insert_admins ON admin_logs;
DROP POLICY IF EXISTS admin_users_read_for_login ON admin_users;
DROP POLICY IF EXISTS admin_users_write_superadmin_only ON admin_users;
DROP POLICY IF EXISTS admin_users_read_all ON admin_users;

-- Drop existing allow-all policies before recreate (idempotent)
DROP POLICY IF EXISTS "Allow all on employees" ON employees;
DROP POLICY IF EXISTS "Allow all on transactions" ON transactions;
DROP POLICY IF EXISTS "Allow all on land_projects" ON land_projects;
DROP POLICY IF EXISTS "Allow all on app_settings" ON app_settings;
DROP POLICY IF EXISTS "Allow all on work_plans" ON work_plans;
DROP POLICY IF EXISTS "Allow all on admin_users" ON admin_users;
DROP POLICY IF EXISTS "Allow all on admin_logs" ON admin_logs;

-- Recreate permissive policies for current client architecture
CREATE POLICY "Allow all on employees" ON employees FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on transactions" ON transactions FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on land_projects" ON land_projects FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on app_settings" ON app_settings FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on work_plans" ON work_plans FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on admin_users" ON admin_users FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on admin_logs" ON admin_logs FOR ALL TO anon, authenticated USING (true) WITH CHECK (true);

COMMIT;
