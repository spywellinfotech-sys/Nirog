-- Promotion contact list for the super admin: doctors, hospitals, labs, pharmacies to invite by WhatsApp, email or call.
-- These people are NOT app users. The list is separate from the registered doctors and facilities.
create table public.prospects (
  id               bigint generated always as identity primary key,
  kind             text not null default 'doctor' check (kind in ('doctor','hospital','lab','pharmacy','centre','other')),
  name             text not null check (char_length(name) between 2 and 120),
  phone            text check (phone ~ '^[6-9][0-9]{9}$'),
  email            text check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' and char_length(email) <= 120),
  city             text not null default '' check (char_length(city) <= 60),
  spec             text not null default '' check (char_length(spec) <= 80),
  status           text not null default 'new' check (status in ('new','messaged','interested','enrolled','not_interested')),
  last_messaged_at timestamptz,
  msg_count        integer not null default 0,
  note             text not null default '' check (char_length(note) <= 300),
  created_at       timestamptz not null default now(),
  check (phone is not null or email is not null)
);
create unique index prospects_phone_uq on public.prospects (phone) where phone is not null;
create unique index prospects_email_uq on public.prospects (lower(email)) where email is not null;
alter table public.prospects enable row level security;
revoke all on public.prospects from anon, authenticated;
create policy prospects_admin_read on public.prospects for select to authenticated using (public.is_admin());
grant select on public.prospects to authenticated;

-- p_rows: [{kind,name,phone,email,city,spec}]. Returns how many were added, skipped as duplicates, or invalid.
create or replace function public.admin_import_prospects(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare r jsonb; ph text; em text; k text; nm text; added int := 0; dup int := 0; bad int := 0; n int;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  if jsonb_typeof(p_rows) <> 'array' then raise exception 'invalid_rows'; end if;
  if jsonb_array_length(p_rows) > 500 then raise exception 'too_many_rows'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    nm := left(btrim(coalesce(r ->> 'name','')), 120);
    ph := right(regexp_replace(coalesce(r ->> 'phone',''), '\D', '', 'g'), 10);
    if ph !~ '^[6-9][0-9]{9}$' then ph := null; end if;
    em := nullif(lower(btrim(coalesce(r ->> 'email',''))), '');
    if em is not null and em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then em := null; end if;
    k := lower(btrim(coalesce(r ->> 'kind','doctor')));
    if k not in ('doctor','hospital','lab','pharmacy','centre','other') then k := 'other'; end if;
    if char_length(nm) < 2 or (ph is null and em is null) then bad := bad + 1; continue; end if;
    begin
      insert into public.prospects (kind, name, phone, email, city, spec)
        values (k, nm, ph, em, left(btrim(coalesce(r ->> 'city','')), 60), left(btrim(coalesce(r ->> 'spec','')), 80));
      added := added + 1;
    exception when unique_violation then dup := dup + 1;
    end;
  end loop;
  return jsonb_build_object('added', added, 'duplicates', dup, 'invalid', bad);
end $$;

create or replace function public.admin_prospect_messaged(p_id bigint) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  update public.prospects set last_messaged_at = now(), msg_count = msg_count + 1,
    status = case when status = 'new' then 'messaged' else status end where id = p_id;
  if not found then raise exception 'not_found'; end if;
end $$;

create or replace function public.admin_set_prospect(p_id bigint, p_status text, p_note text default null) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  if p_status not in ('new','messaged','interested','enrolled','not_interested') then raise exception 'invalid_status'; end if;
  update public.prospects set status = p_status, note = coalesce(left(btrim(p_note), 300), note) where id = p_id;
  if not found then raise exception 'not_found'; end if;
end $$;

create or replace function public.admin_delete_prospect(p_id bigint) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  delete from public.prospects where id = p_id;
end $$;

revoke all on function public.admin_import_prospects(jsonb), public.admin_prospect_messaged(bigint), public.admin_set_prospect(bigint, text, text), public.admin_delete_prospect(bigint) from public, anon;
grant execute on function public.admin_import_prospects(jsonb), public.admin_prospect_messaged(bigint), public.admin_set_prospect(bigint, text, text), public.admin_delete_prospect(bigint) to authenticated;
