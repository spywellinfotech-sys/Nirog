\set D1 '00000000-0000-0000-0000-0000000000d1'
\set D2 '00000000-0000-0000-0000-0000000000d2'
\set A1 '00000000-0000-0000-0000-0000000000a1'
select id as did from public.doctors where user_id = :'D1' \gset
insert into public.bookings (ref, patient_id, doctor_id, slot_date, slot_time, mode, patient_name, patient_age, patient_sex, patient_phone, reason, doctor_fee, status)
values ('CALL-1', :'A1', :did, public.clinic_now()::date + 12, '06:11', 'video', 'Asha', 30, 'Female', '9876500302', '', 300, 'confirmed'),
       ('CALL-2', :'A1', :did, public.clinic_now()::date + 12, '06:31', 'clinic', 'Asha', 30, 'Female', '9876500302', '', 500, 'confirmed');
select id as c1 from public.bookings where ref = 'CALL-1' \gset
select id as c2 from public.bookings where ref = 'CALL-2' \gset
select t.login(:'A1');
select t.denied(format($$select public.start_call(%L)$$, :'c1'), 'booking_not_found', 'a patient cannot start the call');
select t.login(:'D2');
select t.denied(format($$select public.start_call(%L)$$, :'c1'), 'booking_not_found', 'another doctor cannot start the call');
select t.login(:'D1');
select t.denied(format($$select public.start_call(%L)$$, :'c2'), 'not_video', 'a clinic visit has no call');
select t.ok(public.start_call(:'c1'), 'the doctor starts the call');
select t.login(:'A1');
select t.ok((select call_started_at from public.bookings where id = :'c1') > now() - interval '1 minute', 'the patient sees when the call started');
select t.ok((select count(*) from public.notifications where user_id = :'A1' and body like '% is calling you%') = 1, 'the patient is notified');
select t.login(:'D1');
select public.start_call(:'c1');
select t.login(:'A1');
select t.ok((select count(*) from public.notifications where user_id = :'A1' and body like '% is calling you%') = 1, 'a quick second start does not notify again');
select t.login(:'A1');
select t.denied(format($$select public.end_call(%L)$$, :'c1'), 'booking_not_found', 'a patient cannot end the doctor''s call');
select t.login(:'D2');
select t.denied(format($$select public.end_call(%L)$$, :'c1'), 'booking_not_found', 'another doctor cannot end the call');
select t.login(:'D1');
select t.ok(public.end_call(:'c1'), 'the doctor ends the call');
select t.login(:'A1');
select t.ok((select call_started_at from public.bookings where id = :'c1') is null, 'the call is no longer marked as started');
