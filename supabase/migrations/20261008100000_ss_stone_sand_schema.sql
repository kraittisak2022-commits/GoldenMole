-- Stone & sand order system for หจก. พีรสิทธิ์ วัสดุก่อสร้าง (apps/stone-sand), prefix ss_

CREATE TABLE IF NOT EXISTS public.ss_settings (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ss_products (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  unit TEXT NOT NULL DEFAULT 'คิว',
  price_per_unit NUMERIC NOT NULL CHECK (price_per_unit >= 0),
  sort_order INTEGER NOT NULL DEFAULT 0,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ss_zones (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  fee_min NUMERIC NOT NULL CHECK (fee_min >= 0),
  fee_max NUMERIC NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  CHECK (fee_max >= fee_min)
);

CREATE TABLE IF NOT EXISTS public.ss_drivers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  village TEXT NOT NULL DEFAULT '',
  route_group TEXT NOT NULL CHECK (route_group IN ('north', 'south', 'thungpao')),
  truck_size INTEGER NOT NULL CHECK (truck_size IN (3, 5)),
  truck_count INTEGER NOT NULL DEFAULT 1 CHECK (truck_count >= 1),
  contacts JSONB NOT NULL DEFAULT '[]'::jsonb,
  contact_note TEXT NOT NULL DEFAULT '',
  wage_per_trip NUMERIC NOT NULL DEFAULT 0 CHECK (wage_per_trip >= 0),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ss_customers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT NOT NULL DEFAULT '',
  address TEXT NOT NULL DEFAULT '',
  zone_id TEXT REFERENCES public.ss_zones(id),
  tax_id TEXT NOT NULL DEFAULT '',
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION,
  is_credit BOOLEAN NOT NULL DEFAULT FALSE,
  note TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ss_customers_phone_idx ON public.ss_customers (phone);
CREATE INDEX IF NOT EXISTS ss_customers_name_idx ON public.ss_customers (name);

CREATE TABLE IF NOT EXISTS public.ss_orders (
  id TEXT PRIMARY KEY,
  order_no TEXT NOT NULL UNIQUE,
  receipt_no TEXT UNIQUE,
  order_date DATE NOT NULL DEFAULT (now() AT TIME ZONE 'Asia/Bangkok')::date,
  customer_id TEXT NOT NULL REFERENCES public.ss_customers(id),
  customer_snapshot JSONB NOT NULL,
  fulfillment TEXT NOT NULL CHECK (fulfillment IN ('pickup', 'delivery')),
  delivery_address TEXT NOT NULL DEFAULT '',
  pin_lat DOUBLE PRECISION,
  pin_lng DOUBLE PRECISION,
  zone_id TEXT REFERENCES public.ss_zones(id),
  road_distance_km NUMERIC,
  truck_size INTEGER CHECK (truck_size IS NULL OR truck_size IN (3, 5)),
  trips INTEGER NOT NULL DEFAULT 0 CHECK (trips >= 0),
  driver_id TEXT REFERENCES public.ss_drivers(id),
  fee_per_trip NUMERIC NOT NULL DEFAULT 0 CHECK (fee_per_trip >= 0),
  remote_surcharge NUMERIC NOT NULL DEFAULT 0 CHECK (remote_surcharge >= 0),
  discount_type TEXT NOT NULL DEFAULT 'baht' CHECK (discount_type IN ('baht', 'percent')),
  discount_value NUMERIC NOT NULL DEFAULT 0 CHECK (discount_value >= 0),
  subtotal NUMERIC NOT NULL DEFAULT 0,
  delivery_total NUMERIC NOT NULL DEFAULT 0,
  discount_amount NUMERIC NOT NULL DEFAULT 0,
  total NUMERIC NOT NULL DEFAULT 0 CHECK (total >= 0),
  payment_method TEXT NOT NULL CHECK (payment_method IN ('cash', 'transfer', 'cod', 'credit')),
  payment_status TEXT NOT NULL DEFAULT 'unpaid' CHECK (payment_status IN ('unpaid', 'paid', 'credit')),
  paid_at TIMESTAMPTZ,
  delivery_status TEXT NOT NULL CHECK (delivery_status IN ('pickup', 'waiting', 'dispatched', 'delivered')),
  delivered_at TIMESTAMPTZ,
  cleared BOOLEAN NOT NULL DEFAULT FALSE,
  cleared_at TIMESTAMPTZ,
  driver_wage NUMERIC NOT NULL DEFAULT 0 CHECK (driver_wage >= 0),
  note TEXT NOT NULL DEFAULT '',
  cancelled BOOLEAN NOT NULL DEFAULT FALSE,
  verify_token TEXT NOT NULL UNIQUE DEFAULT replace(gen_random_uuid()::text, '-', ''),
  status_log JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ss_orders_customer_idx ON public.ss_orders (customer_id, order_date);
CREATE INDEX IF NOT EXISTS ss_orders_date_idx ON public.ss_orders (order_date DESC);

CREATE TABLE IF NOT EXISTS public.ss_order_items (
  id TEXT PRIMARY KEY,
  order_id TEXT NOT NULL REFERENCES public.ss_orders(id) ON DELETE CASCADE,
  product_id TEXT,
  name TEXT NOT NULL,
  unit TEXT NOT NULL DEFAULT 'คิว',
  unit_price NUMERIC NOT NULL CHECK (unit_price >= 0),
  quantity NUMERIC NOT NULL CHECK (quantity > 0),
  amount NUMERIC NOT NULL CHECK (amount >= 0),
  sort_order INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS ss_order_items_order_idx ON public.ss_order_items (order_id);

CREATE TABLE IF NOT EXISTS public.ss_statements (
  id TEXT PRIMARY KEY,
  statement_no TEXT NOT NULL UNIQUE,
  customer_id TEXT NOT NULL REFERENCES public.ss_customers(id),
  customer_snapshot JSONB NOT NULL,
  period_from DATE NOT NULL,
  period_to DATE NOT NULL,
  total NUMERIC NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'cleared')),
  payment_method TEXT CHECK (payment_method IS NULL OR payment_method IN ('cash', 'transfer')),
  cleared_at TIMESTAMPTZ,
  verify_token TEXT NOT NULL UNIQUE DEFAULT replace(gen_random_uuid()::text, '-', ''),
  note TEXT NOT NULL DEFAULT '',
  created_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ss_statement_orders (
  statement_id TEXT NOT NULL REFERENCES public.ss_statements(id) ON DELETE CASCADE,
  order_id TEXT NOT NULL UNIQUE REFERENCES public.ss_orders(id),
  PRIMARY KEY (statement_id, order_id)
);

CREATE TABLE IF NOT EXISTS public.ss_payments (
  id TEXT PRIMARY KEY DEFAULT ('pay-' || replace(gen_random_uuid()::text, '-', '')),
  order_id TEXT REFERENCES public.ss_orders(id) ON DELETE CASCADE,
  statement_id TEXT REFERENCES public.ss_statements(id) ON DELETE CASCADE,
  amount NUMERIC NOT NULL CHECK (amount >= 0),
  method TEXT NOT NULL CHECK (method IN ('cash', 'transfer', 'cod')),
  paid_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  note TEXT NOT NULL DEFAULT '',
  created_by TEXT,
  CHECK (order_id IS NOT NULL OR statement_id IS NOT NULL)
);

CREATE TABLE IF NOT EXISTS public.ss_doc_counters (
  prefix TEXT NOT NULL,
  period TEXT NOT NULL,
  last_no INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (prefix, period)
);

-- RLS: same permissive pattern as fa_* tables (app login is admin_users, not Supabase Auth)
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'ss_settings', 'ss_products', 'ss_zones', 'ss_drivers', 'ss_customers', 'ss_orders',
    'ss_order_items', 'ss_statements', 'ss_statement_orders', 'ss_payments', 'ss_doc_counters'
  ] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS "Allow all on %s" ON public.%I', t, t);
    EXECUTE format('CREATE POLICY "Allow all on %s" ON public.%I FOR ALL TO public USING (true) WITH CHECK (true)', t, t);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON public.%I TO anon, authenticated', t);
  END LOOP;
END $$;

-- Document numbers: DO / RE / BL + YYMM (Asia/Bangkok) + running 4 digits
CREATE OR REPLACE FUNCTION public.ss_next_doc_no(p_prefix TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_period TEXT := to_char(now() AT TIME ZONE 'Asia/Bangkok', 'YYMM');
  v_no INTEGER;
BEGIN
  IF p_prefix NOT IN ('DO', 'RE', 'BL') THEN
    RAISE EXCEPTION 'invalid document prefix %', p_prefix;
  END IF;
  INSERT INTO ss_doc_counters (prefix, period, last_no)
  VALUES (p_prefix, v_period, 1)
  ON CONFLICT (prefix, period) DO UPDATE SET last_no = ss_doc_counters.last_no + 1
  RETURNING last_no INTO v_no;
  RETURN p_prefix || v_period || '-' || lpad(v_no::TEXT, 4, '0');
END $$;

CREATE OR REPLACE FUNCTION public.ss_log_entry(p_by TEXT, p_event TEXT)
RETURNS JSONB
LANGUAGE sql
STABLE
AS $$
  SELECT jsonb_build_array(jsonb_build_object('at', now(), 'by', coalesce(p_by, ''), 'event', p_event));
$$;

-- Create order + items in one transaction. Paid-now orders get a receipt number immediately.
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
BEGIN
  IF jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 THEN
    RAISE EXCEPTION 'order must have at least one item';
  END IF;

  INSERT INTO ss_orders (
    id, order_no, receipt_no, customer_id, customer_snapshot, fulfillment, delivery_address,
    pin_lat, pin_lng, zone_id, road_distance_km, truck_size, trips, driver_id, fee_per_trip,
    remote_surcharge, discount_type, discount_value, subtotal, delivery_total, discount_amount,
    total, payment_method, payment_status, paid_at, delivery_status, cleared, cleared_at,
    driver_wage, note, status_log, created_by
  ) VALUES (
    v_id,
    ss_next_doc_no('DO'),
    CASE WHEN v_paid THEN ss_next_doc_no('RE') END,
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

CREATE OR REPLACE FUNCTION public.ss_mark_order_paid(p_order_id TEXT, p_method TEXT, p_by TEXT)
RETURNS public.ss_orders
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
    receipt_no = coalesce(receipt_no, ss_next_doc_no('RE')),
    cleared = TRUE,
    cleared_at = now(),
    status_log = status_log || ss_log_entry(p_by, 'paid:' || p_method)
  WHERE id = p_order_id
  RETURNING * INTO v_row;

  INSERT INTO ss_payments (order_id, amount, method, created_by)
  VALUES (p_order_id, v_row.total, p_method, p_by);
  RETURN v_row;
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

CREATE OR REPLACE FUNCTION public.ss_set_delivery_status(p_order_id TEXT, p_status TEXT, p_by TEXT)
RETURNS public.ss_orders
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE v_row ss_orders;
BEGIN
  UPDATE ss_orders SET
    delivery_status = p_status,
    delivered_at = CASE WHEN p_status = 'delivered' THEN now() ELSE NULL END,
    status_log = status_log || ss_log_entry(p_by, 'delivery:' || p_status)
  WHERE id = p_order_id
  RETURNING * INTO v_row;
  IF NOT FOUND THEN RAISE EXCEPTION 'order not found'; END IF;
  RETURN v_row;
END $$;

CREATE OR REPLACE FUNCTION public.ss_create_statement(
  p_customer_id TEXT, p_order_ids TEXT[], p_from DATE, p_to DATE, p_note TEXT, p_by TEXT
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
  SELECT count(*), coalesce(sum(total), 0) INTO v_count, v_total
  FROM ss_orders
  WHERE id = ANY (p_order_ids) AND customer_id = p_customer_id AND NOT cleared AND NOT cancelled
    AND id NOT IN (SELECT order_id FROM ss_statement_orders);
  IF v_count = 0 OR v_count <> coalesce(array_length(p_order_ids, 1), 0) THEN
    RAISE EXCEPTION 'บางออเดอร์ถูกเคลียร์หรืออยู่ในใบวางบิลอื่นแล้ว';
  END IF;

  INSERT INTO ss_statements (id, statement_no, customer_id, customer_snapshot, period_from, period_to, total, note, created_by)
  SELECT
    'stm-' || replace(gen_random_uuid()::text, '-', ''),
    ss_next_doc_no('BL'),
    c.id,
    jsonb_build_object('name', c.name, 'phone', c.phone, 'address', c.address, 'taxId', c.tax_id),
    p_from, p_to, v_total, coalesce(p_note, ''), p_by
  FROM ss_customers c WHERE c.id = p_customer_id
  RETURNING * INTO v_row;

  INSERT INTO ss_statement_orders (statement_id, order_id)
  SELECT v_row.id, unnest(p_order_ids);
  RETURN v_row;
END $$;

CREATE OR REPLACE FUNCTION public.ss_clear_statement(p_statement_id TEXT, p_method TEXT, p_by TEXT)
RETURNS public.ss_statements
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
    receipt_no = coalesce(o.receipt_no, ss_next_doc_no('RE')),
    cleared = TRUE,
    cleared_at = now(),
    status_log = o.status_log || ss_log_entry(p_by, 'cleared:' || v_row.statement_no)
  FROM ss_statement_orders so
  WHERE so.statement_id = p_statement_id AND so.order_id = o.id;

  INSERT INTO ss_payments (statement_id, amount, method, created_by)
  VALUES (p_statement_id, v_row.total, p_method, p_by);
  RETURN v_row;
END $$;

-- Public bill verification (QR). Returns only what the verify page needs; customer name is masked.
CREATE OR REPLACE FUNCTION public.ss_verify_document(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v JSONB;
BEGIN
  SELECT jsonb_build_object(
    'kind', 'order',
    'docNo', o.order_no,
    'receiptNo', o.receipt_no,
    'date', o.order_date,
    'customer', left(o.customer_snapshot->>'name', 3) || '***',
    'total', o.total,
    'paymentStatus', o.payment_status,
    'cleared', o.cleared,
    'cancelled', o.cancelled
  ) INTO v FROM ss_orders o WHERE o.verify_token = p_token;
  IF v IS NOT NULL THEN RETURN v; END IF;

  SELECT jsonb_build_object(
    'kind', 'statement',
    'docNo', s.statement_no,
    'date', s.created_at::date,
    'customer', left(s.customer_snapshot->>'name', 3) || '***',
    'total', s.total,
    'paymentStatus', CASE WHEN s.status = 'cleared' THEN 'paid' ELSE 'credit' END,
    'cleared', s.status = 'cleared',
    'cancelled', FALSE
  ) INTO v FROM ss_statements s WHERE s.verify_token = p_token;
  RETURN v;
END $$;

GRANT EXECUTE ON FUNCTION
  public.ss_next_doc_no(TEXT),
  public.ss_create_order(JSONB, JSONB, TEXT),
  public.ss_mark_order_paid(TEXT, TEXT, TEXT),
  public.ss_mark_order_unpaid(TEXT, TEXT),
  public.ss_set_delivery_status(TEXT, TEXT, TEXT),
  public.ss_create_statement(TEXT, TEXT[], DATE, DATE, TEXT, TEXT),
  public.ss_clear_statement(TEXT, TEXT, TEXT),
  public.ss_verify_document(TEXT)
TO anon, authenticated;

-- Seed data
INSERT INTO public.ss_settings (key, value) VALUES
  ('company', jsonb_build_object(
    'nameTh', 'ห้างหุ้นส่วนจำกัด พีรสิทธิ์ วัสดุก่อสร้าง',
    'nameEn', 'PIRASIT CONSTRUCTION MATERIALS LIMITED PARTNERSHIP',
    'address', '132 หมู่ที่ 2 ตำบลวังแก้ว อำเภอวังเหนือ จังหวัดลำปาง 52140',
    'taxId', '0523566002017',
    'phone', '065-8124686'
  )),
  ('delivery', jsonb_build_object('nearKm', 3, 'maxKm', 10, 'roundTo', 50)),
  ('payment', jsonb_build_object('promptPayId', '', 'bankText', ''))
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.ss_products (id, name, price_per_unit, sort_order) VALUES
  ('small-stone', 'หินเล็กคละ เบอร์ 1-3', 400, 1),
  ('big-stone', 'หินคละใหญ่ เบอร์ 4-6', 300, 2),
  ('fill-sand', 'ทรายถม (ทรายขี้เป็ด)', 220, 3),
  ('mortar-sand', 'ทรายก่อ/เท', 300, 4)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.ss_zones (id, name, fee_min, fee_max, sort_order) VALUES
  ('thung-hua', 'ทุ่งฮั้ว', 300, 400, 1),
  ('wang-kaeo', 'วังแก้ว', 500, 700, 2),
  ('wang-nuea', 'วังเหนือ', 800, 1000, 3),
  ('wang-sai', 'วังซ้าย', 800, 1000, 4),
  ('wang-tai', 'วังใต้', 1000, 1200, 5),
  ('wang-sai-kham', 'วังทรายคำ', 1000, 1200, 6),
  ('wang-thong', 'วังทอง', 1200, 1500, 7),
  ('rong-kho', 'ร่องเคาะ', 1200, 1500, 8)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.ss_drivers (id, name, village, route_group, truck_size, truck_count, contacts, contact_note, sort_order) VALUES
  ('drv-ko', 'อ้ายโก', 'บ้านป่าแหน่ง', 'north', 5, 1,
    '[{"label":"อ้ายโก","phone":"093-310-8437"},{"label":"อ้ายถุ่ย","phone":"093-739-3923"}]', '', 1),
  ('drv-ot', 'โอ็ต', 'บ้านทัพป่าเส้า', 'north', 5, 1,
    '[{"label":"เจ๊แอ๊ว","phone":"090-989-9799"}]', 'ติดต่อผ่านเจ๊แอ๊ว', 2),
  ('drv-thewa', 'เทวา', 'บ้านฮ่องไฮ', 'north', 5, 1,
    '[{"label":"เทวา","phone":"083-764-7365"}]', '', 3),
  ('drv-luangpoon', 'หลวงพูน', 'บ้านฮ่าง', 'north', 3, 1,
    '[{"label":"หลวงพูน","phone":"088-503-7912"},{"label":"หลวงพูน (2)","phone":"081-017-2402"}]', '', 4),
  ('drv-lungchuay', 'ลุงช่วย', 'บ้านฮ่าง', 'north', 3, 1, '[]', 'ไม่มีเบอร์โทร', 5),
  ('drv-owen', 'โอเว่น', 'บ้านทุ่งฝูง', 'south', 5, 1,
    '[{"label":"โอเว่น","phone":"095-443-1728"}]', '', 6),
  ('drv-somsak', 'สมศักดิ์', 'บ้านปง', 'south', 5, 2,
    '[{"label":"สมศักดิ์","phone":"095-592-5409"}]', 'มีรถ 2 คัน', 7),
  ('drv-tui', 'พ่อเลี้ยงตุ๋ย', 'บ้านปง', 'south', 5, 1, '[]', 'ติดต่อ พ่อเลี้ยงตุ๋ย', 8),
  ('drv-chart', 'อาวชาติ', 'บ้านปง', 'south', 5, 1, '[]', 'ติดต่อ อาวชาติ', 9),
  ('drv-injan', 'อินจัน', 'บ้านใหม่', 'thungpao', 3, 1,
    '[{"label":"อินจัน","phone":"097-961-5264"}]', '', 10),
  ('drv-sam', 'แซม', 'บ้านทุ่งฮั้วบ้านบน', 'thungpao', 3, 1,
    '[{"label":"แซม","phone":"095-735-1988"}]', '', 11),
  ('drv-bell', 'อ้ายเบล', 'บ้านแม่ทรายเงิน', 'thungpao', 5, 1,
    '[{"label":"อ้ายเบล","phone":"082-870-5205"},{"label":"แฟนอ้ายเบล","phone":"080-161-0813"}]', '', 12)
ON CONFLICT (id) DO NOTHING;
