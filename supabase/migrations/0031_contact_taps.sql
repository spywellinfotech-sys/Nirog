-- Counts how often patients tap Call or WhatsApp on a facility or an ambulance listing. Shown to the super admin on each listing.
create table public.contact_taps (
  id         bigint generated always as identity primary key,
  kind       text not null check (kind in ('facility', 'ambulance')),
  target_id  bigint not null,
  channel    text not null check (channel in ('call', 'whatsapp')),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index contact_taps_target_idx on public.contact_taps (kind, target_id, created_at desc);
alter table public.contact_taps enable row level security;
revoke all on public.contact_taps from anon, authenticated;

-- One signed-in person counts once per listing and channel in any 10 minutes, so repeated taps do not inflate the number.
create or replace function public.log_contact_tap(p_kind text, p_target bigint, p_channel text) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if p_kind not in ('facility', 'ambulance') or p_channel not in ('call', 'whatsapp') then raise exception 'invalid_input'; end if;
  if p_kind = 'facility' and not exists (select 1 from public.facilities where id = p_target) then return; end if;
  if p_kind = 'ambulance' and not exists (select 1 from public.ambulance_services where id = p_target) then return; end if;
  if exists (select 1 from public.contact_taps where user_id = uid and kind = p_kind and target_id = p_target and channel = p_channel and created_at > now() - interval '10 minutes') then return; end if;
  insert into public.contact_taps (kind, target_id, channel, user_id) values (p_kind, p_target, p_channel, uid);
end $$;

create or replace function public.admin_contact_stats(p_kind text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  return coalesce((select jsonb_object_agg(target_id::text, jsonb_build_object('total', total, 'call', calls, 'whatsapp', wa, 'last30', l30))
    from (select target_id, count(*) as total, count(*) filter (where channel = 'call') as calls, count(*) filter (where channel = 'whatsapp') as wa,
                 count(*) filter (where created_at > now() - interval '30 days') as l30
          from public.contact_taps where kind = p_kind group by target_id) s), '{}'::jsonb);
end $$;
revoke all on function public.log_contact_tap(text, bigint, text), public.admin_contact_stats(text) from public, anon;
grant execute on function public.log_contact_tap(text, bigint, text), public.admin_contact_stats(text) to authenticated;
