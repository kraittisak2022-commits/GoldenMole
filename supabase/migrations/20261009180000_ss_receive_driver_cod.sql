-- The driver hands over all the COD money now, and his driver fee is settled later with the
-- monthly driver clearing. COD orders become paid (with receipts); driver_payout_id stays null,
-- so the orders remain in "ค่ารถยังไม่จ่าย". Undo per order with ss_mark_order_unpaid.
CREATE OR REPLACE FUNCTION public.ss_receive_driver_cod(
  p_driver_id TEXT, p_order_ids TEXT[], p_note TEXT, p_by TEXT, p_cash_expected NUMERIC
)
RETURNS NUMERIC
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_ids TEXT[];
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

  SELECT coalesce(sum(o.total), 0) INTO v_cash
  FROM ss_orders o
  WHERE o.id = ANY (v_ids) AND o.payment_method = 'cod' AND o.payment_status <> 'paid';
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
  FROM ss_orders o
  WHERE o.id = ANY (v_ids) AND o.payment_method = 'cod' AND o.payment_status <> 'paid';

  UPDATE ss_orders o SET
    payment_status = 'paid',
    paid_at = now(),
    receipt_no = coalesce(o.receipt_no, ss_next_doc_no('RE')),
    cleared = TRUE,
    cleared_at = now(),
    status_log = o.status_log || ss_log_entry(p_by, 'paid:cod')
  WHERE o.id = ANY (v_ids) AND o.payment_method = 'cod' AND o.payment_status <> 'paid';

  RETURN v_cash;
END $$;

GRANT EXECUTE ON FUNCTION public.ss_receive_driver_cod(TEXT, TEXT[], TEXT, TEXT, NUMERIC) TO anon, authenticated;
