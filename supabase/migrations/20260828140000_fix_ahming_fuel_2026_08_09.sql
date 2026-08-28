-- แก้รายการน้ำมัน 9 ส.ค. 2569 ที่ไม่ระบุรถ → รถอาหมิง
UPDATE public.transactions
SET
    vehicle_id = 'อาหมิง',
    vehicle_name = 'อาหมิง',
    work_type = 'car',
    fuel_tank = 'main',
    description = 'เติมน้ำมันรถยนต์: อาหมิง 40 ลิตร (ดีเซล · ถังหลัก)',
    updated_at = now()
WHERE id = '1786248023472_fuel_wd';
