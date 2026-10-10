-- Nirog: multi-user backend schema for Supabase (PostgreSQL 15+).
-- Run once in the Supabase SQL editor, or with `supabase db push`.
-- Design rules:
--   * Every table has Row Level Security on. Clients get only the grants listed at the bottom.
--   * Money, status changes and role changes happen in SECURITY DEFINER functions, never via direct writes.
--   * Double booking is blocked by a partial unique index, not only by application checks.
--   * Authority for admin/sales comes from public.staff_members, which no client can write.

------------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------------
create type public.app_role      as enum ('patient','doctor','facility','sales','admin');
create type public.review_status as enum ('pending','approved','rejected');
create type public.booking_status as enum ('pending','confirmed','rejected','cancelled');

------------------------------------------------------------------------------
-- Tables
------------------------------------------------------------------------------
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  role        public.app_role not null default 'patient',
  full_name   text not null default '' check (char_length(full_name) <= 80),
  phone       text check (phone is null or phone ~ '^[0-9+]{10,15}$'),
  email       text check (email is null or char_length(email) <= 254),
  created_at  timestamptz not null default now()
);

create table public.patients (
  id          uuid primary key references public.profiles(id) on delete cascade,
  age         smallint check (age between 0 and 120),
  sex         text check (sex in ('Female','Male','Other')),
  photo_path  text
);

create table public.staff_members (
  user_id         uuid primary key references public.profiles(id) on delete cascade,
  role            public.app_role not null check (role in ('sales','admin')),
  active          boolean not null default true,
  monthly_target  numeric(12,2) not null default 0 check (monthly_target >= 0)
);

create table public.doctors (
  id            bigint generated always as identity primary key,
  user_id       uuid not null unique references public.profiles(id) on delete cascade,
  ref           text not null unique,
  name          text not null check (char_length(name) between 3 and 80),
  spec          text not null check (char_length(spec) between 2 and 60),
  qual          text not null default '',
  exp_years     smallint not null default 0 check (exp_years between 0 and 70),
  fee_inr       integer not null check (fee_inr between 0 and 100000),
  video_fee_inr integer not null default 0 check (video_fee_inr between 0 and 100000),
  video         boolean generated always as (video_fee_inr > 0) stored,
  languages     text not null default 'Hindi, English',
  about         text not null default '' check (char_length(about) <= 1000),
  clinic        text not null default '',
  city          text not null,
  photo_path    text,
  wa            text check (wa is null or wa ~ '^[6-9][0-9]{9}$'),
  status        public.review_status not null default 'pending',
  verified      boolean not null default false,
  review_reason text,
  created_at    timestamptz not null default now()
);
create index doctors_listing_idx on public.doctors (status, city, spec);

-- Registration details are kept apart so the public directory never exposes them.
create table public.doctor_verification (
  doctor_id  bigint primary key references public.doctors(id) on delete cascade,
  council    text not null,
  reg_no     text not null,
  reg_year   smallint not null check (reg_year between 1950 and 2100)
);

create table public.doctor_documents (
  id            bigint generated always as identity primary key,
  doctor_id     bigint not null references public.doctors(id) on delete cascade,
  kind          text not null check (kind in ('reg','id','deg','photo','clinic')),
  storage_path  text not null,
  file_name     text not null default '',
  created_at    timestamptz not null default now()
);

create table public.clinic_locations (
  id         bigint generated always as identity primary key,
  doctor_id  bigint not null references public.doctors(id) on delete cascade,
  name       text not null default '',
  address    text not null,
  city       text not null,
  pin        text check (pin is null or pin ~ '^[0-9]{6}$'),
  map_url    text check (map_url is null or map_url ~ '^https://(www\.google\.[a-z.]+/maps|maps\.google\.[a-z.]+|maps\.app\.goo\.gl|goo\.gl/maps)'),
  lat        double precision check (lat between -90 and 90),
  lng        double precision check (lng between -180 and 180)
);
create index clinic_locations_doctor_idx on public.clinic_locations (doctor_id);

-- Weekly sessions. weekday follows Postgres dow: 0 = Sunday ... 6 = Saturday. Times are minutes after midnight (IST).
create table public.doctor_availability (
  id         bigint generated always as identity primary key,
  doctor_id  bigint not null references public.doctors(id) on delete cascade,
  weekday    smallint not null check (weekday between 0 and 6),
  start_min  smallint not null check (start_min between 0 and 1439),
  end_min    smallint not null check (end_min between 1 and 1440),
  step_min   smallint not null default 20 check (step_min between 10 and 120),
  check (end_min > start_min)
);
create index doctor_availability_idx on public.doctor_availability (doctor_id, weekday);

