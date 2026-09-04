-- Daily LINE digest: รถดรัม + แม็คโคร at 09:00 Asia/Bangkok (02:00 UTC).
-- Schedules only when Vault has:
--   daily_vehicle_usage_function_url
--   daily_vehicle_usage_invoker_secret  (same value as NOTIFY_ADVANCE_INVOKER_SECRET)
--
-- Example (SQL editor / once):
--   select vault.create_secret(
--     'https://<project-ref>.supabase.co/functions/v1/notify-daily-vehicle-usage',
--     'daily_vehicle_usage_function_url');
--   select vault.create_secret('<NOTIFY_ADVANCE_INVOKER_SECRET>',
--     'daily_vehicle_usage_invoker_secret');
DO $$
DECLARE
    fn_url text;
    invoker_secret text;
BEGIN
    BEGIN
        CREATE EXTENSION IF NOT EXISTS pg_cron;
        CREATE EXTENSION IF NOT EXISTS pg_net;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'daily-vehicle-usage: could not ensure pg_cron/pg_net (%).', SQLERRM;
        RETURN;
    END;

    BEGIN
        SELECT decrypted_secret INTO fn_url
        FROM vault.decrypted_secrets WHERE name = 'daily_vehicle_usage_function_url';
        SELECT decrypted_secret INTO invoker_secret
        FROM vault.decrypted_secrets WHERE name = 'daily_vehicle_usage_invoker_secret';
    EXCEPTION WHEN OTHERS THEN
        fn_url := NULL;
        invoker_secret := NULL;
    END;

    IF fn_url IS NULL OR invoker_secret IS NULL THEN
        RAISE NOTICE 'daily-vehicle-usage cron not scheduled: add vault secrets then re-run this migration block.';
        RETURN;
    END IF;

    PERFORM cron.unschedule('daily-vehicle-usage-line')
    WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'daily-vehicle-usage-line');

    PERFORM cron.schedule(
        'daily-vehicle-usage-line',
        '0 2 * * *',
        format(
            $cron$ SELECT net.http_post(
                url := %L,
                headers := jsonb_build_object(
                    'Content-Type','application/json',
                    'x-cm-notify-advance-secret', %L
                ),
                body := '{}'::jsonb
            ) $cron$,
            fn_url,
            invoker_secret
        )
    );
    RAISE NOTICE 'daily-vehicle-usage LINE cron scheduled (09:00 Asia/Bangkok).';
END $$;
