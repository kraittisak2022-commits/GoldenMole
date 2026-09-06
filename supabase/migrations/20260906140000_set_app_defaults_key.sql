-- Atomic patch of one key inside app_settings.app_defaults (avoids hourly cron races).
create or replace function public.set_app_defaults_key(p_key text, p_value jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.app_settings (id, app_defaults)
  values ('default', jsonb_build_object(p_key, p_value))
  on conflict (id) do update
  set app_defaults = jsonb_set(
    coalesce(public.app_settings.app_defaults, '{}'::jsonb),
    array[p_key],
    p_value,
    true
  );
end;
$$;

revoke all on function public.set_app_defaults_key(text, jsonb) from public;
grant execute on function public.set_app_defaults_key(text, jsonb) to service_role;
