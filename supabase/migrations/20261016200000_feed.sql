-- อัพเดตงาน (Feed) — Facebook-style team feed for iOS
-- Auth is custom against admin_users (not Supabase Auth), so RLS mirrors `tasks`: allow all via anon key.
-- Media files live in Google Drive ("GoldenMole Feed"); this table stores the index only.

CREATE TABLE IF NOT EXISTS public.feed_posts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    kind text NOT NULL
        CHECK (kind IN ('admin', 'task_created', 'task_done', 'task_nag', 'leave_digest')),
    author_admin_id text,
    author_name text NOT NULL DEFAULT 'ระบบ',
    body text NOT NULL DEFAULT '',
    task_id text,
    media jsonb NOT NULL DEFAULT '[]'::jsonb,
    meta jsonb NOT NULL DEFAULT '{}'::jsonb,
    dedupe_key text,
    pinned boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_feed_posts_dedupe
    ON public.feed_posts (dedupe_key)
    WHERE dedupe_key IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_feed_posts_created
    ON public.feed_posts (created_at DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_feed_posts_task
    ON public.feed_posts (task_id, created_at DESC)
    WHERE task_id IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_feed_posts_pinned
    ON public.feed_posts (pinned, created_at DESC)
    WHERE pinned = true AND deleted_at IS NULL;

CREATE TABLE IF NOT EXISTS public.feed_reactions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id uuid NOT NULL REFERENCES public.feed_posts (id) ON DELETE CASCADE,
    admin_id text NOT NULL,
    type text NOT NULL
        CHECK (type IN ('like', 'love', 'wow', 'ok')),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (post_id, admin_id)
);

CREATE INDEX IF NOT EXISTS idx_feed_reactions_post
    ON public.feed_reactions (post_id);

CREATE TABLE IF NOT EXISTS public.feed_comments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id uuid NOT NULL REFERENCES public.feed_posts (id) ON DELETE CASCADE,
    author_admin_id text NOT NULL,
    author_name text NOT NULL DEFAULT '',
    body text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_feed_comments_post
    ON public.feed_comments (post_id, created_at ASC)
    WHERE deleted_at IS NULL;

ALTER TABLE public.feed_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feed_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feed_comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow all on feed_posts" ON public.feed_posts;
CREATE POLICY "Allow all on feed_posts"
    ON public.feed_posts
    FOR ALL
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "Allow all on feed_reactions" ON public.feed_reactions;
CREATE POLICY "Allow all on feed_reactions"
    ON public.feed_reactions
    FOR ALL
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "Allow all on feed_comments" ON public.feed_comments;
CREATE POLICY "Allow all on feed_comments"
    ON public.feed_comments
    FOR ALL
    USING (true)
    WITH CHECK (true);

-- Realtime so the iOS feed updates live
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        BEGIN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.feed_posts;
        EXCEPTION WHEN duplicate_object THEN NULL;
        END;
        BEGIN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.feed_reactions;
        EXCEPTION WHEN duplicate_object THEN NULL;
        END;
        BEGIN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.feed_comments;
        EXCEPTION WHEN duplicate_object THEN NULL;
        END;
    ELSE
        RAISE NOTICE 'publication supabase_realtime not found; enable Realtime in the dashboard.';
    END IF;
END $$;

-- Daily system posts: 07:30 and 13:00 Asia/Bangkok (= 00:30 / 06:00 UTC)
DO $$
DECLARE
    base_url text;
    feed_url text;
    invoker_secret text;
    tmp text;
BEGIN
    BEGIN
        CREATE EXTENSION IF NOT EXISTS pg_cron;
        CREATE EXTENSION IF NOT EXISTS pg_net;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'feed-daily-posts cron: could not ensure pg_cron/pg_net (%).', SQLERRM;
        RETURN;
    END;

    BEGIN
        SELECT decrypted_secret INTO base_url
        FROM vault.decrypted_secrets WHERE name = 'daily_vehicle_usage_function_url';
        SELECT decrypted_secret INTO invoker_secret
        FROM vault.decrypted_secrets WHERE name = 'daily_vehicle_usage_invoker_secret';
    EXCEPTION WHEN OTHERS THEN
        base_url := NULL;
        invoker_secret := NULL;
    END;

    IF invoker_secret IS NULL THEN
        BEGIN
            SELECT decrypted_secret INTO tmp
            FROM vault.decrypted_secrets WHERE name = 'daily_attendance_invoker_secret';
            IF tmp IS NOT NULL THEN invoker_secret := tmp; END IF;
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;
    END IF;

    IF base_url IS NOT NULL THEN
        feed_url := regexp_replace(base_url, '/notify-daily-vehicle-usage/?$', '/feed-daily-posts');
    END IF;

    BEGIN
        SELECT decrypted_secret INTO tmp
        FROM vault.decrypted_secrets WHERE name = 'feed_daily_posts_function_url';
        IF tmp IS NOT NULL THEN feed_url := tmp; END IF;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    IF feed_url IS NULL OR invoker_secret IS NULL THEN
        RAISE NOTICE 'feed-daily-posts cron: missing function URL or invoker secret in vault — schedule skipped.';
        RETURN;
    END IF;

    PERFORM cron.unschedule(jobid)
    FROM cron.job WHERE jobname = 'feed-daily-posts';

    PERFORM cron.schedule(
        'feed-daily-posts',
        '30 0,6 * * *',
        format(
            $cron$ SELECT net.http_post(
                url := %L,
                headers := jsonb_build_object(
                    'Content-Type','application/json',
                    'x-cm-notify-advance-secret', %L
                ),
                body := '{}'::jsonb
            ) $cron$,
            feed_url,
            invoker_secret
        )
    );

    RAISE NOTICE 'Scheduled feed-daily-posts at 07:30 and 13:00 Asia/Bangkok.';
END $$;
