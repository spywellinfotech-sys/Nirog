-- Broadcast notifications from the super admin: a title, a message, an optional photo and a short video, sent to everyone or one group.
-- Each send also adds a row to every recipient's notifications, so it shows in their notification list.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('broadcast-media', 'broadcast-media', true, 20971520, array['image/jpeg','image/png','image/webp','video/mp4','video/webm'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists bc_media_read on storage.objects;
create policy bc_media_read on storage.objects for select to anon, authenticated using (bucket_id = 'broadcast-media');
drop policy if exists bc_media_write on storage.objects;
create policy bc_media_write on storage.objects for insert to authenticated with check (bucket_id = 'broadcast-media' and public.is_admin());
drop policy if exists bc_media_delete on storage.objects;
create policy bc_media_delete on storage.objects for delete to authenticated using (bucket_id = 'broadcast-media' and public.is_admin());

create table if not exists public.broadcasts (
  id bigint generated always as identity primary key,
  title text not null check (char_length(title) between 1 and 80),
  body text not null default '' check (char_length(body) <= 500),
  audience text not null check (audience in ('all','patients','doctors','facilities')),
  image_path text check (image_path ~ '^[A-Za-z0-9._-]{1,100}$'),
  video_path text check (video_path ~ '^[A-Za-z0-9._-]{1,100}$'),
  sent_count integer not null default 0,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.broadcasts enable row level security;
revoke all on public.broadcasts from anon, authenticated;
grant select on public.broadcasts to authenticated;
drop policy if exists bc_read on public.broadcasts;
create policy bc_read on public.broadcasts for select to authenticated using (
  public.is_admin() or exists (select 1 from public.profiles p where p.id = auth.uid() and (
    audience = 'all' or (audience = 'patients' and p.role = 'patient') or (audience = 'doctors' and p.role = 'doctor') or (audience = 'facilities' and p.role = 'facility'))));

create or replace function public.admin_send_broadcast(p jsonb) returns public.broadcasts
language plpgsql security definer set search_path = public, pg_temp as $$
declare t text := trim(coalesce(p->>'title','')); b text := trim(coalesce(p->>'body','')); a text := coalesce(p->>'audience','');
  img text := nullif(p->>'image',''); vid text := nullif(p->>'video',''); r public.broadcasts; n integer;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  if char_length(t) < 1 or char_length(t) > 80 then raise exception 'invalid_title'; end if;
  if char_length(b) > 500 then raise exception 'invalid_message'; end if;
  if a not in ('all','patients','doctors','facilities') then raise exception 'invalid_audience'; end if;
  if (img is not null and img !~ '^[A-Za-z0-9._-]{1,100}$') or (vid is not null and vid !~ '^[A-Za-z0-9._-]{1,100}$') then raise exception 'invalid_media'; end if;
  insert into public.broadcasts (title, body, audience, image_path, video_path, created_by) values (t, b, a, img, vid, auth.uid()) returning * into r;
  insert into public.notifications (user_id, body)
    select id, left(case when b = '' then t else t || ': ' || b end, 300) from public.profiles
    where (a = 'all' and role in ('patient','doctor','facility')) or (a = 'patients' and role = 'patient') or (a = 'doctors' and role = 'doctor') or (a = 'facilities' and role = 'facility');
  get diagnostics n = row_count;
  update public.broadcasts set sent_count = n where id = r.id returning * into r;
  return r;
end $$;

create or replace function public.admin_delete_broadcast(p_id bigint) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  delete from public.broadcasts where id = p_id;
  if not found then raise exception 'not_found'; end if;
  return true;
end $$;
revoke all on function public.admin_send_broadcast(jsonb), public.admin_delete_broadcast(bigint) from public, anon;
grant execute on function public.admin_send_broadcast(jsonb), public.admin_delete_broadcast(bigint) to authenticated;
