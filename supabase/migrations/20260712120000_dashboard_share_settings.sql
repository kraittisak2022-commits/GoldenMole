-- Public share link settings for Real-time Dashboard V.4 (singleton row)
BEGIN;

CREATE TABLE IF NOT EXISTS dashboard_share_settings (
    id text PRIMARY KEY DEFAULT 'default',
    enabled boolean NOT NULL DEFAULT false,
    share_token text NOT NULL DEFAULT '',
    pin_hash text,
    show_financial boolean NOT NULL DEFAULT false,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT dashboard_share_settings_singleton CHECK (id = 'default')
);

ALTER TABLE dashboard_share_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow all on dashboard_share_settings" ON dashboard_share_settings;
CREATE POLICY "Allow all on dashboard_share_settings"
    ON dashboard_share_settings
    FOR ALL
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);

INSERT INTO dashboard_share_settings (id, enabled, share_token, pin_hash, show_financial)
VALUES ('default', false, '', null, false)
ON CONFLICT (id) DO NOTHING;

COMMIT;
