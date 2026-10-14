\set ADM '00000000-0000-0000-0000-0000000000b1'
\set P1 '00000000-0000-0000-0000-0000000c0141'
\set P2 '00000000-0000-0000-0000-0000000c0142'
insert into auth.users (id, email) values (:'P1', 'dash1@example.com'), (:'P2', 'dash2@example.com');
select t.login(:'P1');
select t.denied($$select public.admin_dashboard_counts()$$, 'admins_only', 'a patient cannot read the dashboard counts');
select t.denied($$select public.admin_revoke_broadcast(1)$$, 'admins_only', 'a patient cannot revoke a broadcast');
select public.register_push_token('token-dash-p1-aaaaaaaaaaaaaaaaaaaaaa');
select t.root();
select t.login(:'P2');
select public.register_push_token('token-dash-p2-aaaaaaaaaaaaaaaaaaaaaa');
select public.register_push_token('token-dash-p2b-aaaaaaaaaaaaaaaaaaaaa');
select t.root();
select t.login(:'ADM');
select t.ok((select (public.admin_dashboard_counts()->>'patients')::int) >= 2, 'patients are counted');
select t.ok((select (public.admin_dashboard_counts()->>'phones')::int) >= 3, 'registered phones are counted');
select t.ok((select (public.admin_dashboard_counts()->>'phone_users')::int) >= 2, 'users with a registered phone are counted');
select t.ok(public.admin_dashboard_counts()->'facilities' ?& array['lab','centre','hospital','pharmacy','other'], 'every facility category is present');
select t.ok(jsonb_typeof(public.admin_dashboard_counts()->'specialties') = 'array' and (public.admin_dashboard_counts()->'doctors') ? 'listed', 'doctors and specialties are present');
select public.admin_send_broadcast('{"title":"Wrong post","body":"Oops","audience":"patients"}');
select t.root();
select t.ok((select count(*) from public.notifications where body = 'Wrong post: Oops' and broadcast_id is not null) >= 2, 'each notification is linked to its broadcast');
select t.login(:'P1');
select t.ok((select count(*) from public.broadcasts where title = 'Wrong post') = 1, 'a patient can read it before it is revoked');
select t.root();
select t.ok((select count(*) from public.broadcast_tokens((select id from public.broadcasts where title = 'Wrong post')) x where x.token like 'token-dash-%') = 3, 'push would reach the registered phones');
select t.login(:'ADM');
select t.ok(public.admin_revoke_broadcast((select id from public.broadcasts where title = 'Wrong post')) >= 2, 'revoking removes the notification rows');
select t.root();
select t.ok((select count(*) from public.notifications where body = 'Wrong post: Oops') = 0, 'no notification for it is left');
select t.ok((select revoked_at is not null from public.broadcasts where title = 'Wrong post'), 'the broadcast is marked revoked');
select t.ok((select count(*) from public.broadcast_tokens((select id from public.broadcasts where title = 'Wrong post'))) = 0, 'a revoked broadcast sends no push');
select t.login(:'P1');
select t.ok((select count(*) from public.broadcasts where title = 'Wrong post') = 0, 'a patient can no longer read it');
select t.login(:'ADM');
select t.ok((select count(*) from public.broadcasts where title = 'Wrong post') = 1, 'the admin still sees it in history');
select t.denied($$select public.admin_revoke_broadcast(99999)$$, 'not_found', 'revoking an unknown broadcast is refused');
