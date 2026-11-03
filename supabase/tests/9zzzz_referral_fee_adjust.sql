\set U '00000000-0000-0000-0000-0000000c0801'
\set ADM '00000000-0000-0000-0000-0000000000b1'
-- Referral reward Rs 2 and the first Rs 100 of the wallet used against platform fees
insert into auth.users (id, email) values (:'U', 'fee-adjust@example.com');
select t.ok((select patient_inr = 2 and doctor_inr = 2 and facility_inr = 2 and fee_adjust_inr = 100 from public.referral_settings), 'shipped defaults: Rs 2 per referral, Rs 100 reserved for platform fees');
update public.referral_settings set min_withdraw = 20, enabled = true;
update public.platform_settings set fee_on = true, fee_type = 'flat', fee_value = 30, promo_until = null where id = 1;
insert into public.wallet_ledger (user_id, amount_inr, kind, note) values (:'U', 40, 'referral', 'test credit');

select t.login(:'U');
select t.ok((public.my_referral() ->> 'fee_credit')::int = 40 and (public.my_referral() ->> 'withdrawable')::int = 0, 'all of a small wallet is reserved for platform fees');
select (public.create_booking(1, public.clinic_now()::date + 27, '12:40', 'clinic', 'Fee Adjust', 30, 'Female', '9876543210', '')).id as b1 \gset
select t.ok((select platform_fee = 0 and fee_adjusted = 30 from public.bookings where id = :'b1'), 'the wallet pays the whole platform fee');
select t.ok((public.my_referral() ->> 'balance')::int = 10, 'the wallet goes down by the adjusted fee');
select (public.create_booking(1, public.clinic_now()::date + 27, '12:20', 'clinic', 'Fee Adjust', 30, 'Female', '9876543210', '')).id as b2 \gset
select t.ok((select platform_fee = 20 and fee_adjusted = 10 from public.bookings where id = :'b2'), 'a partly covered fee: the wallet pays what it has, the patient pays the rest');
select t.ok((public.my_referral() ->> 'balance')::int = 0, 'wallet is empty after both bookings');

-- Cancelling gives the credit back once.
select public.cancel_booking(:'b1');
select t.ok((public.my_referral() ->> 'balance')::int = 30, 'a cancelled booking returns its credit');
select t.ok((select fee_returned from public.bookings where id = :'b1'), 'the booking is marked as returned');
select t.root();
update public.bookings set status = 'confirmed' where id = :'b1';
update public.bookings set status = 'cancelled' where id = :'b1';
select t.ok((select count(*) from public.wallet_ledger where user_id = :'U' and kind = 'fee_refund') = 1, 'credit is returned only once');
select t.login(:'U');

-- Reserved money cannot be withdrawn; money above the reservation can.
select t.denied($$select public.request_withdrawal(20, 'asha@upi', '9876543210')$$, 'insufficient_balance', 'reserved fee credit cannot be withdrawn');
select t.root();
insert into public.wallet_ledger (user_id, amount_inr, kind, note) values (:'U', 80, 'referral', 'more credit');
select t.login(:'U');
select t.ok((public.my_referral() ->> 'withdrawable')::int = 20, 'only the money above the reserved amount is withdrawable');
select t.ok(public.request_withdrawal(20, 'asha@upi', '9876543210') is not null, 'the withdrawable part can be withdrawn');

-- The admin can change or switch off the reservation.
select t.root();
select t.login(:'ADM');
select t.ok((public.admin_referral_settings('{"fee_adjust_inr": 0}'::jsonb)).fee_adjust_inr = 0, 'admin can switch the fee adjustment off');
select t.root();
select t.login(:'U');
select (public.create_booking(1, public.clinic_now()::date + 28, '12:40', 'clinic', 'Fee Adjust', 30, 'Female', '9876543210', '')).id as b3 \gset
select t.ok((select platform_fee = 30 and fee_adjusted = 0 from public.bookings where id = :'b3'), 'with the adjustment off the patient pays the full platform fee');
select t.root();
update public.referral_settings set fee_adjust_inr = 100;
update public.platform_settings set fee_on = false where id = 1;
