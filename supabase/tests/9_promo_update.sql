\set P '00000000-0000-0000-0000-0000000c0095'
\set ADM '00000000-0000-0000-0000-0000000000b1'
insert into auth.users (id, email) values (:'P', 'promo1@example.com');
select id as did from public.doctors where status = 'approved' order by id limit 1 \gset

select t.anon();
select t.ok((select min_build from public.platform_settings where id = 1) = 0, 'anyone can read the minimum build');
select t.denied($$update public.platform_settings set min_build = 99 where id = 1$$, 'permission denied', 'anon cannot change settings');
select t.root();
select t.login(:'P');
update public.platform_settings set min_build = 99 where id = 1;
select t.root();
select min_build from public.platform_settings where id = 1 \gset
select t.ok(:min_build = 0, 'patient update changed nothing');

update public.platform_settings set fee_on = true, fee_type = 'flat', fee_value = 49, promo_until = now() + interval '2 days' where id = 1;
select t.login(:'P');
select public.create_booking(:did, public.clinic_now()::date + 21, '10:00', 'clinic', 'Promo Patient', 30, 'Female', '9876500012', '');
select t.root();
select t.ok((select platform_fee from public.bookings where patient_name = 'Promo Patient') = 0, 'platform fee is waived during the promo');

update public.platform_settings set promo_until = now() - interval '1 hour' where id = 1;
select t.login(:'P');
select public.create_booking(:did, public.clinic_now()::date + 21, '10:20', 'clinic', 'Promo Over', 30, 'Female', '9876500012', '');
select t.root();
select t.ok((select platform_fee from public.bookings where patient_name = 'Promo Over') = 49, 'fee is charged again after the promo ends');
update public.platform_settings set promo_until = null where id = 1;