-- A day off (slot_time null) or one blocked slot.
create table public.doctor_exceptions (
  id         bigint generated always as identity primary key,
  doctor_id  bigint not null references public.doctors(id) on delete cascade,
  day        date not null,
  slot_time  time,
  unique nulls not distinct (doctor_id, day, slot_time)
);

create table public.platform_settings (
  id               smallint primary key default 1 check (id = 1),
  fee_on           boolean not null default true,
  fee_type         text not null default 'flat' check (fee_type in ('flat','percent')),
  fee_value        numeric(8,2) not null default 49 check (fee_value >= 0),
  support_email    text not null default '',
  support_whatsapp text not null default '',
  check ((fee_type = 'flat' and fee_value <= 5000) or (fee_type = 'percent' and fee_value <= 50))
);
insert into public.platform_settings (id) values (1);

create table public.bookings (
  id                  uuid primary key default gen_random_uuid(),
  ref                 text not null unique,
  patient_id          uuid not null references public.profiles(id),
  doctor_id           bigint not null references public.doctors(id),
  clinic_location_id  bigint references public.clinic_locations(id),
  slot_date           date not null,
  slot_time           time not null,
  mode                text not null check (mode in ('clinic','video')),
  patient_name        text not null check (char_length(patient_name) between 2 and 80),
  patient_age         smallint not null check (patient_age between 0 and 120),
  patient_sex         text not null check (patient_sex in ('Female','Male','Other')),
  patient_phone       text not null check (patient_phone ~ '^[6-9][0-9]{9}$'),
  reason              text not null default '' check (char_length(reason) <= 300),
  doctor_fee          integer not null check (doctor_fee >= 0),
  platform_fee        integer not null default 0 check (platform_fee >= 0),
  status              public.booking_status not null default 'pending',
  decision_reason     text,
  retimed             boolean not null default false,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
-- THE double-booking guard: one active booking per doctor, day and time.
create unique index bookings_no_double_booking
  on public.bookings (doctor_id, slot_date, slot_time)
  where status in ('pending','confirmed');
create index bookings_patient_idx on public.bookings (patient_id, slot_date);
create index bookings_doctor_idx  on public.bookings (doctor_id, slot_date);

create table public.facilities (
  id            bigint generated always as identity primary key,
  user_id       uuid not null unique references public.profiles(id) on delete cascade,
  ref           text not null unique,
  kind          text not null check (kind in ('lab','centre','hospital','other')),
  sub           text not null default '',
  name          text not null check (char_length(name) between 3 and 100),
  city          text not null,
  address       text not null,
  pin           text check (pin is null or pin ~ '^[0-9]{6}$'),
  map_url       text check (map_url is null or map_url ~ '^https://(www\.google\.[a-z.]+/maps|maps\.google\.[a-z.]+|maps\.app\.goo\.gl|goo\.gl/maps)'),
  hours         text not null default '',
  beds          integer check (beds is null or beds between 0 and 20000),
  emergency     boolean not null default false,
  ambulance     boolean not null default false,
  home_service  boolean not null default false,
  services      jsonb not null default '[]'::jsonb,
  wa            text check (wa is null or wa ~ '^[6-9][0-9]{9}$'),
  status        public.review_status not null default 'pending',
  verified      boolean not null default false,
  review_reason text,
  created_at    timestamptz not null default now()
);
create index facilities_listing_idx on public.facilities (status, kind, city);

-- Contact person and licence number are not public.
create table public.facility_private (
  facility_id    bigint primary key references public.facilities(id) on delete cascade,
  contact_name   text not null default '',
  contact_phone  text not null default '',
  licence_no     text not null default ''
);

create table public.leads (
  id          bigint generated always as identity primary key,
  owner_id    uuid not null references public.profiles(id),
  name        text not null check (char_length(name) between 2 and 80),
  phone       text not null check (phone ~ '^[6-9][0-9]{9}$'),
  spec        text not null default '',
  status      text not null default 'new' check (status in ('new','contacted','booked','lost')),
  created_at  timestamptz not null default now()
);

create table public.notifications (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  body        text not null,
  created_at  timestamptz not null default now(),
  read_at     timestamptz
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);

------------------------------------------------------------------------------
-- Helpers (SECURITY DEFINER so policies can use them without recursion)
------------------------------------------------------------------------------
create function public.clinic_now() returns timestamp
language sql stable as $$ select timezone('Asia/Kolkata', now()) $$;

create function public.is_admin() returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.staff_members s where s.user_id = auth.uid() and s.role = 'admin' and s.active)
$$;

