\set U1 '00000000-0000-0000-0000-0000000c0171'
insert into auth.users (id, email) values (:'U1', 'amb1@example.com');
select t.login(:'U1');
select public.register_facility('{"contact_phone":"9876577002","kind":"ambulance","name":"City Care Ambulance","city":"Delhi","address":"Depot Road","emergency":true,"wa":"9876543210","services":[["Basic life support"]],"contact_name":"R. Singh"}'::jsonb);
select t.root();
select t.ok((select kind from public.facilities where name = 'City Care Ambulance') = 'ambulance', 'an ambulance service can register as a facility');
select t.ok((select status::text from public.facilities where name = 'City Care Ambulance') = 'pending', 'a new ambulance service waits for review');
