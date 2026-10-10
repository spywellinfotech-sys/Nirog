\set A '00000000-0000-0000-0000-0000000000a1'
\set B '00000000-0000-0000-0000-0000000000a2'
\set D1 '00000000-0000-0000-0000-0000000000d1'
\set ADM '00000000-0000-0000-0000-0000000000b1'
\set SAL '00000000-0000-0000-0000-0000000000c1'

-- Sign-up creates a patient profile automatically, never a privileged one.
select t.ok((select count(*) from public.profiles) = 7 and (select count(*) from public.profiles where role <> 'patient') = 0,
            'every new auth user becomes a patient profile');
select t.ok((select count(*) from public.patients) = 7, 'every new user gets a patients row');

-- Bootstrap the first admin the documented way (service role / SQL editor).
update public.profiles set role = 'admin' where id = :'ADM';
insert into public.staff_members (user_id, role) values (:'ADM', 'admin');

-- Patients cannot promote themselves.
select t.login(:'A');
select t.denied($$update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-0000000000a1'$$, 'permission denied', 'patient cannot edit own role');
select t.denied($$insert into public.staff_members (user_id, role) values ('00000000-0000-0000-0000-0000000000a1', 'admin')$$, 'permission denied', 'patient cannot grant themselves staff');
select t.denied($$select public.admin_set_staff('00000000-0000-0000-0000-0000000000a1', 'admin')$$, 'admins_only', 'patient cannot call admin_set_staff');
select t.denied($$select public.admin_review_doctor(1, 'approve')$$, 'admins_only', 'patient cannot approve doctors');
select t.ok((select count(*) from public.profiles) = 1, 'patient sees only own profile');
select t.ok((select count(*) from public.staff_members) = 0, 'patient sees no staff rows');
update public.profiles set full_name = 'Asha Rao' where id = :'A';
select t.ok((select full_name from public.profiles where id = :'A') = 'Asha Rao', 'patient can edit own name');
update public.profiles set full_name = 'Hacked' where id = :'B';
select t.root();
select t.ok((select full_name from public.profiles where id = :'B') = '', 'patient cannot edit another profile');

-- Admin creates a sales user.
select t.login(:'ADM');
select public.admin_set_staff(:'SAL', 'sales', true, 50000);
select t.ok((select count(*) from public.profiles) = 7, 'admin sees all profiles');
select t.denied($$select public.admin_set_staff('00000000-0000-0000-0000-0000000000b1', 'sales')$$, 'cannot_demote_self', 'admin cannot demote self');
select t.root();
select t.ok((select role from public.profiles where id = :'SAL') = 'sales', 'staff role applied to profile');

select t.login(:'SAL');
select t.ok(public.is_sales() and not public.is_admin(), 'sales is not admin');
select t.denied($$select public.admin_set_staff('00000000-0000-0000-0000-0000000000a1', 'admin')$$, 'admins_only', 'sales cannot grant roles');
select t.root();

-- Deactivated staff lose access immediately.
update public.staff_members set active = false where user_id = :'SAL';
select t.login(:'SAL');
select t.ok(not public.is_sales(), 'deactivated sales loses access');
select t.root();
update public.staff_members set active = true where user_id = :'SAL';

-- Anonymous visitors.
select t.anon();
select t.denied($$select * from public.bookings$$, 'permission denied', 'anon cannot read bookings');
select t.denied($$select * from public.profiles$$, 'permission denied', 'anon cannot read profiles');
select t.denied($$select * from public.doctor_verification$$, 'permission denied', 'anon cannot read registration details');
select t.denied($$select public.create_booking(1, current_date, '10:00', 'clinic', 'X Y', 20, 'Male', '9000000009', '')$$, 'permission denied', 'anon cannot book');
select t.root();
