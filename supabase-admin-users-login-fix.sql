-- Fix: allow pre-login reads from admin_users
-- Run this in Supabase SQL Editor when login shows:
-- "เชื่อมต่อ/สิทธิ์อ่านตาราง admin_users มีปัญหา"

BEGIN;

ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;

-- Remove restrictive read policy from hardening template (if present)
DROP POLICY IF EXISTS admin_users_read_all ON admin_users;

-- Keep write path restricted
DROP POLICY IF EXISTS admin_users_write_superadmin_only ON admin_users;

-- Allow login flow to read credential rows before auth session exists.
-- NOTE: Current app verifies password hash on client, so SELECT is required.
CREATE POLICY admin_users_read_for_login
ON admin_users
FOR SELECT
TO anon, authenticated
USING (true);

-- Only SuperAdmin can modify admin users.
CREATE POLICY admin_users_write_superadmin_only
ON admin_users
FOR ALL
TO authenticated
USING ((auth.jwt() ->> 'role') = 'SuperAdmin')
WITH CHECK ((auth.jwt() ->> 'role') = 'SuperAdmin');

COMMIT;
