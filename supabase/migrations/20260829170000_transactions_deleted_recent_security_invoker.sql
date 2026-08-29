-- Fix SECURITY DEFINER view lint: respect caller RLS on underlying tables
BEGIN;

CREATE OR REPLACE VIEW public.transactions_deleted_recent
WITH (security_invoker = on)
AS
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

COMMENT ON VIEW public.transactions_deleted_recent IS
    'รายการธุรกรรมที่ถูกลบล่าสุดจาก audit — security_invoker=on เพื่อใช้สิทธิ์/RLS ของผู้เรียก';

COMMIT;
