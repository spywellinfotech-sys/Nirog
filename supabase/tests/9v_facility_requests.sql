\set A1 '00000000-0000-0000-0000-0000000000a1'
\set ADM '00000000-0000-0000-0000-0000000000b1'
\set FO '00000000-0000-0000-0000-0000000c0501'
\set FO2 '00000000-0000-0000-0000-0000000c0502'
insert into auth.users (id, email) values (:'FO', 'fr-lab@example.com'), (:'FO2', 'fr-lab2@example.com');
select t.login(:'FO');
select public.register_facility('{"contact_phone":"9876578001","kind":"lab","name":"Request Lab","city":"Delhi","address":"1 Lab Road","services":[]}'::jsonb);
select t.root();
select id as fid from public.facilities where user_id = :'FO' \gset
select t.login(:'FO2');
select public.register_facility('{"contact_phone":"9876578002","kind":"hospital","name":"Other Hospital","city":"Delhi","address":"2 Hospital Road","services":[]}'::jsonb);
select t.root();
select id as fid2 from public.facilities where user_id = :'FO2' \gset
select t.login(:'A1');
select t.denied($$select public.create_facility_request((select id from public.facilities where name='Request Lab'),'CBC','2099-01-01','Asha','9876500001','')$$, 'facility_unavailable', 'a facility that is not approved cannot take requests');
select t.root();
select t.login(:'ADM');
select public.admin_review_facility(:fid, 'approve', true);
select public.admin_review_facility(:fid2, 'approve', true);
select t.root();
select t.login(:'A1');
select t.denied($$select public.create_facility_request(0,'CBC',public.clinic_now()::date+1,'Asha','9876500001','')$$, 'facility_unavailable', 'unknown facility');
select t.denied($$select public.create_facility_request((select id from public.facilities where name='Request Lab'),'','2099-01-01','Asha','9876500001','')$$, 'invalid_item', 'a test or service is required');
select t.denied($$select public.create_facility_request((select id from public.facilities where name='Request Lab'),'CBC',public.clinic_now()::date+1,'Asha','12345','')$$, 'invalid_phone', 'a valid mobile number is required');
select t.denied($$select public.create_facility_request((select id from public.facilities where name='Request Lab'),'CBC',public.clinic_now()::date-1,'Asha','9876500001','')$$, 'invalid_date', 'past dates are refused');
select t.denied($$select public.create_facility_request((select id from public.facilities where name='Request Lab'),'CBC',public.clinic_now()::date+90,'Asha','9876500001','')$$, 'invalid_date', 'dates more than 60 days away are refused');
select public.create_facility_request(:fid, 'CBC blood test', public.clinic_now()::date+2, 'Asha', '9876500001', 'Fasting') as ref1 \gset
select public.create_facility_request(:fid, 'Thyroid profile', public.clinic_now()::date+3, 'Asha', '9876500001', '') as ref2 \gset
select public.create_facility_request(:fid2, 'Knee consult', public.clinic_now()::date+3, 'Asha', '9876500001', '') as ref3 \gset
select t.ok((select count(*) from public.facility_requests) = 3, 'the patient sees their own requests');
select t.root();
select t.ok((select count(*) from public.notifications where user_id = :'FO' and body like 'New appointment request%') = 2, 'the lab is notified of each request');
select t.login(:'FO');
select t.ok((select count(*) from public.facility_requests) = 2, 'a facility sees only its own requests');
select id as rid from public.facility_requests where ref = :'ref1' \gset
select id as rid2 from public.facility_requests where ref = :'ref2' \gset
select t.denied($$select public.decide_facility_request(1, 'maybe', '')$$, 'invalid_status', 'only confirm or reject');
select public.decide_facility_request(:rid, 'confirmed', '');
select public.decide_facility_request(:rid2, 'rejected', 'Test not available');
select t.denied(format('select public.decide_facility_request(%s, ''rejected'', '''')', :rid), 'already_decided', 'a decided request cannot be changed');
select t.root();
select t.login(:'FO2');
select t.denied(format('select public.decide_facility_request(%s, ''confirmed'', '''')', :rid), 'not_found', 'another facility cannot decide it');
select t.root();
select t.login(:'A1');
select t.ok((select status from public.facility_requests where ref = :'ref1') = 'confirmed', 'the patient sees it confirmed');
select public.cancel_facility_request(:rid);
select t.ok((select status from public.facility_requests where ref = :'ref1') = 'cancelled', 'the patient can cancel');
select t.denied($$select public.admin_request_stats()$$, 'admins_only', 'patients cannot read the counts');
select t.denied($$insert into public.facility_requests (ref,facility_id,patient_id,patient_name,patient_phone,item,preferred_date) values ('X',1,'00000000-0000-0000-0000-0000000000a1','a','9','x',now())$$, 'permission denied', 'no direct inserts');
select t.root();
select t.login(:'ADM');
select public.admin_request_stats() as st \gset
select t.ok((:'st'::jsonb -> (:fid)::text ->> 'total')::int = 2 and (:'st'::jsonb -> (:fid)::text ->> 'rejected')::int = 1, 'admin sees per-facility counts');
select t.root();
select public.admin_delete_patient(:'A1'::uuid) where false;
