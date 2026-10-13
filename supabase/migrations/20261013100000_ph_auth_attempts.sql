-- GoldenMole Photos: sign-in and album PIN attempts, for lockouts against password / PIN guessing.
-- `key_hash` is an HMAC of the IP address, username or album id, so raw addresses are never stored.
-- Written and read only by the Vercel functions with the service-role key.

CREATE TABLE IF NOT EXISTS ph_auth_attempts (
    id BIGSERIAL PRIMARY KEY,
    scope TEXT NOT NULL CHECK (scope IN ('login_ip', 'login_user', 'pin_ip', 'pin_album')),
    key_hash TEXT NOT NULL,
    success BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ph_auth_attempts_lookup_idx ON ph_auth_attempts (scope, key_hash, created_at DESC);
CREATE INDEX IF NOT EXISTS ph_auth_attempts_created_idx ON ph_auth_attempts (created_at);

ALTER TABLE ph_auth_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON ph_auth_attempts FROM anon, authenticated;
