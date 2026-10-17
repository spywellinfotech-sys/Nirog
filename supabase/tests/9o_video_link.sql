\set D1 '00000000-0000-0000-0000-0000000000d1'
\set D2 '00000000-0000-0000-0000-0000000000d2'
\set A1 '00000000-0000-0000-0000-0000000000a1'
\set A2 '00000000-0000-0000-0000-0000000000a2'
select id as did from public.doctors where user_id = :'D1' \gset
insert into public.bookings (ref, patient_id, doctor_id, slot_date, slot_time, mode, patient_name, patient_age, patient_sex, patient_phone, reason, doctor_fee, status)
values ('VID-1', :'A1', :did, public.clinic_now()::date + 11, '05:11', 'video', 'Asha', 30, 'Female', '9876500301', '', 300, 'confirmed'),
       ('VID-2', :'A1', :did, public.clinic_now()::date + 11, '05:31', 'clinic', 'Asha', 30, 'Female', '9876500301', '', 500, 'confirmed'),
       ('VID-3', :'A1', :did, public.clinic_now()::date + 11, '05:51', 'video', 'Asha', 30, 'Female', '9876500301', '', 300, 'pending');
select id as v1 from public.bookings where ref = 'VID-1' \gset
select id as v2 from public.bookings where ref = 'VID-2' \gset
select id as v3 from public.bookings where ref = 'VID-3' \gset
select t.anon();
select t.denied(format($$select public.set_call_link(%L, 'https://meet.google.com/abc-defg-hij')$$, :'v1'), 'permission denied', 'anonymous cannot set a link');
select t.login(:'A1');
select t.denied(format($$select public.set_call_link(%L, 'https://meet.google.com/abc-defg-hij')$$, :'v1'), 'booking_not_found', 'a patient cannot set the link');
select t.login(:'D2');
select t.denied(format($$select public.set_call_link(%L, 'https://meet.google.com/abc-defg-hij')$$, :'v1'), 'booking_not_found', 'another doctor cannot set the link');
select t.login(:'D1');
select t.denied(format($$select public.set_call_link(%L, 'https://meet.google.com/abc-defg-hij')$$, :'v2'), 'not_video', 'clinic visits have no call link');
select t.denied(format($$select public.set_call_link(%L, 'https://meet.google.com/abc-defg-hij')$$, :'v3'), 'booking_not_confirmed', 'only confirmed bookings get a link');
select t.denied(format($$select public.set_call_link(%L, 'http://meet.google.com/x')$$, :'v1'), 'invalid_link', 'plain http is refused');
select t.denied(format($$select public.set_call_link(%L, 'javascript:alert(1)')$$, :'v1'), 'invalid_link', 'script links are refused');
select t.ok(public.set_call_link(:'v1', 'https://meet.google.com/abc-defg-hij'), 'the doctor sets a Meet link');
select t.login(:'A1');
select t.ok((select call_link from public.bookings where id = :'v1') = 'https://meet.google.com/abc-defg-hij', 'the patient can read the link');
select t.ok((select count(*) from public.notifications where user_id = :'A1' and body like 'Your doctor added the video call link%') = 1, 'the patient is notified');
select t.login(:'A2');
select t.ok((select count(*) from public.bookings where id = :'v1') = 0, 'other patients cannot see the booking or link');
select t.login(:'D1');
select t.ok(public.set_call_link(:'v1', '9876543210'), 'a mobile number becomes a WhatsApp link');
select t.ok((select call_link from public.bookings where id = :'v1') = 'https://wa.me/919876543210', 'the WhatsApp link is stored');
select t.ok(public.set_call_link(:'v1', ''), 'the link can be cleared');
select t.ok((select call_link from public.bookings where id = :'v1') is null, 'cleared link is empty');
