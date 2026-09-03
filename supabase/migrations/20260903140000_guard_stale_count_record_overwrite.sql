-- Prevent stale offline count-record upserts from overwriting a newer higher total.
-- Typical failure: device A counted to 652, device B later flushed an older 390 snapshot.
--
-- Rule: for DailyLog Sand / VehicleTrip rows, if the incoming lapTimes list is shorter
-- by >= 5 and its last lap stamp is earlier than the existing last lap, keep the
-- existing count fields (allow small intentional undo/edit steps of 1–4 laps).

BEGIN;

CREATE OR REPLACE FUNCTION public.guard_stale_count_record_overwrite()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  old_laps jsonb;
  new_laps jsonb;
  old_n int;
  new_n int;
  drop_n int;
  old_last text;
  new_last text;
  is_sand boolean;
  is_trip boolean;
BEGIN
  IF TG_OP <> 'UPDATE' THEN
    RETURN NEW;
  END IF;

  IF NEW.category IS DISTINCT FROM 'DailyLog' THEN
    RETURN NEW;
  END IF;

  is_sand := lower(coalesce(NEW.sub_category, '')) = 'sand'
    OR coalesce(NEW.description, '') LIKE 'ร่อนทราย:%';
  is_trip := lower(coalesce(NEW.sub_category, '')) = 'vehicletrip'
    OR (
      coalesce(NEW.vehicle_id, '') <> ''
      AND lower(coalesce(NEW.sub_category, '')) NOT IN ('sand', 'event', 'sandsieve')
    );

  IF NOT (is_sand OR is_trip) THEN
    RETURN NEW;
  END IF;

  old_laps := COALESCE(OLD.work_assignments -> 'lapTimes', '[]'::jsonb);
  new_laps := COALESCE(NEW.work_assignments -> 'lapTimes', '[]'::jsonb);
  IF jsonb_typeof(old_laps) <> 'array' THEN old_laps := '[]'::jsonb; END IF;
  IF jsonb_typeof(new_laps) <> 'array' THEN new_laps := '[]'::jsonb; END IF;

  old_n := jsonb_array_length(old_laps);
  new_n := jsonb_array_length(new_laps);
  drop_n := old_n - new_n;

  IF drop_n < 5 THEN
    RETURN NEW;
  END IF;

  old_last := CASE WHEN old_n > 0 THEN old_laps ->> (old_n - 1) ELSE '' END;
  new_last := CASE WHEN new_n > 0 THEN new_laps ->> (new_n - 1) ELSE '' END;

  -- Incoming ended earlier than what we already stored → treat as stale snapshot.
  IF new_last < old_last THEN
    NEW.work_assignments := OLD.work_assignments;
    NEW.description := OLD.description;
    NEW.note := COALESCE(NEW.note, OLD.note);

    IF is_sand THEN
      NEW.drums_obtained := OLD.drums_obtained;
    END IF;

    IF is_trip THEN
      NEW.trip_count := OLD.trip_count;
      NEW.per_car_trips := OLD.per_car_trips;
      NEW.cubic_per_trip := OLD.cubic_per_trip;
      NEW.per_car_cubic := OLD.per_car_cubic;
      NEW.total_cubic := OLD.total_cubic;
      NEW.work_details := COALESCE(NEW.work_details, OLD.work_details);
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_stale_count_record_overwrite ON public.transactions;
CREATE TRIGGER trg_guard_stale_count_record_overwrite
  BEFORE UPDATE ON public.transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_stale_count_record_overwrite();

COMMENT ON FUNCTION public.guard_stale_count_record_overwrite() IS
  'Blocks stale offline Sand/VehicleTrip upserts that would drop many laps to an older snapshot.';

COMMIT;