create function public.is_sales() returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.staff_members s where s.user_id = auth.uid() and s.role = 'sales' and s.active)
$$;

create function public.my_doctor_id() returns bigint
language sql stable security definer set search_path = public, pg_temp as $$
  select d.id from public.doctors d where d.user_id = auth.uid()
$$;

create function public.my_facility_id() returns bigint
language sql stable security definer set search_path = public, pg_temp as $$
  select f.id from public.facilities f where f.user_id = auth.uid()
$$;

create function public.is_approved_doctor(p_doctor bigint) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from public.doctors d where d.id = p_doctor and d.status = 'approved')
$$;

create function public.notify(p_user uuid, p_body text) returns void
language sql security definer set search_path = public, pg_temp as $$
  insert into public.notifications (user_id, body) values (p_user, left(p_body, 400))
$$;

create function public.new_ref(p_prefix text) returns text
language plpgsql volatile as $$
declare chars constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; r text := ''; i int;
begin
  for i in 1..5 loop r := r || substr(chars, 1 + floor(random() * length(chars))::int, 1); end loop;
  return p_prefix || '-' || r;
end $$;

-- New auth users always start as patients. Role is never read from client-supplied metadata.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  insert into public.profiles (id, role, full_name, phone, email)
  values (new.id, 'patient',
          left(coalesce(new.raw_user_meta_data ->> 'full_name', ''), 80),
          nullif(regexp_replace(coalesce(new.phone, ''), '[^0-9+]', '', 'g'), ''),
          new.email);
  insert into public.patients (id) values (new.id);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

------------------------------------------------------------------------------
-- Slot logic
------------------------------------------------------------------------------
-- Returns 'free' | 'busy' | 'blocked' | 'past' | 'off' | 'invalid'.
create function public.slot_state(p_doctor bigint, p_day date, p_time time, p_exclude uuid default null)
returns text language plpgsql stable security definer set search_path = public, pg_temp as $$
declare m int := extract(hour from p_time)::int * 60 + extract(minute from p_time)::int;
begin
  if extract(second from p_time) <> 0 then return 'invalid'; end if;
  if not exists (
    select 1 from public.doctor_availability a
    where a.doctor_id = p_doctor and a.weekday = extract(dow from p_day)::int
      and m >= a.start_min and m + a.step_min <= a.end_min and (m - a.start_min) % a.step_min = 0
  ) then return 'invalid'; end if;
  if exists (select 1 from public.doctor_exceptions e where e.doctor_id = p_doctor and e.day = p_day and e.slot_time is null) then
    return 'off'; end if;
  if (p_day + p_time) < public.clinic_now() + interval '30 minutes' then return 'past'; end if;
  if exists (select 1 from public.doctor_exceptions e where e.doctor_id = p_doctor and e.day = p_day and e.slot_time = p_time) then
    return 'blocked'; end if;
  if exists (select 1 from public.bookings b where b.doctor_id = p_doctor and b.slot_date = p_day and b.slot_time = p_time
             and b.status in ('pending','confirmed') and b.id is distinct from p_exclude) then
    return 'busy'; end if;
  return 'free';
end $$;

-- What patients see: slot times and a state, never who booked.
create function public.open_slots(p_doctor bigint, p_day date)
returns table (slot_time time, state text)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not public.is_approved_doctor(p_doctor) then return; end if;
  if p_day < (public.clinic_now())::date or p_day > (public.clinic_now())::date + 60 then return; end if;
  return query
    select t.slot_time, public.slot_state(p_doctor, p_day, t.slot_time)
    from (
      select distinct (time '00:00' + make_interval(mins => g))::time as slot_time
      from public.doctor_availability a,
           lateral generate_series(a.start_min::int, (a.end_min - a.step_min)::int, a.step_min::int) g
      where a.doctor_id = p_doctor and a.weekday = extract(dow from p_day)::int
    ) t
    where public.slot_state(p_doctor, p_day, t.slot_time) <> 'off'
    order by t.slot_time;
