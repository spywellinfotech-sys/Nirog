-- Attended / not attended marking for doctors (bookings) and facilities (requests). Null = not marked yet.
alter table public.bookings add column if not exists attendance text check (attendance in ('attended','no_show'));
alter table public.facility_requests add column if not exists attendance text check (attendance in ('attended','no_show'));

create or replace function public.mark_attendance(p_booking uuid, p_attended boolean) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare did bigint := public.my_doctor_id(); b public.bookings;
begin
  if did is null then raise exception 'doctors_only'; end if;
  if p_attended is null then raise exception 'invalid_status'; end if;
  select * into b from public.bookings where id = p_booking and doctor_id = did for update;
  if not found then raise exception 'booking_not_found'; end if;
  if b.status <> 'confirmed' then raise exception 'not_confirmed'; end if;
  if public.clinic_now() < (b.slot_date + b.slot_time) then raise exception 'visit_not_started'; end if;
  update public.bookings set attendance = case when p_attended then 'attended' else 'no_show' end, updated_at = now() where id = b.id;
end $$;

create or replace function public.mark_facility_attendance(p_id bigint, p_attended boolean) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare q public.facility_requests;
begin
  if p_attended is null then raise exception 'invalid_status'; end if;
  select * into q from public.facility_requests where id = p_id and facility_id = public.my_facility_id() for update;
  if q.id is null then raise exception 'not_found'; end if;
  if q.status <> 'confirmed' then raise exception 'not_confirmed'; end if;
  if public.clinic_now()::date < q.preferred_date then raise exception 'visit_not_started'; end if;
  update public.facility_requests set attendance = case when p_attended then 'attended' else 'no_show' end, updated_at = now() where id = q.id;
end $$;

revoke all on function public.mark_attendance(uuid, boolean), public.mark_facility_attendance(bigint, boolean) from public, anon;
grant execute on function public.mark_attendance(uuid, boolean), public.mark_facility_attendance(bigint, boolean) to authenticated;
