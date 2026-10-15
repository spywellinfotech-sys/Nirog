\set D1 '00000000-0000-0000-0000-0000000000d1'
\set ADM '00000000-0000-0000-0000-0000000000b1'
\set P '00000000-0000-0000-0000-0000000c0201'
\set F '00000000-0000-0000-0000-0000000c0202'
insert into auth.users (id, email) values (:'P', 'del1@example.com'), (:'F', 'del2@example.com');
insert into auth.identities (user_id) values (:'P');
update public.profiles set full_name = 'Delete Me', phone = '+919876500201' where id = :'P';
insert into public.patients (id, age, sex) values (:'P', 33, 'Male') on conflict do nothing;
select id as did from public.doctors where user_id = :'D1' \gset
insert into public.bookings (ref, patient_id, doctor_id, slot_date, slot_time, mode, patient_name, patient_age, patient_sex, patient_phone, reason, doctor_fee, status)
values ('DEL-1', :'P', :did, public.clinic_now()::date + 9, '04:11', 'clinic', 'Delete Me', 33, 'Male', '9876500201', 'private reason', 500, 'confirmed');
insert into public.push_tokens (user_id, token, platform) values (:'P', 'token-del-1-aaaaaaaaaaaaaaaaaaaa', 'android');
select t.denied($$select public.delete_my_account()$$, 'not_authenticated', 'an anonymous caller cannot delete an account');
select t.login(:'ADM');
select t.denied($$select public.delete_my_account()$$, 'staff_cannot_delete', 'staff accounts cannot use self-delete');
select t.login(:'P');
select public.delete_my_account();
select t.root();
select t.ok((select status::text from public.bookings where ref = 'DEL-1') = 'cancelled', 'open bookings are cancelled');
select t.ok((select patient_name || patient_phone || reason from public.bookings where ref = 'DEL-1') = 'Deleted user9000000000', 'the patient details on bookings are erased');
select t.ok((select count(*) from public.push_tokens where user_id = :'P') = 0 and (select count(*) from public.patients where id = :'P') = 0, 'tokens and patient record are removed');
select t.ok((select full_name from public.profiles where id = :'P') = '' and (select phone from public.profiles where id = :'P') is null and (select email from auth.users where id = :'P') is null, 'profile and sign-in details are cleared');
select t.ok((select banned_until from auth.users where id = :'P') is not null and (select count(*) from auth.identities where user_id = :'P') = 0, 'the sign-in is closed');
