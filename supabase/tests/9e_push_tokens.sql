\set P1 '00000000-0000-0000-0000-0000000c0131'
\set P2 '00000000-0000-0000-0000-0000000c0132'
\set D1 '00000000-0000-0000-0000-0000000000d1'
\set ADM '00000000-0000-0000-0000-0000000000b1'
insert into auth.users (id, email) values (:'P1', 'push1@example.com'), (:'P2', 'push2@example.com');
select t.anon();
select t.denied($$select public.register_push_token('aaaaaaaaaaaaaaaaaaaaaaaaaaaa')$$, 'permission denied', 'anonymous users cannot register a token');
select t.root();
select t.login(:'P1');
select t.denied($$select public.register_push_token('short')$$, 'invalid_token', 'a token must look real');
select public.register_push_token('token-p1-phone-aaaaaaaaaaaaaaaaaaaa');
select t.denied($$select * from public.push_tokens$$, 'permission denied', 'users cannot read the token table');
select t.denied($$select * from public.broadcast_tokens(1)$$, 'permission denied', 'users cannot read tokens for a broadcast');
select t.root();
select t.ok((select user_id from public.push_tokens where token = 'token-p1-phone-aaaaaaaaaaaaaaaaaaaa') = :'P1', 'the token belongs to the signed-in user');
-- the same phone signs in as someone else: the token moves
select t.login(:'P2');
select public.register_push_token('token-p1-phone-aaaaaaaaaaaaaaaaaaaa');
select t.root();
select t.ok((select user_id from public.push_tokens where token = 'token-p1-phone-aaaaaaaaaaaaaaaaaaaa') = :'P2', 'a shared phone follows the user who signed in last');
select t.login(:'P1');
select public.drop_push_token('token-p1-phone-aaaaaaaaaaaaaaaaaaaa');
select t.root();
select t.ok((select count(*) from public.push_tokens where token = 'token-p1-phone-aaaaaaaaaaaaaaaaaaaa') = 1, 'a user cannot drop another user''s token');
select t.login(:'P2');
select public.drop_push_token('token-p1-phone-aaaaaaaaaaaaaaaaaaaa');
select t.root();
select t.ok((select count(*) from public.push_tokens) = 0, 'a user can drop their own token (sign out)');
-- at most five phones per user
select t.login(:'P1');
select public.register_push_token('token-many-' || i || '-aaaaaaaaaaaaaaaaaaaa') from generate_series(1, 7) i;
select t.root();
select t.ok((select count(*) from public.push_tokens where user_id = :'P1') = 5, 'at most 5 phones per user are kept');
-- the tokens of a broadcast's targets
select t.login(:'D1');
select public.register_push_token('token-doctor-aaaaaaaaaaaaaaaaaaaaaaaa');
select t.root();
select t.login(:'ADM');
select public.admin_send_broadcast('{"title":"Only patients","audience":"patients"}');
select public.admin_send_broadcast('{"title":"Only doctors","audience":"doctors"}');
select t.root();
select t.ok((select count(*) from public.broadcast_tokens((select id from public.broadcasts where title = 'Only patients'))) = 5, 'a patients broadcast reaches the patient tokens only');
select t.ok((select count(*) from public.broadcast_tokens((select id from public.broadcasts where title = 'Only doctors'))) = 1, 'a doctors broadcast reaches the doctor token only');
select t.ok(public.remove_push_tokens(array['token-doctor-aaaaaaaaaaaaaaaaaaaaaaaa']) = 1, 'dead tokens can be removed by the server');
