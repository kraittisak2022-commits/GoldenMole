-- Daily AI market insights for Gold (Thai 96.5% + XAU/USD) and Oil (Thai fuel + Brent/WTI).
-- The Edge Function `market-insights` upserts one row per run; the app reads the latest row.
BEGIN;

CREATE TABLE IF NOT EXISTS market_insights (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    generated_at timestamptz NOT NULL DEFAULT now(),
    as_of_date date NOT NULL DEFAULT (now() AT TIME ZONE 'Asia/Bangkok')::date,
    -- ok = all sources fresh, partial = some estimated, failed = AI/data unavailable
    status text NOT NULL DEFAULT 'ok',
    payload jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS market_insights_generated_at_idx
    ON market_insights (generated_at DESC);

ALTER TABLE market_insights ENABLE ROW LEVEL SECURITY;

-- Read for app clients; writes happen through the Edge Function (service role bypasses RLS).
DROP POLICY IF EXISTS "market_insights read" ON market_insights;
CREATE POLICY "market_insights read"
    ON market_insights
    FOR SELECT
    TO anon, authenticated
    USING (true);

COMMIT;

-- Optional daily schedule via pg_cron + pg_net. Never fails the migration:
-- schedules only when the function URL + invoker secret are present in Supabase Vault.
-- To enable later, store secrets then re-run this block:
--   select vault.create_secret('https://<project-ref>.functions.supabase.co/market-insights',
--                              'market_insights_function_url');
--   select vault.create_secret('<MARKET_INSIGHTS_INVOKER_SECRET>', 'market_insights_invoker_secret');
DO $$
DECLARE
    fn_url text;
    invoker_secret text;
BEGIN
    BEGIN
        CREATE EXTENSION IF NOT EXISTS pg_cron;
        CREATE EXTENSION IF NOT EXISTS pg_net;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'market-insights: could not ensure pg_cron/pg_net (%). Enable them in the Supabase dashboard.', SQLERRM;
        RETURN;
    END;

    BEGIN
        SELECT decrypted_secret INTO fn_url
        FROM vault.decrypted_secrets WHERE name = 'market_insights_function_url';
        SELECT decrypted_secret INTO invoker_secret
        FROM vault.decrypted_secrets WHERE name = 'market_insights_invoker_secret';
    EXCEPTION WHEN OTHERS THEN
        fn_url := NULL;
        invoker_secret := NULL;
    END;

    IF fn_url IS NULL OR invoker_secret IS NULL THEN
        RAISE NOTICE 'market-insights cron not scheduled: add vault secrets market_insights_function_url and market_insights_invoker_secret, then re-run the scheduling block.';
        RETURN;
    END IF;

    -- Remove any prior schedule with the same name, then (re)create it. 02:00 Asia/Bangkok = 19:00 UTC.
    PERFORM cron.unschedule('market-insights-daily')
    WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'market-insights-daily');

    PERFORM cron.schedule(
        'market-insights-daily',
        '0 19 * * *',
        format(
            $cron$ SELECT net.http_post(
                url := %L,
                headers := jsonb_build_object('Content-Type','application/json','x-cm-market-secret', %L),
                body := '{}'::jsonb
            ) $cron$,
            fn_url,
            invoker_secret
        )
    );
    RAISE NOTICE 'market-insights daily cron scheduled.';
END $$;
