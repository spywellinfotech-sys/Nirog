\set A1 '00000000-0000-0000-0000-0000000000a1'
\set ADM '00000000-0000-0000-0000-0000000000b1'
select t.login(:'A1');
select t.denied($$select public.admin_patients('', 10, 0)$$, 'admins_only', 'patients cannot list patients');
select t.login(:'ADM');
select public.admin_patients('', 100, 0) as l \gset
select t.ok((:'l'::jsonb ->> 'total')::int >= 1 and jsonb_array_length(:'l'::jsonb -> 'rows') >= 1, 'admin sees patients');
select t.ok(not exists (select 1 from jsonb_array_elements(:'l'::jsonb -> 'rows') r where r ->> 'id' in (select id::text from public.profiles where role <> 'patient')), 'only patients are listed');
select public.admin_patients('zzzz-no-such-name', 10, 0) as e \gset
select t.ok((:'e'::jsonb ->> 'total')::int = 0, 'search filters by name');
select t.root();
\set P '00000000-0000-0000-0000-0000000c0391'
\set D1 '00000000-0000-0000-0000-0000000000d1'
insert into auth.users (id, email) values (:'P', 'adm-del@example.com');
insert into auth.identities (user_id) values (:'P');
update public.profiles set full_name = 'Admin Deletes Me', phone = '+919876500301' where id = :'P';
select id as did from public.doctors where user_id = :'D1' \gset
insert into public.bookings (ref, patient_id, doctor_id, slot_date, slot_time, mode, patient_name, patient_age, patient_sex, patient_phone, reason, doctor_fee, status)
values ('ADP-1', :'P', :did, public.clinic_now()::date + 33, '06:43', 'clinic', 'Admin Deletes Me', 33, 'Male', '9876500301', 'private', 500, 'confirmed');
select t.login(:'A1');
select t.denied(format($$select public.admin_delete_patient('%s')$$, :'P'), 'admins_only', 'patients cannot erase patients');
select t.login(:'ADM');
select t.denied(format($$select public.admin_delete_patient('%s')$$, :'D1'), 'not_a_patient', 'a doctor account cannot be erased as a patient');
select t.denied(format($$select public.admin_delete_patient('%s')$$, :'ADM'), 'not_a_patient', 'staff cannot be erased as a patient');
select public.admin_delete_patient(:'P');
select t.root();
select t.ok((select status::text from public.bookings where ref = 'ADP-1') = 'cancelled' and (select patient_name || reason from public.bookings where ref = 'ADP-1') = 'Deleted user', 'admin erase cancels bookings and wipes details');
select t.ok((select full_name from public.profiles where id = :'P') = '' and (select email from auth.users where id = :'P') is null and (select banned_until from auth.users where id = :'P') is not null, 'admin erase clears the profile and closes the sign-in');
