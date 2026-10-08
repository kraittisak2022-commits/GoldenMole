-- Order source: 'shop' = ร้านวัสดุก่อสร้าง (หน้าร้าน), 'pit' = ท่าทราย (สั่งจากท่าทรายโดยตรง).
-- ท่าทราย orders get their own number series (TS); a monthly statement holds one source only.

ALTER TABLE public.ss_orders
  ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'shop' CHECK (source IN ('shop', 'pit'));
ALTER TABLE public.ss_statements
  ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'shop' CHECK (source IN ('shop', 'pit'));
CREATE INDEX IF NOT EXISTS ss_orders_source_date_idx ON public.ss_orders (source, order_date DESC);

CREATE OR REPLACE FUNCTION public.ss_next_doc_no(p_prefix TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_period TEXT := to_char(now() AT TIME ZONE 'Asia/Bangkok', 'YYMM');
  v_no INTEGER;
BEGIN
  IF p_prefix NOT IN ('DO', 'TS', 'RE', 'BL', 'DP') THEN
    RAISE EXCEPTION 'invalid document prefix %', p_prefix;
  END IF;
  INSERT INTO ss_doc_counters (prefix, period, last_no)
  VALUES (p_prefix, v_period, 1)
  ON CONFLICT (prefix, period) DO UPDATE SET last_no = ss_doc_counters.last_no + 1
  RETURNING last_no INTO v_no;
  RETURN p_prefix || v_period || '-' || lpad(v_no::TEXT, 4, '0');
END $$;

CREATE OR REPLACE FUNCTION public.ss_create_order(p_order JSONB, p_items JSONB, p_by TEXT)
RETURNS public.ss_orders
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_id TEXT := 'ord-' || replace(gen_random_uuid()::text, '-', '');
  v_row ss_orders;
  v_item JSONB;
  v_idx INTEGER := 0;
  v_paid BOOLEAN := coalesce((p_order->>'payment_status') = 'paid', FALSE);
  v_source TEXT := coalesce(nullif(p_order->>'source', ''), 'shop');
BEGIN
  IF jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 THEN
    RAISE EXCEPTION 'order must have at least one item';
  END IF;
  IF v_source NOT IN ('shop', 'pit') THEN
    RAISE EXCEPTION 'invalid order source %', v_source;
  END IF;

  INSERT INTO ss_orders (
    id, order_no, receipt_no, source, customer_id, customer_snapshot, fulfillment, delivery_address,
    pin_lat, pin_lng, zone_id, road_distance_km, truck_size, trips, driver_id, fee_per_trip,
    remote_surcharge, discount_type, discount_value, subtotal, delivery_total, discount_amount,
    total, payment_method, payment_status, paid_at, delivery_status, cleared, cleared_at,
    driver_wage, note, status_log, created_by
  ) VALUES (
    v_id,
    ss_next_doc_no(CASE WHEN v_source = 'pit' THEN 'TS' ELSE 'DO' END),
    CASE WHEN v_paid THEN ss_next_doc_no('RE') END,
    v_source,
    p_order->>'customer_id',
    p_order->'customer_snapshot',
    p_order->>'fulfillment',
    coalesce(p_order->>'delivery_address', ''),
    (p_order->>'pin_lat')::double precision,
    (p_order->>'pin_lng')::double precision,
    nullif(p_order->>'zone_id', ''),
    (p_order->>'road_distance_km')::numeric,
    (p_order->>'truck_size')::integer,
    coalesce((p_order->>'trips')::integer, 0),
    nullif(p_order->>'driver_id', ''),
    coalesce((p_order->>'fee_per_trip')::numeric, 0),
    coalesce((p_order->>'remote_surcharge')::numeric, 0),
    coalesce(p_order->>'discount_type', 'baht'),
    coalesce((p_order->>'discount_value')::numeric, 0),
    coalesce((p_order->>'subtotal')::numeric, 0),
    coalesce((p_order->>'delivery_total')::numeric, 0),
    coalesce((p_order->>'discount_amount')::numeric, 0),
    coalesce((p_order->>'total')::numeric, 0),
    p_order->>'payment_method',
    coalesce(p_order->>'payment_status', 'unpaid'),
    CASE WHEN v_paid THEN now() END,
    p_order->>'delivery_status',
    v_paid,
    CASE WHEN v_paid THEN now() END,
    coalesce((p_order->>'driver_wage')::numeric, 0),
    coalesce(p_order->>'note', ''),
    ss_log_entry(p_by, 'created'),
    p_by
  ) RETURNING * INTO v_row;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    INSERT INTO ss_order_items (id, order_id, product_id, name, unit, unit_price, quantity, amount, sort_order)
    VALUES (
      'itm-' || replace(gen_random_uuid()::text, '-', ''),
      v_id,
      v_item->>'product_id',
      v_item->>'name',
      coalesce(v_item->>'unit', 'คิว'),
      (v_item->>'unit_price')::numeric,
      (v_item->>'quantity')::numeric,
      (v_item->>'amount')::numeric,
      v_idx
    );
    v_idx := v_idx + 1;
  END LOOP;

  IF v_paid THEN
    INSERT INTO ss_payments (order_id, amount, method, created_by)
    VALUES (v_id, v_row.total, CASE WHEN v_row.payment_method IN ('cash', 'transfer', 'cod') THEN v_row.payment_method ELSE 'cash' END, p_by);
  END IF;

  RETURN v_row;
END $$;

DROP FUNCTION IF EXISTS public.ss_create_statement(TEXT, TEXT[], DATE, DATE, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.ss_create_statement(
  p_customer_id TEXT, p_order_ids TEXT[], p_from DATE, p_to DATE, p_note TEXT, p_by TEXT, p_source TEXT
)
RETURNS public.ss_statements
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_row ss_statements;
  v_total NUMERIC;
  v_count INTEGER;
BEGIN
  IF p_source NOT IN ('shop', 'pit') THEN
    RAISE EXCEPTION 'invalid order source %', p_source;
  END IF;
  IF EXISTS (SELECT 1 FROM ss_orders WHERE id = ANY (p_order_ids) AND source <> p_source) THEN
    RAISE EXCEPTION 'ใบวางบิลรวมออเดอร์ร้านวัสดุกับออเดอร์ท่าทรายไม่ได้';
  END IF;

  SELECT count(*), coalesce(sum(total), 0) INTO v_count, v_total
  FROM ss_orders
  WHERE id = ANY (p_order_ids) AND customer_id = p_customer_id AND NOT cleared AND NOT cancelled
    AND id NOT IN (SELECT order_id FROM ss_statement_orders);
  IF v_count = 0 OR v_count <> coalesce(array_length(p_order_ids, 1), 0) THEN
    RAISE EXCEPTION 'บางออเดอร์ถูกเคลียร์หรืออยู่ในใบวางบิลอื่นแล้ว';
  END IF;

  INSERT INTO ss_statements (id, statement_no, source, customer_id, customer_snapshot, period_from, period_to, total, note, created_by)
  SELECT
    'stm-' || replace(gen_random_uuid()::text, '-', ''),
    ss_next_doc_no('BL'),
    p_source,
    c.id,
    jsonb_build_object('name', c.name, 'phone', c.phone, 'address', c.address, 'taxId', c.tax_id),
    p_from, p_to, v_total, coalesce(p_note, ''), p_by
  FROM ss_customers c WHERE c.id = p_customer_id
  RETURNING * INTO v_row;

  INSERT INTO ss_statement_orders (statement_id, order_id)
  SELECT v_row.id, unnest(p_order_ids);
  RETURN v_row;
END $$;

GRANT EXECUTE ON FUNCTION public.ss_create_statement(TEXT, TEXT[], DATE, DATE, TEXT, TEXT, TEXT) TO anon, authenticated;
