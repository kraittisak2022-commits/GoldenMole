-- ประวัติการเปลี่ยนแปลง transactions — สำรองก่อนแก้/ลบ และกู้คืนได้
--
-- ดูรายการที่ถูกลบล่าสุด:
--   SELECT * FROM public.transactions_deleted_recent LIMIT 50;
--
-- กู้คืนแถวที่เผลอลบ (ใช้ประวัติล่าสุดของ tx_id):
--   SELECT public.restore_transaction('transaction_id_here');
--
-- กู้คืนจาก audit_id เฉพาะ:
--   SELECT public.restore_transaction('transaction_id_here', 12345);
--
-- ล้างประวัติเก่า (เก็บ SNAPSHOT ไว้):
--   DELETE FROM public.transactions_audit
--   WHERE changed_at < now() - interval '2 years' AND op <> 'SNAPSHOT';

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. ตารางเก็บประวัติ
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.transactions_audit (
    audit_id        bigserial PRIMARY KEY,
    tx_id           text NOT NULL,
    op              text NOT NULL CHECK (op IN ('INSERT', 'UPDATE', 'DELETE', 'SNAPSHOT')),
    changed_at      timestamptz NOT NULL DEFAULT now(),
    actor           text,
    changed_columns text[],
    old_row         jsonb,
    new_row         jsonb
);

CREATE INDEX IF NOT EXISTS transactions_audit_tx_idx
    ON public.transactions_audit (tx_id, changed_at DESC);

CREATE INDEX IF NOT EXISTS transactions_audit_changed_at_idx
    ON public.transactions_audit (changed_at DESC);

CREATE INDEX IF NOT EXISTS transactions_audit_deleted_idx
    ON public.transactions_audit (changed_at DESC)
    WHERE op = 'DELETE';

COMMENT ON TABLE public.transactions_audit IS
    'Audit log for transactions — stores row snapshots on INSERT/UPDATE/DELETE for recovery.';

-- ---------------------------------------------------------------------------
-- 2. อ่าน actor จาก session (ถ้ามี)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.transactions_audit_actor()
RETURNS text
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(
        NULLIF(trim(current_setting('app.actor', true)), ''),
        NULLIF(trim(auth.jwt() ->> 'email'), ''),
        NULLIF(trim(auth.jwt() ->> 'sub'), '')
    );
$$;

-- ---------------------------------------------------------------------------
-- 3. Trigger บันทึกการเปลี่ยนแปลง
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.log_transactions_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_actor text;
    v_old jsonb;
    v_new jsonb;
    v_changed text[];
    k text;
BEGIN
    v_actor := public.transactions_audit_actor();

    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.transactions_audit (tx_id, op, actor, new_row)
        VALUES (NEW.id, 'INSERT', v_actor, to_jsonb(NEW));
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' THEN
        INSERT INTO public.transactions_audit (tx_id, op, actor, old_row)
        VALUES (OLD.id, 'DELETE', v_actor, to_jsonb(OLD));
        RETURN OLD;
    END IF;

    -- UPDATE
    v_old := to_jsonb(OLD) - 'updated_at';
    v_new := to_jsonb(NEW) - 'updated_at';
    IF v_old = v_new THEN
        RETURN NEW;
    END IF;

    v_changed := ARRAY[]::text[];
    FOR k IN SELECT jsonb_object_keys(v_new)
    LOOP
        IF (v_old -> k) IS DISTINCT FROM (v_new -> k) THEN
            v_changed := array_append(v_changed, k);
        END IF;
    END LOOP;

    INSERT INTO public.transactions_audit (
        tx_id, op, actor, changed_columns, old_row, new_row
    )
    VALUES (NEW.id, 'UPDATE', v_actor, v_changed, to_jsonb(OLD), to_jsonb(NEW));

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_transactions_audit ON public.transactions;
CREATE TRIGGER trg_transactions_audit
    AFTER INSERT OR UPDATE OR DELETE ON public.transactions
    FOR EACH ROW
    EXECUTE FUNCTION public.log_transactions_change();

-- ---------------------------------------------------------------------------
-- 4. สแนปช็อตข้อมูลปัจจุบัน (จุดตั้งต้น — รันครั้งเดียว)
-- ---------------------------------------------------------------------------
INSERT INTO public.transactions_audit (tx_id, op, new_row)
SELECT t.id, 'SNAPSHOT', to_jsonb(t)
FROM public.transactions t
WHERE NOT EXISTS (
    SELECT 1 FROM public.transactions_audit a WHERE a.op = 'SNAPSHOT'
);

