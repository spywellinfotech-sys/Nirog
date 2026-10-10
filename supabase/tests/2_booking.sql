\set A '00000000-0000-0000-0000-0000000000a1'
\set B '00000000-0000-0000-0000-0000000000a2'
\set D1 '00000000-0000-0000-0000-0000000000d1'
\set D2 '00000000-0000-0000-0000-0000000000d2'
\set ADM '00000000-0000-0000-0000-0000000000b1'
\set DAY '(public.clinic_now()::date + 7)'

-- Doctors register; they start pending and invisible.
select t.login(:'D1');
select public.register_doctor('{"name":"Dr. Anjali Verma","spec":"General Physician","qual":"MBBS","exp_years":14,"fee_inr":500,"video_fee_inr":350,"city":"Delhi","clinic":"Shanti Clinic","address":"12 Park Road","pin":"110001","map_url":"https://www.google.com/maps/place/x/@28.6,77.2,17z","council":"Delhi Medical Council","reg_no":"DMC-1","reg_year":2008,"days":[0,1,2,3,4,5,6],"sessions":[{"s":600,"e":780}],"step":20,"wa":"9811122244"}'::jsonb);
select t.root();
select t.login(:'D2');
select public.register_doctor('{"name":"Dr. Rohit Malhotra","spec":"Cardiologist","fee_inr":900,"city":"Delhi","address":"5 Heart Lane","council":"DMC","reg_no":"DMC-2","reg_year":2001,"days":[1,2,3,4,5],"sessions":[{"s":600,"e":720}],"step":30}'::jsonb);
select t.root();
select t.ok((select role from public.profiles where id = :'D1') = 'doctor', 'registering makes the profile a doctor');
select t.ok((select status from public.doctors where id = 1) = 'pending', 'new doctor starts pending');

select t.anon();
select t.ok((select count(*) from public.doctors) = 0, 'pending doctors are hidden from the public');
select t.ok((select count(*) from public.open_slots(1, :DAY)) = 0, 'no slots for an unapproved doctor');
select t.root();

select t.login(:'A');
select t.denied($$select public.create_booking(1, public.clinic_now()::date + 7, '10:00', 'clinic', 'Asha Rao', 30, 'Female', '9876543210', '')$$, 'doctor_unavailable', 'cannot book a pending doctor');
select t.root();

select t.login(:'D1');
select t.ok((select count(*) from public.doctors) = 1, 'doctor sees own pending row');
select t.ok((select council from public.doctor_verification where doctor_id = 1) = 'Delhi Medical Council', 'doctor can read own registration details');
select t.denied($$update public.doctors set status = 'approved', verified = true where id = 1$$, 'permission denied', 'doctor cannot approve self');
select t.denied($$select public.admin_review_doctor(1, 'approve')$$, 'admins_only', 'doctor cannot call review function');
select t.root();

select t.login(:'ADM');
select public.admin_review_doctor(1, 'approve', true);
select public.admin_review_doctor(2, 'reject', false, 'Documents unclear');
select t.root();

select t.anon();
select t.ok((select count(*) from public.doctors) = 1 and (select verified from public.doctors where id = 1), 'public sees only the approved, verified doctor');
select t.denied($$select reg_no from public.doctor_verification$$, 'permission denied', 'registration number is not public');
select t.ok((select count(*) from public.open_slots(1, :DAY)) = 9, 'open_slots lists 10:00-13:00 in 20-minute steps (9 slots)');
select t.ok((select bool_and(state = 'free') from public.open_slots(1, :DAY)), 'all slots free before any booking');
select t.root();

