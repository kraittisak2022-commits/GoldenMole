-- Daily LINE: fuel stock (main + reserve) at 09:00 Asia/Bangkok (02:00 UTC).
-- Reuses vault secrets from daily vehicle usage when present:
--   daily_vehicle_usage_function_url / daily_vehicle_usage_invoker_secret
-- Also accepts dedicated:
--   daily_fuel_stock_function_url / daily_fuel_stock_invoker_secret
DO $$
DECLARE
    fn_url text;
    invoker_secret text;
BEGIN
    BEGIN
        CREATE EXTENSION IF NOT EXISTS pg_cron;
        CREATE EXTENSION IF NOT EXISTS pg_net;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'daily-fuel-stock: could not ensure pg_cron/pg_net (%).', SQLERRM;
        RETURN;
    END;

    BEGIN
        SELECT decrypted_secret INTO fn_url
        FROM vault.decrypted_secrets WHERE name = 'daily_fuel_stock_function_url';
        IF fn_url IS NULL THEN
            -- derive from vehicle-usage URL host if that secret exists
            SELECT regexp_replace(
                decrypted_secret,
                '/notify-daily-vehicle-usage/?$',
                '/notify-daily-fuel-stock'
            ) INTO fn_url
            FROM vault.decrypted_secrets
            WHERE name = 'daily_vehicle_usage_function_url';
        END IF;

        SELECT decrypted_secret INTO invoker_secret
        FROM vault.decrypted_secrets WHERE name = 'daily_fuel_stock_invoker_secret';
        IF invoker_secret IS NULL THEN
            SELECT decrypted_secret INTO invoker_secret
            FROM vault.decrypted_secrets WHERE name = 'daily_vehicle_usage_invoker_secret';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        fn_url := NULL;
        invoker_secret := NULL;
    END;

    IF fn_url IS NULL OR invoker_secret IS NULL THEN
        RAISE NOTICE 'daily-fuel-stock cron not scheduled: missing vault secrets.';
        RETURN;
    END IF;

    PERFORM cron.unschedule(jobid)
    FROM cron.job WHERE jobname = 'daily-fuel-stock-line';

    PERFORM cron.schedule(
        'daily-fuel-stock-line',
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
    RAISE NOTICE 'daily-fuel-stock LINE cron scheduled (09:00 Asia/Bangkok).';
END $$;
