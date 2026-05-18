-- คอลัมน์บริบทหน้าจอจากแอป Android (SaveErrorContext)

ALTER TABLE public.mobile_error_reports
    ADD COLUMN IF NOT EXISTS screen_page text;

ALTER TABLE public.mobile_error_reports
    ADD COLUMN IF NOT EXISTS screen_action text;

ALTER TABLE public.mobile_error_reports
    ADD COLUMN IF NOT EXISTS screen_button text;

ALTER TABLE public.mobile_error_reports
    ADD COLUMN IF NOT EXISTS error_field text;
