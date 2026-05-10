-- รายงานข้อผิดพลาดจากแอปมือถือ (Android) → ดูได้ในเว็บ ตั้งค่า > แอป Android

CREATE TABLE IF NOT EXISTS public.mobile_error_reports (
    id text PRIMARY KEY,
    created_at timestamptz NOT NULL DEFAULT now(),
    platform text NOT NULL DEFAULT 'android',
    reported_by_username text,
    reported_by_name text,
    app_version text,
    device_info text,
    error_summary text NOT NULL,
    error_detail text,
    user_note text,
    source text NOT NULL DEFAULT 'manual',
    reviewed boolean NOT NULL DEFAULT false,
    reviewed_at timestamptz,
    reviewed_by text
);

CREATE INDEX IF NOT EXISTS idx_mobile_error_reports_created_at
    ON public.mobile_error_reports (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_mobile_error_reports_unreviewed
    ON public.mobile_error_reports (reviewed)
    WHERE reviewed = false;

ALTER TABLE public.mobile_error_reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow all on mobile_error_reports" ON public.mobile_error_reports;
CREATE POLICY "Allow all on mobile_error_reports"
    ON public.mobile_error_reports
    FOR ALL
    USING (true)
    WITH CHECK (true);
