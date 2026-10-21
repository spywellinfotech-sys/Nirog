-- 1) Patient weight (optional): saved on the booking and on the patient's profile so it is prefilled next time.
alter table public.bookings add column if not exists patient_weight numeric(5,1) check (patient_weight is null or patient_weight between 1 and 400);
alter table public.patients add column if not exists weight numeric(5,1) check (weight is null or weight between 1 and 400);
grant update (weight) on public.patients to authenticated;

drop function if exists public.create_booking(bigint, date, time, text, text, int, text, text, text);
create function public.create_booking(
  p_doctor bigint, p_day date, p_time time, p_mode text,
  p_name text, p_age int, p_sex text, p_phone text, p_reason text default '', p_weight numeric default null)
returns public.bookings language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid(); d public.doctors; ps public.platform_settings; fee int; pf int; loc bigint; b public.bookings;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.profiles where id = uid and role = 'patient') then raise exception 'patients_only'; end if;
  if length(trim(coalesce(p_name,''))) < 2 then raise exception 'invalid_name'; end if;
  if p_age is null or p_age < 0 or p_age > 120 then raise exception 'invalid_age'; end if;
  if p_sex not in ('Female','Male','Other') then raise exception 'invalid_sex'; end if;
  if p_weight is not null and (p_weight < 1 or p_weight > 400) then raise exception 'invalid_weight'; end if;
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
                                 patient_name, patient_age, patient_sex, patient_phone, reason, doctor_fee, platform_fee, patient_weight)
    values (public.new_ref('NR'), uid, p_doctor, loc, p_day, p_time, p_mode,
            trim(p_name), p_age, p_sex, p_phone, left(coalesce(p_reason,''), 300), fee, pf, round(p_weight, 1))
    returning * into b;
  exception when unique_violation then
    raise exception 'slot_taken';   -- lost a race against another patient
  end;

  update public.patients set age = p_age, sex = p_sex, weight = coalesce(round(p_weight, 1), weight) where id = uid;
  perform public.notify(d.user_id, 'New booking request from ' || trim(p_name) || ' for ' || to_char(p_day, 'DD Mon') || ' ' || to_char(p_time, 'HH12:MI AM') || '. Please approve or reject.');
  perform public.notify(uid, 'Request sent to ' || d.name || '. Waiting for approval.');
  return b;
end $$;
revoke all on function public.create_booking(bigint, date, time, text, text, int, text, text, text, numeric) from public, anon;
grant execute on function public.create_booking(bigint, date, time, text, text, int, text, text, text, numeric) to authenticated;

-- 2) Platform fee on tests, scans and other facility requests: a percent of the test price, set by the admin, separate from the appointment fee.
alter table public.platform_settings add column if not exists test_fee_on boolean not null default false;
alter table public.platform_settings add column if not exists test_fee_pct numeric(5,2) not null default 0 check (test_fee_pct between 0 and 50);
grant update (test_fee_on, test_fee_pct) on public.platform_settings to authenticated;
alter table public.facility_requests add column if not exists item_price integer check (item_price is null or item_price >= 0);
alter table public.facility_requests add column if not exists platform_fee integer not null default 0 check (platform_fee >= 0);

create or replace function public.create_facility_request(p_facility bigint, p_item text, p_date date, p_name text, p_phone text, p_note text default '')
returns text language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); f record; r text; n int; ps public.platform_settings; price int; pf int := 0; e jsonb; nm text;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.profiles where id = uid and role = 'patient') then raise exception 'not_a_patient'; end if;
  select id, user_id, name, kind, services into f from public.facilities where id = p_facility and status = 'approved' and kind in ('lab','centre','hospital');
  if f.id is null then raise exception 'facility_unavailable'; end if;
  if char_length(btrim(coalesce(p_item,''))) < 2 then raise exception 'invalid_item'; end if;
  if char_length(btrim(coalesce(p_name,''))) < 2 then raise exception 'invalid_name'; end if;
  if coalesce(p_phone,'') !~ '^[6-9][0-9]{9}$' then raise exception 'invalid_phone'; end if;
  if p_date is null or p_date < public.clinic_now()::date or p_date > public.clinic_now()::date + 60 then raise exception 'invalid_date'; end if;
  select count(*) into n from public.facility_requests where patient_id = uid and status = 'pending';
  if n >= 5 then raise exception 'too_many_requests'; end if;
  -- price comes from the facility's own list, never from the patient
  if jsonb_typeof(f.services) = 'array' then
    for e in select * from jsonb_array_elements(f.services) loop
      nm := case when jsonb_typeof(e) = 'array' then e ->> 0 when jsonb_typeof(e) = 'object' then e ->> 'name' else null end;
      if nm is not null and lower(btrim(nm)) = lower(btrim(p_item)) then
        price := case when jsonb_typeof(e) = 'array' then nullif(e ->> 1, '')::int when jsonb_typeof(e) = 'object' then nullif(e ->> 'price', '')::int else null end;
        exit;
      end if;
    end loop;
  end if;
  select * into ps from public.platform_settings where id = 1;
  if price is not null and ps.test_fee_on and not (ps.promo_until is not null and ps.promo_until > now()) then
    pf := round(price * ps.test_fee_pct / 100)::int;
  end if;
  r := public.new_ref('FR');
  insert into public.facility_requests (ref, facility_id, patient_id, patient_name, patient_phone, item, preferred_date, note, item_price, platform_fee)
    values (r, f.id, uid, left(btrim(p_name),80), p_phone, left(btrim(p_item),120), p_date, left(btrim(coalesce(p_note,'')),300), price, pf);
  perform public.notify(f.user_id, 'New appointment request ' || r || ': ' || left(btrim(p_item),60) || ' on ' || to_char(p_date,'DD Mon'));
  return r;
end $$;

create or replace function public.admin_request_stats() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  return coalesce((select jsonb_object_agg(facility_id::text, jsonb_build_object('total', total, 'pending', pend, 'confirmed', conf, 'rejected', rej, 'last30', l30, 'fees', fees))
    from (select facility_id, count(*) as total, count(*) filter (where status='pending') as pend, count(*) filter (where status='confirmed') as conf,
                 count(*) filter (where status='rejected') as rej, count(*) filter (where created_at > now() - interval '30 days') as l30,
                 coalesce(sum(platform_fee) filter (where status='confirmed'), 0) as fees
          from public.facility_requests group by facility_id) s), '{}'::jsonb);
end $$;
