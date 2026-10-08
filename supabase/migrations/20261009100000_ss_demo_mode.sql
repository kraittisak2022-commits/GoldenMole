-- Guided-tour demo data: rows tagged with demo_session are real rows that only the presenting browser
-- sees, get throwaway DEMO- document numbers (the real DO/TS/RE/BL counters never move), and are
-- removed by ss_delete_demo at the end of the tour (or by ss_delete_stale_demo a day later).

ALTER TABLE ss_customers ADD COLUMN IF NOT EXISTS demo_session TEXT;
ALTER TABLE ss_orders ADD COLUMN IF NOT EXISTS demo_session TEXT;
ALTER TABLE ss_statements ADD COLUMN IF NOT EXISTS demo_session TEXT;

CREATE INDEX IF NOT EXISTS ss_customers_demo_idx ON ss_customers (demo_session) WHERE demo_session IS NOT NULL;
CREATE INDEX IF NOT EXISTS ss_orders_demo_idx ON ss_orders (demo_session) WHERE demo_session IS NOT NULL;
CREATE INDEX IF NOT EXISTS ss_statements_demo_idx ON ss_statements (demo_session) WHERE demo_session IS NOT NULL;

CREATE OR REPLACE FUNCTION ss_doc_no(p_prefix TEXT, p_demo BOOLEAN)
RETURNS TEXT
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF p_demo THEN
    RETURN 'DEMO-' || p_prefix || '-' || lpad((floor(random() * 10000))::INTEGER::TEXT, 4, '0');
  END IF;
  RETURN ss_next_doc_no(p_prefix);
END $$;

CREATE OR REPLACE FUNCTION ss_create_order(p_order JSONB, p_items JSONB, p_by TEXT)
RETURNS ss_orders
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
  v_date DATE := coalesce(nullif(p_order->>'order_date', '')::date, (now() AT TIME ZONE 'Asia/Bangkok')::date);
  v_demo TEXT := nullif(p_order->>'demo_session', '');
