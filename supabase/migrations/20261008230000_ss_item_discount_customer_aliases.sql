-- Per-product discount (บาทต่อคิว) on order lines, and other names a customer is known by (เสี่ยบาส → ร้านสินทวีวังเหนือ).
-- Line amount stays list price × quantity; the order's discount_amount includes the per-คิว discounts.

ALTER TABLE public.ss_order_items
  ADD COLUMN IF NOT EXISTS discount_per_unit NUMERIC NOT NULL DEFAULT 0 CHECK (discount_per_unit >= 0);

ALTER TABLE public.ss_customers
  ADD COLUMN IF NOT EXISTS aliases TEXT NOT NULL DEFAULT '';

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

CREATE OR REPLACE FUNCTION public.ss_update_order(p_order_id TEXT, p_order JSONB, p_items JSONB, p_by TEXT)
RETURNS public.ss_orders
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_row ss_orders;
  v_item JSONB;
  v_idx INTEGER := 0;
  v_stmt TEXT;
  v_method TEXT := p_order->>'payment_method';
BEGIN
  IF jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 THEN
    RAISE EXCEPTION 'ออเดอร์ต้องมีสินค้าอย่างน้อย 1 รายการ';
  END IF;

  SELECT * INTO v_row FROM ss_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'order not found'; END IF;

  UPDATE ss_orders SET
    order_date = coalesce((p_order->>'order_date')::date, order_date),
    delivery_address = coalesce(p_order->>'delivery_address', delivery_address),
    truck_size = CASE WHEN fulfillment = 'delivery' THEN (p_order->>'truck_size')::integer ELSE truck_size END,
    trips = CASE WHEN fulfillment = 'delivery' THEN coalesce((p_order->>'trips')::integer, trips) ELSE 0 END,
    fee_per_trip = CASE WHEN fulfillment = 'delivery' THEN coalesce((p_order->>'fee_per_trip')::numeric, fee_per_trip) ELSE 0 END,
    remote_surcharge = CASE WHEN fulfillment = 'delivery' THEN coalesce((p_order->>'remote_surcharge')::numeric, remote_surcharge) ELSE 0 END,
    discount_type = coalesce(p_order->>'discount_type', discount_type),
    discount_value = coalesce((p_order->>'discount_value')::numeric, discount_value),
    subtotal = (p_order->>'subtotal')::numeric,
    delivery_total = (p_order->>'delivery_total')::numeric,
    discount_amount = (p_order->>'discount_amount')::numeric,
    total = (p_order->>'total')::numeric,
    payment_method = coalesce(v_method, payment_method),
    payment_status = CASE
      WHEN payment_status = 'paid' THEN 'paid'
      WHEN coalesce(v_method, payment_method) = 'credit' THEN 'credit'
      ELSE 'unpaid'
    END,
    note = coalesce(p_order->>'note', note),
    status_log = status_log || ss_log_entry(p_by, 'edited')
  WHERE id = p_order_id
  RETURNING * INTO v_row;

  DELETE FROM ss_order_items WHERE order_id = p_order_id;
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    INSERT INTO ss_order_items (id, order_id, product_id, name, unit, unit_price, quantity, amount, discount_per_unit, sort_order)
    VALUES (
      'itm-' || replace(gen_random_uuid()::text, '-', ''),
      p_order_id,
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

  UPDATE ss_payments SET
    amount = v_row.total,
    method = CASE WHEN v_row.payment_method IN ('cash', 'transfer', 'cod') THEN v_row.payment_method ELSE method END
  WHERE order_id = p_order_id;

  SELECT statement_id INTO v_stmt FROM ss_statement_orders WHERE order_id = p_order_id;
  IF v_stmt IS NOT NULL THEN PERFORM ss_refresh_statement(v_stmt); END IF;

  RETURN v_row;
END $$;
