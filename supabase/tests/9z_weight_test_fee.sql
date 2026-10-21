\set A1 '00000000-0000-0000-0000-0000000000a1'
\set ADM '00000000-0000-0000-0000-0000000000b1'
\set FO '00000000-0000-0000-0000-0000000c0701'
-- Patient weight on a booking (optional, validated, remembered on the profile)
update public.bookings set status = 'cancelled' where patient_id = :'A1' and status in ('pending','confirmed');
select t.login(:'A1');
select t.denied($$select public.create_booking(1, public.clinic_now()::date + 14, '12:40', 'clinic', 'Asha Rao', 30, 'Female', '9876543210', '', 0)$$, 'invalid_weight', 'weight below 1 kg rejected');
select t.denied($$select public.create_booking(1, public.clinic_now()::date + 14, '12:40', 'clinic', 'Asha Rao', 30, 'Female', '9876543210', '', 500)$$, 'invalid_weight', 'weight above 400 kg rejected');
select public.create_booking(1, public.clinic_now()::date + 14, '12:40', 'clinic', 'Asha Rao', 30, 'Female', '9876543210', '', 62.5);
select t.ok((select patient_weight from public.bookings where patient_id = :'A1' and slot_time = '12:40' and slot_date = public.clinic_now()::date + 14) = 62.5, 'the booking keeps the weight');
select t.ok((select weight from public.patients where id = :'A1') = 62.5, 'the weight is remembered on the patient profile');
select public.create_booking(1, public.clinic_now()::date + 14, '12:20', 'clinic', 'Asha Rao', 30, 'Female', '9876543210', '');
select t.ok((select patient_weight from public.bookings where patient_id = :'A1' and slot_time = '12:20' and slot_date = public.clinic_now()::date + 14) is null, 'weight is optional');
select t.ok((select weight from public.patients where id = :'A1') = 62.5, 'a booking without weight keeps the saved weight');
select t.root();

-- Platform fee on tests: a percent of the test price, separate from the appointment fee
insert into auth.users (id, email) values (:'FO', 'fee-lab@example.com');
select t.login(:'FO');
select public.register_facility('{"contact_phone":"9876578601","kind":"lab","name":"Fee Lab","city":"Delhi","address":"3 Lab Road","services":[["HbA1c",400],["Consultation"]]}'::jsonb);
select t.root();
select id as flid from public.facilities where user_id = :'FO' \gset
select t.login(:'ADM');
select public.admin_review_facility(:flid, 'approve', true);
select t.root();
update public.platform_settings set promo_until = null where id = 1;
select t.login(:'A1');
select public.create_facility_request(:flid, 'hba1c', public.clinic_now()::date + 2, 'Asha', '9876500001', '') as fr0 \gset
select t.ok((select platform_fee from public.facility_requests where ref = :'fr0') = 0, 'no test fee while the test fee is off');
select t.root();
update public.platform_settings set test_fee_on = true, test_fee_pct = 10 where id = 1;
select t.login(:'A1');
select public.create_facility_request(:flid, 'HbA1c', public.clinic_now()::date + 2, 'Asha', '9876500001', '') as fr1 \gset
select t.ok((select item_price from public.facility_requests where ref = :'fr1') = 400 and (select platform_fee from public.facility_requests where ref = :'fr1') = 40, 'test fee is 10 percent of the lab price');
select public.create_facility_request(:flid, 'Consultation', public.clinic_now()::date + 3, 'Asha', '9876500001', '') as fr2 \gset
select t.ok((select item_price from public.facility_requests where ref = :'fr2') is null and (select platform_fee from public.facility_requests where ref = :'fr2') = 0, 'no price listed means no fee');
select public.create_facility_request(:flid, 'Something typed by hand', public.clinic_now()::date + 3, 'Asha', '9876500001', '') as fr3 \gset
select t.ok((select platform_fee from public.facility_requests where ref = :'fr3') = 0, 'a test that is not on the lab list has no fee');
select t.root();
update public.facility_requests set status = 'cancelled' where patient_id = :'A1' and status = 'pending';
update public.platform_settings set promo_until = now() + interval '1 day' where id = 1;
select t.login(:'A1');
select public.create_facility_request(:flid, 'HbA1c', public.clinic_now()::date + 4, 'Asha', '9876500001', '') as fr4 \gset
select t.ok((select platform_fee from public.facility_requests where ref = :'fr4') = 0, 'no test fee during the free promo');
select t.root();
update public.platform_settings set promo_until = null, test_fee_on = false, test_fee_pct = 0 where id = 1;
select t.login(:'ADM');
select t.denied($$update public.platform_settings set test_fee_pct = 60 where id = 1$$, 'violates check constraint', 'test fee cannot exceed 50 percent');
select t.root();
