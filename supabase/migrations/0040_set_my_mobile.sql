-- A patient who signed in with Google adds a mobile number once. Doctors and facilities use it to reach them about bookings.
create or replace function public.set_my_mobile(p_mobile text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.profiles where id = uid and role = 'patient') then raise exception 'not_a_patient'; end if;
  if coalesce(p_mobile, '') !~ '^[6-9][0-9]{9}$' then raise exception 'invalid_phone'; end if;
  if exists (select 1 from public.profiles where phone = '+91' || p_mobile and id <> uid) then raise exception 'phone_in_use'; end if;
  update public.profiles set phone = '+91' || p_mobile where id = uid;
end $$;
revoke all on function public.set_my_mobile(text) from public, anon;
grant execute on function public.set_my_mobile(text) to authenticated;
