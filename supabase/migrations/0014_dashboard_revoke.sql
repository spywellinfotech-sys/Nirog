-- Super admin dashboard counts, and revoking a wrong broadcast.
-- Revoking hides the broadcast from everyone (popup and bell) and removes the notification rows it created.
alter table public.broadcasts add column if not exists revoked_at timestamptz;
alter table public.notifications add column if not exists broadcast_id bigint references public.broadcasts(id) on delete cascade;
create index if not exists notifications_broadcast_idx on public.notifications (broadcast_id) where broadcast_id is not null;

drop policy if exists bc_read on public.broadcasts;
create policy bc_read on public.broadcasts for select to authenticated using (
  public.is_admin() or (revoked_at is null and exists (select 1 from public.profiles p where p.id = auth.uid() and (
    audience = 'all' or (audience = 'patients' and p.role = 'patient') or (audience = 'doctors' and p.role = 'doctor') or (audience = 'facilities' and p.role = 'facility'))
    and (city is null or lower(trim(city)) = public.my_city()))));

create or replace function public.admin_send_broadcast(p jsonb) returns public.broadcasts
language plpgsql security definer set search_path = public, pg_temp as $$
declare t text := trim(coalesce(p->>'title','')); b text := trim(coalesce(p->>'body','')); a text := coalesce(p->>'audience','');
  c text := nullif(trim(coalesce(p->>'city','')), '');
  img text := nullif(p->>'image',''); vid text := nullif(p->>'video',''); r public.broadcasts; n integer;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  if char_length(t) < 1 or char_length(t) > 80 then raise exception 'invalid_title'; end if;
  if char_length(b) > 500 then raise exception 'invalid_message'; end if;
  if a not in ('all','patients','doctors','facilities') then raise exception 'invalid_audience'; end if;
  if c is not null and char_length(c) > 60 then raise exception 'invalid_city'; end if;
  if (img is not null and img !~ '^[A-Za-z0-9._-]{1,100}$') or (vid is not null and vid !~ '^[A-Za-z0-9._-]{1,100}$') then raise exception 'invalid_media'; end if;
  insert into public.broadcasts (title, body, audience, city, image_path, video_path, created_by) values (t, b, a, c, img, vid, auth.uid()) returning * into r;
  insert into public.notifications (user_id, body, broadcast_id)
    select uid, left(case when b = '' then t else t || ': ' || b end, 300), r.id from public.broadcast_targets(a, c);
  get diagnostics n = row_count;
  update public.broadcasts set sent_count = n where id = r.id returning * into r;
  return r;
end $$;
revoke all on function public.admin_send_broadcast(jsonb) from public, anon;
grant execute on function public.admin_send_broadcast(jsonb) to authenticated;

create or replace function public.admin_revoke_broadcast(p_id bigint) returns integer
language plpgsql security definer set search_path = public, pg_temp as $$
declare b public.broadcasts; n integer;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  select * into b from public.broadcasts where id = p_id;
  if not found then raise exception 'not_found'; end if;
  if b.revoked_at is null then update public.broadcasts set revoked_at = now() where id = p_id; end if;
  -- notifications made before this migration carry no broadcast id: match them by text and send time
  delete from public.notifications where broadcast_id = p_id
    or (broadcast_id is null and body = left(case when b.body = '' then b.title else b.title || ': ' || b.body end, 300)
        and created_at between b.created_at - interval '2 minutes' and b.created_at + interval '2 minutes');
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.admin_revoke_broadcast(bigint) from public, anon;
grant execute on function public.admin_revoke_broadcast(bigint) to authenticated;

create or replace function public.broadcast_tokens(p_broadcast bigint) returns table (token text)
language sql stable security definer set search_path = public, pg_temp as $$
  select t.token from public.broadcasts b
  join lateral public.broadcast_targets(b.audience, b.city) x on true
  join public.push_tokens t on t.user_id = x.uid
  where b.id = p_broadcast and b.revoked_at is null
$$;

create or replace function public.admin_dashboard_counts() returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare r jsonb;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  select jsonb_build_object(
    'patients', (select count(*) from public.profiles where role = 'patient'),
    'doctors', jsonb_build_object('listed', (select count(*) from public.doctors where status = 'approved'), 'pending', (select count(*) from public.doctors where status = 'pending')),
    'facilities', (select coalesce(jsonb_object_agg(k.kind, jsonb_build_object(
        'listed', (select count(*) from public.facilities f where f.kind = k.kind and f.status = 'approved'),
        'pending', (select count(*) from public.facilities f where f.kind = k.kind and f.status = 'pending'))), '{}'::jsonb)
      from (values ('lab'), ('centre'), ('hospital'), ('other')) as k(kind)),
    'specialties', (select coalesce(jsonb_agg(jsonb_build_object('spec', s.spec, 'n', s.n) order by s.n desc, s.spec), '[]'::jsonb)
      from (select spec, count(*) n from public.doctors where status = 'approved' group by spec order by count(*) desc, spec limit 12) s),
    'phones', (select count(*) from public.push_tokens),
    'phone_users', (select count(distinct user_id) from public.push_tokens)
  ) into r;
  return r;
end $$;
revoke all on function public.admin_dashboard_counts() from public, anon;
grant execute on function public.admin_dashboard_counts() to authenticated;
