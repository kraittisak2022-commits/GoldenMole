-- Stone-sand: allow choosing the order date when creating an order (defaults to today, Bangkok).

CREATE OR REPLACE FUNCTION public.ss_create_order(p_order jsonb, p_items jsonb, p_by text)
 RETURNS ss_orders
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_id TEXT := 'ord-' || replace(gen_random_uuid()::text, '-', '');
  v_row ss_orders;
  v_item JSONB;
  v_idx INTEGER := 0;
  v_paid BOOLEAN := coalesce((p_order->>'payment_status') = 'paid', FALSE);
  v_source TEXT := coalesce(nullif(p_order->>'source', ''), 'shop');
  v_date DATE := coalesce(nullif(p_order->>'order_date', '')::date, (now() AT TIME ZONE 'Asia/Bangkok')::date);
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
    remote_surcharge, discount_type, discount_value, subtotal, delivery_total, discount_amount,
    total, payment_method, payment_status, paid_at, delivery_status, cleared, cleared_at,
    driver_wage, note, status_log, created_by
  ) VALUES (
    v_id,
    ss_next_doc_no(CASE WHEN v_source = 'pit' THEN 'TS' ELSE 'DO' END),
    CASE WHEN v_paid THEN ss_next_doc_no('RE') END,
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
END $function$;
