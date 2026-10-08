-- SuperAdmin edit/delete for the stone-sand order app.
-- Statement totals (and their payment rows) must follow their orders, so every
-- order edit/delete goes through these functions instead of raw table writes.

CREATE OR REPLACE FUNCTION public.ss_refresh_statement(p_statement_id text)
RETURNS void
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_count INTEGER;
  v_total NUMERIC;
BEGIN
  SELECT count(*), coalesce(sum(o.total), 0) INTO v_count, v_total
  FROM ss_statement_orders so JOIN ss_orders o ON o.id = so.order_id
  WHERE so.statement_id = p_statement_id;

  IF v_count = 0 THEN
    DELETE FROM ss_statements WHERE id = p_statement_id;
    RETURN;
  END IF;

  UPDATE ss_statements SET total = v_total WHERE id = p_statement_id;
  UPDATE ss_payments SET amount = v_total WHERE statement_id = p_statement_id;
END $function$;

CREATE OR REPLACE FUNCTION public.ss_update_order(p_order_id text, p_order jsonb, p_items jsonb, p_by text)
RETURNS ss_orders
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
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
    INSERT INTO ss_order_items (id, order_id, product_id, name, unit, unit_price, quantity, amount, sort_order)
    VALUES (
      'itm-' || replace(gen_random_uuid()::text, '-', ''),
      p_order_id,
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

  UPDATE ss_payments SET
    amount = v_row.total,
    method = CASE WHEN v_row.payment_method IN ('cash', 'transfer', 'cod') THEN v_row.payment_method ELSE method END
  WHERE order_id = p_order_id;

  SELECT statement_id INTO v_stmt FROM ss_statement_orders WHERE order_id = p_order_id;
  IF v_stmt IS NOT NULL THEN PERFORM ss_refresh_statement(v_stmt); END IF;

  RETURN v_row;
END $function$;

CREATE OR REPLACE FUNCTION public.ss_delete_order(p_order_id text)
RETURNS void
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE v_stmt TEXT;
BEGIN
  SELECT statement_id INTO v_stmt FROM ss_statement_orders WHERE order_id = p_order_id;
  DELETE FROM ss_statement_orders WHERE order_id = p_order_id;
  -- items and payments cascade
  DELETE FROM ss_orders WHERE id = p_order_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'order not found'; END IF;
  IF v_stmt IS NOT NULL THEN PERFORM ss_refresh_statement(v_stmt); END IF;
END $function$;

-- Deleting a cleared statement puts its orders back to outstanding.
CREATE OR REPLACE FUNCTION public.ss_delete_statement(p_statement_id text, p_by text)
RETURNS void
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE v_row ss_statements;
BEGIN
  SELECT * INTO v_row FROM ss_statements WHERE id = p_statement_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'statement not found'; END IF;

  IF v_row.status = 'cleared' THEN
    UPDATE ss_orders o SET
      payment_status = CASE WHEN o.payment_method = 'credit' THEN 'credit' ELSE 'unpaid' END,
      paid_at = NULL,
      cleared = FALSE,
      cleared_at = NULL,
      status_log = o.status_log || ss_log_entry(p_by, 'uncleared:' || v_row.statement_no)
    FROM ss_statement_orders so
    WHERE so.statement_id = p_statement_id AND so.order_id = o.id;
  END IF;

  -- links and payments cascade
  DELETE FROM ss_statements WHERE id = p_statement_id;
END $function$;
