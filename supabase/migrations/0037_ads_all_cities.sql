-- A patient who has not picked a city (All cities) now sees every running ad. Picking a city shows that city's ads and the ones for every city.
create or replace function public.active_ads(p_city text default null) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'title', title, 'advertiser', advertiser, 'kind', kind, 'media', media_path,
    'images', case when cardinality(images) > 0 then to_jsonb(images) else jsonb_build_array(media_path) end, 'link', link_url) order by created_at desc), '[]'::jsonb)
  from (select * from public.ads a
        where a.active and a.starts_on <= (now() at time zone 'Asia/Kolkata')::date and (a.ends_on is null or a.ends_on >= (now() at time zone 'Asia/Kolkata')::date)
          and (coalesce(trim(p_city), '') = '' or a.city is null or lower(a.city) = lower(trim(p_city)))
        order by a.created_at desc limit 10) x;
$$;
revoke all on function public.active_ads(text) from public, anon;
grant execute on function public.active_ads(text) to authenticated;