end $$;

------------------------------------------------------------------------------
-- Booking workflow
------------------------------------------------------------------------------
create function public.create_booking(
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
  pf  := case when not ps.fee_on then 0 when ps.fee_type = 'flat' then round(ps.fee_value)::int
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

create function public.doctor_decide_booking(p_booking uuid, p_decision text, p_time time default null, p_reason text default null)
returns public.bookings language plpgsql security definer set search_path = public, pg_temp as $$
declare did bigint := public.my_doctor_id(); b public.bookings; d public.doctors;
begin
  if did is null then raise exception 'doctors_only'; end if;
  select * into b from public.bookings where id = p_booking and doctor_id = did for update;
  if not found then raise exception 'booking_not_found'; end if;
  if b.status <> 'pending' then raise exception 'not_pending'; end if;
  select * into d from public.doctors where id = did;

  if p_decision = 'confirm' then
    if d.status <> 'approved' then raise exception 'doctor_unavailable'; end if;
    if p_time is not null and p_time <> b.slot_time then
      if public.slot_state(did, b.slot_date, p_time, b.id) <> 'free' then raise exception 'slot_unavailable'; end if;
      begin
        update public.bookings set slot_time = p_time, retimed = true where id = b.id;
      exception when unique_violation then raise exception 'slot_taken';
      end;
    end if;
    update public.bookings set status = 'confirmed', decision_reason = null, updated_at = now() where id = b.id returning * into b;
    perform public.notify(b.patient_id, d.name || ' confirmed your appointment for ' || to_char(b.slot_date, 'DD Mon') || ' ' || to_char(b.slot_time, 'HH12:MI AM') || '. Ref ' || b.ref || '.');
  elsif p_decision = 'reject' then
    update public.bookings set status = 'rejected', decision_reason = left(nullif(trim(coalesce(p_reason,'')), ''), 140), updated_at = now()
      where id = b.id returning * into b;
    perform public.notify(b.patient_id, d.name || ' could not accept your request for ' || to_char(b.slot_date, 'DD Mon') || ' ' || to_char(b.slot_time, 'HH12:MI AM') || coalesce(': ' || b.decision_reason, '.'));
  else
    raise exception 'invalid_decision';
  end if;
  return b;
end $$;

create function public.cancel_booking(p_booking uuid)
returns public.bookings language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); b public.bookings; d public.doctors; who text;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  select * into b from public.bookings where id = p_booking for update;
  if not found then raise exception 'booking_not_found'; end if;
  select * into d from public.doctors where id = b.doctor_id;
  if b.patient_id = uid then who := 'patient';
  elsif d.user_id = uid then who := 'doctor';
  elsif public.is_admin() then who := 'admin';
  else raise exception 'booking_not_found'; end if;   -- do not reveal that it exists
  if b.status not in ('pending','confirmed') then raise exception 'not_cancellable'; end if;
  update public.bookings set status = 'cancelled', updated_at = now() where id = b.id returning * into b;
  if who <> 'patient' then perform public.notify(b.patient_id, 'Your appointment with ' || d.name || ' for ' || to_char(b.slot_date, 'DD Mon') || ' ' || to_char(b.slot_time, 'HH12:MI AM') || ' was cancelled.'); end if;
  if who <> 'doctor'  then perform public.notify(d.user_id, b.patient_name || ' cancelled the appointment for ' || to_char(b.slot_date, 'DD Mon') || ' ' || to_char(b.slot_time, 'HH12:MI AM') || '.'); end if;
  return b;
end $$;

create function public.reschedule_booking(p_booking uuid, p_day date, p_time time)
returns public.bookings language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); b public.bookings; d public.doctors;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  select * into b from public.bookings where id = p_booking and patient_id = uid for update;
  if not found then raise exception 'booking_not_found'; end if;
  if b.status not in ('pending','confirmed') then raise exception 'not_cancellable'; end if;
  case public.slot_state(b.doctor_id, p_day, p_time, b.id)
    when 'free' then null;
    when 'busy' then raise exception 'slot_taken';
    else raise exception 'slot_unavailable';
  end case;
  begin
    update public.bookings set slot_date = p_day, slot_time = p_time, status = 'pending', retimed = false,
           decision_reason = null, updated_at = now() where id = b.id returning * into b;
  exception when unique_violation then raise exception 'slot_taken';
  end;
  select * into d from public.doctors where id = b.doctor_id;
  perform public.notify(d.user_id, 'Rescheduled request from ' || b.patient_name || ' for ' || to_char(p_day, 'DD Mon') || ' ' || to_char(p_time, 'HH12:MI AM') || '. Please approve or reject.');
  return b;
