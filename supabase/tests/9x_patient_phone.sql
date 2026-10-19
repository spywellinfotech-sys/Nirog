\set ADM '00000000-0000-0000-0000-0000000000b1'
\set GP '00000000-0000-0000-0000-0000000c0601'
insert into auth.users (id, email) values (:'GP', 'google-patient@example.com');
update public.profiles set full_name = 'Google Only Patient' where id = :'GP';
select id as did from public.doctors order by id limit 1 \gset
insert into public.bookings (ref, patient_id, doctor_id, slot_date, slot_time, mode, patient_name, patient_age, patient_sex, patient_phone, doctor_fee, status)
values ('GP-1', :'GP', :did, public.clinic_now()::date + 40, '09:07', 'clinic', 'Google Only Patient', 40, 'Male', '9876500888', 100, 'confirmed');
select t.login(:'ADM');
select public.admin_patients('Google Only') as r \gset
select t.ok((:'r'::jsonb -> 'rows' -> 0 ->> 'phone') = '+919876500888', 'the admin sees the mobile from the latest booking when the profile has none');
select t.root();
