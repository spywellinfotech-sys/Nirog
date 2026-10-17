\set D1 '00000000-0000-0000-0000-0000000000d1'
\set F1 '00000000-0000-0000-0000-0000000000f1'
\set A1 '00000000-0000-0000-0000-0000000000a1'
\set A2 '00000000-0000-0000-0000-0000000000a2'
\set ADM '00000000-0000-0000-0000-0000000000b1'
\set N1 '00000000-0000-0000-0000-0000000c0301'
\set N2 '00000000-0000-0000-0000-0000000c0302'
\set N3 '00000000-0000-0000-0000-0000000c0303'
insert into auth.users (id, email) values (:'N1', 'ref-n1@example.com'), (:'N2', 'ref-n2@example.com'), (:'N3', 'ref-n3@example.com');

select t.denied($$select public.my_referral()$$, 'not_authenticated', 'anonymous cannot read a wallet');
select t.login(:'A1');
select public.my_referral() as r1 \gset
select t.ok(length(:'r1'::jsonb ->> 'code') = 8 and (:'r1'::jsonb ->> 'balance')::int = 0, 'a user gets a referral code and an empty wallet');
select (public.my_referral() ->> 'code') = (:'r1'::jsonb ->> 'code') as same \gset
select t.ok(:'same', 'the code stays the same');
select :'r1'::jsonb ->> 'code' as acode \gset

-- A new patient applies the code: the referrer gets the patient reward at once.
select t.login(:'N1');
select t.denied($$select public.apply_referral('NOPE1234')$$, 'invalid_code', 'unknown code is refused');
select public.my_referral() ->> 'code' as n1code \gset
select t.denied(format($$select public.apply_referral(%L)$$, :'n1code'), 'own_code', 'own code is refused');
select t.ok(public.apply_referral(lower(:'acode')), 'a valid code is accepted (any case)');
select t.denied(format($$select public.apply_referral(%L)$$, :'acode'), 'already_applied', 'a code can be applied only once');
select t.login(:'A1');
select t.ok((public.my_referral() ->> 'balance')::int = 1, 'patient install pays Rs 1');

-- Old accounts cannot apply a code.
select t.root();
update public.profiles set created_at = now() - interval '5 days' where id = :'N2';
select t.login(:'N2');
select t.denied(format($$select public.apply_referral(%L)$$, :'acode'), 'too_late', 'accounts older than 3 days cannot apply a code');

-- Doctor registration pays only after admin approval.
select t.root();
select t.login(:'N3');
select t.ok(public.apply_referral(:'acode'), 'second invitee applies the code');
select t.root();
select t.login(:'A1');
select t.ok((public.my_referral() ->> 'balance')::int = 2, 'second patient install pays Rs 1');

select t.root();
select id as did from public.doctors where user_id = :'D1' \gset
-- make D1 a referred, pending doctor
update public.profiles set referred_by = (select id from public.profiles where ref_code = :'acode') where id = :'D1';
update public.doctors set status = 'pending', verified = false where id = :did;
select t.login(:'A1');
select t.ok((public.my_referral() ->> 'balance')::int = 2, 'a pending doctor pays nothing yet');
select t.login(:'ADM');
select public.admin_review_doctor(:did, 'approve');
select public.admin_review_doctor(:did, 'approve');
select t.root();
select t.ok((select count(*) from public.referral_rewards where referred_id = :'D1' and kind = 'doctor') = 1, 'approving twice pays once');
select t.login(:'A1');
select t.ok((public.my_referral() ->> 'balance')::int = 12, 'approved doctor pays Rs 10');
select t.login(:'ADM');
select public.admin_review_doctor(:did, 'reject', false, 'test');
select t.root();
select t.ok((select count(*) from public.wallet_ledger where user_id = :'A1' and kind = 'referral') = 3, 'rejection pays nothing');

-- Facility reward
select t.root();
select id as fid from public.facilities where user_id = :'F1' \gset
update public.profiles set referred_by = (select id from public.profiles where ref_code = :'acode') where id = :'F1';
select t.login(:'ADM');
select public.admin_review_facility(:fid, 'approve');
select t.login(:'A1');
select t.ok((public.my_referral() ->> 'balance')::int = 22, 'approved facility pays Rs 10');

-- Withdrawals
select t.denied($$select public.request_withdrawal(100, 'asha@upi')$$, 'insufficient_balance', 'cannot withdraw more than the balance');
select t.denied($$select public.request_withdrawal(10, 'asha@upi')$$, 'below_minimum', 'cannot withdraw below the minimum');
select t.denied($$select public.request_withdrawal(50, 'not an upi')$$, 'invalid_upi', 'bad UPI id is refused');
select t.root();
update public.referral_settings set min_withdraw = 20;
select t.login(:'A1');
select public.request_withdrawal(20, 'Asha@OKbank') as wid \gset
select t.ok((public.my_referral() ->> 'balance')::int = 2, 'a withdrawal request holds the amount');
select t.ok((public.my_referral() -> 'withdrawals' -> 0 ->> 'upi') = 'asha@okbank', 'UPI id is stored lower case');
select t.denied($$select public.request_withdrawal(20, 'asha@upi')$$, 'pending_exists', 'only one pending request at a time');
select t.denied($$select public.admin_withdrawals()$$, 'admins_only', 'users cannot list payouts');
select t.denied(format($$select public.admin_decide_withdrawal(%s, 'paid', 'X1')$$, :wid), 'admins_only', 'users cannot pay out');
select t.login(:'ADM');
select t.ok(jsonb_array_length(public.admin_withdrawals()) = 1, 'admin sees the pending request');
select t.denied(format($$select public.admin_decide_withdrawal(%s, 'paid')$$, :wid), 'utr_required', 'payment needs a UTR');
select public.admin_decide_withdrawal(:wid, 'reject', null, 'wrong UPI');
select t.login(:'A1');
select t.ok((public.my_referral() ->> 'balance')::int = 22, 'a rejected withdrawal returns the money');
select public.request_withdrawal(22, 'asha@okbank') as wid2 \gset
select t.login(:'ADM');
select public.admin_decide_withdrawal(:wid2, 'paid', 'UTR123456');
select t.denied(format($$select public.admin_decide_withdrawal(%s, 'reject')$$, :wid2), 'already_decided', 'a paid request cannot be changed');
select t.login(:'A1');
select t.ok((public.my_referral() ->> 'balance')::int = 0, 'paid withdrawal leaves zero balance');

-- Tables are not directly readable
select t.denied($$select * from public.wallet_ledger$$, 'permission denied', 'ledger is not directly readable');
select t.denied($$update public.wallet_ledger set amount_inr = 999$$, 'permission denied', 'ledger cannot be edited by users');
