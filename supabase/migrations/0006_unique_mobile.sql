-- One account per mobile number, and a mobile number can be used for only one doctor or facility registration.
-- (The same Google/email account cannot register twice: register_* require role = 'patient' and then change the role.)
create unique index if not exists profiles_phone_uq on public.profiles(phone) where phone is not null;

create or replace function public.register_doctor(p jsonb) returns public.doctors
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); d public.doctors; day int; sess jsonb;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.profiles where id = uid and role = 'patient') then raise exception 'already_registered'; end if;
  if exists (select 1 from public.bookings where patient_id = uid) then raise exception 'account_has_bookings'; end if;
  if not (coalesce(p ->> 'phone', '') ~ '^[6-9][0-9]{9}$') then raise exception 'invalid_phone'; end if;
  if exists (select 1 from public.profiles where phone = '+91' || (p ->> 'phone') and id <> uid) then raise exception 'phone_in_use'; end if;
  if jsonb_typeof(p -> 'days') <> 'array' or jsonb_array_length(p -> 'days') = 0 then raise exception 'invalid_days'; end if;
  if jsonb_typeof(p -> 'sessions') <> 'array' or jsonb_array_length(p -> 'sessions') not between 1 and 3 then raise exception 'invalid_sessions'; end if;

  insert into public.doctors (user_id, ref, name, spec, qual, exp_years, fee_inr, video_fee_inr, languages, about, clinic, city, wa)
  values (uid, public.new_ref('DR'), trim(p ->> 'name'), trim(p ->> 'spec'), coalesce(p ->> 'qual', ''),
          coalesce((p ->> 'exp_years')::int, 0), (p ->> 'fee_inr')::int, coalesce((p ->> 'video_fee_inr')::int, 0),
          coalesce(nullif(p ->> 'languages', ''), 'Hindi, English'), coalesce(p ->> 'about', ''),
          coalesce(p ->> 'clinic', ''), p ->> 'city', nullif(p ->> 'wa', ''))
  returning * into d;

  insert into public.doctor_verification (doctor_id, council, reg_no, reg_year)
  values (d.id, trim(p ->> 'council'), trim(p ->> 'reg_no'), (p ->> 'reg_year')::int);

  insert into public.clinic_locations (doctor_id, name, address, city, pin, map_url, lat, lng)
  values (d.id, coalesce(p ->> 'clinic', ''), p ->> 'address', p ->> 'city', nullif(p ->> 'pin', ''), nullif(p ->> 'map_url', ''),
          (p ->> 'lat')::double precision, (p ->> 'lng')::double precision);

  for day in select jsonb_array_elements_text(p -> 'days')::int loop
    for sess in select * from jsonb_array_elements(p -> 'sessions') loop
      insert into public.doctor_availability (doctor_id, weekday, start_min, end_min, step_min)
      values (d.id, day, (sess ->> 's')::int, (sess ->> 'e')::int, coalesce((p ->> 'step')::int, 20));
    end loop;
  end loop;

  update public.profiles set role = 'doctor', full_name = d.name, phone = '+91' || (p ->> 'phone') where id = uid;
  return d;
end $$;

create or replace function public.register_facility(p jsonb) returns public.facilities
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); f public.facilities;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.profiles where id = uid and role = 'patient') then raise exception 'already_registered'; end if;
  if exists (select 1 from public.bookings where patient_id = uid) then raise exception 'account_has_bookings'; end if;
  if not (coalesce(p ->> 'contact_phone', '') ~ '^[6-9][0-9]{9}$') then raise exception 'invalid_phone'; end if;
  if exists (select 1 from public.profiles where phone = '+91' || (p ->> 'contact_phone') and id <> uid) then raise exception 'phone_in_use'; end if;
  insert into public.facilities (user_id, ref, kind, sub, name, city, address, pin, map_url, hours, beds,
                                 emergency, ambulance, home_service, services, wa)
  values (uid, public.new_ref('FC'), p ->> 'kind', coalesce(p ->> 'sub', ''), trim(p ->> 'name'), p ->> 'city', p ->> 'address', nullif(p ->> 'pin', ''), nullif(p ->> 'map_url', ''),
          coalesce(p ->> 'hours', ''), nullif(p ->> 'beds', '')::int, coalesce((p ->> 'emergency')::boolean, false),
          coalesce((p ->> 'ambulance')::boolean, false), coalesce((p ->> 'home_service')::boolean, false),
          coalesce(p -> 'services', '[]'::jsonb), nullif(p ->> 'wa', ''))
  returning * into f;
  insert into public.facility_private (facility_id, contact_name, contact_phone, licence_no)
  values (f.id, coalesce(p ->> 'contact_name', ''), coalesce(p ->> 'contact_phone', ''), coalesce(p ->> 'licence_no', ''));
  update public.profiles set role = 'facility', full_name = f.name, phone = '+91' || (p ->> 'contact_phone') where id = uid;
  return f;
end $$;
