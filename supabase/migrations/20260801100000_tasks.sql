-- งาน (Tasks) — สิ่งที่ต้องทำรายวัน/สัปดาห์/เดือน/ปี สำหรับแอป iOS
-- เจ้าของงานอ้างอิง admin_users.id ที่ระดับแอป (ระบบล็อกอินไม่ได้ใช้ Supabase Auth)
-- งานส่วนตัวกรองที่ฝั่งไคลเอนต์: visibility = 'public' OR owner_admin_id = <current admin>

CREATE TABLE IF NOT EXISTS public.tasks (
    id text PRIMARY KEY,
    title text NOT NULL,
    note text,
    owner_admin_id text NOT NULL,
    owner_name text,
    assignee_admin_id text,
    assignee_name text,
    visibility text NOT NULL DEFAULT 'public'
        CHECK (visibility IN ('public', 'private')),
    scope text NOT NULL DEFAULT 'Daily'
        CHECK (scope IN ('Daily', 'Weekly', 'Monthly', 'Yearly')),
    due_date text NOT NULL,
    remind_at timestamptz,
    status text NOT NULL DEFAULT 'Todo'
        CHECK (status IN ('Todo', 'InProgress', 'Done')),
    priority text NOT NULL DEFAULT 'Normal'
        CHECK (priority IN ('Urgent', 'High', 'Normal', 'Low')),
    is_focus boolean NOT NULL DEFAULT false,
    focus_order integer,
    completed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tasks_due_date ON public.tasks (due_date DESC);
CREATE INDEX IF NOT EXISTS idx_tasks_owner ON public.tasks (owner_admin_id);
CREATE INDEX IF NOT EXISTS idx_tasks_assignee ON public.tasks (assignee_admin_id);
CREATE INDEX IF NOT EXISTS idx_tasks_focus ON public.tasks (due_date, focus_order)
    WHERE is_focus = true;

ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow all on tasks" ON public.tasks;
CREATE POLICY "Allow all on tasks"
    ON public.tasks
    FOR ALL
    USING (true)
    WITH CHECK (true);
