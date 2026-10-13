\set ADM '00000000-0000-0000-0000-0000000000b1'
\set D1 '00000000-0000-0000-0000-0000000000d1'
\set P '00000000-0000-0000-0000-0000000c0111'
\set F1 '00000000-0000-0000-0000-0000000000f1'
insert into auth.users (id, email) values (:'P', 'bc1@example.com');
select count(*) as before_n from public.notifications where user_id = :'P' \gset
select t.login(:'P');
select t.denied($$select public.admin_send_broadcast('{"title":"x","audience":"all"}')$$, 'admins_only', 'a patient cannot send a broadcast');
select t.root();
select t.login(:'ADM');
select t.denied($$select public.admin_send_broadcast('{"title":"","audience":"all"}')$$, 'invalid_title', 'a title is required');
select t.denied($$select public.admin_send_broadcast('{"title":"x","audience":"everyone"}')$$, 'invalid_audience', 'audience must be valid');
select t.denied($$select public.admin_send_broadcast('{"title":"x","audience":"all","image":"../x.jpg"}')$$, 'invalid_media', 'media paths are checked');
select public.admin_send_broadcast('{"title":"Free checkups","body":"This week only","audience":"patients","image":"a1.jpg","video":"v1.mp4"}');
select public.admin_send_broadcast('{"title":"For doctors","body":"New feature","audience":"doctors"}');
select t.ok((select sent_count from public.broadcasts where title = 'Free checkups') >= 1, 'sent count is recorded');
select t.root();
select t.ok((select count(*) from public.notifications where user_id = :'P') = :before_n + 1, 'a patient gets the patient broadcast as a notification');
select t.ok((select count(*) from public.notifications where user_id = :'P' and body like 'For doctors%') = 0, 'a patient does not get the doctors broadcast');
select t.ok((select count(*) from public.notifications where user_id = :'D1' and body like 'For doctors%') = 1, 'a doctor gets the doctors broadcast');
select t.login(:'P');
select t.ok((select count(*) from public.broadcasts) = 1 and (select title from public.broadcasts) = 'Free checkups', 'a patient can read only broadcasts meant for patients');
select t.root();
select t.login(:'D1');
select t.ok((select count(*) from public.broadcasts) = 1 and (select title from public.broadcasts) = 'For doctors', 'a doctor can read only broadcasts meant for doctors');
select t.root();
select t.anon();
select t.denied($$select * from public.broadcasts$$, 'permission denied', 'anonymous users cannot read broadcasts');
select t.root();
select t.login(:'P');
select t.denied($$select public.admin_delete_broadcast(1)$$, 'admins_only', 'a patient cannot delete a broadcast');
select t.root();
select t.login(:'ADM');
select public.admin_delete_broadcast((select id from public.broadcasts where title = 'For doctors'));
select t.ok((select count(*) from public.broadcasts) = 1, 'admin can delete a broadcast');
select t.root();
