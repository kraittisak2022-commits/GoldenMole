-- GoldenMole Photos (apps/photo, photo.goldenmole.pro).
-- Every table is read and written only by the Vercel functions with the service-role key:
-- RLS is on and there are no policies, so the anon key sees nothing.

CREATE TABLE IF NOT EXISTS ph_albums (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 200),
    report_date DATE NOT NULL,
    drive_folder_id TEXT NOT NULL,
    share_token TEXT NOT NULL UNIQUE,
    allow_link_upload BOOLEAN NOT NULL DEFAULT TRUE,
    cover_media_id UUID,
    media_count INTEGER NOT NULL DEFAULT 0,
    created_by TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS ph_albums_live_idx ON ph_albums (report_date DESC, created_at DESC) WHERE deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS ph_media (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    album_id UUID NOT NULL REFERENCES ph_albums (id) ON DELETE CASCADE,
    drive_file_id TEXT NOT NULL UNIQUE,
    kind TEXT NOT NULL CHECK (kind IN ('image', 'video')),
    mime TEXT NOT NULL,
    name TEXT NOT NULL,
    size_bytes BIGINT NOT NULL DEFAULT 0,
    width INTEGER NOT NULL DEFAULT 0,
    height INTEGER NOT NULL DEFAULT 0,
    taken_at TIMESTAMPTZ,
    uploaded_by_name TEXT,
    uploaded_by_staff_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ph_media_album_idx ON ph_media (album_id, created_at);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ph_albums_cover_media_fk') THEN
        ALTER TABLE ph_albums
            ADD CONSTRAINT ph_albums_cover_media_fk FOREIGN KEY (cover_media_id) REFERENCES ph_media (id) ON DELETE SET NULL;
    END IF;
END $$;

-- Year and month folders in Drive, keyed `root`, `2569`, `2569/10`. The primary key stops two requests
-- from creating the same folder twice.
CREATE TABLE IF NOT EXISTS ph_drive_folders (
    path_key TEXT PRIMARY KEY,
    folder_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ph_settings (
    id SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    google_refresh_token TEXT,
    google_email TEXT,
    connected_at TIMESTAMPTZ,
    connected_by TEXT
);

ALTER TABLE ph_albums ENABLE ROW LEVEL SECURITY;
ALTER TABLE ph_media ENABLE ROW LEVEL SECURITY;
ALTER TABLE ph_drive_folders ENABLE ROW LEVEL SECURITY;
ALTER TABLE ph_settings ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON ph_albums, ph_media, ph_drive_folders, ph_settings FROM anon, authenticated;
