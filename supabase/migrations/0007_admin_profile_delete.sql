-- Admin: full profile view and delete for doctors and facilities.
create or replace function public.admin_profile(p_kind text, p_id bigint) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare r jsonb;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  if p_kind = 'doctor' then
    select jsonb_build_object(
      'kind', 'doctor', 'row', to_jsonb(d), 'email', pr.email, 'phone', pr.phone,
      'verification', (select to_jsonb(v) from public.doctor_verification v where v.doctor_id = d.id),
      'locations', coalesce((select jsonb_agg(to_jsonb(l)) from public.clinic_locations l where l.doctor_id = d.id), '[]'),
      'availability', coalesce((select jsonb_agg(jsonb_build_object('weekday', a.weekday, 'start_min', a.start_min, 'end_min', a.end_min, 'step_min', a.step_min) order by a.weekday, a.start_min) from public.doctor_availability a where a.doctor_id = d.id), '[]'),
      'docs', coalesce((select jsonb_agg(jsonb_build_object('kind', x.kind, 'storage_path', x.storage_path, 'file_name', x.file_name)) from public.doctor_documents x where x.doctor_id = d.id), '[]'),
      'bookings', (select count(*) from public.bookings b where b.doctor_id = d.id))
    into r
    from public.doctors d left join public.profiles pr on pr.id = d.user_id where d.id = p_id;
  elsif p_kind = 'facility' then
    select jsonb_build_object(
      'kind', 'facility', 'row', to_jsonb(f), 'email', pr.email, 'phone', pr.phone,
      'private', (select to_jsonb(fp) from public.facility_private fp where fp.facility_id = f.id),
      'docs', coalesce((select jsonb_agg(jsonb_build_object('kind', x.kind, 'storage_path', x.storage_path, 'file_name', x.file_name)) from public.facility_documents x where x.facility_id = f.id), '[]'))
    into r
    from public.facilities f left join public.profiles pr on pr.id = f.user_id where f.id = p_id;
  else raise exception 'invalid_kind'; end if;
  if r is null then raise exception 'not_found'; end if;
  return r;
end $$;

create or replace function public.admin_delete_doctor(p_doctor bigint) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  select user_id into uid from public.doctors where id = p_doctor;
  if uid is null then raise exception 'not_found'; end if;
  if exists (select 1 from public.bookings where doctor_id = p_doctor) then raise exception 'has_bookings'; end if;
  delete from public.doctor_exceptions where doctor_id = p_doctor;
  delete from public.doctor_availability where doctor_id = p_doctor;
  delete from public.clinic_locations where doctor_id = p_doctor;
  delete from public.doctor_documents where doctor_id = p_doctor;
  delete from public.doctor_verification where doctor_id = p_doctor;
  delete from public.doctors where id = p_doctor;
  begin
    perform set_config('storage.allow_delete_query', 'true', true);
    delete from storage.objects where bucket_id in ('doctor-media', 'verification-docs') and name like uid::text || '/%';
  exception when others then null;
  end;
  update public.profiles set role = 'patient', phone = null where id = uid and role = 'doctor';
  return true;
end $$;

create or replace function public.admin_delete_facility(p_facility bigint) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  select user_id into uid from public.facilities where id = p_facility;
  if uid is null then raise exception 'not_found'; end if;
  delete from public.facility_documents where facility_id = p_facility;
  delete from public.facility_private where facility_id = p_facility;
  delete from public.facilities where id = p_facility;
  begin
    perform set_config('storage.allow_delete_query', 'true', true);
    delete from storage.objects where bucket_id in ('doctor-media', 'verification-docs') and name like uid::text || '/%';
  exception when others then null;
  end;
  update public.profiles set role = 'patient', phone = null where id = uid and role = 'facility';
  return true;
end $$;