-- Booking
select t.login(:'A');
select t.denied($$select public.create_booking(1, public.clinic_now()::date + 7, '10:05', 'clinic', 'Asha Rao', 30, 'Female', '9876543210', '')$$, 'slot_unavailable', 'off-grid time rejected');
select t.denied($$select public.create_booking(1, public.clinic_now()::date + 7, '14:00', 'clinic', 'Asha Rao', 30, 'Female', '9876543210', '')$$, 'slot_unavailable', 'outside doctor hours rejected');
select t.denied($$select public.create_booking(1, public.clinic_now()::date - 1, '10:00', 'clinic', 'Asha Rao', 30, 'Female', '9876543210', '')$$, 'slot_unavailable', 'past date rejected');
select t.denied($$select public.create_booking(1, public.clinic_now()::date + 7, '10:00', 'clinic', 'A', 30, 'Female', '9876543210', '')$$, 'invalid_name', 'short name rejected');
select t.denied($$select public.create_booking(1, public.clinic_now()::date + 7, '10:00', 'clinic', 'Asha Rao', 300, 'Female', '9876543210', '')$$, 'invalid_age', 'bad age rejected');
select t.denied($$select public.create_booking(1, public.clinic_now()::date + 7, '10:00', 'clinic', 'Asha Rao', 30, 'Female', '12345', '')$$, 'invalid_phone', 'bad phone rejected');
select t.denied($$select public.create_booking(1, public.clinic_now()::date + 7, '10:00', 'phone', 'Asha Rao', 30, 'Female', '9876543210', '')$$, 'invalid_mode', 'bad mode rejected');
select t.denied($$select public.create_booking(99, public.clinic_now()::date + 7, '10:00', 'clinic', 'Asha Rao', 30, 'Female', '9876543210', '')$$, 'doctor_unavailable', 'unknown doctor rejected');
select t.denied($$select public.create_booking(2, public.clinic_now()::date + 7, '10:00', 'clinic', 'Asha Rao', 30, 'Female', '9876543210', '')$$, 'doctor_unavailable', 'rejected doctor cannot be booked');

select public.create_booking(1, public.clinic_now()::date + 7, '10:00', 'clinic', 'Asha Rao', 30, 'Female', '9876543210', 'Fever');
select t.ok((select status::text from public.bookings where patient_name = 'Asha Rao') = 'pending', 'booking starts pending');
select t.ok((select doctor_fee from public.bookings where patient_name = 'Asha Rao') = 500 and (select platform_fee from public.bookings where patient_name = 'Asha Rao') = 49,
            'fees are computed on the server (500 + 49)');
select t.ok((select age from public.patients where id = :'A') = 30, 'patient age saved to patient record');
select t.root();

select t.anon();
select t.ok((select state from public.open_slots(1, :DAY) where slot_time = '10:00') = 'busy', 'booked slot shows busy to everyone');
select t.root();

-- Double booking: second patient, same slot.
select t.login(:'B');
select t.denied($$select public.create_booking(1, public.clinic_now()::date + 7, '10:00', 'clinic', 'Bala K', 40, 'Male', '9876500000', '')$$, 'slot_taken', 'second patient cannot take the same slot');
select t.root();
-- Even a buggy or malicious writer bypassing the function hits the database constraint.
select t.denied($$insert into public.bookings (ref, patient_id, doctor_id, slot_date, slot_time, mode, patient_name, patient_age, patient_sex, patient_phone, doctor_fee)
   values ('NR-RACE1', '00000000-0000-0000-0000-0000000000a2', 1, public.clinic_now()::date + 7, '10:00', 'clinic', 'Bala K', 40, 'Male', '9876500000', 500)$$,
   'bookings_no_double_booking', 'database constraint blocks double booking');

-- Video fee and video-not-offered
select t.login(:'B');
select public.create_booking(1, public.clinic_now()::date + 7, '10:20', 'video', 'Bala K', 40, 'Male', '9876500000', '');
select t.ok((select doctor_fee from public.bookings where patient_name = 'Bala K') = 350, 'video booking uses video fee');
select t.root();

-- Privacy between patients and doctors.
select t.login(:'A');
select t.ok((select count(*) from public.bookings) = 1 and (select patient_name from public.bookings) = 'Asha Rao', 'patient sees only own booking');
select t.denied($$select public.doctor_decide_booking((select id from public.bookings limit 1), 'confirm')$$, 'doctors_only', 'patient cannot confirm bookings');
select t.denied($$update public.bookings set status = 'confirmed'$$, 'permission denied', 'patient cannot write bookings directly');
select t.root();

select t.login(:'D2');
select t.ok((select count(*) from public.bookings) = 0, 'another doctor sees none of these bookings');
select t.root();

