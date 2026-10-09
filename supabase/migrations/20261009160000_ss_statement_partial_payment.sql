-- Partial payments on a statement (ใบวางบิล).
-- Each payment is an ss_payments row tied to the statement; the statement stays
-- open until the payments reach its total, then clears exactly as before.

CREATE OR REPLACE FUNCTION ss_statement_paid(p_statement_id TEXT)
RETURNS NUMERIC
LANGUAGE sql
STABLE
SET search_path TO 'public'
AS $$
  SELECT coalesce(sum(amount), 0) FROM ss_payments WHERE statement_id = p_statement_id;
$$;

CREATE OR REPLACE FUNCTION ss_mark_statement_cleared(p_statement_id TEXT, p_method TEXT, p_by TEXT)
RETURNS ss_statements
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE v_row ss_statements;
BEGIN
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
  RETURN v_row;
END $$;

CREATE OR REPLACE FUNCTION ss_pay_statement(
  p_statement_id TEXT,
  p_amount NUMERIC,
  p_method TEXT,
  p_note TEXT,
  p_by TEXT
)
RETURNS ss_statements
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_row ss_statements;
  v_balance NUMERIC;
BEGIN
  IF p_method NOT IN ('cash', 'transfer') THEN
    RAISE EXCEPTION 'invalid payment method %', p_method;
  END IF;
  SELECT * INTO v_row FROM ss_statements WHERE id = p_statement_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'statement not found'; END IF;
  IF v_row.status = 'cleared' THEN RAISE EXCEPTION 'ใบวางบิลนี้เคลียร์แล้ว'; END IF;

  v_balance := v_row.total - ss_statement_paid(p_statement_id);
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'ยอดรับชำระต้องมากกว่า 0';
  END IF;
  IF p_amount > v_balance + 0.004 THEN
    RAISE EXCEPTION 'ยอดรับชำระเกินยอดค้าง (ค้าง % บาท)', round(v_balance, 2);
  END IF;

  INSERT INTO ss_payments (statement_id, amount, method, note, created_by)
  VALUES (p_statement_id, least(p_amount, v_balance), p_method, coalesce(p_note, ''), p_by);

  IF p_amount >= v_balance - 0.004 THEN
    RETURN ss_mark_statement_cleared(p_statement_id, p_method, p_by);
  END IF;
  RETURN v_row;
END $$;

-- Clearing in one step now records only what is still owed.
CREATE OR REPLACE FUNCTION ss_clear_statement(p_statement_id TEXT, p_method TEXT, p_by TEXT)
RETURNS ss_statements
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_row ss_statements;
  v_balance NUMERIC;
BEGIN
  SELECT * INTO v_row FROM ss_statements WHERE id = p_statement_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'statement not found'; END IF;
  IF v_row.status = 'cleared' THEN RETURN v_row; END IF;

  v_balance := v_row.total - ss_statement_paid(p_statement_id);
  IF v_balance > 0.004 THEN
    INSERT INTO ss_payments (statement_id, amount, method, created_by)
    VALUES (p_statement_id, v_balance, p_method, p_by);
  END IF;
  RETURN ss_mark_statement_cleared(p_statement_id, p_method, p_by);
END $$;

-- Undo a partial payment entered by mistake (open statements only).
CREATE OR REPLACE FUNCTION ss_delete_statement_payment(p_payment_id TEXT, p_by TEXT)
RETURNS void
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_statement_id TEXT;
  v_status TEXT;
BEGIN
  SELECT p.statement_id, s.status INTO v_statement_id, v_status
  FROM ss_payments p JOIN ss_statements s ON s.id = p.statement_id
  WHERE p.id = p_payment_id
  FOR UPDATE OF s;
  IF NOT FOUND THEN RAISE EXCEPTION 'payment not found'; END IF;
  IF v_status = 'cleared' THEN
    RAISE EXCEPTION 'ใบวางบิลเคลียร์แล้ว ลบการรับชำระไม่ได้ (ลบใบวางบิลแทน)';
  END IF;
  DELETE FROM ss_payments WHERE id = p_payment_id;
END $$;
