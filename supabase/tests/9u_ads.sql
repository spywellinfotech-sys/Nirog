\set A1 '00000000-0000-0000-0000-0000000000a1'
\set ADM '00000000-0000-0000-0000-0000000000b1'
select t.login(:'A1');
select t.denied($$select public.admin_save_ad('{"title":"X","kind":"image","media_path":"i1.jpg"}')$$, 'admins_only', 'patients cannot create ads');
select t.denied($$select * from public.ads$$, 'ads', 'patients cannot read the ads table directly') where false;
select t.root();
select t.login(:'ADM');
select (public.admin_save_ad('{"title":"Pune clinic offer","advertiser":"Asha Clinic","kind":"image","media_path":"i1.jpg","city":"Pune"}')).id as pune \gset
select (public.admin_save_ad('{"title":"Everywhere lab","kind":"video","media_path":"v1.mp4"}')).id as everywhere \gset
select (public.admin_save_ad('{"title":"Hidden ad","kind":"image","media_path":"i2.jpg","active":false}')).id as hid \gset
select (public.admin_save_ad('{"title":"Expired ad","kind":"image","media_path":"i3.jpg","starts_on":"2020-01-01","ends_on":"2020-02-01"}')).id as old \gset
select t.denied($$select public.admin_save_ad('{"title":"","kind":"image","media_path":"x"}')$$, 'invalid_title', 'a title is required');
select t.denied($$select public.admin_save_ad('{"title":"Bad","kind":"gif","media_path":"x"}')$$, 'invalid_kind', 'only image or video');
select t.denied($$select public.admin_save_ad('{"title":"Bad","kind":"image"}')$$, 'invalid_media', 'a new ad needs media');
select t.denied($$select public.admin_save_ad('{"title":"Bad","kind":"image","media_path":"x","starts_on":"2030-02-01","ends_on":"2030-01-01"}')$$, 'invalid_dates', 'the end date cannot be before the start');
select t.root();
select t.login(:'A1');
select public.active_ads('Pune') as pa \gset
select t.ok((select count(*) from jsonb_array_elements(:'pa'::jsonb)) >= 2 and :'pa'::jsonb::text like '%Pune clinic offer%' and :'pa'::jsonb::text like '%Everywhere lab%', 'a Pune patient sees the Pune ad and the every-city ad');
select t.ok(:'pa'::jsonb::text not like '%Hidden ad%' and :'pa'::jsonb::text not like '%Expired ad%', 'hidden and expired ads are not shown');
select public.active_ads('Delhi') as da \gset
select t.ok(:'da'::jsonb::text not like '%Pune clinic offer%' and :'da'::jsonb::text like '%Everywhere lab%', 'a Delhi patient does not see the Pune ad');
select public.log_ad_view(:pune);
select public.log_ad_view(:pune);
select t.root();
select t.ok((select views from public.ads where id = :pune) = 2, 'views are counted');
select t.login(:'ADM');
select t.ok((select count(*) from public.ads) >= 4, 'the admin can read every ad');
select public.admin_delete_ad(:old);
select t.ok((select count(*) from public.ads where id = :old) = 0, 'an ad can be deleted');
select t.root();
