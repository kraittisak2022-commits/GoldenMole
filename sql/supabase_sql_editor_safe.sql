-- รันใน Supabase SQL Editor ทั้งไฟล์ (Run) — แต่ละบล็อกเป็นคำสั่งสมบูรณ์
-- อย่าเลือกรันแค่บรรทัดชื่อคอลัมน์ เช่น reviewed boolean ... จะ error 42601

-- 1) พนักงาน inactive
ALTER TABLE public.employees
    ADD COLUMN IF NOT EXISTS inactive boolean NOT NULL DEFAULT false;

-- 2) คอลัมน์รายงาน error จากแอป (บริบทหน้าจอ)
ALTER TABLE public.mobile_error_reports
    ADD COLUMN IF NOT EXISTS screen_page text;
ALTER TABLE public.mobile_error_reports
    ADD COLUMN IF NOT EXISTS screen_action text;
ALTER TABLE public.mobile_error_reports
    ADD COLUMN IF NOT EXISTS screen_button text;
ALTER TABLE public.mobile_error_reports
    ADD COLUMN IF NOT EXISTS error_field text;

ALTER TABLE public.mobile_error_reports
    ADD COLUMN IF NOT EXISTS resolved boolean NOT NULL DEFAULT false;
ALTER TABLE public.mobile_error_reports
    ADD COLUMN IF NOT EXISTS resolved_at timestamptz;
ALTER TABLE public.mobile_error_reports
    ADD COLUMN IF NOT EXISTS resolved_by text;
