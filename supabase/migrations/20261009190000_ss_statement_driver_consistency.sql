-- Keep เคลียร์บิล (statements) and เคลียร์ค่ารถ (driver clearing) from collecting the same order twice.
-- Whichever claims an order first owns its payment:
--   * an order in a statement is paid only through that statement, so driver clearing does not take
--     its COD money and it cannot be marked paid on its own;
--   * an order already paid (e.g. COD handed over by the driver) is cleared, so it cannot join a statement
--     (ss_create_statement already requires NOT cleared).

CREATE OR REPLACE FUNCTION public.ss_order_in_statement(p_order_id TEXT)
RETURNS TEXT
LANGUAGE sql STABLE
SET search_path = public
AS $$
  SELECT s.statement_no FROM ss_statement_orders so JOIN ss_statements s ON s.id = so.statement_id
  WHERE so.order_id = p_order_id LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.ss_mark_order_paid(p_order_id TEXT, p_method TEXT, p_by TEXT)
RETURNS public.ss_orders
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_row ss_orders;
  v_statement TEXT;
BEGIN
  SELECT * INTO v_row FROM ss_orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'order not found'; END IF;
  IF v_row.payment_status = 'paid' THEN RETURN v_row; END IF;
  v_statement := ss_order_in_statement(p_order_id);
  IF v_statement IS NOT NULL THEN
    RAISE EXCEPTION 'ออเดอร์นี้อยู่ในใบวางบิล % ให้รับชำระที่หน้าเคลียร์บิล', v_statement;
  END IF;

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

-- COD money the driver still holds: unpaid COD orders that are not billed on a statement.
CREATE OR REPLACE FUNCTION public.ss_driver_cod_orders(p_ids TEXT[])
RETURNS SETOF public.ss_orders
LANGUAGE sql STABLE
SET search_path = public
AS $$
  SELECT o.* FROM ss_orders o
  WHERE o.id = ANY (p_ids) AND o.payment_method = 'cod' AND o.payment_status <> 'paid'
    AND NOT EXISTS (SELECT 1 FROM ss_statement_orders so WHERE so.order_id = o.id)
$$;

CREATE OR REPLACE FUNCTION public.ss_create_driver_payout(
  p_driver_id TEXT, p_lines JSONB, p_method TEXT, p_note TEXT, p_by TEXT, p_cash_expected NUMERIC
)
RETURNS public.ss_driver_payouts
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_row ss_driver_payouts;
  v_lines INTEGER := jsonb_array_length(coalesce(p_lines, '[]'::jsonb));
  v_ids TEXT[];
  v_cod TEXT[];
  v_count INTEGER;
  v_total NUMERIC;
  v_cash NUMERIC;
BEGIN
  IF p_method NOT IN ('cash', 'transfer') THEN
    RAISE EXCEPTION 'invalid payment method %', p_method;
  END IF;
  IF v_lines = 0 THEN
    RAISE EXCEPTION 'เลือกออเดอร์อย่างน้อย 1 รายการ';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_lines) l WHERE coalesce((l->>'amount')::numeric, -1) < 0) THEN
    RAISE EXCEPTION 'ยอดค่ารถต้องไม่ติดลบ';
  END IF;

  SELECT array_agg(DISTINCT l->>'order_id') INTO v_ids FROM jsonb_array_elements(p_lines) l;
  PERFORM 1 FROM ss_orders WHERE id = ANY (v_ids) FOR UPDATE;

  SELECT count(*) INTO v_count
  FROM ss_orders o
  WHERE o.id = ANY (v_ids)
    AND o.driver_id = p_driver_id
    AND o.fulfillment = 'delivery'
    AND NOT o.cancelled
    AND o.driver_payout_id IS NULL;
  IF v_count <> v_lines THEN
    RAISE EXCEPTION 'บางออเดอร์จ่ายค่ารถไปแล้ว หรือไม่ใช่ของคนขับคนนี้ ลองโหลดหน้าใหม่';
  END IF;

  SELECT array_agg(id), coalesce(sum(total), 0) INTO v_cod, v_cash FROM ss_driver_cod_orders(v_ids);
  IF v_cash <> coalesce(p_cash_expected, 0) THEN
    RAISE EXCEPTION 'ยอดเงินเก็บปลายทางเปลี่ยนไป ลองโหลดหน้าใหม่';
  END IF;

  SELECT coalesce(sum((l->>'amount')::numeric), 0) INTO v_total FROM jsonb_array_elements(p_lines) l;

  INSERT INTO ss_driver_payouts (id, payout_no, driver_id, driver_name, total, method, note, created_by)
  SELECT
    'dpo-' || replace(gen_random_uuid()::text, '-', ''),
    ss_next_doc_no('DP'),
    d.id, d.name, v_total, p_method, coalesce(p_note, ''), p_by
  FROM ss_drivers d WHERE d.id = p_driver_id
  RETURNING * INTO v_row;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'driver not found'; END IF;

  UPDATE ss_orders o SET
    driver_payout_id = v_row.id,
    driver_wage = (l->>'amount')::numeric,
    status_log = o.status_log || ss_log_entry(p_by, 'wage_paid:' || v_row.payout_no)
  FROM jsonb_array_elements(p_lines) l
  WHERE o.id = l->>'order_id';

  INSERT INTO ss_payments (order_id, amount, method, note, created_by, driver_payout_id)
  SELECT o.id, o.total, 'cod', 'รับจากคนขับ ' || v_row.payout_no, p_by, v_row.id
  FROM ss_orders o WHERE o.id = ANY (coalesce(v_cod, '{}'));

  UPDATE ss_orders o SET
    payment_status = 'paid',
    paid_at = now(),
    receipt_no = coalesce(o.receipt_no, ss_next_doc_no('RE')),
    cleared = TRUE,
    cleared_at = now(),
    status_log = o.status_log || ss_log_entry(p_by, 'paid:cod')
  WHERE o.id = ANY (coalesce(v_cod, '{}'));

  RETURN v_row;
