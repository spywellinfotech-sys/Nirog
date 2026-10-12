\set ADM '00000000-0000-0000-0000-0000000000b1'
\set P '00000000-0000-0000-0000-0000000c0093'
\set Q '00000000-0000-0000-0000-0000000c0094'
insert into auth.users (id, email) values (:'P', 'rev1@example.com'), (:'Q', 'rev2@example.com');
select id as did from public.doctors order by id limit 1 \gset
insert into public.bookings (ref, patient_id, doctor_id, slot_date, slot_time, mode, patient_name, patient_age, patient_sex, patient_phone, doctor_fee, status)
values ('RV-PAST', :'P', :did, public.clinic_now()::date - 3, '10:00', 'clinic', 'Asha Verma', 30, 'Female', '9876500011', 500, 'confirmed'),
       ('RV-NEXT', :'P', :did, public.clinic_now()::date + 5, '10:00', 'clinic', 'Asha Verma', 30, 'Female', '9876500011', 500, 'confirmed'),
       ('RV-PEND', :'P', :did, public.clinic_now()::date - 2, '11:00', 'clinic', 'Asha Verma', 30, 'Female', '9876500011', 500, 'pending');
select id as bpast from public.bookings where ref = 'RV-PAST' \gset
select id as bnext from public.bookings where ref = 'RV-NEXT' \gset
select id as bpend from public.bookings where ref = 'RV-PEND' \gset

select t.login(:'Q');
select t.denied('select public.submit_review('''||:'bpast'||''', 5, ''x'')', 'booking_not_found', 'another patient cannot review someone else''s visit');
select t.root();
select t.login(:'P');
select t.denied('select public.submit_review('''||:'bnext'||''', 5, ''x'')', 'visit_not_done', 'a future visit cannot be reviewed');
select t.denied('select public.submit_review('''||:'bpend'||''', 5, ''x'')', 'booking_not_confirmed', 'a pending booking cannot be reviewed');
select t.denied('select public.submit_review('''||:'bpast'||''', 6, ''x'')', 'invalid_rating', 'rating must be 1 to 5');
select public.submit_review(:'bpast', 4, 'Very patient doctor');
select t.ok((select count(*) from public.reviews) = 1, 'the patient can review a confirmed past visit');
select public.submit_review(:'bpast', 5, 'Updated review');
select t.ok((select count(*) from public.reviews) = 1 and (select rating from public.reviews) = 5, 'reviewing again edits the same review');
select t.root();
select t.anon();
select t.ok((select n from public.doctor_ratings where doctor_id = :did) = 1 and (select avg_rating from public.doctor_ratings where doctor_id = :did) = 5.0, 'anyone can see the rating summary');
select t.ok((select patient_name from public.doctor_reviews limit 1) = 'Asha', 'public reviews show the first name only');
select t.denied($$select * from public.reviews$$, 'permission denied', 'the raw reviews table is not public');
select t.root();
select t.login(:'P');
select t.denied('select public.admin_delete_review(1)', 'admins_only', 'a patient cannot delete reviews');
select t.root();
select t.login(:'ADM');
select public.admin_delete_review((select id from public.reviews limit 1));
select t.root();
select t.ok((select count(*) from public.reviews) = 0, 'admin can delete a review');
