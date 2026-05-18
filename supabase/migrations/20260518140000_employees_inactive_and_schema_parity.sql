-- พนักงาน inactive + ยืนยันคอลัมน์ transactions (idempotent, รันทีละคำสั่ง)

ALTER TABLE public.employees
    ADD COLUMN IF NOT EXISTS inactive boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.employees.inactive IS 'true = ไม่แสดงในรายการเลือกพนักงาน / เก็บประวัติไว้';

ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS work_type_by_employee jsonb;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS work_assignments jsonb;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS custom_work_categories jsonb DEFAULT '[]'::jsonb;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS fuel_movement text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS trip_billing_mode text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS income_payment_status text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS sand_work_start text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS sand_batch_id text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS sand_home_batch_usages jsonb;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS payroll_lock_action text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS unlocked_by_admin_id text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS unlocked_by_admin_name text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS unlocked_at text;

-- ตาราง mobile_error_reports สร้างแล้วจาก migration 20260510230000 — อย่ารันแค่บล็อกคอลัมน์โดยไม่มี CREATE/ALTER
-- resolved + RLS: ดู 20260518120000_mobile_error_reports_resolved.sql
