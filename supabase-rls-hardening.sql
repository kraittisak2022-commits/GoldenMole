-- ============================================
-- RLS Hardening Template (manual apply)
-- ============================================
-- ใช้ร่วมกับ Supabase Auth JWT claim:
--   auth.jwt() ->> 'role'       เช่น SuperAdmin / Admin / Assistant
--   auth.jwt() ->> 'admin_id'   id ของ admin_users
--
-- หมายเหตุ:
-- 1) สคริปต์นี้เป็นแม่แบบสำหรับ production
-- 2) ต้องปรับให้ตรงระบบ auth จริงก่อน apply

BEGIN;

ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE land_projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_logs ENABLE ROW LEVEL SECURITY;

-- ลบนโยบาย allow-all เดิม (ถ้ามี)
DROP POLICY IF EXISTS "Allow all on employees" ON employees;
DROP POLICY IF EXISTS "Allow all on transactions" ON transactions;
DROP POLICY IF EXISTS "Allow all on land_projects" ON land_projects;
DROP POLICY IF EXISTS "Allow all on app_settings" ON app_settings;
DROP POLICY IF EXISTS "Allow all on work_plans" ON work_plans;
DROP POLICY IF EXISTS "Allow all on admin_users" ON admin_users;
DROP POLICY IF EXISTS "Allow all on admin_logs" ON admin_logs;

-- --------------------------
-- Admin users / Admin logs
-- --------------------------
-- IMPORTANT:
-- Current login flow validates admin_users password hash on the client
-- before a Supabase auth session exists, so anon must be able to SELECT.
DROP POLICY IF EXISTS admin_users_read_for_login ON admin_users;
CREATE POLICY admin_users_read_for_login
ON admin_users FOR SELECT
TO anon, authenticated
USING (true);

DROP POLICY IF EXISTS admin_users_write_superadmin_only ON admin_users;
CREATE POLICY admin_users_write_superadmin_only
ON admin_users FOR ALL
TO authenticated
USING ((auth.jwt() ->> 'role') = 'SuperAdmin')
WITH CHECK ((auth.jwt() ->> 'role') = 'SuperAdmin');

CREATE POLICY admin_logs_read_admins
ON admin_logs FOR SELECT
USING ((auth.jwt() ->> 'role') IN ('SuperAdmin', 'Admin'));

CREATE POLICY admin_logs_insert_admins
ON admin_logs FOR INSERT
WITH CHECK ((auth.jwt() ->> 'role') IN ('SuperAdmin', 'Admin', 'Assistant'));

-- --------------------------
-- Transactions
-- --------------------------
CREATE POLICY transactions_read_logged_in
ON transactions FOR SELECT
USING ((auth.jwt() ->> 'role') IN ('SuperAdmin', 'Admin', 'Assistant'));

CREATE POLICY transactions_write_not_assistant
ON transactions FOR INSERT
WITH CHECK ((auth.jwt() ->> 'role') IN ('SuperAdmin', 'Admin'));

CREATE POLICY transactions_update_not_assistant
ON transactions FOR UPDATE
USING ((auth.jwt() ->> 'role') IN ('SuperAdmin', 'Admin'))
WITH CHECK ((auth.jwt() ->> 'role') IN ('SuperAdmin', 'Admin'));

CREATE POLICY transactions_delete_superadmin
ON transactions FOR DELETE
USING ((auth.jwt() ->> 'role') = 'SuperAdmin');

-- --------------------------
-- Other business tables
-- --------------------------
CREATE POLICY employees_read_logged_in
ON employees FOR SELECT
USING ((auth.jwt() ->> 'role') IN ('SuperAdmin', 'Admin', 'Assistant'));

CREATE POLICY employees_write_admin
ON employees FOR ALL
USING ((auth.jwt() ->> 'role') IN ('SuperAdmin', 'Admin'))
WITH CHECK ((auth.jwt() ->> 'role') IN ('SuperAdmin', 'Admin'));

CREATE POLICY land_projects_read_logged_in
ON land_projects FOR SELECT
USING ((auth.jwt() ->> 'role') IN ('SuperAdmin', 'Admin', 'Assistant'));

CREATE POLICY land_projects_write_admin
ON land_projects FOR ALL
USING ((auth.jwt() ->> 'role') IN ('SuperAdmin', 'Admin'))
WITH CHECK ((auth.jwt() ->> 'role') IN ('SuperAdmin', 'Admin'));

CREATE POLICY app_settings_read_logged_in
ON app_settings FOR SELECT
USING ((auth.jwt() ->> 'role') IN ('SuperAdmin', 'Admin', 'Assistant'));

CREATE POLICY app_settings_write_superadmin
ON app_settings FOR ALL
USING ((auth.jwt() ->> 'role') = 'SuperAdmin')
WITH CHECK ((auth.jwt() ->> 'role') = 'SuperAdmin');

CREATE POLICY work_plans_read_logged_in
ON work_plans FOR SELECT
USING ((auth.jwt() ->> 'role') IN ('SuperAdmin', 'Admin', 'Assistant'));

CREATE POLICY work_plans_write_admin
ON work_plans FOR ALL
USING ((auth.jwt() ->> 'role') IN ('SuperAdmin', 'Admin'))
WITH CHECK ((auth.jwt() ->> 'role') IN ('SuperAdmin', 'Admin'));

COMMIT;
