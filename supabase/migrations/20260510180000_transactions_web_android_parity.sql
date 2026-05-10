-- Web + Android parity: ensure every column used by Flutter AppTransaction / web Transaction exists.
-- Idempotent (IF NOT EXISTS). Safe to run on projects bootstrapped from sql/supabase_android_ready.sql or older dumps.

ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS work_type_by_employee jsonb;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS event_type text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS event_priority text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS trip_billing_mode text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS income_payment_status text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS sand_work_start text;

COMMENT ON COLUMN public.transactions.trip_billing_mode IS 'DailyLog VehicleTrip: PerTrip | LumpSum';
COMMENT ON COLUMN public.transactions.income_payment_status IS 'Income: Unpaid | Paid';

-- Realtime: add table if publication exists (same pattern as sql/supabase_android_ready.sql)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
  ) THEN
    BEGIN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.transactions;
    EXCEPTION
      WHEN duplicate_object THEN NULL;
      WHEN undefined_table THEN NULL;
    END;
  END IF;
END $$;
