\set A1 '00000000-0000-0000-0000-0000000000a1'
\set A2 '00000000-0000-0000-0000-0000000000a2'
-- Local stand-in for pg_net: records the calls instead of sending them.
create schema if not exists net;
create table net.calls (url text, body jsonb, headers jsonb);
create or replace function net.http_post(url text, body jsonb, headers jsonb) returns bigint language sql as $$ insert into net.calls values (url, body, headers) returning 1::bigint $$;
insert into public.push_tokens (token, user_id) values ('token-push-trigger-aaaaaaaaaaaaaaaa', :'A1');

select public.notify(:'A1', 'before the url is set');
select t.ok((select count(*) from net.calls) = 0, 'no push while the function URL is not configured');
update public.push_internal set url = 'https://example.test/functions/v1/send-push';
select public.notify(:'A2', 'user without a phone');
select t.ok((select count(*) from net.calls) = 0, 'no push for a user with no phone registered');
select public.notify(:'A1', 'You have a booking');
select t.ok((select count(*) from net.calls) = 1, 'a notification triggers one push call');
select t.ok((select body ->> 'notification_id' from net.calls limit 1)::bigint = (select max(id) from public.notifications where user_id = :'A1'), 'the push carries the notification id');
select t.ok((select headers ->> 'x-push-key' from net.calls limit 1) = (select key from public.push_internal) and (select url from net.calls limit 1) = 'https://example.test/functions/v1/send-push', 'the call goes to the function with the private key');
insert into public.broadcasts (title, body, audience) values ('Camp', 'Free camp', 'all') returning id as bid \gset
insert into public.notifications (user_id, body, broadcast_id) values (:'A1', 'broadcast row', :bid);
select t.ok((select count(*) from net.calls) = 1, 'rows that belong to a broadcast do not push twice');
insert into public.notifications (user_id, body) values (:'A1', 'plain row');
select t.ok((select count(*) from net.calls) = 2, 'plain notifications push each time');
select t.ok(has_function_privilege('anon', 'public.push_on_notification()', 'execute') = false, 'the trigger function is not callable by clients');
select t.login(:'A1');
select t.denied($$select * from public.push_internal$$, 'permission denied', 'clients cannot read the private key');
select t.root();
-- a failing push must not block the notification
create or replace function net.http_post(url text, body jsonb, headers jsonb) returns bigint language plpgsql as $$ begin raise exception 'boom'; end $$;
select public.notify(:'A1', 'still saved');
select t.ok((select count(*) from public.notifications where body = 'still saved') = 1, 'a failing push does not block the notification');
