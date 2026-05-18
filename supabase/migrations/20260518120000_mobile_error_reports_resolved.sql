-- สถานะ "แก้ไขเรียบร้อย" สำหรับรายงานจากแอป Android (เว็บ ตั้งค่า > แอป Android)

ALTER TABLE public.mobile_error_reports
    ADD COLUMN IF NOT EXISTS resolved boolean NOT NULL DEFAULT false;

ALTER TABLE public.mobile_error_reports
    ADD COLUMN IF NOT EXISTS resolved_at timestamptz;

ALTER TABLE public.mobile_error_reports
    ADD COLUMN IF NOT EXISTS resolved_by text;

CREATE INDEX IF NOT EXISTS idx_mobile_error_reports_unresolved
    ON public.mobile_error_reports (resolved)
    WHERE resolved = false;
