-- Stone-sand: limit a login to one order source (ร้านวัสดุก่อสร้าง / ท่าทราย). NULL = sees both.
ALTER TABLE public.admin_users
  ADD COLUMN IF NOT EXISTS order_source TEXT
  CHECK (order_source IS NULL OR order_source IN ('shop', 'pit'));
