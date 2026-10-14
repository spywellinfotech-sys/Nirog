\set ADM '00000000-0000-0000-0000-0000000000b1'
\set P1 '00000000-0000-0000-0000-0000000c0151'
insert into auth.users (id, email) values (:'P1', 'amb1@example.com');
select t.login(:'ADM');
select public.admin_save_ambulance('{"name":"City Care Ambulance","phone":"98765 43210","city":"Pune","kind":"private","note":"24x7"}');
select public.admin_save_ambulance('{"name":"Anywhere Ambulance","phone":"9123456789","kind":"private"}');
select public.admin_save_ambulance('{"name":"Hidden Ambulance","phone":"9000000000","active":false}');
select t.denied($$select public.admin_save_ambulance('{"name":"Bad","phone":"abc"}')$$, 'invalid_phone', 'a phone must look like a number');
select t.denied($$select public.admin_save_ambulance('{"name":"A","phone":"9123456789"}')$$, 'invalid_name', 'a name needs 3 letters');
select t.denied($$select public.admin_save_ambulance('{"name":"Okay Name","phone":"9123456789","kind":"x"}')$$, 'invalid_kind', 'the kind is checked');
select t.ok((select count(*) from public.ambulance_services where name = 'Hidden Ambulance') = 1, 'the admin sees an inactive service');
select t.root();
select t.anon();
select t.ok((select count(*) from public.ambulance_services where name in ('City Care Ambulance','Anywhere Ambulance')) = 2, 'anyone can read active services');
select t.ok((select count(*) from public.ambulance_services where name = 'Hidden Ambulance') = 0, 'inactive services are hidden from the public');
select t.ok((select city is null from public.ambulance_services where name = 'Anywhere Ambulance'), 'a blank city means every location');
select t.denied($$insert into public.ambulance_services (name, phone) values ('Sneaky One','9123456789')$$, 'permission denied', 'the public cannot add services');
select t.root();
select t.login(:'P1');
select t.denied($$select public.admin_save_ambulance('{"name":"Patient Add","phone":"9123456789"}')$$, 'admins_only', 'a patient cannot add a service');
select t.denied($$select public.admin_delete_ambulance(1)$$, 'admins_only', 'a patient cannot delete a service');
select t.root();
select t.login(:'ADM');
select public.admin_save_ambulance(json_build_object('id', (select id from public.ambulance_services where name = 'City Care Ambulance'), 'name', 'City Care Ambulance', 'phone', '9876543210', 'city', 'Pune', 'kind', 'govt')::jsonb);
select t.ok((select kind = 'govt' and phone = '9876543210' from public.ambulance_services where name = 'City Care Ambulance'), 'the admin can edit a service');
select t.ok(public.admin_delete_ambulance((select id from public.ambulance_services where name = 'Hidden Ambulance')), 'the admin can delete a service');
select t.root();
