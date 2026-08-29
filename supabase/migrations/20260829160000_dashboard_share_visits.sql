-- Track Real-time V.4 share link viewers (device / IP / visit counts)
BEGIN;

CREATE TABLE IF NOT EXISTS dashboard_share_visits (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    share_token text NOT NULL DEFAULT '',
    device_key text NOT NULL,
    device_label text NOT NULL DEFAULT '',
    ip_address text NOT NULL DEFAULT '',
    user_agent text NOT NULL DEFAULT '',
    visit_count integer NOT NULL DEFAULT 1 CHECK (visit_count >= 1),
    first_seen_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT dashboard_share_visits_device_key_unique UNIQUE (device_key)
);

CREATE INDEX IF NOT EXISTS dashboard_share_visits_last_seen_idx
    ON dashboard_share_visits (last_seen_at DESC);

CREATE INDEX IF NOT EXISTS dashboard_share_visits_share_token_idx
    ON dashboard_share_visits (share_token);

ALTER TABLE dashboard_share_visits ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow all on dashboard_share_visits" ON dashboard_share_visits;
CREATE POLICY "Allow all on dashboard_share_visits"
    ON dashboard_share_visits
    FOR ALL
    TO anon, authenticated
    USING (true)
    WITH CHECK (true);

COMMIT;
