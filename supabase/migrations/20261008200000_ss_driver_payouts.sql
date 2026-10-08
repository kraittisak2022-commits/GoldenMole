-- Driver pay ("เคลียร์ค่ารถ"): pay a driver for a batch of delivery orders in one go.
-- The amount paid per order is written back to ss_orders.driver_wage.

CREATE TABLE IF NOT EXISTS public.ss_driver_payouts (
  id TEXT PRIMARY KEY,
  payout_no TEXT NOT NULL UNIQUE,
  driver_id TEXT NOT NULL REFERENCES public.ss_drivers(id),
  driver_name TEXT NOT NULL DEFAULT '',
  total NUMERIC NOT NULL DEFAULT 0 CHECK (total >= 0),
  method TEXT NOT NULL CHECK (method IN ('cash', 'transfer')),
  note TEXT NOT NULL DEFAULT '',
  created_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ss_driver_payouts_driver_idx ON public.ss_driver_payouts (driver_id, created_at DESC);

ALTER TABLE public.ss_orders
  ADD COLUMN IF NOT EXISTS driver_payout_id TEXT REFERENCES public.ss_driver_payouts(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS ss_orders_driver_payout_idx ON public.ss_orders (driver_payout_id);

ALTER TABLE public.ss_driver_payouts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Allow all on ss_driver_payouts" ON public.ss_driver_payouts;
CREATE POLICY "Allow all on ss_driver_payouts" ON public.ss_driver_payouts FOR ALL TO public USING (true) WITH CHECK (true);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.ss_driver_payouts TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.ss_next_doc_no(p_prefix TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_period TEXT := to_char(now() AT TIME ZONE 'Asia/Bangkok', 'YYMM');
  v_no INTEGER;
BEGIN
  IF p_prefix NOT IN ('DO', 'RE', 'BL', 'DP') THEN
    RAISE EXCEPTION 'invalid document prefix %', p_prefix;
  END IF;
  INSERT INTO ss_doc_counters (prefix, period, last_no)
  VALUES (p_prefix, v_period, 1)
  ON CONFLICT (prefix, period) DO UPDATE SET last_no = ss_doc_counters.last_no + 1
  RETURNING last_no INTO v_no;
  RETURN p_prefix || v_period || '-' || lpad(v_no::TEXT, 4, '0');
END $$;

-- p_lines: [{ "order_id": "...", "amount": 500 }, ...]
CREATE OR REPLACE FUNCTION public.ss_create_driver_payout(
  p_driver_id TEXT, p_lines JSONB, p_method TEXT, p_note TEXT, p_by TEXT
)
RETURNS public.ss_driver_payouts
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_row ss_driver_payouts;
  v_lines INTEGER := jsonb_array_length(coalesce(p_lines, '[]'::jsonb));
  v_count INTEGER;
  v_total NUMERIC;
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

  PERFORM 1 FROM ss_orders
  WHERE id IN (SELECT l->>'order_id' FROM jsonb_array_elements(p_lines) l)
  FOR UPDATE;

  SELECT count(*) INTO v_count
  FROM ss_orders o
  WHERE o.id IN (SELECT DISTINCT l->>'order_id' FROM jsonb_array_elements(p_lines) l)
    AND o.driver_id = p_driver_id
    AND o.fulfillment = 'delivery'
    AND NOT o.cancelled
    AND o.driver_payout_id IS NULL;
  IF v_count <> v_lines THEN
    RAISE EXCEPTION 'บางออเดอร์จ่ายค่ารถไปแล้ว หรือไม่ใช่ของคนขับคนนี้ ลองโหลดหน้าใหม่';
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

  RETURN v_row;
END $$;

-- Undo a payout: its orders go back to "ค่ารถยังไม่จ่าย" (driver_payout_id is cleared by ON DELETE SET NULL).
CREATE OR REPLACE FUNCTION public.ss_delete_driver_payout(p_payout_id TEXT, p_by TEXT)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE v_row ss_driver_payouts;
BEGIN
  SELECT * INTO v_row FROM ss_driver_payouts WHERE id = p_payout_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'payout not found'; END IF;

  UPDATE ss_orders SET status_log = status_log || ss_log_entry(p_by, 'wage_unpaid:' || v_row.payout_no)
  WHERE driver_payout_id = p_payout_id;

  DELETE FROM ss_driver_payouts WHERE id = p_payout_id;
END $$;

CREATE OR REPLACE FUNCTION public.ss_refresh_driver_payout(p_payout_id TEXT)
RETURNS void
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
  v_total NUMERIC;
BEGIN
  SELECT count(*), coalesce(sum(driver_wage), 0) INTO v_count, v_total
  FROM ss_orders WHERE driver_payout_id = p_payout_id;
  IF v_count = 0 THEN
    DELETE FROM ss_driver_payouts WHERE id = p_payout_id;
  ELSE
    UPDATE ss_driver_payouts SET total = v_total WHERE id = p_payout_id;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.ss_delete_order(p_order_id text)
RETURNS void
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_stmt TEXT;
  v_payout TEXT;
BEGIN
  SELECT statement_id INTO v_stmt FROM ss_statement_orders WHERE order_id = p_order_id;
  SELECT driver_payout_id INTO v_payout FROM ss_orders WHERE id = p_order_id;
  DELETE FROM ss_statement_orders WHERE order_id = p_order_id;
  -- items and payments cascade
  DELETE FROM ss_orders WHERE id = p_order_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'order not found'; END IF;
  IF v_stmt IS NOT NULL THEN PERFORM ss_refresh_statement(v_stmt); END IF;
  IF v_payout IS NOT NULL THEN PERFORM ss_refresh_driver_payout(v_payout); END IF;
END $function$;

GRANT EXECUTE ON FUNCTION
  public.ss_create_driver_payout(TEXT, JSONB, TEXT, TEXT, TEXT),
  public.ss_delete_driver_payout(TEXT, TEXT),
  public.ss_refresh_driver_payout(TEXT)
TO anon, authenticated;