end $$;

create function public.mark_notifications_read() returns void
language sql security definer set search_path = public, pg_temp as $$
  update public.notifications set read_at = now() where user_id = auth.uid() and read_at is null
$$;

------------------------------------------------------------------------------
-- Registration and review
------------------------------------------------------------------------------
-- p example: {"name","spec","qual","exp_years","fee_inr","video_fee_inr","languages","about","clinic","city",
--   "address","pin","map_url","lat","lng","wa","council","reg_no","reg_year",
--   "days":[1,2,3],"sessions":[{"s":600,"e":780}],"step":20}
create function public.register_doctor(p jsonb) returns public.doctors
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); d public.doctors; day int; sess jsonb;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.profiles where id = uid and role = 'patient') then raise exception 'already_registered'; end if;
  if exists (select 1 from public.bookings where patient_id = uid) then raise exception 'account_has_bookings'; end if;
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

  update public.profiles set role = 'doctor', full_name = d.name where id = uid;
  return d;
end $$;

-- p example: {"kind","sub","name","contact_name","contact_phone","city","address","pin","map_url","hours","beds",
--   "emergency","ambulance","home_service","services":[...],"wa","licence_no"}
create function public.register_facility(p jsonb) returns public.facilities
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); f public.facilities;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.profiles where id = uid and role = 'patient') then raise exception 'already_registered'; end if;
  if exists (select 1 from public.bookings where patient_id = uid) then raise exception 'account_has_bookings'; end if;
  insert into public.facilities (user_id, ref, kind, sub, name, city, address, pin, map_url, hours, beds,
                                 emergency, ambulance, home_service, services, wa)
  values (uid, public.new_ref('FC'), p ->> 'kind', coalesce(p ->> 'sub', ''), trim(p ->> 'name'), p ->> 'city', p ->> 'address', nullif(p ->> 'pin', ''), nullif(p ->> 'map_url', ''),
          coalesce(p ->> 'hours', ''), nullif(p ->> 'beds', '')::int, coalesce((p ->> 'emergency')::boolean, false),
          coalesce((p ->> 'ambulance')::boolean, false), coalesce((p ->> 'home_service')::boolean, false),
          coalesce(p -> 'services', '[]'::jsonb), nullif(p ->> 'wa', ''))
  returning * into f;
  insert into public.facility_private (facility_id, contact_name, contact_phone, licence_no)
  values (f.id, coalesce(p ->> 'contact_name', ''), coalesce(p ->> 'contact_phone', ''), coalesce(p ->> 'licence_no', ''));
  update public.profiles set role = 'facility', full_name = f.name where id = uid;
  return f;
end $$;

create function public.admin_review_doctor(p_doctor bigint, p_decision text, p_verified boolean default true, p_reason text default null)
returns public.doctors language plpgsql security definer set search_path = public, pg_temp as $$
declare d public.doctors;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  if p_decision = 'approve' then
    update public.doctors set status = 'approved', verified = coalesce(p_verified, true), review_reason = null where id = p_doctor returning * into d;
  elsif p_decision = 'reject' then
    update public.doctors set status = 'rejected', verified = false, review_reason = left(p_reason, 200) where id = p_doctor returning * into d;
  else raise exception 'invalid_decision'; end if;
  if not found then raise exception 'doctor_not_found'; end if;
  perform public.notify(d.user_id, case when d.status = 'approved' then 'Your profile was approved and is now visible to patients.'
                                        else 'Your profile was not approved' || coalesce(': ' || d.review_reason, '.') end);
  return d;
end $$;

