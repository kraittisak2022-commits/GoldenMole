-- Backfill mobile sand-wash rows so web Daily Wizard can read them.
-- Scope:
--   - transactions.sub_category = 'Sand'
--   - category currently saved as Thai labels from mobile
-- Action:
--   - Normalize category to 'DailyLog'
--
-- Run sections in order.

-- ============================================================
-- 1) PREVIEW (before update)
-- ============================================================
SELECT
  category,
  sub_category,
  COUNT(*) AS row_count
FROM transactions
WHERE sub_category = 'Sand'
GROUP BY category, sub_category
ORDER BY row_count DESC;

SELECT
  id,
  date,
  category,
  sub_category,
  description
FROM transactions
WHERE sub_category = 'Sand'
  AND category IN ('บันทึกการร่อนทราย', 'ทรายที่ล้างที่บ้าน', 'ค่าแรง')
ORDER BY date DESC, id DESC;

-- ============================================================
-- 2) BACKFILL UPDATE
-- ============================================================
UPDATE transactions
SET
  category = 'DailyLog'
WHERE sub_category = 'Sand'
  AND category IN ('บันทึกการร่อนทราย', 'ทรายที่ล้างที่บ้าน')
  AND category <> 'DailyLog';

-- ============================================================
-- 3) VERIFY (after update)
-- ============================================================
SELECT
  category,
  sub_category,
  COUNT(*) AS row_count
FROM transactions
WHERE sub_category = 'Sand'
GROUP BY category, sub_category
ORDER BY row_count DESC;

SELECT
  COUNT(*) AS remaining_non_dailylog_sand
FROM transactions
WHERE sub_category = 'Sand'
  AND category IN ('บันทึกการร่อนทราย', 'ทรายที่ล้างที่บ้าน');

