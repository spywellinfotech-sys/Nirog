-- Ads become slideshows: a banner ad holds up to 8 photos shown one after another, may carry a sponsor link (https only),
-- and counts link clicks. Video ads stay single videos and are shown in their own place at the bottom of the page.
alter table public.ads add column images text[] not null default '{}' check (cardinality(images) <= 8);
alter table public.ads add column link_url text check (link_url is null or (link_url ~ '^https://[^ ]+$' and char_length(link_url) <= 300));
alter table public.ads add column clicks bigint not null default 0;
update public.ads set images = array[media_path] where kind = 'image' and cardinality(images) = 0;

create or replace function public.admin_save_ad(p jsonb) returns public.ads
language plpgsql security definer set search_path = public, pg_temp as $$
declare i bigint := nullif(p->>'id','')::bigint; t text := trim(coalesce(p->>'title','')); adv text := trim(coalesce(p->>'advertiser',''));
  k text := p->>'kind'; mp text := trim(coalesce(p->>'media_path','')); c text := nullif(trim(coalesce(p->>'city','')), '');
  s date := coalesce(nullif(p->>'starts_on','')::date, (now() at time zone 'Asia/Kolkata')::date); e date := nullif(p->>'ends_on','')::date;
  lk text := nullif(trim(coalesce(p->>'link_url','')), '');
  imgs text[] := coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p->'images', '[]'::jsonb)) x), '{}');
  act boolean := coalesce((p->>'active')::boolean, true); r public.ads;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  if char_length(t) < 1 or char_length(t) > 80 then raise exception 'invalid_title'; end if;
  if char_length(adv) > 80 then raise exception 'invalid_advertiser'; end if;
  if k not in ('image', 'video') then raise exception 'invalid_kind'; end if;
  if k = 'image' and cardinality(imgs) > 8 then raise exception 'too_many_images'; end if;
  if k = 'image' and mp = '' and cardinality(imgs) > 0 then mp := imgs[1]; end if;
  if i is null and mp = '' then raise exception 'invalid_media'; end if;
  if c is not null and char_length(c) > 60 then raise exception 'invalid_city'; end if;
  if e is not null and e < s then raise exception 'invalid_dates'; end if;
  if lk is not null and (lk !~ '^https://[^ ]+$' or char_length(lk) > 300) then raise exception 'invalid_link'; end if;
  if i is null then
    insert into public.ads (title, advertiser, kind, media_path, images, link_url, city, starts_on, ends_on, active)
    values (t, adv, k, mp, case when k = 'image' then imgs else '{}' end, lk, c, s, e, act) returning * into r;
  else
    update public.ads set title = t, advertiser = adv, kind = k, link_url = lk, city = c, starts_on = s, ends_on = e, active = act,
      media_path = case when mp = '' then media_path else mp end,
      images = case when k <> 'image' then '{}' when cardinality(imgs) > 0 then imgs else images end
      where id = i returning * into r;
    if not found then raise exception 'not_found'; end if;
  end if;
  return r;
end $$;

create or replace function public.active_ads(p_city text default null) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'title', title, 'advertiser', advertiser, 'kind', kind, 'media', media_path,
    'images', case when cardinality(images) > 0 then to_jsonb(images) else jsonb_build_array(media_path) end, 'link', link_url) order by created_at desc), '[]'::jsonb)
  from (select * from public.ads a
        where a.active and a.starts_on <= (now() at time zone 'Asia/Kolkata')::date and (a.ends_on is null or a.ends_on >= (now() at time zone 'Asia/Kolkata')::date)
          and (a.city is null or lower(a.city) = lower(coalesce(trim(p_city), '')))
        order by a.created_at desc limit 10) x;
$$;

create or replace function public.log_ad_click(p_id bigint) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then return; end if;
  update public.ads set clicks = clicks + 1 where id = p_id and active;
end $$;
revoke all on function public.admin_save_ad(jsonb), public.active_ads(text), public.log_ad_click(bigint) from public, anon;
grant execute on function public.admin_save_ad(jsonb), public.active_ads(text), public.log_ad_click(bigint) to authenticated;
