-- รวมชื่อรถตาเปลื่ยน / ISUZU KB ที่บันทึกคนละแบบ → รถตาเปลื่ยน (ISUZU KB)
-- ครอบคลุมแถว Fuel/Withdraw work_type=car และแถวเบิกที่อ้างรถตาเปลี่ยน (สะกดผิด)

UPDATE public.transactions
SET
    vehicle_id = 'รถตาเปลื่ยน (ISUZU KB)',
    vehicle_name = 'รถตาเปลื่ยน (ISUZU KB)',
    work_type = 'car',
    description = 'เติมน้ำมันรถยนต์: รถตาเปลื่ยน (ISUZU KB) '
        || trim(trailing '.' from trim(trailing '0' from quantity::text))
        || ' ลิตร (ดีเซล · ถังหลัก)',
    updated_at = now()
WHERE category = 'Fuel'
  AND sub_category = 'Withdraw'
  AND vehicle_id IN (
      'ISUZU KB',
      'รถISUZUKB',
      'รถตาเปลื่ยน',
      'ISUZUตา',
      'IsuzuKB'
  );

-- แถวเฉพาะที่ vehicle_id ว่างแต่เป็นรถตาเปลื่ยนจริง
UPDATE public.transactions
SET
    vehicle_id = 'รถตาเปลื่ยน (ISUZU KB)',
    vehicle_name = 'รถตาเปลื่ยน (ISUZU KB)',
    work_type = 'car',
    quantity = CASE id
        WHEN '1785839191507_fuel_wd' THEN 9.5
        ELSE quantity
    END,
    description = CASE id
        WHEN '1785839191507_fuel_wd' THEN
            'เติมน้ำมันรถยนต์: รถตาเปลื่ยน (ISUZU KB) 9.5 ลิตร (ดีเซล · ถังหลัก)'
        WHEN '1786356730783_fuel_wd' THEN
            'เติมน้ำมันรถยนต์: รถตาเปลื่ยน (ISUZU KB) 19 ลิตร (ดีเซล · ถังหลัก)'
        WHEN '1786356801885_fuel_wd' THEN
            'เติมน้ำมันรถยนต์: รถตาเปลื่ยน (ISUZU KB) 16 ลิตร (ดีเซล · ถังหลัก)'
        ELSE description
    END,
    updated_at = now()
WHERE id IN (
    '1785839191507_fuel_wd',
    '1786356730783_fuel_wd',
    '1786356801885_fuel_wd'
);
