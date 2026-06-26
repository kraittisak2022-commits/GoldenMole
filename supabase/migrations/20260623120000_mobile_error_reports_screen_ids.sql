-- รหัสหน้าและขั้นตอนสำหรับรายงาน error จากแอปมือถือ

ALTER TABLE public.mobile_error_reports
    ADD COLUMN IF NOT EXISTS screen_page_id text;

ALTER TABLE public.mobile_error_reports
    ADD COLUMN IF NOT EXISTS screen_step_id text;
