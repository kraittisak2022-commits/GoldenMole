-- Android-ready Supabase patch (idempotent)
-- Run in Supabase SQL Editor on your target project.

BEGIN;

-- 1) Core tables (safe create for existing projects)
CREATE TABLE IF NOT EXISTS public.transactions (
  id text PRIMARY KEY,
  date text NOT NULL,
  type text NOT NULL,
  category text NOT NULL,
  sub_category text,
  description text NOT NULL DEFAULT '',
  amount numeric NOT NULL DEFAULT 0,
  employee_id text,
  employee_ids jsonb DEFAULT '[]'::jsonb,
  driver_id text,
  driver_wage numeric,
  vehicle_wage numeric,
  vehicle_id text,
  quantity numeric,
  unit text,
  unit_price numeric,
  project_id text,
  mileage numeric,
  image_url text,
  location text,
  labor_status text,
  work_type text,
  work_type_by_employee jsonb,
  work_assignments jsonb,
  custom_work_categories jsonb DEFAULT '[]'::jsonb,
  ot_amount numeric,
  advance_amount numeric,
  special_amount numeric,
  ot_hours numeric,
  ot_description text,
  leave_reason text,
  leave_days numeric,
  note text,
  work_details text,
  fuel_type text,
  fuel_movement text,
  payroll_period jsonb,
  payroll_snapshot jsonb,
  machine_id text,
  machine_hours numeric,
  machine_work_type text,
  sand_morning numeric,
  sand_afternoon numeric,
  sand_machine_type text,
  sand_operators jsonb DEFAULT '[]'::jsonb,
  sand_transport numeric,
  drums_obtained numeric,
  drums_washed_at_home numeric,
  sand_work_start text,
  sand_morning_start text,
  sand_afternoon_start text,
  sand_evening_end text,
  trip_count numeric,
  trip_morning numeric,
  trip_afternoon numeric,
  cubic_per_trip numeric,
  total_cubic numeric,
  per_car_trips numeric,
  per_car_cubic numeric,
  trip_billing_mode text,
  income_payment_status text,
  event_type text,
  event_priority text,
  event_time text,
  sand_batch_id text,
  sand_home_batch_usages jsonb,
  payroll_lock_action text,
  unlocked_by_admin_id text,
  unlocked_by_admin_name text,
  unlocked_at text,
  created_at timestamptz DEFAULT now()
);

-- 2) Add Android-required columns for old databases
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS sub_category text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS note text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS employee_ids jsonb DEFAULT '[]'::jsonb;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS work_assignments jsonb;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS custom_work_categories jsonb DEFAULT '[]'::jsonb;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS fuel_movement text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS sand_operators jsonb DEFAULT '[]'::jsonb;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS drums_obtained numeric;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS drums_washed_at_home numeric;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS sand_morning_start text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS sand_afternoon_start text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS sand_evening_end text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS trip_count numeric;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS trip_morning numeric;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS trip_afternoon numeric;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS cubic_per_trip numeric;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS total_cubic numeric;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS per_car_trips numeric;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS per_car_cubic numeric;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS trip_billing_mode text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS income_payment_status text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS event_time text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS work_type_by_employee jsonb;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS sand_work_start text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS event_type text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS event_priority text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS sand_batch_id text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS sand_home_batch_usages jsonb;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS payroll_lock_action text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS unlocked_by_admin_id text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS unlocked_by_admin_name text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS unlocked_at text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now();

-- 3) Helpful defaults / not-null guards for app-side JSON parsing
UPDATE public.transactions
SET employee_ids = '[]'::jsonb
WHERE employee_ids IS NULL;

UPDATE public.transactions
SET sand_operators = '[]'::jsonb
WHERE sand_operators IS NULL;

UPDATE public.transactions
SET custom_work_categories = '[]'::jsonb
WHERE custom_work_categories IS NULL;

-- 4) Indexes for Android + Daily Wizard workloads
CREATE INDEX IF NOT EXISTS idx_transactions_date ON public.transactions(date);
CREATE INDEX IF NOT EXISTS idx_transactions_created_at ON public.transactions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_transactions_category ON public.transactions(category);
CREATE INDEX IF NOT EXISTS idx_transactions_sub_category ON public.transactions(sub_category);
CREATE INDEX IF NOT EXISTS idx_transactions_date_category ON public.transactions(date, category);
CREATE INDEX IF NOT EXISTS idx_transactions_date_sub_category ON public.transactions(date, sub_category);
CREATE INDEX IF NOT EXISTS idx_transactions_vehicle_date ON public.transactions(vehicle_id, date);
CREATE INDEX IF NOT EXISTS idx_transactions_driver_date ON public.transactions(driver_id, date);
CREATE INDEX IF NOT EXISTS idx_transactions_fuel_movement_date ON public.transactions(fuel_movement, date);
CREATE INDEX IF NOT EXISTS idx_transactions_labor_status_date ON public.transactions(labor_status, date);

-- 5) Realtime (optional but useful for web dashboard updates)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_publication
    WHERE pubname = 'supabase_realtime'
  ) THEN
    BEGIN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.transactions;
    EXCEPTION
      WHEN duplicate_object THEN NULL;
      WHEN undefined_table THEN NULL;
    END;
  END IF;
END $$;

-- 6) RLS baseline (same access model used by current app)
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow all on transactions" ON public.transactions;
CREATE POLICY "Allow all on transactions"
ON public.transactions
FOR ALL
USING (true)
WITH CHECK (true);

COMMIT;

-- Verification query (run after script):
-- SELECT count(*) AS total_tx, max(created_at) AS latest_tx FROM public.transactions;
