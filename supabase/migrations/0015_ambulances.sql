-- Ambulance directory. Anyone can read active entries; only the super admin adds, edits or removes them.
-- A blank city means the service is listed in every location.
create table if not exists public.ambulance_services (
  id bigint generated always as identity primary key,
  name text not null check (char_length(name) between 3 and 80),
  phone text not null check (phone ~ '^\+?[0-9][0-9 -]{2,14}$'),
  city text check (city is null or char_length(city) between 1 and 60),
  kind text not null default 'private' check (kind in ('govt','private')),
  note text not null default '' check (char_length(note) <= 120),
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.ambulance_services enable row level security;
revoke all on public.ambulance_services from anon, authenticated;
grant select on public.ambulance_services to anon, authenticated;
drop policy if exists amb_read on public.ambulance_services;
create policy amb_read on public.ambulance_services for select to anon, authenticated using (active or public.is_admin());

create or replace function public.admin_save_ambulance(p jsonb) returns public.ambulance_services
language plpgsql security definer set search_path = public, pg_temp as $$
declare i bigint := nullif(p->>'id','')::bigint; n text := trim(coalesce(p->>'name','')); ph text := trim(coalesce(p->>'phone',''));
  c text := nullif(trim(coalesce(p->>'city','')), ''); k text := coalesce(nullif(p->>'kind',''), 'private'); nt text := trim(coalesce(p->>'note',''));
  act boolean := coalesce((p->>'active')::boolean, true); r public.ambulance_services;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  if char_length(n) < 3 or char_length(n) > 80 then raise exception 'invalid_name'; end if;
  if ph !~ '^\+?[0-9][0-9 -]{2,14}$' then raise exception 'invalid_phone'; end if;
  if k not in ('govt','private') then raise exception 'invalid_kind'; end if;
  if c is not null and char_length(c) > 60 then raise exception 'invalid_city'; end if;
  if char_length(nt) > 120 then raise exception 'invalid_note'; end if;
  if i is null then
    insert into public.ambulance_services (name, phone, city, kind, note, active) values (n, ph, c, k, nt, act) returning * into r;
  else
    update public.ambulance_services set name = n, phone = ph, city = c, kind = k, note = nt, active = act where id = i returning * into r;
    if not found then raise exception 'not_found'; end if;
  end if;
  return r;
end $$;
create or replace function public.admin_delete_ambulance(p_id bigint) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  delete from public.ambulance_services where id = p_id;
  if not found then raise exception 'not_found'; end if;
  return true;
end $$;
revoke all on function public.admin_save_ambulance(jsonb), public.admin_delete_ambulance(bigint) from public, anon;
grant execute on function public.admin_save_ambulance(jsonb), public.admin_delete_ambulance(bigint) to authenticated;
