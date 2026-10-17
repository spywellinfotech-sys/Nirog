-- The doctor leaves the call: the patient's "Doctor is calling" banner goes away at once.
create or replace function public.end_call(p_booking uuid) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  update public.bookings bk set call_started_at = null
    from public.doctors d where d.id = bk.doctor_id and d.user_id = uid and bk.id = p_booking;
  if not found then raise exception 'booking_not_found'; end if;
  return true;
end $$;
revoke all on function public.end_call(uuid) from public, anon;
grant execute on function public.end_call(uuid) to authenticated;