-- ---------------------------------------------------------------------------
-- 5. ฟังก์ชันกู้คืน
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.restore_transaction(
    p_tx_id text,
    p_audit_id bigint DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_audit public.transactions_audit%ROWTYPE;
    v_payload jsonb;
    v_exists boolean;
BEGIN
    IF p_audit_id IS NOT NULL THEN
        SELECT * INTO v_audit
        FROM public.transactions_audit
        WHERE audit_id = p_audit_id AND tx_id = p_tx_id;
    ELSE
        SELECT * INTO v_audit
        FROM public.transactions_audit
        WHERE tx_id = p_tx_id
        ORDER BY changed_at DESC, audit_id DESC
        LIMIT 1;
    END IF;

    IF NOT FOUND THEN
        RETURN format('ไม่พบประวัติสำหรับ tx_id=%s', p_tx_id);
    END IF;

    SELECT EXISTS (SELECT 1 FROM public.transactions WHERE id = p_tx_id)
    INTO v_exists;

    IF v_audit.op IN ('DELETE', 'SNAPSHOT') THEN
        v_payload := COALESCE(v_audit.old_row, v_audit.new_row);
        IF v_payload IS NULL THEN
            RETURN format('audit_id=%s ไม่มีข้อมูลแถวให้กู้คืน', v_audit.audit_id);
        END IF;
        IF v_exists THEN
            RETURN format(
                'แถว %s ยังมีอยู่ — ใช้ audit UPDATE แทน หรือลบก่อนแล้วค่อยกู้คืน',
                p_tx_id
            );
        END IF;
        INSERT INTO public.transactions
        SELECT * FROM jsonb_populate_record(NULL::public.transactions, v_payload);
        RETURN format(
            'กู้คืน INSERT จาก %s audit_id=%s สำเร็จ',
            v_audit.op, v_audit.audit_id
        );
    END IF;

    IF v_audit.op = 'UPDATE' THEN
        v_payload := v_audit.old_row;
        IF v_payload IS NULL THEN
            RETURN format('audit_id=%s ไม่มี old_row', v_audit.audit_id);
        END IF;
        IF NOT v_exists THEN
            INSERT INTO public.transactions
            SELECT * FROM jsonb_populate_record(NULL::public.transactions, v_payload);
            RETURN format(
                'กู้คืน INSERT จาก UPDATE audit_id=%s สำเร็จ (แถวหายไปแล้ว)',
                v_audit.audit_id
            );
        END IF;
        UPDATE public.transactions t
        SET
            date = (v_payload ->> 'date'),
            type = (v_payload ->> 'type'),
            category = (v_payload ->> 'category'),
            sub_category = (v_payload ->> 'sub_category'),
            description = (v_payload ->> 'description'),
            amount = NULLIF(v_payload ->> 'amount', '')::numeric,
            employee_id = (v_payload ->> 'employee_id'),
            employee_ids = v_payload -> 'employee_ids',
            driver_id = (v_payload ->> 'driver_id'),
            driver_wage = NULLIF(v_payload ->> 'driver_wage', '')::numeric,
            vehicle_wage = NULLIF(v_payload ->> 'vehicle_wage', '')::numeric,
            vehicle_id = (v_payload ->> 'vehicle_id'),
            quantity = NULLIF(v_payload ->> 'quantity', '')::numeric,
            unit = (v_payload ->> 'unit'),
            unit_price = NULLIF(v_payload ->> 'unit_price', '')::numeric,
            project_id = (v_payload ->> 'project_id'),
            mileage = NULLIF(v_payload ->> 'mileage', '')::numeric,
            image_url = (v_payload ->> 'image_url'),
            location = (v_payload ->> 'location'),
            labor_status = (v_payload ->> 'labor_status'),
            work_type = (v_payload ->> 'work_type'),
            ot_amount = NULLIF(v_payload ->> 'ot_amount', '')::numeric,
            advance_amount = NULLIF(v_payload ->> 'advance_amount', '')::numeric,
            special_amount = NULLIF(v_payload ->> 'special_amount', '')::numeric,
            ot_hours = NULLIF(v_payload ->> 'ot_hours', '')::numeric,
            ot_description = (v_payload ->> 'ot_description'),
            leave_reason = (v_payload ->> 'leave_reason'),
            leave_days = NULLIF(v_payload ->> 'leave_days', '')::numeric,
            note = (v_payload ->> 'note'),
            work_details = (v_payload ->> 'work_details'),
            fuel_type = (v_payload ->> 'fuel_type'),
            payroll_period = v_payload -> 'payroll_period',
            payroll_snapshot = v_payload -> 'payroll_snapshot',
            machine_id = (v_payload ->> 'machine_id'),
            machine_hours = NULLIF(v_payload ->> 'machine_hours', '')::numeric,
            machine_work_type = (v_payload ->> 'machine_work_type'),
            sand_morning = NULLIF(v_payload ->> 'sand_morning', '')::numeric,
            sand_afternoon = NULLIF(v_payload ->> 'sand_afternoon', '')::numeric,
            sand_machine_type = (v_payload ->> 'sand_machine_type'),
            sand_operators = v_payload -> 'sand_operators',
            sand_transport = NULLIF(v_payload ->> 'sand_transport', '')::numeric,
            event_time = (v_payload ->> 'event_time'),
            created_at = NULLIF(v_payload ->> 'created_at', '')::timestamptz,
            fuel_movement = (v_payload ->> 'fuel_movement'),
            work_type_by_employee = v_payload -> 'work_type_by_employee',
            work_assignments = v_payload -> 'work_assignments',
            custom_work_categories = v_payload -> 'custom_work_categories',
            drums_obtained = NULLIF(v_payload ->> 'drums_obtained', '')::numeric,
            drums_washed_at_home = NULLIF(v_payload ->> 'drums_washed_at_home', '')::numeric,
            sand_work_start = (v_payload ->> 'sand_work_start'),
            sand_morning_start = (v_payload ->> 'sand_morning_start'),
            sand_afternoon_start = (v_payload ->> 'sand_afternoon_start'),
            sand_evening_end = (v_payload ->> 'sand_evening_end'),
            trip_count = NULLIF(v_payload ->> 'trip_count', '')::numeric,
            trip_morning = NULLIF(v_payload ->> 'trip_morning', '')::numeric,
            trip_afternoon = NULLIF(v_payload ->> 'trip_afternoon', '')::numeric,
            cubic_per_trip = NULLIF(v_payload ->> 'cubic_per_trip', '')::numeric,
            total_cubic = NULLIF(v_payload ->> 'total_cubic', '')::numeric,
            per_car_trips = NULLIF(v_payload ->> 'per_car_trips', '')::numeric,
            per_car_cubic = NULLIF(v_payload ->> 'per_car_cubic', '')::numeric,
            event_type = (v_payload ->> 'event_type'),
            event_priority = (v_payload ->> 'event_priority'),
            trip_billing_mode = (v_payload ->> 'trip_billing_mode'),
            income_payment_status = (v_payload ->> 'income_payment_status'),
            sand_batch_id = (v_payload ->> 'sand_batch_id'),
            sand_home_batch_usages = v_payload -> 'sand_home_batch_usages',
            payroll_lock_action = (v_payload ->> 'payroll_lock_action'),
            unlocked_by_admin_id = (v_payload ->> 'unlocked_by_admin_id'),
            unlocked_by_admin_name = (v_payload ->> 'unlocked_by_admin_name'),
            unlocked_at = (v_payload ->> 'unlocked_at'),
            fuel_tank = (v_payload ->> 'fuel_tank'),
            vehicle_name = (v_payload ->> 'vehicle_name'),
            driver_name = (v_payload ->> 'driver_name')
        WHERE t.id = p_tx_id;
        RETURN format(
            'กู้คืน UPDATE จาก audit_id=%s สำเร็จ (คอลัมน์: %s)',
            v_audit.audit_id,
            COALESCE(array_to_string(v_audit.changed_columns, ', '), '-')
        );
    END IF;

    IF v_audit.op = 'INSERT' THEN
        RETURN format(
            'audit_id=%s เป็น INSERT — แถวถูกสร้างใหม่ ไม่ต้องกู้คืน',
            v_audit.audit_id
        );
    END IF;

    RETURN format('ไม่รองรับ op=%s', v_audit.op);
END;
$$;

COMMENT ON FUNCTION public.restore_transaction(text, bigint) IS
    'กู้คืนแถว transactions จากประวัติ audit — ใช้ audit ล่าสุดหรือระบุ audit_id';

-- ---------------------------------------------------------------------------
-- 6. View ดูรายการที่ถูกลบล่าสุด
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.transactions_deleted_recent AS
SELECT
    audit_id,
    tx_id,
    changed_at,
    actor,
    old_row ->> 'date' AS date,
    old_row ->> 'category' AS category,
    old_row ->> 'sub_category' AS sub_category,
    old_row ->> 'description' AS description,
    old_row ->> 'quantity' AS quantity,
    old_row ->> 'amount' AS amount,
    old_row ->> 'vehicle_id' AS vehicle_id
FROM public.transactions_audit
WHERE op = 'DELETE'
ORDER BY changed_at DESC;

-- ---------------------------------------------------------------------------
-- 7. RLS — อ่านได้อย่างเดียวจาก client; trigger เขียนผ่าน SECURITY DEFINER
-- ---------------------------------------------------------------------------
ALTER TABLE public.transactions_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS transactions_audit_select ON public.transactions_audit;
CREATE POLICY transactions_audit_select
    ON public.transactions_audit
    FOR SELECT
    USING (true);

COMMIT;
