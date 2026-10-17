\set D1 '00000000-0000-0000-0000-0000000000d1'
\set A1 '00000000-0000-0000-0000-0000000000a1'
\set A2 '00000000-0000-0000-0000-0000000000a2'
\set ADM '00000000-0000-0000-0000-0000000000b1'
select id as did from public.doctors where user_id = :'D1' \gset
select t.login(:'ADM');
select public.admin_doctor_stats(:did) as st0 \gset
select t.root();
-- Three confirmed bookings (one video), one cancelled; platform fee 20 on each; one prescription.
insert into public.bookings (ref, patient_id, doctor_id, slot_date, slot_time, mode, patient_name, patient_age, patient_sex, patient_phone, reason, doctor_fee, platform_fee, status)
values ('ACC-1', :'A1', :did, public.clinic_now()::date + 20, '07:11', 'clinic', 'Asha', 30, 'Female', '9876500401', '', 500, 20, 'confirmed'),
       ('ACC-2', :'A1', :did, public.clinic_now()::date + 20, '07:31', 'video', 'Asha', 30, 'Female', '9876500401', '', 300, 20, 'confirmed'),
       ('ACC-3', :'A2', :did, public.clinic_now()::date + 20, '07:51', 'clinic', 'Bala', 30, 'Male', '9876500402', '', 500, 20, 'confirmed'),
       ('ACC-4', :'A2', :did, public.clinic_now()::date + 20, '08:11', 'clinic', 'Bala', 30, 'Male', '9876500402', '', 500, 20, 'cancelled');
select id as bid from public.bookings where ref = 'ACC-1' \gset
insert into public.prescriptions (booking_id, doctor_id, patient_id, diagnosis) values (:'bid', :did, :'A1', 'Fever');

select t.login(:'A1');
select t.denied($$select public.admin_accounts()$$, 'admins_only', 'users cannot read the books');
select t.denied(format($$select public.admin_doctor_stats(%s)$$, :did), 'admins_only', 'users cannot read doctor stats');
select t.denied($$select public.admin_expense_add('{"category":"server","amount_inr":100}')$$, 'admins_only', 'users cannot add expenses');
select t.denied($$select * from public.admin_expenses$$, 'permission denied', 'expenses are not directly readable');
select t.login(:'ADM');
select public.admin_doctor_stats(:did) as st \gset
select t.ok((:'st'::jsonb ->> 'total')::int - (:'st0'::jsonb ->> 'total')::int = 4 and (:'st'::jsonb ->> 'confirmed')::int - (:'st0'::jsonb ->> 'confirmed')::int = 3 and (:'st'::jsonb ->> 'cancelled')::int - (:'st0'::jsonb ->> 'cancelled')::int = 1, 'doctor stats count bookings by status');
select t.ok((:'st'::jsonb ->> 'video')::int - (:'st0'::jsonb ->> 'video')::int = 1 and (:'st'::jsonb ->> 'clinic')::int - (:'st0'::jsonb ->> 'clinic')::int = 2, 'doctor stats split video and clinic');
select t.ok((:'st'::jsonb ->> 'prescriptions')::int - (:'st0'::jsonb ->> 'prescriptions')::int = 1, 'doctor stats count prescriptions');
select t.ok((:'st'::jsonb ->> 'platform_fees')::int - (:'st0'::jsonb ->> 'platform_fees')::int = 60 and (:'st'::jsonb ->> 'doctor_fees')::int - (:'st0'::jsonb ->> 'doctor_fees')::int = 1300, 'doctor stats add up fees of confirmed bookings only');
select public.admin_accounts() as a0 \gset
select public.admin_expense_add('{"category":"marketing","amount_inr":150,"note":"Flyers"}') as e1 \gset
select public.admin_expense_add('{"category":"server","amount_inr":50}');
select t.denied($$select public.admin_expense_add('{"category":"gold","amount_inr":50}')$$, 'invalid_category', 'unknown expense category is refused');
select t.denied($$select public.admin_expense_add('{"category":"sms","amount_inr":-5}')$$, 'invalid_amount', 'negative expense is refused');
select public.admin_accounts() as a1 \gset
select t.ok((:'a1'::jsonb ->> 'expenses')::int - (:'a0'::jsonb ->> 'expenses')::int = 200, 'expenses add up');
select t.ok((:'a1'::jsonb ->> 'earned')::int - (:'a0'::jsonb ->> 'earned')::int = 0 and (:'a1'::jsonb ->> 'earned')::int >= 60, 'earnings are platform fees of confirmed bookings');
select t.ok((:'a1'::jsonb ->> 'net')::int = (:'a1'::jsonb ->> 'earned')::int - (:'a1'::jsonb ->> 'referral_credited')::int - (:'a1'::jsonb ->> 'expenses')::int, 'net = earned - referral - expenses');
select t.ok(jsonb_array_length(:'a1'::jsonb -> 'months') = 6 and jsonb_array_length(:'a1'::jsonb -> 'recent') >= 2, 'six months and recent expenses are listed');
select t.ok(public.admin_expense_delete(:e1), 'admin can delete an expense');
select public.admin_accounts() as a2 \gset
select t.ok((:'a2'::jsonb ->> 'expenses')::int = (:'a0'::jsonb ->> 'expenses')::int + 50, 'deleted expense is gone');
select t.login(:'A1');
select t.denied($$select public.request_withdrawal(20, 'asha@upi', '12345')$$, 'mobile_required', 'a withdrawal needs a mobile number');
select t.root();
