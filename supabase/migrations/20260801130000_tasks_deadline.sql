-- Optional deadline (date+time) for tasks in the iOS "งาน" menu.
-- Display-only carry-over of unfinished tasks does not need a schema change.

ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS deadline timestamptz;

CREATE INDEX IF NOT EXISTS idx_tasks_deadline
    ON public.tasks (deadline)
    WHERE deadline IS NOT NULL;
