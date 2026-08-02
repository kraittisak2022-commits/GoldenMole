-- Assignment inbox for the iOS "งาน" menu.
-- `assigned_at` stamps when a task was handed to someone; `assignee_seen_at` clears the
-- in-app badge once that person acknowledges it. Notification delivery stays in-app only.

ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS assigned_at timestamptz;
ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS assignee_seen_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_tasks_assignee_unseen
    ON public.tasks (assignee_admin_id)
    WHERE assignee_seen_at IS NULL;
