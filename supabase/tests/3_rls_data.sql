\set A '00000000-0000-0000-0000-0000000000a1'
\set B '00000000-0000-0000-0000-0000000000a2'
\set D1 '00000000-0000-0000-0000-0000000000d1'
\set F1 '00000000-0000-0000-0000-0000000000f1'
\set ADM '00000000-0000-0000-0000-0000000000b1'
\set SAL '00000000-0000-0000-0000-0000000000c1'

-- Facility registration and review
select t.login(:'F1');
select public.register_facility('{"contact_phone":"9811100000","kind":"lab","sub":"Pathology","name":"City Diagnostics","city":"Delhi","address":"7 Lab Road","hours":"7 AM to 9 PM","home_service":true,"services":[["CBC",300],["Lipid profile",600]],"wa":"9811100000","contact_name":"R. Sharma","contact_phone":"9811100001","licence_no":"LIC-77"}'::jsonb);
select t.ok((select count(*) from public.facility_private) = 1, 'facility owner can read own private details');
select t.root();
select t.anon();
select t.ok((select count(*) from public.facilities) = 0, 'pending facility hidden from public');
select t.root();
select t.login(:'ADM');
select t.ok((select licence_no from public.facility_private) = 'LIC-77', 'admin can read facility private details');
select public.admin_review_facility(1, 'approve', true);
select t.root();
select t.anon();
select t.ok((select count(*) from public.facilities) = 1 and (select name from public.facilities) = 'City Diagnostics', 'approved facility is public');
select t.denied($$select * from public.facility_private$$, 'permission denied', 'public cannot read facility private details');
select t.denied($$select contact_phone from public.facilities$$, 'column', 'contact data is not a column of the public directory');
select t.root();
select t.login(:'A');
select t.ok((select count(*) from public.facility_private) = 0, 'patient sees no facility private rows (RLS)');
select t.root();

-- Notifications are private
select t.login(:'A');
select t.ok((select count(*) from public.notifications) >= 1, 'patient has notifications');
select t.ok((select count(*) from public.notifications where user_id <> :'A') = 0, 'patient sees only own notifications');
select public.mark_notifications_read();
select t.ok((select count(*) from public.notifications where read_at is null) = 0, 'notifications can be marked read');
select t.denied($$insert into public.notifications (user_id, body) values ('00000000-0000-0000-0000-0000000000a2', 'spam')$$, 'permission denied', 'clients cannot create notifications');
select t.root();

-- Platform settings: everyone reads, only admin writes
select t.anon();
select t.ok((select fee_value from public.platform_settings) = 49, 'platform fee is readable by anyone');
select t.denied($$update public.platform_settings set fee_value = 0$$, 'permission denied', 'anon cannot change fee');
select t.root();
select t.login(:'A');
update public.platform_settings set fee_value = 0;
select t.root();
select t.ok((select fee_value from public.platform_settings) = 49, 'patient update of the platform fee changes nothing (RLS)');
select t.login(:'ADM');
update public.platform_settings set fee_type = 'percent', fee_value = 5, support_email = 'help@example.test', support_whatsapp = '9837900303';
select t.denied($$update public.platform_settings set fee_value = 60$$, 'platform_settings_check', 'percent over 50 rejected');
select t.root();
select t.ok((select fee_type from public.platform_settings) = 'percent', 'admin can change platform fee');

-- New bookings use the new fee; old ones keep theirs.
select t.login(:'B');
select public.create_booking(1, public.clinic_now()::date + 7, '12:00', 'clinic', 'Bala K', 40, 'Male', '9876500000', '');
select t.ok((select platform_fee from public.bookings where slot_time = '12:00') = 25, 'new booking uses the new 5% fee (500 -> 25)');
select t.ok((select platform_fee from public.bookings where slot_time = '11:00') = 49, 'existing booking keeps the fee it was made with');
select t.root();

-- Leads
select t.login(:'SAL');
insert into public.leads (owner_id, name, phone, spec) values (:'SAL', 'Ravi', '9812345678', 'Dentist');
select t.denied($$insert into public.leads (owner_id, name, phone) values ('00000000-0000-0000-0000-0000000000b1', 'Spoof', '9812345679')$$, 'row-level security', 'sales cannot create leads for others');
select t.root();
select t.login(:'A');
select t.ok((select count(*) from public.leads) = 0, 'patients cannot see leads');
select t.denied($$insert into public.leads (owner_id, name, phone) values ('00000000-0000-0000-0000-0000000000a1', 'Me', '9812345670')$$, 'row-level security', 'patients cannot create leads');
select t.root();
select t.login(:'ADM');
select t.ok((select count(*) from public.leads) = 1, 'admin sees all leads');
select t.root();

-- Doctor self-service limits
select t.login(:'D1');
update public.doctors set fee_inr = 600, about = 'Updated' where id = 1;
select t.ok((select fee_inr from public.doctors where id = 1) = 600, 'doctor can edit own fee and about');
select t.denied($$update public.doctors set verified = false where id = 1$$, 'permission denied', 'doctor cannot touch verification');
select t.denied($$update public.doctors set user_id = '00000000-0000-0000-0000-0000000000a1' where id = 1$$, 'permission denied', 'doctor cannot reassign the listing');
select t.root();

-- Persistence across sessions ("another device"): a fresh login sees the same data.
select t.login(:'A');
select t.ok((select count(*) from public.bookings where patient_name = 'Asha Rao') = 1, 'bookings persist and show on a fresh session');
select t.root();
