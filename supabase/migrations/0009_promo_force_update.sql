-- Promo period (platform fee waived until promo_until) and force-update floor (min_build).
alter table public.platform_settings add column if not exists promo_until timestamptz;
alter table public.platform_settings add column if not exists min_build integer not null default 0 check (min_build >= 0);
alter table public.platform_settings add column if not exists update_url text not null default 'https://github.com/spywellinfotech-sys/Nirog/releases/tag/latest-apk';
grant update (promo_until, min_build, update_url) on public.platform_settings to authenticated;

create or replace function public.create_booking(
  p_doctor bigint, p_day date, p_time time, p_mode text,
  p_name text, p_age int, p_sex text, p_phone text, p_reason text default '')
returns public.bookings language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid(); d public.doctors; ps public.platform_settings; fee int; pf int; loc bigint; b public.bookings;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.profiles where id = uid and role = 'patient') then raise exception 'patients_only'; end if;
  if length(trim(coalesce(p_name,''))) < 2 then raise exception 'invalid_name'; end if;
  if p_age is null or p_age < 0 or p_age > 120 then raise exception 'invalid_age'; end if;
  if p_sex not in ('Female','Male','Other') then raise exception 'invalid_sex'; end if;
  if p_phone !~ '^[6-9][0-9]{9}$' then raise exception 'invalid_phone'; end if;
  if p_mode not in ('clinic','video') then raise exception 'invalid_mode'; end if;
  if (select count(*) from public.bookings where patient_id = uid and status in ('pending','confirmed')) >= 10 then
    raise exception 'too_many_active_bookings'; end if;

  select * into d from public.doctors where id = p_doctor and status = 'approved';
  if not found then raise exception 'doctor_unavailable'; end if;
  if p_mode = 'video' and not d.video then raise exception 'video_not_offered'; end if;

  case public.slot_state(p_doctor, p_day, p_time)
    when 'free' then null;
    when 'busy' then raise exception 'slot_taken';
    else raise exception 'slot_unavailable';
  end case;

  select * into ps from public.platform_settings where id = 1;
  fee := case when p_mode = 'video' then d.video_fee_inr else d.fee_inr end;
  pf  := case when not ps.fee_on or (ps.promo_until is not null and ps.promo_until > now()) then 0 when ps.fee_type = 'flat' then round(ps.fee_value)::int
              else round(fee * ps.fee_value / 100)::int end;
  select id into loc from public.clinic_locations where doctor_id = p_doctor order by id limit 1;

  begin
    insert into public.bookings (ref, patient_id, doctor_id, clinic_location_id, slot_date, slot_time, mode,
                                 patient_name, patient_age, patient_sex, patient_phone, reason, doctor_fee, platform_fee)
    values (public.new_ref('NR'), uid, p_doctor, loc, p_day, p_time, p_mode,
            trim(p_name), p_age, p_sex, p_phone, left(coalesce(p_reason,''), 300), fee, pf)
    returning * into b;
  exception when unique_violation then
    raise exception 'slot_taken';   -- lost a race against another patient
  end;

  update public.patients set age = p_age, sex = p_sex where id = uid;
  perform public.notify(d.user_id, 'New booking request from ' || trim(p_name) || ' for ' || to_char(p_day, 'DD Mon') || ' ' || to_char(p_time, 'HH12:MI AM') || '. Please approve or reject.');
  perform public.notify(uid, 'Request sent to ' || d.name || '. Waiting for approval.');
  return b;
end $$;
