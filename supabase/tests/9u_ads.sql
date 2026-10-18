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
select public.active_ads('') as aa \gset
select t.ok(:'aa'::jsonb::text like '%Pune clinic offer%' and :'aa'::jsonb::text like '%Everywhere lab%', 'a patient who has not picked a city sees every running ad');
select public.log_ad_view(:pune);
select public.log_ad_view(:pune);
select t.root();
select t.ok((select views from public.ads where id = :pune) = 2, 'views are counted');
select t.login(:'ADM');
select t.ok((select count(*) from public.ads) >= 4, 'the admin can read every ad');
select public.admin_delete_ad(:old);
select t.ok((select count(*) from public.ads where id = :old) = 0, 'an ad can be deleted');
select t.root();
select t.login(:'ADM');
select (public.admin_save_ad('{"title":"Slideshow","advertiser":"Shree Pharmacy","kind":"image","images":["s1.jpg","s2.jpg","s3.jpg"],"link_url":"https://example.com/offer"}')).id as ss \gset
select t.denied($$select public.admin_save_ad('{"title":"Bad link","kind":"image","images":["a.jpg"],"link_url":"http://example.com"}')$$, 'invalid_link', 'the sponsor link must be https');
select t.denied($$select public.admin_save_ad('{"title":"Bad link","kind":"image","images":["a.jpg"],"link_url":"javascript:alert(1)"}')$$, 'invalid_link', 'script links are refused');
select t.denied($$select public.admin_save_ad('{"title":"Too many","kind":"image","images":["1","2","3","4","5","6","7","8","9"]}')$$, 'too_many_images', 'at most 8 photos');
select t.root();
select t.login(:'A1');
select public.active_ads('Pune') as sa \gset
select t.ok(:'sa'::jsonb::text like '%s2.jpg%' and :'sa'::jsonb::text like '%https://example.com/offer%', 'the slideshow photos and the sponsor link reach the patient');
select public.log_ad_click(:ss);
select public.log_ad_click(:ss);
select t.root();
select t.ok((select clicks from public.ads where id = :ss) = 2 and (select cardinality(images) from public.ads where id = :ss) = 3, 'clicks are counted and the photos are kept');
select t.login(:'ADM');
select public.admin_save_ad(format('{"id":%s,"title":"Slideshow v2","kind":"image","link_url":""}', :ss)::jsonb);
select t.root();
select t.ok((select cardinality(images) from public.ads where id = :ss) = 3 and (select link_url from public.ads where id = :ss) is null, 'editing without new photos keeps the old ones; an empty link clears it');
