-- Patients who sign in with Google have no mobile on their profile. The admin list now falls back to the mobile they gave on their latest booking.
create or replace function public.admin_patients(p_search text default '', p_limit int default 50, p_offset int default 0) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare s text := '%' || replace(replace(replace(lower(trim(coalesce(p_search, ''))), '\', '\\'), '%', '\%'), '_', '\_') || '%'; lim int := least(greatest(coalesce(p_limit, 50), 1), 100); off int := greatest(coalesce(p_offset, 0), 0);
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  return jsonb_build_object(
    'total', (select count(*) from public.profiles p where p.role = 'patient' and lower(p.full_name) like s
              and not exists (select 1 from auth.users u where u.id = p.id and u.banned_until = 'infinity')),
    'rows', coalesce((select jsonb_agg(x order by (x ->> 'at') desc) from (
      select jsonb_build_object('id', p.id, 'name', p.full_name, 'phone', coalesce(p.phone, (select '+91' || b.patient_phone from public.bookings b where b.patient_id = p.id order by b.created_at desc limit 1)), 'email', p.email, 'at', p.created_at,
        'bookings', (select count(*) from public.bookings b where b.patient_id = p.id),
        'confirmed', (select count(*) from public.bookings b where b.patient_id = p.id and b.status = 'confirmed')) as x
      from public.profiles p where p.role = 'patient' and lower(p.full_name) like s
        and not exists (select 1 from auth.users u where u.id = p.id and u.banned_until = 'infinity')
      order by p.created_at desc limit lim offset off) q), '[]'::jsonb));
end $$;

revoke all on function public.admin_patients(text, int, int) from public, anon;
grant execute on function public.admin_patients(text, int, int) to authenticated;
