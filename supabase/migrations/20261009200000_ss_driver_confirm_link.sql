-- Driver confirmation link: each order gets a secret token (separate from the bill verify token,
-- which customers see). The driver opens /d/<token> without logging in, sees the job, and confirms
-- delivery plus the COD cash collected. The order becomes delivered; payment stays with the shop
-- (the cash is still settled at เคลียร์ค่ารถ), the driver's report is only recorded.

ALTER TABLE ss_orders
  ADD COLUMN IF NOT EXISTS driver_token TEXT NOT NULL DEFAULT replace(gen_random_uuid()::text, '-', ''),
  ADD COLUMN IF NOT EXISTS driver_cash_reported NUMERIC(12, 2),
  ADD COLUMN IF NOT EXISTS driver_reported_at TIMESTAMPTZ;

CREATE UNIQUE INDEX IF NOT EXISTS ss_orders_driver_token_key ON ss_orders (driver_token);

CREATE OR REPLACE FUNCTION ss_driver_job(p_token TEXT)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'orderNo', o.order_no,
    'orderDate', o.order_date,
    'driver', d.name,
    'customer', o.customer_snapshot->>'name',
    'phone', o.customer_snapshot->>'phone',
    'items', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('name', i.name, 'quantity', i.quantity, 'unit', i.unit) ORDER BY i.sort_order)
      FROM ss_order_items i WHERE i.order_id = o.id
    ), '[]'::jsonb),
    'truckSize', o.truck_size,
    'trips', o.trips,
    'zone', z.name,
    'address', o.delivery_address,
    'lat', o.pin_lat,
    'lng', o.pin_lng,
    'note', o.note,
    'codAmount', CASE
      WHEN o.payment_method = 'cod' AND o.payment_status <> 'paid' AND ss_order_in_statement(o.id) IS NULL THEN o.total
      ELSE 0 END,
    'paid', o.payment_status = 'paid',
    'deliveryStatus', o.delivery_status,
    'deliveredAt', o.delivered_at,
    'cashReported', o.driver_cash_reported,
    'reportedAt', o.driver_reported_at,
    'cancelled', o.cancelled
  )
  FROM ss_orders o
  LEFT JOIN ss_drivers d ON d.id = o.driver_id
  LEFT JOIN ss_zones z ON z.id = o.zone_id
  WHERE o.driver_token = p_token AND o.fulfillment = 'delivery' AND length(p_token) >= 32;
$$;

CREATE OR REPLACE FUNCTION ss_driver_confirm(p_token TEXT, p_cash NUMERIC DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  o ss_orders;
  v_by TEXT;
  v_cod BOOLEAN;
BEGIN
  IF length(coalesce(p_token, '')) < 32 THEN RAISE EXCEPTION 'ไม่พบงานนี้'; END IF;
  SELECT * INTO o FROM ss_orders WHERE driver_token = p_token AND fulfillment = 'delivery' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ไม่พบงานนี้'; END IF;
  IF o.cancelled THEN RAISE EXCEPTION 'ออเดอร์นี้ถูกยกเลิกแล้ว'; END IF;

  v_cod := o.payment_method = 'cod' AND o.payment_status <> 'paid' AND ss_order_in_statement(o.id) IS NULL;
  IF v_cod AND p_cash IS NULL THEN RAISE EXCEPTION 'กรุณาระบุเงินสดที่เก็บจากลูกค้า'; END IF;
  IF p_cash IS NOT NULL AND (p_cash < 0 OR p_cash > 9999999) THEN RAISE EXCEPTION 'จำนวนเงินไม่ถูกต้อง'; END IF;

  SELECT 'คนขับ ' || d.name INTO v_by FROM ss_drivers d WHERE d.id = o.driver_id;
  v_by := coalesce(v_by, 'คนขับ') || ' (ลิงก์)';

  UPDATE ss_orders SET
    delivery_status = 'delivered',
    delivered_at = CASE WHEN o.delivery_status = 'delivered' THEN coalesce(o.delivered_at, now()) ELSE now() END,
    driver_cash_reported = CASE WHEN v_cod THEN round(p_cash, 2) ELSE o.driver_cash_reported END,
    driver_reported_at = now(),
    status_log = status_log
      || CASE WHEN o.delivery_status <> 'delivered' THEN ss_log_entry(v_by, 'delivery:delivered') ELSE '[]'::jsonb END
      || CASE WHEN v_cod THEN ss_log_entry(v_by, 'driver_cash:' || round(p_cash, 2)) ELSE '[]'::jsonb END
  WHERE id = o.id;

  RETURN ss_driver_job(p_token);
END $$;

REVOKE ALL ON FUNCTION ss_driver_job(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION ss_driver_confirm(TEXT, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION ss_driver_job(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION ss_driver_confirm(TEXT, NUMERIC) TO anon, authenticated;
