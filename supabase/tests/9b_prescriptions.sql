\set D1 '00000000-0000-0000-0000-0000000000d1'
\set D2 '00000000-0000-0000-0000-0000000000d2'
\set ADM '00000000-0000-0000-0000-0000000000b1'
\set P '00000000-0000-0000-0000-0000000c0101'
\set Q '00000000-0000-0000-0000-0000000c0102'
insert into auth.users (id, email) values (:'P', 'rx1@example.com'), (:'Q', 'rx2@example.com');
select id as did from public.doctors where user_id = :'D1' \gset
insert into public.bookings (ref, patient_id, doctor_id, slot_date, slot_time, mode, patient_name, patient_age, patient_sex, patient_phone, doctor_fee, status)
values ('RX-TODAY', :'P', :did, public.clinic_now()::date, '03:07', 'clinic', 'Asha Verma', 30, 'Female', '9876500021', 500, 'confirmed'),
       ('RX-NEXT',  :'P', :did, public.clinic_now()::date + 5, '03:07', 'clinic', 'Asha Verma', 30, 'Female', '9876500021', 500, 'confirmed'),
       ('RX-PEND',  :'P', :did, public.clinic_now()::date - 1, '03:27', 'clinic', 'Asha Verma', 30, 'Female', '9876500021', 500, 'pending');
select id as bt from public.bookings where ref = 'RX-TODAY' \gset
select id as bn from public.bookings where ref = 'RX-NEXT' \gset
select id as bp from public.bookings where ref = 'RX-PEND' \gset

select t.login(:'P');
select t.denied('select public.save_prescription(''{"booking_id":"'||:'bt'||'","advice":"x"}'')', 'doctors_only', 'a patient cannot write a prescription');
select t.root();
select t.login(:'D2');
select t.denied('select public.save_prescription(''{"booking_id":"'||:'bt'||'","advice":"x"}'')', 'booking_not_found', 'another doctor cannot write it');
select t.root();
select t.login(:'D1');
select t.denied('select public.save_prescription(''{"booking_id":"'||:'bn'||'","advice":"x"}'')', 'visit_not_started', 'not before the visit day');
select t.denied('select public.save_prescription(''{"booking_id":"'||:'bp'||'","advice":"x"}'')', 'booking_not_confirmed', 'only a confirmed booking');
select t.denied('select public.save_prescription(''{"booking_id":"'||:'bt'||'"}'')', 'empty_prescription', 'an empty prescription is refused');
select t.denied('select public.save_prescription(''{"booking_id":"'||:'bt'||'","files":["other/x.jpg"]}'')', 'invalid_files', 'files must live under the booking folder');
select t.denied('select public.save_prescription(''{"booking_id":"'||:'bt'||'","advice":"x","follow_up":"2001-01-01"}'')', 'invalid_follow_up', 'follow-up cannot be in the past');
select public.save_prescription(jsonb_build_object('booking_id', :'bt', 'diagnosis', 'Viral fever', 'advice', 'Rest and fluids',
  'medicines', jsonb_build_array(jsonb_build_object('name','Paracetamol 500','dose','1 tab','freq','Twice a day','days','3'), jsonb_build_object('name','  ')),
  'files', jsonb_build_array(:'bt' || '/rx1.jpg')));
select t.ok((select jsonb_array_length(medicines) from public.prescriptions) = 1, 'blank medicine rows are dropped');
select public.save_prescription(jsonb_build_object('booking_id', :'bt', 'advice', 'Rest, fluids and review'));
select t.ok((select count(*) from public.prescriptions) = 1 and (select advice from public.prescriptions) like '%review', 'saving again edits the same prescription');
select t.root();
select t.ok((select count(*) from public.notifications where user_id = :'P' and body like '%prescription%') = 2, 'the patient is notified');
select t.login(:'P');
select t.ok((select count(*) from public.prescriptions) = 1, 'the patient sees their prescription');
select t.root();
select t.login(:'Q');
select t.ok((select count(*) from public.prescriptions) = 0, 'another patient sees nothing');
select t.root();
select t.login(:'D2');
select t.ok((select count(*) from public.prescriptions) = 0, 'another doctor sees nothing');
select t.root();
select t.login(:'ADM');
select t.ok((select count(*) from public.prescriptions) = 1, 'admin can read it');
select t.root();
select t.anon();
select t.denied($$select * from public.prescriptions$$, 'permission denied', 'anonymous users cannot read prescriptions');
select t.root();
