-- ระบุรถ/เครื่องจักรสำหรับแถวใช้น้ำมันเครื่องร่อนทราย
UPDATE public.transactions
SET
    vehicle_id = 'เครื่องจักรร่อนทราย เครื่องปั่นไฟ',
    vehicle_name = 'เครื่องจักรร่อนทราย เครื่องปั่นไฟ',
    updated_at = now()
WHERE category = 'Fuel'
  AND sub_category = 'SandSieve'
  AND (
      vehicle_id IS NULL
      OR trim(vehicle_id) = ''
      OR vehicle_id <> 'เครื่องจักรร่อนทราย เครื่องปั่นไฟ'
  );
