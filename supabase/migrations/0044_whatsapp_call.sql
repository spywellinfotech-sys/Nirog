-- Video visits now run on WhatsApp video calling: the notification tells the patient to expect a WhatsApp call.
create or replace function public.start_call(p_booking uuid) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); b public.bookings; dn text; ts timestamp;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  select bk.* into b from public.bookings bk join public.doctors d on d.id = bk.doctor_id
    where bk.id = p_booking and d.user_id = uid for update of bk;
  if not found then raise exception 'booking_not_found'; end if;
  select name into dn from public.doctors where id = b.doctor_id;
  if b.mode <> 'video' then raise exception 'not_video'; end if;
  if b.status <> 'confirmed' then raise exception 'booking_not_confirmed'; end if;
  ts := b.slot_date + b.slot_time;
  if public.clinic_now() < ts then raise exception 'call_not_open'; end if;
  if public.clinic_now() > ts + interval '24 hours' then raise exception 'call_closed'; end if;
  if b.call_started_at is null or b.call_started_at < now() - interval '2 minutes' then
    perform public.notify(b.patient_id, dn || ' is calling you on WhatsApp for your video consultation. Keep WhatsApp open on the mobile number you gave for the booking.');
  end if;
  update public.bookings set call_started_at = now() where id = p_booking;
  return true;
end $$;
revoke all on function public.start_call(uuid) from public, anon;
grant execute on function public.start_call(uuid) to authenticated;
