-- The doctor starts a video consultation: the patient is told at once (in-app and as a push) and sees a "Doctor is calling" banner.
alter table public.bookings add column call_started_at timestamptz;

create or replace function public.start_call(p_booking uuid) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); b public.bookings; dn text;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  select bk.* into b from public.bookings bk join public.doctors d on d.id = bk.doctor_id
    where bk.id = p_booking and d.user_id = uid for update of bk;
  if not found then raise exception 'booking_not_found'; end if;
  select name into dn from public.doctors where id = b.doctor_id;
  if b.mode <> 'video' then raise exception 'not_video'; end if;
  if b.status <> 'confirmed' then raise exception 'booking_not_confirmed'; end if;
  if b.call_started_at is null or b.call_started_at < now() - interval '2 minutes' then
    perform public.notify(b.patient_id, dn || ' is calling you for your video consultation. Open My appointments and tap Join video call.');
  end if;
  update public.bookings set call_started_at = now() where id = p_booking;
  return true;
end $$;
revoke all on function public.start_call(uuid) from public, anon;
grant execute on function public.start_call(uuid) to authenticated;
