\set ADM '00000000-0000-0000-0000-0000000000b1'
\set P1 '00000000-0000-0000-0000-0000000c0121'
\set P2 '00000000-0000-0000-0000-0000000c0122'
\set P3 '00000000-0000-0000-0000-0000000c0123'
insert into auth.users (id, email) values (:'P1', 'geo1@example.com'), (:'P2', 'geo2@example.com'), (:'P3', 'geo3@example.com');
select t.login(:'P1');
update public.patients set city = ' Pune ' where id = :'P1';
select t.ok((select city from public.patients where id = :'P1') = ' Pune ', 'a patient can save their own city');
select t.root();
select t.login(:'P2');
update public.patients set city = 'Delhi' where id = :'P2';
select t.root();
-- P3 has no city
select t.login(:'P1');
select t.denied($$select public.admin_broadcast_reach('patients', 'Pune')$$, 'admins_only', 'a patient cannot count reach');
select t.root();
select t.login(:'ADM');
select t.ok(public.admin_broadcast_reach('patients', 'pune') = 1, 'city match ignores case and spaces');
select t.ok(public.admin_broadcast_reach('patients', 'Delhi') = 1, 'another city counts separately');
select t.ok(public.admin_broadcast_reach('patients', null) >= 3, 'no city means every patient');
select t.ok(public.admin_broadcast_reach('patients', 'Nowhere') = 0, 'an empty city reaches nobody');
select public.admin_send_broadcast('{"title":"Pune camp","body":"Sunday","audience":"patients","city":"Pune"}');
select public.admin_send_broadcast('{"title":"Everyone","audience":"patients"}');
select t.root();
select t.ok((select count(*) from public.notifications where user_id = :'P1' and body like 'Pune camp%') = 1, 'the Pune patient gets the Pune broadcast');
select t.ok((select count(*) from public.notifications where user_id = :'P2' and body like 'Pune camp%') = 0, 'a Delhi patient does not');
select t.ok((select count(*) from public.notifications where user_id = :'P3' and body like 'Pune camp%') = 0, 'a patient with no city does not');
select t.ok((select count(*) from public.notifications where user_id = :'P3' and body like 'Everyone%') = 1, 'a broadcast without a city still reaches them');
select t.login(:'P1');
select t.ok((select count(*) from public.broadcasts where title = 'Pune camp') = 1, 'the Pune patient can read the Pune broadcast');
select t.root();
select t.login(:'P2');
select t.ok((select count(*) from public.broadcasts where title = 'Pune camp') = 0 and (select count(*) from public.broadcasts where title = 'Everyone') = 1, 'a Delhi patient reads only the broadcast for everyone');
select t.root();
