-- เก็บชื่อรถ / ชื่อคนขับคู่กับรหัสในแต่ละแถวบันทึก
ALTER TABLE public.transactions
  ADD COLUMN IF NOT EXISTS vehicle_name text,
  ADD COLUMN IF NOT EXISTS driver_name text;

-- แถวเก่าที่ vehicle_id เป็นชื่อรถ (ไม่ใช่รหัสแคตตาล็อก v_...)
UPDATE public.transactions
SET vehicle_name = trim(vehicle_id)
WHERE vehicle_name IS NULL
  AND vehicle_id IS NOT NULL
  AND trim(vehicle_id) <> ''
  AND vehicle_id NOT LIKE 'v_%';
