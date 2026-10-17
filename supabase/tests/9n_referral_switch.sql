\set A1 '00000000-0000-0000-0000-0000000000a1'
\set ADM '00000000-0000-0000-0000-0000000000b1'
\set N1 '00000000-0000-0000-0000-0000000c0401'
\set N2 '00000000-0000-0000-0000-0000000c0402'
insert into auth.users (id, email) values (:'N1', 'sw-n1@example.com'), (:'N2', 'sw-n2@example.com');
select t.login(:'A1');
select public.my_referral() ->> 'code' as acode \gset
select t.ok((public.my_referral() ->> 'enabled')::boolean, 'programme is on by default');
select public.my_referral() ->> 'balance' as bal0 \gset
select t.denied($$select public.admin_referral_settings('{"enabled":false}')$$, 'admins_only', 'users cannot switch the programme');
select t.login(:'ADM');
select t.ok(not (public.admin_referral_settings('{"enabled":false}')).enabled, 'admin can switch the programme off');
select t.login(:'N1');
select t.denied(format($$select public.apply_referral(%L)$$, :'acode'), 'program_off', 'codes cannot be applied while off');
select t.login(:'ADM');
select public.admin_referral_settings('{"enabled":true}');
select t.login(:'N2');
select t.ok(public.apply_referral(:'acode'), 'codes work again when switched on');
select t.root();
select t.login(:'A1');
select t.ok((public.my_referral() ->> 'balance')::int = :bal0::int + 1, 'reward is paid again after switching on');
