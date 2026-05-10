-- Web Daily Wizard + PayrollUnlock: columns referenced by keysToSnake(Transaction) but missing from older schemas.

ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS sand_batch_id text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS sand_home_batch_usages jsonb;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS payroll_lock_action text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS unlocked_by_admin_id text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS unlocked_by_admin_name text;
ALTER TABLE public.transactions ADD COLUMN IF NOT EXISTS unlocked_at text;

COMMENT ON COLUMN public.transactions.sand_batch_id IS 'Daily Wizard sand wash batch id';
COMMENT ON COLUMN public.transactions.sand_home_batch_usages IS 'Home sand wash batch allocations JSON array';
COMMENT ON COLUMN public.transactions.payroll_lock_action IS 'PayrollUnlock tx: unlock | relock';
