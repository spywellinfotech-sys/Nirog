\set D1 '00000000-0000-0000-0000-0000000000d1'
\set D2 '00000000-0000-0000-0000-0000000000d2'
\set A1 '00000000-0000-0000-0000-0000000000a1'
\set FO '00000000-0000-0000-0000-0000000c0701'
select id as did from public.doctors where user_id = :'D1' \gset
insert into public.bookings (ref, patient_id, doctor_id, slot_date, slot_time, mode, patient_name, patient_age, patient_sex, patient_phone, reason, doctor_fee, status)
values ('ATT-1', :'A1', :did, public.clinic_now()::date - 5, '07:01', 'clinic', 'Asha', 30, 'Female', '9876500302', '', 300, 'confirmed'),
       ('ATT-2', :'A1', :did, public.clinic_now()::date - 5, '07:21', 'clinic', 'Asha', 30, 'Female', '9876500302', '', 300, 'confirmed'),
       ('ATT-3', :'A1', :did, public.clinic_now()::date + 9, '07:41', 'clinic', 'Asha', 30, 'Female', '9876500302', '', 300, 'confirmed'),
       ('ATT-4', :'A1', :did, public.clinic_now()::date - 5, '08:01', 'clinic', 'Asha', 30, 'Female', '9876500302', '', 300, 'rejected');
select id as b1 from public.bookings where ref = 'ATT-1' \gset
select id as b2 from public.bookings where ref = 'ATT-2' \gset
select id as b3 from public.bookings where ref = 'ATT-3' \gset
select id as b4 from public.bookings where ref = 'ATT-4' \gset
select t.login(:'A1');
select t.denied(format($$select public.mark_attendance(%L, true)$$, :'b1'), 'doctors_only', 'a patient cannot mark attendance');
select t.login(:'D2');
select t.denied(format($$select public.mark_attendance(%L, true)$$, :'b1'), 'booking_not_found', 'another doctor cannot mark attendance');
select t.login(:'D1');
select t.denied(format($$select public.mark_attendance(%L, true)$$, :'b3'), 'visit_not_started', 'a future visit cannot be marked');
select t.denied(format($$select public.mark_attendance(%L, true)$$, :'b4'), 'not_confirmed', 'a rejected booking cannot be marked');
select public.mark_attendance(:'b1', true);
select public.mark_attendance(:'b2', false);
select t.ok((select attendance from public.bookings where id = :'b1') = 'attended', 'attended is saved');
select t.ok((select attendance from public.bookings where id = :'b2') = 'no_show', 'not attended is saved');
select public.mark_attendance(:'b2', true);
select t.ok((select attendance from public.bookings where id = :'b2') = 'attended', 'the doctor can correct a mark');
select t.root();
-- facility side
select id as flid from public.facilities where user_id = :'FO' \gset
insert into public.facility_requests (ref, facility_id, patient_id, patient_name, patient_phone, item, preferred_date, status)
values ('FATT-1', :flid, :'A1', 'Asha', '9876500001', 'HbA1c', public.clinic_now()::date - 2, 'confirmed'),
       ('FATT-2', :flid, :'A1', 'Asha', '9876500001', 'HbA1c', public.clinic_now()::date + 5, 'confirmed');
select id as q1 from public.facility_requests where ref = 'FATT-1' \gset
select id as q2 from public.facility_requests where ref = 'FATT-2' \gset
select t.login(:'A1');
select t.denied(format($$select public.mark_facility_attendance(%L, true)$$, :'q1'), 'not_found', 'a patient cannot mark a facility request');
select t.login(:'FO');
select t.denied(format($$select public.mark_facility_attendance(%L, true)$$, :'q2'), 'visit_not_started', 'a future request cannot be marked');
select public.mark_facility_attendance(:'q1', false);
select t.ok((select attendance from public.facility_requests where id = :'q1') = 'no_show', 'facility not attended is saved');
select t.root();
