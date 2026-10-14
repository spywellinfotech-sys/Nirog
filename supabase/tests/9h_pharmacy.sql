\set U1 '00000000-0000-0000-0000-0000000c0161'
insert into auth.users (id, email) values (:'U1', 'pharm1@example.com');
select t.login(:'U1');
select public.register_facility('{"contact_phone":"9876577001","kind":"pharmacy","name":"Green Cross Pharmacy","city":"Delhi","address":"12 Market Road","home_service":true,"services":[["Prescription medicines"],["Home delivery"]],"contact_name":"A. Gupta"}'::jsonb);
select t.root();
select t.ok((select kind from public.facilities where name = 'Green Cross Pharmacy') = 'pharmacy', 'a pharmacy can register as its own facility type');
select t.ok((select status::text from public.facilities where name = 'Green Cross Pharmacy') = 'pending', 'a new pharmacy waits for the super admin to review it');
select t.denied($$update public.facilities set kind = 'grocery' where name = 'Green Cross Pharmacy'$$, 'facilities_kind_check', 'unknown facility types are refused');
