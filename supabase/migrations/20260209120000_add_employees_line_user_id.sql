-- LINE Messaging API: optional recipient id per employee (add friend to OA first)
alter table public.employees
  add column if not exists line_user_id text;

comment on column public.employees.line_user_id is 'LINE Messaging API userId (e.g. U...) for advance notifications';