BEGIN
  IF jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 THEN
    RAISE EXCEPTION 'order must have at least one item';
  END IF;
  IF v_source NOT IN ('shop', 'pit') THEN
    RAISE EXCEPTION 'invalid order source %', v_source;
  END IF;

  INSERT INTO ss_orders (
    id, order_no, receipt_no, order_date, source, customer_id, customer_snapshot, fulfillment, delivery_address,
    pin_lat, pin_lng, zone_id, road_distance_km, truck_size, trips, driver_id, fee_per_trip,
    remote_surcharge, delivery_discount, discount_type, discount_value, subtotal, delivery_total, discount_amount,
    total, payment_method, payment_status, paid_at, delivery_status, cleared, cleared_at,
    driver_wage, note, status_log, created_by, demo_session
  ) VALUES (
    v_id,
    ss_doc_no(CASE WHEN v_source = 'pit' THEN 'TS' ELSE 'DO' END, v_demo IS NOT NULL),
    CASE WHEN v_paid THEN ss_doc_no('RE', v_demo IS NOT NULL) END,
    v_date,
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
    greatest(coalesce((p_order->>'delivery_discount')::numeric, 0), 0),
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
    p_by,
    v_demo
  ) RETURNING * INTO v_row;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    INSERT INTO ss_order_items (id, order_id, product_id, name, unit, unit_price, quantity, amount, discount_per_unit, sort_order)
    VALUES (
      'itm-' || replace(gen_random_uuid()::text, '-', ''),
      v_id,
      v_item->>'product_id',
      v_item->>'name',
      coalesce(v_item->>'unit', 'คิว'),
      (v_item->>'unit_price')::numeric,
      (v_item->>'quantity')::numeric,
      (v_item->>'amount')::numeric,
      greatest(coalesce((v_item->>'discount_per_unit')::numeric, 0), 0),
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

CREATE OR REPLACE FUNCTION ss_mark_order_paid(p_order_id TEXT, p_method TEXT, p_by TEXT)
RETURNS ss_orders
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE v_row ss_orders;
BEGIN
  SELECT * INTO v_row FROM ss_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'order not found'; END IF;
  IF v_row.payment_status = 'paid' THEN RETURN v_row; END IF;

  UPDATE ss_orders SET
    payment_status = 'paid',
    paid_at = now(),
    receipt_no = coalesce(receipt_no, ss_doc_no('RE', demo_session IS NOT NULL)),
    cleared = TRUE,
    cleared_at = now(),
    status_log = status_log || ss_log_entry(p_by, 'paid:' || p_method)
  WHERE id = p_order_id
  RETURNING * INTO v_row;

  INSERT INTO ss_payments (order_id, amount, method, created_by)
  VALUES (p_order_id, v_row.total, p_method, p_by);
  RETURN v_row;
END $$;

CREATE OR REPLACE FUNCTION ss_create_statement(
  p_customer_id TEXT, p_order_ids TEXT[], p_from DATE, p_to DATE, p_note TEXT, p_by TEXT, p_source TEXT
)
RETURNS ss_statements
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_row ss_statements;
  v_total NUMERIC;
  v_count INTEGER;
  v_demo TEXT;
BEGIN
  IF p_source NOT IN ('shop', 'pit') THEN
    RAISE EXCEPTION 'invalid order source %', p_source;
  END IF;
  IF EXISTS (SELECT 1 FROM ss_orders WHERE id = ANY (p_order_ids) AND source <> p_source) THEN
    RAISE EXCEPTION 'ใบวางบิลรวมออเดอร์ร้านวัสดุกับออเดอร์ท่าทรายไม่ได้';
  END IF;
  IF (SELECT count(DISTINCT coalesce(demo_session, '')) FROM ss_orders WHERE id = ANY (p_order_ids)) > 1 THEN
    RAISE EXCEPTION 'ใบวางบิลรวมออเดอร์สาธิตกับออเดอร์จริงไม่ได้';
  END IF;
  SELECT demo_session INTO v_demo FROM ss_orders WHERE id = ANY (p_order_ids) LIMIT 1;

  SELECT count(*), coalesce(sum(total), 0) INTO v_count, v_total
  FROM ss_orders
  WHERE id = ANY (p_order_ids) AND customer_id = p_customer_id AND NOT cleared AND NOT cancelled
    AND id NOT IN (SELECT order_id FROM ss_statement_orders);
  IF v_count = 0 OR v_count <> coalesce(array_length(p_order_ids, 1), 0) THEN
    RAISE EXCEPTION 'บางออเดอร์ถูกเคลียร์หรืออยู่ในใบวางบิลอื่นแล้ว';
  END IF;

  INSERT INTO ss_statements (id, statement_no, source, customer_id, customer_snapshot, period_from, period_to, total, note, created_by, demo_session)
  SELECT
    'stm-' || replace(gen_random_uuid()::text, '-', ''),
    ss_doc_no('BL', v_demo IS NOT NULL),
    p_source,
    c.id,
    jsonb_build_object('name', c.name, 'phone', c.phone, 'address', c.address, 'taxId', c.tax_id),
    p_from, p_to, v_total, coalesce(p_note, ''), p_by, v_demo
  FROM ss_customers c WHERE c.id = p_customer_id
  RETURNING * INTO v_row;

  INSERT INTO ss_statement_orders (statement_id, order_id)
  SELECT v_row.id, unnest(p_order_ids);
  RETURN v_row;
END $$;

CREATE OR REPLACE FUNCTION ss_clear_statement(p_statement_id TEXT, p_method TEXT, p_by TEXT)
RETURNS ss_statements
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE v_row ss_statements;
BEGIN
  SELECT * INTO v_row FROM ss_statements WHERE id = p_statement_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'statement not found'; END IF;
  IF v_row.status = 'cleared' THEN RETURN v_row; END IF;

  UPDATE ss_statements SET status = 'cleared', payment_method = p_method, cleared_at = now()
  WHERE id = p_statement_id RETURNING * INTO v_row;

  UPDATE ss_orders o SET
    payment_status = 'paid',
    paid_at = coalesce(o.paid_at, now()),
    receipt_no = coalesce(o.receipt_no, ss_doc_no('RE', o.demo_session IS NOT NULL)),
    cleared = TRUE,
    cleared_at = now(),
    status_log = o.status_log || ss_log_entry(p_by, 'cleared:' || v_row.statement_no)
  FROM ss_statement_orders so
  WHERE so.statement_id = p_statement_id AND so.order_id = o.id;

  INSERT INTO ss_payments (statement_id, amount, method, created_by)
  VALUES (p_statement_id, v_row.total, p_method, p_by);
  RETURN v_row;
END $$;

CREATE OR REPLACE FUNCTION ss_delete_demo(p_session TEXT)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF coalesce(p_session, '') NOT LIKE 'demo-%' THEN
    RAISE EXCEPTION 'invalid demo session';
  END IF;
  DELETE FROM ss_statements WHERE demo_session = p_session;
  DELETE FROM ss_statement_orders so USING ss_orders o WHERE so.order_id = o.id AND o.demo_session = p_session;
  DELETE FROM ss_orders WHERE demo_session = p_session;
  DELETE FROM ss_customers c
  WHERE c.demo_session = p_session
    AND NOT EXISTS (SELECT 1 FROM ss_orders o WHERE o.customer_id = c.id)
    AND NOT EXISTS (SELECT 1 FROM ss_statements s WHERE s.customer_id = c.id);
END $$;

CREATE OR REPLACE FUNCTION ss_delete_stale_demo()
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE v_session TEXT;
BEGIN
  FOR v_session IN
    SELECT demo_session FROM ss_customers WHERE demo_session IS NOT NULL AND created_at < now() - INTERVAL '1 day'
    UNION
    SELECT demo_session FROM ss_orders WHERE demo_session IS NOT NULL AND created_at < now() - INTERVAL '1 day'
    UNION
    SELECT demo_session FROM ss_statements WHERE demo_session IS NOT NULL AND created_at < now() - INTERVAL '1 day'
  LOOP
    PERFORM ss_delete_demo(v_session);
  END LOOP;
END $$;
