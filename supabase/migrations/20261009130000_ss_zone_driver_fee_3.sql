-- Driver fee per trip for 3-cubic-metre trucks. driver_fee is the 5-cubic-metre (normal) truck rate.
ALTER TABLE public.ss_zones
  ADD COLUMN IF NOT EXISTS driver_fee_3 NUMERIC NOT NULL DEFAULT 0 CHECK (driver_fee_3 >= 0);
