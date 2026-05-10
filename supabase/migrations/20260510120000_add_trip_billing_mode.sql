-- VehicleTrip: PerTrip (default) vs LumpSum (เหมา รวมคิว)
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS trip_billing_mode text;

COMMENT ON COLUMN public.transactions.trip_billing_mode IS 'DailyLog VehicleTrip: PerTrip | LumpSum';