create function public.admin_review_facility(p_facility bigint, p_decision text, p_verified boolean default true, p_reason text default null)
returns public.facilities language plpgsql security definer set search_path = public, pg_temp as $$
declare f public.facilities;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  if p_decision = 'approve' then
    update public.facilities set status = 'approved', verified = coalesce(p_verified, true), review_reason = null where id = p_facility returning * into f;
  elsif p_decision = 'reject' then
    update public.facilities set status = 'rejected', verified = false, review_reason = left(p_reason, 200) where id = p_facility returning * into f;
  else raise exception 'invalid_decision'; end if;
  if not found then raise exception 'facility_not_found'; end if;
  perform public.notify(f.user_id, case when f.status = 'approved' then 'Your listing was approved and is now visible.'
                                        else 'Your listing was not approved' || coalesce(': ' || f.review_reason, '.') end);
  return f;
end $$;

create function public.admin_set_staff(p_user uuid, p_role text, p_active boolean default true, p_target numeric default 0)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  if p_role not in ('sales','admin') then raise exception 'invalid_role'; end if;
  if p_user = auth.uid() and (p_role <> 'admin' or not p_active) then raise exception 'cannot_demote_self'; end if;
  if exists (select 1 from public.doctors where user_id = p_user) or exists (select 1 from public.facilities where user_id = p_user) then
    raise exception 'user_is_doctor_or_facility'; end if;
  update public.profiles set role = p_role::public.app_role where id = p_user;
  if not found then raise exception 'user_not_found'; end if;
  insert into public.staff_members (user_id, role, active, monthly_target) values (p_user, p_role::public.app_role, p_active, coalesce(p_target, 0))
  on conflict (user_id) do update set role = excluded.role, active = excluded.active, monthly_target = excluded.monthly_target;
end $$;

------------------------------------------------------------------------------
-- Row Level Security
------------------------------------------------------------------------------
alter table public.profiles            enable row level security;
alter table public.patients            enable row level security;
alter table public.staff_members       enable row level security;
alter table public.doctors             enable row level security;
alter table public.doctor_verification enable row level security;
alter table public.doctor_documents    enable row level security;
alter table public.clinic_locations    enable row level security;
alter table public.doctor_availability enable row level security;
alter table public.doctor_exceptions   enable row level security;
alter table public.platform_settings   enable row level security;
alter table public.bookings            enable row level security;
alter table public.facilities          enable row level security;
alter table public.facility_private    enable row level security;
alter table public.leads               enable row level security;
alter table public.notifications       enable row level security;

create policy profiles_read   on public.profiles for select using (id = auth.uid() or public.is_admin());
create policy profiles_update on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

create policy patients_read   on public.patients for select using (id = auth.uid() or public.is_admin());
create policy patients_update on public.patients for update using (id = auth.uid()) with check (id = auth.uid());

create policy staff_read on public.staff_members for select using (user_id = auth.uid() or public.is_admin());

create policy doctors_read on public.doctors for select
  using (status = 'approved' or user_id = auth.uid() or public.is_admin());
create policy doctors_update on public.doctors for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy dverif_read on public.doctor_verification for select
  using (doctor_id = public.my_doctor_id() or public.is_admin());
create policy ddocs_read on public.doctor_documents for select
  using (doctor_id = public.my_doctor_id() or public.is_admin());
create policy ddocs_insert on public.doctor_documents for insert with check (doctor_id = public.my_doctor_id());

create policy loc_read on public.clinic_locations for select
  using (public.is_approved_doctor(doctor_id) or doctor_id = public.my_doctor_id() or public.is_admin());
create policy loc_write on public.clinic_locations for all
  using (doctor_id = public.my_doctor_id()) with check (doctor_id = public.my_doctor_id());

create policy avail_read on public.doctor_availability for select
  using (public.is_approved_doctor(doctor_id) or doctor_id = public.my_doctor_id() or public.is_admin());
create policy avail_write on public.doctor_availability for all
  using (doctor_id = public.my_doctor_id()) with check (doctor_id = public.my_doctor_id());

create policy exc_read on public.doctor_exceptions for select
  using (doctor_id = public.my_doctor_id() or public.is_admin());
create policy exc_write on public.doctor_exceptions for all
  using (doctor_id = public.my_doctor_id()) with check (doctor_id = public.my_doctor_id());

create policy settings_read   on public.platform_settings for select using (true);
create policy settings_update on public.platform_settings for update using (public.is_admin()) with check (public.is_admin());

create policy bookings_read on public.bookings for select
  using (patient_id = auth.uid() or doctor_id = public.my_doctor_id() or public.is_admin());