-- p holds only the fields to change. Doctor: name, spec, qual, exp_years, fee_inr, video_fee_inr, languages, about, clinic, city, wa,
-- phone, address, pin, map_url, council, reg_no, reg_year. Facility: name, sub, city, address, pin, map_url, hours, beds, emergency,
-- ambulance, home_service, wa, contact_name, contact_phone, licence_no.
create or replace function public.admin_update_doctor(p_doctor bigint, p jsonb) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  select user_id into uid from public.doctors where id = p_doctor;
  if uid is null then raise exception 'not_found'; end if;
  if p ? 'phone' then
    if not ((p ->> 'phone') ~ '^[6-9][0-9]{9}$') then raise exception 'invalid_phone'; end if;
    if exists (select 1 from public.profiles where phone = '+91' || (p ->> 'phone') and id <> uid) then raise exception 'phone_in_use'; end if;
    update public.profiles set phone = '+91' || (p ->> 'phone') where id = uid;
  end if;
  update public.doctors set
    name = case when p ? 'name' then trim(p ->> 'name') else name end,
    spec = case when p ? 'spec' then trim(p ->> 'spec') else spec end,
    qual = case when p ? 'qual' then coalesce(p ->> 'qual', '') else qual end,
    exp_years = case when p ? 'exp_years' then (p ->> 'exp_years')::int else exp_years end,
    fee_inr = case when p ? 'fee_inr' then (p ->> 'fee_inr')::int else fee_inr end,
    video_fee_inr = case when p ? 'video_fee_inr' then coalesce((p ->> 'video_fee_inr')::int, 0) else video_fee_inr end,
    languages = case when p ? 'languages' then coalesce(nullif(p ->> 'languages', ''), 'Hindi, English') else languages end,
    about = case when p ? 'about' then coalesce(p ->> 'about', '') else about end,
    clinic = case when p ? 'clinic' then coalesce(p ->> 'clinic', '') else clinic end,
    city = case when p ? 'city' then p ->> 'city' else city end,
    wa = case when p ? 'wa' then nullif(p ->> 'wa', '') else wa end
  where id = p_doctor;
  update public.clinic_locations set
    name = case when p ? 'clinic' then coalesce(p ->> 'clinic', '') else name end,
    city = case when p ? 'city' then p ->> 'city' else city end,
    address = case when p ? 'address' then p ->> 'address' else address end,
    pin = case when p ? 'pin' then nullif(p ->> 'pin', '') else pin end,
    map_url = case when p ? 'map_url' then nullif(p ->> 'map_url', '') else map_url end
  where doctor_id = p_doctor;
  update public.doctor_verification set
    council = case when p ? 'council' then trim(p ->> 'council') else council end,
    reg_no = case when p ? 'reg_no' then trim(p ->> 'reg_no') else reg_no end,
    reg_year = case when p ? 'reg_year' then (p ->> 'reg_year')::int else reg_year end
  where doctor_id = p_doctor;
  if p ? 'name' then update public.profiles set full_name = trim(p ->> 'name') where id = uid; end if;
  return true;
end $$;

create or replace function public.admin_update_facility(p_facility bigint, p jsonb) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  select user_id into uid from public.facilities where id = p_facility;
  if uid is null then raise exception 'not_found'; end if;
  if p ? 'contact_phone' then
    if not ((p ->> 'contact_phone') ~ '^[6-9][0-9]{9}$') then raise exception 'invalid_phone'; end if;
    if exists (select 1 from public.profiles where phone = '+91' || (p ->> 'contact_phone') and id <> uid) then raise exception 'phone_in_use'; end if;
    update public.profiles set phone = '+91' || (p ->> 'contact_phone') where id = uid;
  end if;
  update public.facilities set
    name = case when p ? 'name' then trim(p ->> 'name') else name end,
    sub = case when p ? 'sub' then coalesce(p ->> 'sub', '') else sub end,
    city = case when p ? 'city' then p ->> 'city' else city end,
    address = case when p ? 'address' then p ->> 'address' else address end,
    pin = case when p ? 'pin' then nullif(p ->> 'pin', '') else pin end,
    map_url = case when p ? 'map_url' then nullif(p ->> 'map_url', '') else map_url end,
    hours = case when p ? 'hours' then coalesce(p ->> 'hours', '') else hours end,
    beds = case when p ? 'beds' then nullif(p ->> 'beds', '')::int else beds end,
    emergency = case when p ? 'emergency' then (p ->> 'emergency')::boolean else emergency end,
    ambulance = case when p ? 'ambulance' then (p ->> 'ambulance')::boolean else ambulance end,
    home_service = case when p ? 'home_service' then (p ->> 'home_service')::boolean else home_service end,
    wa = case when p ? 'wa' then nullif(p ->> 'wa', '') else wa end
  where id = p_facility;
  update public.facility_private set
    contact_name = case when p ? 'contact_name' then coalesce(p ->> 'contact_name', '') else contact_name end,
    contact_phone = case when p ? 'contact_phone' then p ->> 'contact_phone' else contact_phone end,
    licence_no = case when p ? 'licence_no' then coalesce(p ->> 'licence_no', '') else licence_no end
  where facility_id = p_facility;
  if p ? 'name' then update public.profiles set full_name = trim(p ->> 'name') where id = uid; end if;
  return true;
end $$;

revoke all on function public.admin_profile(text, bigint), public.admin_delete_doctor(bigint), public.admin_delete_facility(bigint), public.admin_update_doctor(bigint, jsonb), public.admin_update_facility(bigint, jsonb) from public, anon;
grant execute on function public.admin_profile(text, bigint), public.admin_delete_doctor(bigint), public.admin_delete_facility(bigint), public.admin_update_doctor(bigint, jsonb), public.admin_update_facility(bigint, jsonb) to authenticated;
