-- ย้ายรายการน้ำมันตั้งแต่ 04/08/2569 ย้อนหลัง (55 รายการ) ออกจาก transactions ไปเก็บในตารางแยก
CREATE TABLE public.fuel_archive_2026_08_04 (LIKE public.transactions INCLUDING DEFAULTS);
ALTER TABLE public.fuel_archive_2026_08_04
  ADD COLUMN archived_at timestamptz NOT NULL DEFAULT now(),
  ADD PRIMARY KEY (id);
COMMENT ON TABLE public.fuel_archive_2026_08_04 IS 'Fuel transactions dated 2026-08-04 and earlier, moved out of public.transactions on 2026-10-03.';

ALTER TABLE public.fuel_archive_2026_08_04 ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all on fuel_archive_2026_08_04" ON public.fuel_archive_2026_08_04 FOR ALL TO public USING (true) WITH CHECK (true);
GRANT SELECT ON public.fuel_archive_2026_08_04 TO anon, authenticated;

DO $$
DECLARE
  copied int;
  deleted int;
BEGIN
  INSERT INTO public.fuel_archive_2026_08_04
    SELECT t.*, now() FROM public.transactions t
    WHERE t.category = 'Fuel' AND t.date <= '2026-08-04';
  GET DIAGNOSTICS copied = ROW_COUNT;

  DELETE FROM public.transactions
    WHERE id IN (SELECT id FROM public.fuel_archive_2026_08_04);
  GET DIAGNOSTICS deleted = ROW_COUNT;

  IF copied <> 55 OR deleted <> copied THEN
    RAISE EXCEPTION 'fuel archive count mismatch: copied %, deleted %', copied, deleted;
  END IF;
END $$;
