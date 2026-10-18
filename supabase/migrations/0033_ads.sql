-- Ads: the super admin puts a banner image or a short video in front of patients in one city or in every city.
-- Media goes in the existing public 'broadcast-media' bucket (admin-only upload).
create table public.ads (
  id          bigint generated always as identity primary key,
  title       text not null check (char_length(title) between 1 and 80),
  advertiser  text not null default '' check (char_length(advertiser) <= 80),
  kind        text not null check (kind in ('image', 'video')),
  media_path  text not null check (char_length(media_path) between 1 and 200),
  city        text check (city is null or char_length(city) <= 60),
  starts_on   date not null default (now() at time zone 'Asia/Kolkata')::date,
  ends_on     date,
  active      boolean not null default true,
  views       bigint not null default 0,
  created_at  timestamptz not null default now(),
  check (ends_on is null or ends_on >= starts_on)
);
alter table public.ads enable row level security;
revoke all on public.ads from anon, authenticated;
grant select on public.ads to authenticated;
create policy ads_admin_read on public.ads for select to authenticated using (public.is_admin());

create or replace function public.admin_save_ad(p jsonb) returns public.ads
language plpgsql security definer set search_path = public, pg_temp as $$
declare i bigint := nullif(p->>'id','')::bigint; t text := trim(coalesce(p->>'title','')); adv text := trim(coalesce(p->>'advertiser',''));
  k text := p->>'kind'; mp text := trim(coalesce(p->>'media_path','')); c text := nullif(trim(coalesce(p->>'city','')), '');
  s date := coalesce(nullif(p->>'starts_on','')::date, (now() at time zone 'Asia/Kolkata')::date); e date := nullif(p->>'ends_on','')::date;
  act boolean := coalesce((p->>'active')::boolean, true); r public.ads;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  if char_length(t) < 1 or char_length(t) > 80 then raise exception 'invalid_title'; end if;
  if char_length(adv) > 80 then raise exception 'invalid_advertiser'; end if;
  if k not in ('image', 'video') then raise exception 'invalid_kind'; end if;
  if i is null and mp = '' then raise exception 'invalid_media'; end if;
  if c is not null and char_length(c) > 60 then raise exception 'invalid_city'; end if;
  if e is not null and e < s then raise exception 'invalid_dates'; end if;
  if i is null then
    insert into public.ads (title, advertiser, kind, media_path, city, starts_on, ends_on, active) values (t, adv, k, mp, c, s, e, act) returning * into r;
  else
    update public.ads set title = t, advertiser = adv, kind = k, media_path = case when mp = '' then media_path else mp end, city = c, starts_on = s, ends_on = e, active = act where id = i returning * into r;
    if not found then raise exception 'not_found'; end if;
  end if;
  return r;
end $$;

create or replace function public.admin_delete_ad(p_id bigint) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  delete from public.ads where id = p_id;
  if not found then raise exception 'not_found'; end if;
  return true;
end $$;

-- What a patient sees: running ads for their city, plus ads that run in every city. Newest first, at most five.
create or replace function public.active_ads(p_city text default null) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'title', title, 'advertiser', advertiser, 'kind', kind, 'media', media_path) order by created_at desc), '[]'::jsonb)
  from (select * from public.ads a
        where a.active and a.starts_on <= (now() at time zone 'Asia/Kolkata')::date and (a.ends_on is null or a.ends_on >= (now() at time zone 'Asia/Kolkata')::date)
          and (a.city is null or lower(a.city) = lower(coalesce(trim(p_city), '')))
        order by a.created_at desc limit 5) x;
$$;

create or replace function public.log_ad_view(p_id bigint) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then return; end if;
  update public.ads set views = views + 1 where id = p_id and active;
end $$;

revoke all on function public.admin_save_ad(jsonb), public.admin_delete_ad(bigint), public.active_ads(text), public.log_ad_view(bigint) from public, anon;
grant execute on function public.admin_save_ad(jsonb), public.admin_delete_ad(bigint), public.active_ads(text), public.log_ad_view(bigint) to authenticated;
