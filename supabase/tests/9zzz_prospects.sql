\set ADM '00000000-0000-0000-0000-0000000000b1'
\set A1 '00000000-0000-0000-0000-0000000000a1'
select t.login(:'A1');
select t.denied($$select public.admin_import_prospects('[{"name":"Dr Test","phone":"9811100001"}]'::jsonb)$$, 'admins_only', 'a patient cannot import contacts');
select t.ok((select count(*) from public.prospects) = 0, 'a patient cannot read the contact list');
select t.root();
select t.login(:'ADM');
select public.admin_import_prospects('[{"kind":"doctor","name":"Dr Asha","phone":"+91 98111-00001","city":"Pune","spec":"Dentist"},{"kind":"lab","name":"City Lab","email":"Lab@Example.com"},{"kind":"pharmacy","name":"No Contact"},{"kind":"weird","name":"Odd Kind","phone":"9811100003"},{"kind":"doctor","name":"Dr Dup","phone":"9811100001"}]'::jsonb) as imp \gset
select t.ok((:'imp'::jsonb ->> 'added')::int = 3 and (:'imp'::jsonb ->> 'duplicates')::int = 1 and (:'imp'::jsonb ->> 'invalid')::int = 1, 'import counts added, duplicate and invalid rows');
select t.ok((select phone from public.prospects where name = 'Dr Asha') = '9811100001', 'phone is cleaned to 10 digits');
select t.ok((select email from public.prospects where name = 'City Lab') = 'lab@example.com', 'email is lower-cased');
select t.ok((select kind from public.prospects where name = 'Odd Kind') = 'other', 'unknown type becomes other');
select id as pid from public.prospects where name = 'Dr Asha' \gset
select public.admin_prospect_messaged(:pid);
select public.admin_prospect_messaged(:pid);
select t.ok((select msg_count from public.prospects where id = :pid) = 2 and (select status from public.prospects where id = :pid) = 'messaged' and (select last_messaged_at from public.prospects where id = :pid) is not null, 'messaging is counted and the status moves to messaged');
select public.admin_set_prospect(:pid, 'interested', 'Call Monday');
select t.ok((select status || '|' || note from public.prospects where id = :pid) = 'interested|Call Monday', 'status and note are saved');
select public.admin_prospect_messaged(:pid);
select t.ok((select status from public.prospects where id = :pid) = 'interested', 'messaging again keeps the status');
select t.denied($$select public.admin_set_prospect(1, 'bogus')$$, 'invalid_status', 'a bad status is refused');
select public.admin_delete_prospect(:pid);
select t.ok((select count(*) from public.prospects where id = :pid) = 0, 'a contact can be removed');
select t.root();