-- Doctor decisions
select t.login(:'D1');
select t.ok((select count(*) from public.bookings) = 2, 'doctor sees both requests');
select t.ok((select count(*) from public.notifications where body like 'New booking request%') = 2, 'doctor was notified of both requests');
select public.doctor_decide_booking((select id from public.bookings where patient_name = 'Asha Rao'), 'confirm', '10:40');
select t.ok((select status::text || slot_time::text from public.bookings where patient_name = 'Asha Rao') = 'confirmed10:40:00', 'doctor confirmed with a new time');
select t.ok((select retimed from public.bookings where patient_name = 'Asha Rao'), 'booking marked as retimed');
select t.denied($$select public.doctor_decide_booking((select id from public.bookings where patient_name = 'Asha Rao'), 'reject')$$, 'not_pending', 'cannot decide twice');
select t.denied($$select public.doctor_decide_booking((select id from public.bookings where patient_name = 'Bala K'), 'confirm', '10:40')$$, 'slot_unavailable', 'doctor cannot move a booking onto a taken slot');
select public.doctor_decide_booking((select id from public.bookings where patient_name = 'Bala K'), 'reject', null, 'On leave that day');
select t.root();

select t.login(:'B');
select t.ok((select status::text || decision_reason from public.bookings) = 'rejectedOn leave that day', 'patient sees the rejection reason');
select t.ok((select count(*) from public.notifications where body like '%could not accept%On leave%') = 1, 'patient notified of rejection');
select t.root();
select t.anon();
select t.ok((select state from public.open_slots(1, :DAY) where slot_time = '10:20') = 'free', 'rejected request releases its slot');
select t.ok((select state from public.open_slots(1, :DAY) where slot_time = '10:00') = 'free', 'old slot is free after the doctor moved the booking');
select t.ok((select state from public.open_slots(1, :DAY) where slot_time = '10:40') = 'busy', 'moved-to slot is busy');
select t.root();

-- Cancellation and rebooking the freed slot
select t.login(:'B');
select public.create_booking(1, public.clinic_now()::date + 7, '10:00', 'clinic', 'Bala K', 40, 'Male', '9876500000', '');
select public.cancel_booking((select id from public.bookings where status = 'pending'));
select t.ok((select count(*) from public.bookings where status = 'cancelled') = 1, 'patient can cancel own pending booking');
select t.denied($$select public.cancel_booking((select id from public.bookings where status = 'cancelled' limit 1))$$, 'not_cancellable', 'cannot cancel twice');
select t.denied($$select public.cancel_booking((select id from public.bookings where patient_name = 'Asha Rao'))$$, 'booking_not_found', 'cannot see or cancel another patient''s booking');
select public.create_booking(1, public.clinic_now()::date + 7, '10:00', 'clinic', 'Bala K', 40, 'Male', '9876500000', '');
select t.ok(true, 'a cancelled slot can be booked again');
select t.root();

-- Reschedule returns the booking to pending and checks the new slot.
select t.login(:'B');
select t.denied($$select public.reschedule_booking((select id from public.bookings where status = 'pending'), public.clinic_now()::date + 7, '10:40')$$, 'slot_taken', 'cannot reschedule onto a taken slot');
select public.reschedule_booking((select id from public.bookings where status = 'pending'), public.clinic_now()::date + 8, '11:00');
select t.ok((select slot_time::text from public.bookings where status = 'pending') = '11:00:00', 'reschedule moves the booking');
select t.root();

-- Days off and blocked slots
select t.login(:'D1');
insert into public.doctor_exceptions (doctor_id, day, slot_time) values (1, public.clinic_now()::date + 9, null);
insert into public.doctor_exceptions (doctor_id, day, slot_time) values (1, public.clinic_now()::date + 10, '11:00');
select t.denied($$insert into public.doctor_exceptions (doctor_id, day, slot_time) values (2, public.clinic_now()::date + 9, null)$$, 'row-level security', 'doctor cannot edit another doctor''s schedule');
select t.root();
select t.login(:'A');
select t.ok((select count(*) from public.open_slots(1, public.clinic_now()::date + 9)) = 0, 'day off shows no slots');
select t.ok((select state from public.open_slots(1, public.clinic_now()::date + 10) where slot_time = '11:00') = 'blocked', 'blocked slot shows blocked');
select t.denied($$select public.create_booking(1, public.clinic_now()::date + 9, '10:00', 'clinic', 'Asha Rao', 30, 'Female', '9876543210', '')$$, 'slot_unavailable', 'cannot book a day off');
select t.denied($$select public.create_booking(1, public.clinic_now()::date + 10, '11:00', 'clinic', 'Asha Rao', 30, 'Female', '9876543210', '')$$, 'slot_unavailable', 'cannot book a blocked slot');
select t.root();

-- Concurrency note: two sessions racing for one slot are serialised by the unique index; see tests/3_concurrency.sh.
