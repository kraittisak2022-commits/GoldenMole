-- Pickup (มารับเอง) has its own price per คิว; delivery keeps price_per_unit.
ALTER TABLE public.ss_products
  ADD COLUMN IF NOT EXISTS pickup_price_per_unit NUMERIC CHECK (pickup_price_per_unit >= 0);

COMMENT ON COLUMN public.ss_products.pickup_price_per_unit IS
  'Price per unit when the customer picks up (มารับเอง); null = same as price_per_unit.';

UPDATE public.ss_products SET pickup_price_per_unit = 200 WHERE id = 'fill-sand';
UPDATE public.ss_products SET pickup_price_per_unit = 300 WHERE id = 'mortar-sand';
UPDATE public.ss_products SET pickup_price_per_unit = 300 WHERE id = 'small-stone';
UPDATE public.ss_products SET pickup_price_per_unit = 220 WHERE id = 'big-stone';
