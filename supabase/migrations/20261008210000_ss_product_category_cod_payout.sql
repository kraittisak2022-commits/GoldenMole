-- 1) Product category (หิน / ทราย) for the new-order product picker.
ALTER TABLE public.ss_products
  ADD COLUMN IF NOT EXISTS category TEXT NOT NULL DEFAULT 'stone' CHECK (category IN ('stone', 'sand'));
UPDATE public.ss_products SET category = 'sand' WHERE name LIKE '%ทราย%';

-- 2) Cash-on-delivery money the driver collected is settled in the driver payout:
--    the payout records a 'cod' payment per order, so deleting the payout undoes it.
ALTER TABLE public.ss_payments
  ADD COLUMN IF NOT EXISTS driver_payout_id TEXT REFERENCES public.ss_driver_payouts(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS ss_payments_driver_payout_idx ON public.ss_payments (driver_payout_id);

DROP FUNCTION IF EXISTS public.ss_create_driver_payout(TEXT, JSONB, TEXT, TEXT, TEXT);

-- p_lines: [{ "order_id": "...", "amount": 500 }, ...]
-- p_cash_expected: COD money the screen showed; must still match what is outstanding.
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

  SELECT coalesce(sum(o.total), 0) INTO v_cash
  FROM ss_orders o
  WHERE o.id = ANY (v_ids) AND o.payment_method = 'cod' AND o.payment_status <> 'paid';
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
  FROM ss_orders o
  WHERE o.id = ANY (v_ids) AND o.payment_method = 'cod' AND o.payment_status <> 'paid';

  UPDATE ss_orders o SET
    payment_status = 'paid',
    paid_at = now(),
    receipt_no = coalesce(o.receipt_no, ss_next_doc_no('RE')),
    cleared = TRUE,
    cleared_at = now(),
    status_log = o.status_log || ss_log_entry(p_by, 'paid:cod')
  WHERE o.id IN (SELECT order_id FROM ss_payments WHERE driver_payout_id = v_row.id);

  RETURN v_row;
END $$;

-- Undo a payout: orders go back to "ค่ารถยังไม่จ่าย", and COD money taken through it goes back to unpaid.
CREATE OR REPLACE FUNCTION public.ss_delete_driver_payout(p_payout_id TEXT, p_by TEXT)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE v_row ss_driver_payouts;
BEGIN
  SELECT * INTO v_row FROM ss_driver_payouts WHERE id = p_payout_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'payout not found'; END IF;

  UPDATE ss_orders SET
    payment_status = CASE WHEN payment_method = 'credit' THEN 'credit' ELSE 'unpaid' END,
    paid_at = NULL,
    cleared = FALSE,
    cleared_at = NULL,
    status_log = status_log || ss_log_entry(p_by, 'unpaid')
  WHERE id IN (SELECT order_id FROM ss_payments WHERE driver_payout_id = p_payout_id);

  UPDATE ss_orders SET status_log = status_log || ss_log_entry(p_by, 'wage_unpaid:' || v_row.payout_no)
  WHERE driver_payout_id = p_payout_id;

  -- payments cascade, orders.driver_payout_id is set null
  DELETE FROM ss_driver_payouts WHERE id = p_payout_id;
END $$;

CREATE OR REPLACE FUNCTION public.ss_mark_order_unpaid(p_order_id TEXT, p_by TEXT)
RETURNS public.ss_orders
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE v_row ss_orders;
BEGIN
  IF EXISTS (
    SELECT 1 FROM ss_statement_orders so JOIN ss_statements s ON s.id = so.statement_id
    WHERE so.order_id = p_order_id AND s.status = 'cleared'
  ) THEN
    RAISE EXCEPTION 'ออเดอร์นี้อยู่ในใบวางบิลที่เคลียร์แล้ว ยกเลิกไม่ได้';
  END IF;
  IF EXISTS (SELECT 1 FROM ss_payments WHERE order_id = p_order_id AND driver_payout_id IS NOT NULL) THEN
    RAISE EXCEPTION 'รับเงินปลายทางผ่านเคลียร์ค่ารถแล้ว ต้องลบรายการจ่ายค่ารถก่อน';
  END IF;

  DELETE FROM ss_payments WHERE order_id = p_order_id;
  UPDATE ss_orders SET
    payment_status = CASE WHEN payment_method = 'credit' THEN 'credit' ELSE 'unpaid' END,
    paid_at = NULL,
    cleared = FALSE,
    cleared_at = NULL,
    status_log = status_log || ss_log_entry(p_by, 'unpaid')
  WHERE id = p_order_id
  RETURNING * INTO v_row;
  RETURN v_row;
END $$;

GRANT EXECUTE ON FUNCTION public.ss_create_driver_payout(TEXT, JSONB, TEXT, TEXT, TEXT, NUMERIC) TO anon, authenticated;
