\set A1 '00000000-0000-0000-0000-0000000000a1'
select id as did from public.doctors order by id limit 1 \gset
select to_char(public.clinic_now() + interval '23 hours 30 minutes', 'YYYY-MM-DD') as d1, to_char(public.clinic_now() + interval '23 hours 30 minutes', 'HH24:MI') as t1 \gset
select to_char(public.clinic_now() + interval '40 minutes', 'YYYY-MM-DD') as d2, to_char(public.clinic_now() + interval '40 minutes', 'HH24:MI') as t2 \gset
select to_char(public.clinic_now() + interval '10 hours', 'YYYY-MM-DD') as d3, to_char(public.clinic_now() + interval '10 hours', 'HH24:MI') as t3 \gset
insert into public.bookings (ref, patient_id, doctor_id, slot_date, slot_time, mode, patient_name, patient_age, patient_sex, patient_phone, doctor_fee, status)
values ('RM-DAY', :'A1', :did, :'d1', :'t1', 'clinic', 'Rem Day', 30, 'Male', '9876500777', 100, 'confirmed'),
       ('RM-HOUR', :'A1', :did, :'d2', :'t2', 'video', 'Rem Hour', 30, 'Male', '9876500778', 100, 'confirmed'),
       ('RM-LATER', :'A1', :did, :'d3', :'t3', 'clinic', 'Rem Later', 30, 'Male', '9876500779', 100, 'confirmed'),
       ('RM-PEND', :'A1', :did, :'d2', :'t2'::time + interval '5 minutes', 'clinic', 'Rem Pend', 30, 'Male', '9876500780', 100, 'pending');
select public.send_booking_reminders() as n1 \gset
select t.ok(:n1 = 2, 'a day and an hour reminder are sent, nothing for later or pending bookings');
select t.ok((select count(*) from public.notifications where user_id = :'A1' and body like 'Reminder: you have an appointment%tomorrow%') = 1, 'one day-before reminder');
select t.ok((select count(*) from public.notifications where user_id = :'A1' and body like 'Reminder: your video call%Open the app to join.') = 1, 'one hour-before reminder for a video call');
select public.send_booking_reminders() as n2 \gset
select t.ok(:n2 = 0, 'reminders are not sent twice');
select t.denied($$select public.send_booking_reminders()$$, 'permission denied', 'the public cannot trigger reminders') where false;
