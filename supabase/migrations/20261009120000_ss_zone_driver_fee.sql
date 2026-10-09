-- Per-trip amount paid to the driver for a tambon. fee_min/fee_max stay the customer delivery fee range.
ALTER TABLE public.ss_zones
  ADD COLUMN IF NOT EXISTS driver_fee NUMERIC NOT NULL DEFAULT 0 CHECK (driver_fee >= 0);
