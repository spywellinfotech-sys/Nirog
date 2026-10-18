-- Appointment requests to labs, diagnostic centres and hospitals. Patient sends a request, the facility confirms or rejects, admin sees counts.
create table public.facility_requests (
  id             bigint generated always as identity primary key,
  ref            text not null unique,
  facility_id    bigint not null references public.facilities(id) on delete cascade,
  patient_id     uuid not null references public.profiles(id) on delete cascade,
  patient_name   text not null,
  patient_phone  text not null,
  item           text not null check (char_length(item) between 2 and 120),
  preferred_date date not null,
  note           text not null default '' check (char_length(note) <= 300),
  status         text not null default 'pending' check (status in ('pending','confirmed','rejected','cancelled')),
  reason         text not null default '' check (char_length(reason) <= 200),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index facility_requests_fac_idx on public.facility_requests (facility_id, created_at desc);
create index facility_requests_pat_idx on public.facility_requests (patient_id, created_at desc);
alter table public.facility_requests enable row level security;
revoke all on public.facility_requests from anon, authenticated;
create policy fr_read_patient on public.facility_requests for select to authenticated using (patient_id = auth.uid());
create policy fr_read_facility on public.facility_requests for select to authenticated using (facility_id = public.my_facility_id());
grant select on public.facility_requests to authenticated;

create or replace function public.create_facility_request(p_facility bigint, p_item text, p_date date, p_name text, p_phone text, p_note text default '')
returns text language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); f record; r text; n int;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.profiles where id = uid and role = 'patient') then raise exception 'not_a_patient'; end if;
  select id, user_id, name, kind into f from public.facilities where id = p_facility and status = 'approved' and kind in ('lab','centre','hospital');
  if f.id is null then raise exception 'facility_unavailable'; end if;
  if char_length(btrim(coalesce(p_item,''))) < 2 then raise exception 'invalid_item'; end if;
  if char_length(btrim(coalesce(p_name,''))) < 2 then raise exception 'invalid_name'; end if;
  if coalesce(p_phone,'') !~ '^[6-9][0-9]{9}$' then raise exception 'invalid_phone'; end if;
  if p_date is null or p_date < public.clinic_now()::date or p_date > public.clinic_now()::date + 60 then raise exception 'invalid_date'; end if;
  select count(*) into n from public.facility_requests where patient_id = uid and status = 'pending';
  if n >= 5 then raise exception 'too_many_requests'; end if;
  r := public.new_ref('FR');
  insert into public.facility_requests (ref, facility_id, patient_id, patient_name, patient_phone, item, preferred_date, note)
    values (r, f.id, uid, left(btrim(p_name),80), p_phone, left(btrim(p_item),120), p_date, left(btrim(coalesce(p_note,'')),300));
  perform public.notify(f.user_id, 'New appointment request ' || r || ': ' || left(btrim(p_item),60) || ' on ' || to_char(p_date,'DD Mon'));
  return r;
end $$;

create or replace function public.decide_facility_request(p_id bigint, p_status text, p_reason text default '')
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare q public.facility_requests; fname text;
begin
  if p_status not in ('confirmed','rejected') then raise exception 'invalid_status'; end if;
  select * into q from public.facility_requests where id = p_id and facility_id = public.my_facility_id();
  if q.id is null then raise exception 'not_found'; end if;
  if q.status <> 'pending' then raise exception 'already_decided'; end if;
  update public.facility_requests set status = p_status, reason = left(btrim(coalesce(p_reason,'')),200), updated_at = now() where id = p_id;
  select name into fname from public.facilities where id = q.facility_id;
  perform public.notify(q.patient_id, case when p_status = 'confirmed' then fname || ' confirmed your request ' || q.ref || ' for ' || to_char(q.preferred_date,'DD Mon') || '.'
    else fname || ' could not accept your request ' || q.ref || '.' end);
end $$;

create or replace function public.cancel_facility_request(p_id bigint) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.facility_requests set status = 'cancelled', updated_at = now()
    where id = p_id and patient_id = auth.uid() and status in ('pending','confirmed');
  if not found then raise exception 'not_found'; end if;
end $$;

create or replace function public.admin_request_stats() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  return coalesce((select jsonb_object_agg(facility_id::text, jsonb_build_object('total', total, 'pending', pend, 'confirmed', conf, 'rejected', rej, 'last30', l30))
    from (select facility_id, count(*) as total, count(*) filter (where status='pending') as pend, count(*) filter (where status='confirmed') as conf,
                 count(*) filter (where status='rejected') as rej, count(*) filter (where created_at > now() - interval '30 days') as l30
          from public.facility_requests group by facility_id) s), '{}'::jsonb);
end $$;

revoke all on function public.create_facility_request(bigint,text,date,text,text,text), public.decide_facility_request(bigint,text,text), public.cancel_facility_request(bigint), public.admin_request_stats() from public, anon;
grant execute on function public.create_facility_request(bigint,text,date,text,text,text), public.decide_facility_request(bigint,text,text), public.cancel_facility_request(bigint), public.admin_request_stats() to authenticated;

-- Erasure also wipes these requests (patient's own delete and admin erase).
do $$
declare d text;
begin
  d := pg_get_functiondef('public.delete_my_account()'::regprocedure);
  d := replace(d, 'delete from public.prescriptions where patient_id = uid;', 'delete from public.prescriptions where patient_id = uid; delete from public.facility_requests where patient_id = uid;');
  execute d;
  d := pg_get_functiondef('public.admin_delete_patient(uuid)'::regprocedure);
  d := replace(d, 'delete from public.prescriptions where patient_id = p_user;', 'delete from public.prescriptions where patient_id = p_user; delete from public.facility_requests where patient_id = p_user;');
  execute d;
end $$;