create policy fac_read on public.facilities for select
  using (status = 'approved' or user_id = auth.uid() or public.is_admin());
create policy facpriv_read on public.facility_private for select
  using (facility_id = public.my_facility_id() or public.is_admin());
create policy facpriv_update on public.facility_private for update
  using (facility_id = public.my_facility_id()) with check (facility_id = public.my_facility_id());
create policy fac_update on public.facilities for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy leads_read   on public.leads for select using ((owner_id = auth.uid() and public.is_sales()) or public.is_admin());
create policy leads_insert on public.leads for insert with check ((owner_id = auth.uid() and public.is_sales()) or public.is_admin());
create policy leads_update on public.leads for update
  using ((owner_id = auth.uid() and public.is_sales()) or public.is_admin())
  with check ((owner_id = auth.uid() and public.is_sales()) or public.is_admin());

create policy notif_read   on public.notifications for select using (user_id = auth.uid());
create policy notif_update on public.notifications for update using (user_id = auth.uid()) with check (user_id = auth.uid());

------------------------------------------------------------------------------
-- Grants (least privilege): start from nothing, then add exactly what the app needs.
------------------------------------------------------------------------------
revoke all on all tables    in schema public from public, anon, authenticated;
revoke all on all sequences in schema public from public, anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
alter default privileges in schema public revoke all on tables    from anon, authenticated;
alter default privileges in schema public revoke all on functions from public, anon, authenticated;

grant usage on schema public to anon, authenticated;

-- Public directory: only safe columns.
grant select (id, name, spec, qual, exp_years, fee_inr, video_fee_inr, video, languages, about, clinic, city, photo_path, wa, status, verified, review_reason, ref)
  on public.doctors to anon, authenticated;
grant select (id, doctor_id, name, address, city, pin, map_url, lat, lng) on public.clinic_locations to anon, authenticated;
grant select on public.doctor_availability to anon, authenticated;
grant select (id, kind, sub, name, city, address, pin, map_url, hours, beds, emergency, ambulance, home_service, services, wa, status, verified, review_reason, ref)
  on public.facilities to anon, authenticated;
grant select on public.platform_settings to anon, authenticated;

-- Signed-in users.
grant select on public.profiles, public.patients, public.staff_members, public.bookings, public.notifications,
                public.doctor_exceptions, public.doctor_verification, public.doctor_documents, public.leads, public.facility_private to authenticated;
grant update (contact_name, contact_phone) on public.facility_private to authenticated;
grant update (full_name, phone, email) on public.profiles to authenticated;
grant update (age, sex, photo_path)    on public.patients to authenticated;
grant update (qual, exp_years, fee_inr, video_fee_inr, languages, about, clinic, photo_path, wa) on public.doctors to authenticated;
grant update (sub, name, address, pin, map_url, hours, beds, emergency, ambulance, home_service, services, wa)
  on public.facilities to authenticated;
grant insert, update, delete on public.clinic_locations, public.doctor_availability, public.doctor_exceptions to authenticated;
grant insert on public.doctor_documents to authenticated;
grant insert, update on public.leads to authenticated;
grant update (read_at) on public.notifications to authenticated;
grant update (fee_on, fee_type, fee_value, support_email, support_whatsapp) on public.platform_settings to authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- Functions the app may call.
grant execute on function public.open_slots(bigint, date) to anon, authenticated;
grant execute on function public.create_booking(bigint, date, time, text, text, int, text, text, text) to authenticated;
grant execute on function public.doctor_decide_booking(uuid, text, time, text) to authenticated;
grant execute on function public.cancel_booking(uuid) to authenticated;
grant execute on function public.reschedule_booking(uuid, date, time) to authenticated;
grant execute on function public.mark_notifications_read() to authenticated;
grant execute on function public.register_doctor(jsonb) to authenticated;
grant execute on function public.register_facility(jsonb) to authenticated;
grant execute on function public.admin_review_doctor(bigint, text, boolean, text) to authenticated;
grant execute on function public.admin_review_facility(bigint, text, boolean, text) to authenticated;
grant execute on function public.admin_set_staff(uuid, text, boolean, numeric) to authenticated;
-- Used inside policies, so the signed-in role needs them.
grant execute on function public.is_admin(), public.is_sales(), public.my_doctor_id(), public.my_facility_id(), public.is_approved_doctor(bigint), public.clinic_now() to anon, authenticated;
