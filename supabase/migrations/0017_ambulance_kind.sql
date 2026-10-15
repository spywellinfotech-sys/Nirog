-- Ambulance services can register as a facility type (listed after admin approval).
alter table public.facilities drop constraint if exists facilities_kind_check;
alter table public.facilities add constraint facilities_kind_check check (kind in ('lab','centre','hospital','pharmacy','ambulance','other'));

create or replace function public.admin_dashboard_counts() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare r jsonb;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  select jsonb_build_object(
    'patients', (select count(*) from public.profiles where role = 'patient'),
    'doctors', jsonb_build_object('listed', (select count(*) from public.doctors where status = 'approved'), 'pending', (select count(*) from public.doctors where status = 'pending')),
    'facilities', (select coalesce(jsonb_object_agg(k.kind, jsonb_build_object(
        'listed', (select count(*) from public.facilities f where f.kind = k.kind and f.status = 'approved'),
        'pending', (select count(*) from public.facilities f where f.kind = k.kind and f.status = 'pending'))), '{}'::jsonb)
      from (values ('lab'), ('centre'), ('hospital'), ('pharmacy'), ('ambulance'), ('other')) as k(kind)),
    'specialties', (select coalesce(jsonb_agg(jsonb_build_object('spec', s.spec, 'n', s.n) order by s.n desc, s.spec), '[]'::jsonb)
      from (select spec, count(*) n from public.doctors where status = 'approved' group by spec order by count(*) desc, spec limit 12) s),
    'phones', (select count(*) from public.push_tokens),
    'phone_users', (select count(distinct user_id) from public.push_tokens)
  ) into r;
  return r;
end $$;
revoke all on function public.admin_dashboard_counts() from public, anon;
grant execute on function public.admin_dashboard_counts() to authenticated;
