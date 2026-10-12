\set ADM '00000000-0000-0000-0000-0000000000b1'
\set U1 '00000000-0000-0000-0000-0000000c0091'
\set U2 '00000000-0000-0000-0000-0000000c0092'
select id as did from public.doctors where user_id = :'U1' \gset
select id as fid from public.facilities where user_id = :'U2' \gset
-- U1 is a doctor (no bookings) and U2 a facility, both created in test 6.
select t.login(:'U1');
select t.denied('select public.admin_profile(''doctor'', '||:did||')', 'admins_only', 'a non-admin cannot view full profiles');
select t.denied('select public.admin_update_doctor('||:did||', ''{"fee_inr":1}'')', 'admins_only', 'a non-admin cannot edit a doctor');
select t.denied('select public.admin_delete_doctor('||:did||')', 'admins_only', 'a non-admin cannot delete a doctor');
select t.root();
select t.login(:'ADM');
select t.ok((select (public.admin_profile('doctor', :did) -> 'row' ->> 'name')) = 'Dr. Dup One', 'admin sees the full doctor profile');
select t.ok((select public.admin_profile('doctor', :did) ->> 'phone') = '+919876511111', 'full profile includes the mobile number');
select t.ok((select public.admin_profile('facility', :fid) -> 'private' ->> 'contact_phone') = '9876533333', 'admin sees the facility contact');
select public.admin_update_doctor(:did, '{"fee_inr":750,"about":"Edited by admin","city":"Pune","phone":"9876544444","pin":"411001"}'::jsonb);
select t.ok((select fee_inr from public.doctors where id = :did) = 750 and (select about from public.doctors where id = :did) = 'Edited by admin' and (select name from public.doctors where id = :did) = 'Dr. Dup One', 'admin edit changes only the given doctor fields');
select t.ok((select pin from public.clinic_locations where doctor_id = :did) = '411001' and (select phone from public.profiles where id = :'U1') = '+919876544444', 'admin edit updates clinic location and mobile number');
select t.denied('select public.admin_update_doctor('||:did||', ''{"phone":"9876533333"}'')', 'phone_in_use', 'admin edit cannot take another account''s mobile number');
select public.admin_update_facility(:fid, '{"hours":"24x7","contact_name":"Ravi"}'::jsonb);
select t.ok((select hours from public.facilities where id = :fid) = '24x7' and (select contact_name from public.facility_private where facility_id = :fid) = 'Ravi', 'admin edit updates a facility');
select t.denied($$select public.admin_delete_doctor(1)$$, 'has_bookings', 'a doctor with bookings cannot be deleted');
select public.admin_delete_doctor(:did);
select public.admin_delete_facility(:fid);
select t.root();
select t.ok((select count(*) from public.doctors where user_id = :'U1') = 0, 'deleted doctor is gone');
select t.ok((select count(*) from public.doctor_verification v where not exists (select 1 from public.doctors d where d.id = v.doctor_id)) = 0, 'no orphan verification rows');
select t.ok((select role from public.profiles where id = :'U1') = 'patient' and (select phone from public.profiles where id = :'U1') is null, 'deleted doctor account returns to patient and frees the mobile number');
select t.ok((select count(*) from public.facilities where user_id = :'U2') = 0, 'deleted facility is gone');
select t.login(:'U1');
select public.register_doctor('{"phone":"9876544444","name":"Dr. Dup One","spec":"Cardiologist","fee_inr":900,"city":"Delhi","address":"5 Heart Lane","council":"DMC","reg_no":"DMC-91","reg_year":2001,"days":[1,2],"sessions":[{"s":600,"e":720}]}'::jsonb);
select t.ok((select role from public.profiles where id = :'U1') = 'doctor', 'the same mobile number can register again after deletion');
select t.root();
