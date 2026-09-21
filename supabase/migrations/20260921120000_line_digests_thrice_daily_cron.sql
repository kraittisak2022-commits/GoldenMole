-- Thin LINE digest crons: 3 slots/day Asia/Bangkok (09 / 13 / 17) instead of hourly.
-- Offsets avoid all three Edge functions firing in the same second.
-- Soft cap of 5 sends/day is enforced in Edge (lineDailySendBudget).
DO $$
DECLARE
    v_url text;
    f_url text;
    a_url text;
    invoker_secret text;
    tmp text;
BEGIN
    BEGIN
        CREATE EXTENSION IF NOT EXISTS pg_cron;
        CREATE EXTENSION IF NOT EXISTS pg_net;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'line-digests-thrice: could not ensure pg_cron/pg_net (%).', SQLERRM;
        RETURN;
    END;

    BEGIN
        SELECT decrypted_secret INTO v_url
        FROM vault.decrypted_secrets WHERE name = 'daily_vehicle_usage_function_url';
        SELECT decrypted_secret INTO invoker_secret
        FROM vault.decrypted_secrets WHERE name = 'daily_vehicle_usage_invoker_secret';
    EXCEPTION WHEN OTHERS THEN
        v_url := NULL;
        invoker_secret := NULL;
    END;

    IF v_url IS NOT NULL THEN
        f_url := regexp_replace(v_url, '/notify-daily-vehicle-usage/?$', '/notify-daily-fuel-stock');
        a_url := regexp_replace(v_url, '/notify-daily-vehicle-usage/?$', '/notify-daily-attendance');
    END IF;

    BEGIN
        SELECT decrypted_secret INTO tmp
        FROM vault.decrypted_secrets WHERE name = 'daily_fuel_stock_function_url';
        IF tmp IS NOT NULL THEN f_url := tmp; END IF;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    BEGIN
        SELECT decrypted_secret INTO tmp
        FROM vault.decrypted_secrets WHERE name = 'daily_attendance_function_url';
        IF tmp IS NOT NULL THEN a_url := tmp; END IF;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    IF invoker_secret IS NULL THEN
        BEGIN
            SELECT decrypted_secret INTO tmp
            FROM vault.decrypted_secrets WHERE name = 'daily_fuel_stock_invoker_secret';
            IF tmp IS NOT NULL THEN invoker_secret := tmp; END IF;
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;
    END IF;
    IF invoker_secret IS NULL THEN
        BEGIN
            SELECT decrypted_secret INTO tmp
            FROM vault.decrypted_secrets WHERE name = 'daily_attendance_invoker_secret';
            IF tmp IS NOT NULL THEN invoker_secret := tmp; END IF;
        EXCEPTION WHEN OTHERS THEN
            NULL;
        END;
    END IF;

    IF invoker_secret IS NULL THEN
        RAISE NOTICE 'line-digests-thrice: missing invoker secret in vault.';
        RETURN;
    END IF;

    -- Vehicle 09:00 / 13:00 / 17:00 BKK (= 02 / 06 / 10 UTC)
    IF v_url IS NOT NULL THEN
        PERFORM cron.unschedule(jobid)
        FROM cron.job WHERE jobname = 'daily-vehicle-usage-line';
        PERFORM cron.schedule(
            'daily-vehicle-usage-line',
            '0 2,6,10 * * *',
            format(
                $cron$ SELECT net.http_post(
                    url := %L,
                    headers := jsonb_build_object(
                        'Content-Type','application/json',
                        'x-cm-notify-advance-secret', %L
                    ),
                    body := '{}'::jsonb
                ) $cron$,
                v_url,
                invoker_secret
            )
        );
    END IF;

    -- Fuel 09:05 / 13:05 / 17:05 BKK
    IF f_url IS NOT NULL THEN
        PERFORM cron.unschedule(jobid)
        FROM cron.job WHERE jobname = 'daily-fuel-stock-line';
        PERFORM cron.schedule(
            'daily-fuel-stock-line',
            '5 2,6,10 * * *',
            format(
                $cron$ SELECT net.http_post(
                    url := %L,
                    headers := jsonb_build_object(
                        'Content-Type','application/json',
                        'x-cm-notify-advance-secret', %L
                    ),
                    body := '{}'::jsonb
                ) $cron$,
                f_url,
                invoker_secret
            )
        );
    END IF;

    -- Attendance 09:10 / 13:10 / 17:10 BKK
    IF a_url IS NOT NULL THEN
        PERFORM cron.unschedule(jobid)
        FROM cron.job WHERE jobname = 'daily-attendance-line';
        PERFORM cron.schedule(
            'daily-attendance-line',
            '10 2,6,10 * * *',
            format(
                $cron$ SELECT net.http_post(
                    url := %L,
                    headers := jsonb_build_object(
                        'Content-Type','application/json',
                        'x-cm-notify-advance-secret', %L
                    ),
                    body := '{}'::jsonb
                ) $cron$,
                a_url,
                invoker_secret
            )
        );
    END IF;

    RAISE NOTICE 'LINE digests thinned to 09/13/17 Asia/Bangkok (≤5 msgs/day soft cap in Edge).';
END $$;
