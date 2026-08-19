-- รายชื่อรถ / เครื่องจักร + คนขับเริ่มต้น (แหล่งความจริง แยกจาก app_settings JSON)
CREATE TABLE IF NOT EXISTS public.vehicles (
    id text PRIMARY KEY,
    name text NOT NULL,
    default_driver_id text,
    sort_order integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT vehicles_name_unique UNIQUE (name)
);

CREATE INDEX IF NOT EXISTS idx_vehicles_sort_order ON public.vehicles (sort_order, name);

ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow all on vehicles" ON public.vehicles;
CREATE POLICY "Allow all on vehicles"
    ON public.vehicles
    FOR ALL
    USING (true)
    WITH CHECK (true);

-- Seed จาก app_settings.cars + vehicleDefaultDrivers (ถ้าตารางยังว่าง)
INSERT INTO public.vehicles (id, name, default_driver_id, sort_order)
SELECT
    'v_' || substr(md5(trim(elem.value)), 1, 16),
    trim(elem.value),
    NULLIF(trim(COALESCE(s.app_defaults #>> ARRAY['vehicleDefaultDrivers', trim(elem.value)], '')), ''),
    (elem.ordinality - 1)::integer
FROM public.app_settings s
CROSS JOIN LATERAL jsonb_array_elements_text(COALESCE(s.cars, '[]'::jsonb))
    WITH ORDINALITY AS elem(value, ordinality)
WHERE s.id = 'default'
  AND trim(elem.value) <> ''
  AND NOT EXISTS (SELECT 1 FROM public.vehicles LIMIT 1)
ON CONFLICT (name) DO NOTHING;
