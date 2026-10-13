-- Location targeting for broadcasts. Patients keep the city they browse in; doctors and facilities already have one.
-- A broadcast with a city goes only to users in that city (case-insensitive). Patients with no city saved are skipped.
alter table public.patients add column if not exists city text check (city is null or char_length(city) <= 60);
grant update (city) on public.patients to authenticated;
alter table public.broadcasts add column if not exists city text check (city is null or char_length(city) between 1 and 60);

create or replace function public.my_city() returns text
language sql stable security definer set search_path = public, pg_temp as $$
  select lower(trim(coalesce(
    (select pt.city from public.patients pt where pt.id = auth.uid()),
    (select d.city from public.doctors d where d.user_id = auth.uid()),
    (select f.city from public.facilities f where f.user_id = auth.uid()))))
$$;
revoke all on function public.my_city() from public, anon;
grant execute on function public.my_city() to authenticated;

drop policy if exists bc_read on public.broadcasts;
create policy bc_read on public.broadcasts for select to authenticated using (
  public.is_admin() or exists (select 1 from public.profiles p where p.id = auth.uid() and (
    audience = 'all' or (audience = 'patients' and p.role = 'patient') or (audience = 'doctors' and p.role = 'doctor') or (audience = 'facilities' and p.role = 'facility'))
    and (city is null or lower(trim(city)) = public.my_city())));

-- Who a send would reach, used by the admin screen before sending and by the send itself.
create or replace function public.broadcast_targets(p_audience text, p_city text) returns table (uid uuid)
language sql stable security definer set search_path = public, pg_temp as $$
  select pr.id from public.profiles pr
  where ((p_audience = 'all' and pr.role in ('patient','doctor','facility')) or (p_audience = 'patients' and pr.role = 'patient')
      or (p_audience = 'doctors' and pr.role = 'doctor') or (p_audience = 'facilities' and pr.role = 'facility'))
    and (nullif(trim(coalesce(p_city, '')), '') is null or lower(trim(p_city)) = lower(trim(coalesce(
      (select pt.city from public.patients pt where pt.id = pr.id),
      (select d.city from public.doctors d where d.user_id = pr.id),
      (select f.city from public.facilities f where f.user_id = pr.id), ''))))
$$;
revoke all on function public.broadcast_targets(text, text) from public, anon, authenticated;

create or replace function public.admin_broadcast_reach(p_audience text, p_city text default null) returns integer
language plpgsql security definer set search_path = public, pg_temp as $$
declare n integer;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  if p_audience not in ('all','patients','doctors','facilities') then raise exception 'invalid_audience'; end if;
  select count(*) into n from public.broadcast_targets(p_audience, p_city);
  return n;
end $$;
revoke all on function public.admin_broadcast_reach(text, text) from public, anon;
grant execute on function public.admin_broadcast_reach(text, text) to authenticated;

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
  insert into public.notifications (user_id, body)
    select uid, left(case when b = '' then t else t || ': ' || b end, 300) from public.broadcast_targets(a, c);
  get diagnostics n = row_count;
  update public.broadcasts set sent_count = n where id = r.id returning * into r;
  return r;
end $$;
revoke all on function public.admin_send_broadcast(jsonb) from public, anon;
grant execute on function public.admin_send_broadcast(jsonb) to authenticated;