END $$;

CREATE OR REPLACE FUNCTION public.ss_receive_driver_cod(
  p_driver_id TEXT, p_order_ids TEXT[], p_note TEXT, p_by TEXT, p_cash_expected NUMERIC
)
RETURNS NUMERIC
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_ids TEXT[];
  v_cod TEXT[];
  v_driver TEXT;
  v_cash NUMERIC;
BEGIN
  SELECT array_agg(DISTINCT x) INTO v_ids FROM unnest(coalesce(p_order_ids, '{}')) x;
  IF v_ids IS NULL THEN
    RAISE EXCEPTION 'เลือกออเดอร์อย่างน้อย 1 รายการ';
  END IF;
  SELECT name INTO v_driver FROM ss_drivers WHERE id = p_driver_id;
  IF v_driver IS NULL THEN RAISE EXCEPTION 'driver not found'; END IF;

  PERFORM 1 FROM ss_orders WHERE id = ANY (v_ids) FOR UPDATE;
  IF (
    SELECT count(*) FROM ss_orders o
    WHERE o.id = ANY (v_ids) AND o.driver_id = p_driver_id AND o.fulfillment = 'delivery'
      AND NOT o.cancelled AND o.driver_payout_id IS NULL
  ) <> cardinality(v_ids) THEN
    RAISE EXCEPTION 'บางออเดอร์เคลียร์ค่ารถไปแล้ว หรือไม่ใช่ของคนขับคนนี้ ลองโหลดหน้าใหม่';
  END IF;

  SELECT array_agg(id), coalesce(sum(total), 0) INTO v_cod, v_cash FROM ss_driver_cod_orders(v_ids);
  IF v_cash <= 0 THEN
    RAISE EXCEPTION 'ไม่มีเงินเก็บปลายทางที่ต้องรับจากคนขับ';
  END IF;
  IF v_cash <> coalesce(p_cash_expected, 0) THEN
    RAISE EXCEPTION 'ยอดเงินเก็บปลายทางเปลี่ยนไป ลองโหลดหน้าใหม่';
  END IF;

  INSERT INTO ss_payments (order_id, amount, method, note, created_by)
  SELECT o.id, o.total, 'cod',
    trim('รับเงินปลายทางจากคนขับ ' || v_driver || ' (ค่ารถรอเคลียร์รอบเดือน) ' || coalesce(p_note, '')),
    p_by
  FROM ss_orders o WHERE o.id = ANY (v_cod);

  UPDATE ss_orders o SET
    payment_status = 'paid',
    paid_at = now(),
    receipt_no = coalesce(o.receipt_no, ss_next_doc_no('RE')),
    cleared = TRUE,
    cleared_at = now(),
    status_log = o.status_log || ss_log_entry(p_by, 'paid:cod')
  WHERE o.id = ANY (v_cod);

  RETURN v_cash;
END $$;

GRANT EXECUTE ON FUNCTION public.ss_order_in_statement(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ss_driver_cod_orders(TEXT[]) TO anon, authenticated;
