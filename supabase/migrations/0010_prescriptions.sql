-- Online prescriptions: typed (medicines, advice, follow-up) and/or photos of a handwritten prescription.
-- Only the doctor of a confirmed booking whose visit day has arrived can write one. The patient, that doctor and admins can read it.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('prescriptions', 'prescriptions', false, 5242880, array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

create table if not exists public.prescriptions (
  id bigint generated always as identity primary key,
  booking_id uuid not null unique references public.bookings(id) on delete cascade,
  doctor_id bigint not null references public.doctors(id),
  patient_id uuid not null references public.profiles(id),
  diagnosis text not null default '' check (char_length(diagnosis) <= 300),
  medicines jsonb not null default '[]' check (jsonb_typeof(medicines) = 'array' and jsonb_array_length(medicines) <= 15),
  advice text not null default '' check (char_length(advice) <= 1000),
  follow_up date,
  files text[] not null default '{}' check (cardinality(files) <= 4),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.prescriptions enable row level security;
revoke all on public.prescriptions from anon, authenticated;
grant select on public.prescriptions to authenticated;
drop policy if exists rx_read on public.prescriptions;
create policy rx_read on public.prescriptions for select to authenticated
  using (patient_id = auth.uid() or doctor_id = public.my_doctor_id() or public.is_admin());

-- Files live under <booking id>/<file name>.
drop policy if exists rx_obj_read on storage.objects;
create policy rx_obj_read on storage.objects for select to authenticated using (
  bucket_id = 'prescriptions' and (public.is_admin() or exists (
    select 1 from public.bookings b where b.id::text = (storage.foldername(name))[1]
      and (b.patient_id = auth.uid() or b.doctor_id = public.my_doctor_id()))));
drop policy if exists rx_obj_write on storage.objects;
create policy rx_obj_write on storage.objects for insert to authenticated with check (
  bucket_id = 'prescriptions' and exists (
    select 1 from public.bookings b where b.id::text = (storage.foldername(name))[1]
      and b.doctor_id = public.my_doctor_id() and b.status = 'confirmed'));
drop policy if exists rx_obj_update on storage.objects;
create policy rx_obj_update on storage.objects for update to authenticated using (
  bucket_id = 'prescriptions' and exists (
    select 1 from public.bookings b where b.id::text = (storage.foldername(name))[1]
      and b.doctor_id = public.my_doctor_id() and b.status = 'confirmed'));
drop policy if exists rx_obj_delete on storage.objects;
create policy rx_obj_delete on storage.objects for delete to authenticated using (
  bucket_id = 'prescriptions' and exists (
    select 1 from public.bookings b where b.id::text = (storage.foldername(name))[1]
      and b.doctor_id = public.my_doctor_id()));

create or replace function public.save_prescription(p jsonb) returns public.prescriptions
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  did bigint := public.my_doctor_id(); bid uuid; b public.bookings; d public.doctors; r public.prescriptions;
  meds jsonb := coalesce(p->'medicines', '[]'); m jsonb; clean jsonb := '[]'; fl text[] := '{}'; f text; fu date; dx text; adv text; existed boolean;
begin
  if did is null then raise exception 'doctors_only'; end if;
  begin bid := (p->>'booking_id')::uuid; exception when others then raise exception 'booking_not_found'; end;
  select * into b from public.bookings where id = bid and doctor_id = did;
  if not found then raise exception 'booking_not_found'; end if;
  if b.status <> 'confirmed' then raise exception 'booking_not_confirmed'; end if;
  if b.slot_date > public.clinic_now()::date then raise exception 'visit_not_started'; end if;

  if jsonb_typeof(meds) <> 'array' or jsonb_array_length(meds) > 15 then raise exception 'too_many_medicines'; end if;
  for m in select * from jsonb_array_elements(meds) loop
    if length(trim(coalesce(m->>'name',''))) = 0 then continue; end if;
    clean := clean || jsonb_build_array(jsonb_build_object(
      'name', left(trim(m->>'name'), 80), 'dose', left(trim(coalesce(m->>'dose','')), 40),
      'freq', left(trim(coalesce(m->>'freq','')), 60), 'days', left(trim(coalesce(m->>'days','')), 30),
      'notes', left(trim(coalesce(m->>'notes','')), 120)));
  end loop;
  if jsonb_typeof(coalesce(p->'files','[]')) <> 'array' then raise exception 'invalid_files'; end if;
  for f in select jsonb_array_elements_text(coalesce(p->'files','[]')) loop
    if f !~ ('^' || bid::text || '/[A-Za-z0-9._-]{1,80}$') then raise exception 'invalid_files'; end if;
    fl := fl || f;
  end loop;
  if cardinality(fl) > 4 then raise exception 'too_many_files'; end if;
  begin fu := nullif(p->>'follow_up','')::date; exception when others then raise exception 'invalid_follow_up'; end;
  if fu is not null and fu < public.clinic_now()::date then raise exception 'invalid_follow_up'; end if;
  dx := left(trim(coalesce(p->>'diagnosis','')), 300); adv := left(trim(coalesce(p->>'advice','')), 1000);
  if dx = '' and adv = '' and jsonb_array_length(clean) = 0 and cardinality(fl) = 0 then raise exception 'empty_prescription'; end if;

  select exists (select 1 from public.prescriptions where booking_id = bid) into existed;
  insert into public.prescriptions (booking_id, doctor_id, patient_id, diagnosis, medicines, advice, follow_up, files)
  values (bid, did, b.patient_id, dx, clean, adv, fu, fl)
  on conflict (booking_id) do update set diagnosis = excluded.diagnosis, medicines = excluded.medicines, advice = excluded.advice,
    follow_up = excluded.follow_up, files = excluded.files, updated_at = now()
  returning * into r;
  select * into d from public.doctors where id = did;
  perform public.notify(b.patient_id, case when existed then 'Your prescription from ' || d.name || ' was updated. Open Appointments to view it.'
                                           else d.name || ' has shared your prescription. Open Appointments to view it.' end);
  return r;
end $$;
revoke all on function public.save_prescription(jsonb) from public, anon;
grant execute on function public.save_prescription(jsonb) to authenticated;
