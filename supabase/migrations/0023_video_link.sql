-- Video consultation: the doctor adds a call link (Google Meet, Zoom, Jitsi, WhatsApp...) to a video booking; the patient sees a Join button.
alter table public.bookings add column call_link text check (call_link is null or char_length(call_link) <= 300);

create or replace function public.set_call_link(p_booking uuid, p_link text) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); b public.bookings; v text := nullif(trim(coalesce(p_link, '')), '');
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  select bk.* into b from public.bookings bk join public.doctors d on d.id = bk.doctor_id
    where bk.id = p_booking and d.user_id = uid for update of bk;
  if not found then raise exception 'booking_not_found'; end if;
  if b.mode <> 'video' then raise exception 'not_video'; end if;
  if b.status <> 'confirmed' then raise exception 'booking_not_confirmed'; end if;
  if v ~ '^[6-9][0-9]{9}$' then v := 'https://wa.me/91' || v; end if;
  if v is not null and v !~* '^https://[a-z0-9.-]+\.[a-z]{2,}(/[^[:space:]]*)?$' then raise exception 'invalid_link'; end if;
  update public.bookings set call_link = v, updated_at = now() where id = p_booking;
  if v is not null and v is distinct from b.call_link then
    perform public.notify(b.patient_id, 'Your doctor added the video call link for your appointment on ' || to_char(b.slot_date, 'DD Mon') || '. Open My appointments to join.');
  end if;
  return true;
end $$;
revoke all on function public.set_call_link(uuid, text) from public, anon;
grant execute on function public.set_call_link(uuid, text) to authenticated;
