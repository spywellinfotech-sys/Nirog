-- Erased patients (sign-in closed) no longer appear in the patient list or the patient count.
create or replace function public.admin_patients(p_search text default '', p_limit int default 50, p_offset int default 0) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare s text := '%' || replace(replace(replace(lower(trim(coalesce(p_search, ''))), '\', '\\'), '%', '\%'), '_', '\_') || '%'; lim int := least(greatest(coalesce(p_limit, 50), 1), 100); off int := greatest(coalesce(p_offset, 0), 0);
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  return jsonb_build_object(
    'total', (select count(*) from public.profiles p where p.role = 'patient' and lower(p.full_name) like s
              and not exists (select 1 from auth.users u where u.id = p.id and u.banned_until = 'infinity')),
    'rows', coalesce((select jsonb_agg(x order by (x ->> 'at') desc) from (
      select jsonb_build_object('id', p.id, 'name', p.full_name, 'phone', p.phone, 'email', p.email, 'at', p.created_at,
        'bookings', (select count(*) from public.bookings b where b.patient_id = p.id),
        'confirmed', (select count(*) from public.bookings b where b.patient_id = p.id and b.status = 'confirmed')) as x
      from public.profiles p where p.role = 'patient' and lower(p.full_name) like s
        and not exists (select 1 from auth.users u where u.id = p.id and u.banned_until = 'infinity')
      order by p.created_at desc limit lim offset off) q), '[]'::jsonb));
end $$;

create or replace function public.admin_dashboard_counts() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare r jsonb;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  select jsonb_build_object(
    'patients', (select count(*) from public.profiles p where p.role = 'patient' and not exists (select 1 from auth.users u where u.id = p.id and u.banned_until = 'infinity')),
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
revoke all on function public.admin_patients(text, int, int), public.admin_dashboard_counts() from public, anon;
grant execute on function public.admin_patients(text, int, int), public.admin_dashboard_counts() to authenticated;
