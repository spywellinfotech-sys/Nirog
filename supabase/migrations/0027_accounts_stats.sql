-- Super admin books: platform earnings, referral spend, other expenses; per-doctor activity and earnings; mobile number on withdrawals.

-- 1) Withdrawals now carry a mobile number (needed to pay or contact the person).
alter table public.withdrawals add column mobile text check (mobile is null or mobile ~ '^[6-9][0-9]{9}$');
drop function if exists public.request_withdrawal(int, text);
create or replace function public.request_withdrawal(p_amount int, p_upi text, p_mobile text) returns bigint
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); s public.referral_settings; wid bigint; v text := lower(trim(p_upi)); m text := regexp_replace(coalesce(p_mobile, ''), '\s', '', 'g');
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  select * into s from public.referral_settings;
  if m !~ '^[6-9][0-9]{9}$' then raise exception 'mobile_required'; end if;
  if v !~ '^[a-z0-9._-]{2,64}@[a-z0-9]{2,32}$' then raise exception 'invalid_upi'; end if;
  perform 1 from public.profiles where id = uid for update;
  if p_amount is null or p_amount < s.min_withdraw then raise exception 'below_minimum'; end if;
  if exists (select 1 from public.withdrawals where user_id = uid and status = 'pending') then raise exception 'pending_exists'; end if;
  if p_amount > public.wallet_balance(uid) then raise exception 'insufficient_balance'; end if;
  insert into public.withdrawals (user_id, amount_inr, upi, mobile) values (uid, p_amount, v, m) returning withdrawals.id into wid;
  insert into public.wallet_ledger (user_id, amount_inr, kind, note) values (uid, -p_amount, 'withdraw', 'Withdrawal to ' || v);
  return wid;
end $$;
revoke all on function public.request_withdrawal(int, text, text) from public, anon;
grant execute on function public.request_withdrawal(int, text, text) to authenticated;

create or replace function public.admin_withdrawals(p_status text default 'pending') returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'amount', w.amount_inr, 'upi', w.upi, 'status', w.status,
            'utr', w.utr, 'note', w.note, 'at', w.created_at, 'name', p.full_name, 'phone', coalesce(w.mobile, p.phone), 'role', p.role) order by w.created_at)
          from public.withdrawals w join public.profiles p on p.id = w.user_id
          where p_status = 'all' or w.status = p_status), '[]'::jsonb);
end $$;

-- 2) Expenses entered by the super admin (marketing, servers, SMS, salaries...). Referral rewards are counted automatically.
create table public.admin_expenses (
  id         bigint generated always as identity primary key,
  spent_on   date not null default (now() at time zone 'Asia/Kolkata')::date,
  category   text not null check (category in ('marketing', 'server', 'sms', 'salary', 'other')),
  amount_inr int not null check (amount_inr > 0 and amount_inr <= 100000000),
  note       text not null default '' check (char_length(note) <= 200),
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null
);
create index admin_expenses_date_idx on public.admin_expenses (spent_on desc);
alter table public.admin_expenses enable row level security;
revoke all on public.admin_expenses from anon, authenticated;

create or replace function public.admin_expense_add(p jsonb) returns bigint
language plpgsql security definer set search_path = public, pg_temp as $$
declare id bigint;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  if coalesce(p ->> 'category', '') not in ('marketing', 'server', 'sms', 'salary', 'other') then raise exception 'invalid_category'; end if;
  if (p ->> 'amount_inr') !~ '^[0-9]{1,9}$' or (p ->> 'amount_inr')::int < 1 then raise exception 'invalid_amount'; end if;
  insert into public.admin_expenses (spent_on, category, amount_inr, note, created_by)
  values (coalesce(nullif(p ->> 'spent_on', '')::date, (now() at time zone 'Asia/Kolkata')::date), p ->> 'category', (p ->> 'amount_inr')::int, left(coalesce(p ->> 'note', ''), 200), auth.uid())
  returning admin_expenses.id into id;
  return id;
end $$;

create or replace function public.admin_expense_delete(p_id bigint) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  delete from public.admin_expenses where id = p_id;
  return found;
end $$;

-- 3) The books. "Earned" = platform fees on confirmed bookings. Payment collection is not built yet, so this is what is
--    recorded against bookings, not cash received.
create or replace function public.admin_accounts() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare earned bigint; docfees bigint; refc bigint; refpaid bigint; walletbal bigint; exp bigint; r jsonb;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  select coalesce(sum(platform_fee), 0), coalesce(sum(doctor_fee), 0) into earned, docfees from public.bookings where status = 'confirmed';
  select coalesce(sum(amount_inr), 0) into refc from public.referral_rewards;
  select coalesce(sum(amount_inr), 0) into refpaid from public.withdrawals where status = 'paid';
  select coalesce(sum(amount_inr), 0) into walletbal from public.wallet_ledger;
  select coalesce(sum(amount_inr), 0) into exp from public.admin_expenses;
  r := jsonb_build_object(
    'earned', earned, 'doctor_fees', docfees,
    'referral_credited', refc, 'referral_paid', refpaid, 'wallet_owed', walletbal,
    'expenses', exp, 'net', earned - refc - exp,
    'by_category', coalesce((select jsonb_agg(jsonb_build_object('category', category, 'amount', s) order by s desc)
        from (select category, sum(amount_inr)::bigint as s from public.admin_expenses group by category) x), '[]'::jsonb),
    'months', coalesce((select jsonb_agg(jsonb_build_object('month', to_char(m, 'Mon YYYY'),
        'earned', (select coalesce(sum(platform_fee), 0) from public.bookings where status = 'confirmed' and date_trunc('month', slot_date) = m),
        'referral', (select coalesce(sum(amount_inr), 0) from public.referral_rewards where date_trunc('month', created_at at time zone 'Asia/Kolkata') = m),
        'expenses', (select coalesce(sum(amount_inr), 0) from public.admin_expenses where date_trunc('month', spent_on) = m)) order by m desc)
        from generate_series(date_trunc('month', (now() at time zone 'Asia/Kolkata')::date) - interval '5 months', date_trunc('month', (now() at time zone 'Asia/Kolkata')::date), interval '1 month') m), '[]'::jsonb),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'on', spent_on, 'category', category, 'amount', amount_inr, 'note', note) order by spent_on desc, id desc)
        from (select * from public.admin_expenses order by spent_on desc, id desc limit 50) y), '[]'::jsonb));
  return r;
end $$;

-- 4) Activity and earnings of one doctor, shown on the admin's profile view.
create or replace function public.admin_doctor_stats(p_doctor bigint) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  return (select jsonb_build_object(
    'total', count(*),
    'pending', count(*) filter (where status = 'pending'),
    'confirmed', count(*) filter (where status = 'confirmed'),
    'cancelled', count(*) filter (where status = 'cancelled'),
    'rejected', count(*) filter (where status = 'rejected'),
    'video', count(*) filter (where status = 'confirmed' and mode = 'video'),
    'clinic', count(*) filter (where status = 'confirmed' and mode = 'clinic'),
    'doctor_fees', coalesce(sum(doctor_fee) filter (where status = 'confirmed'), 0),
    'platform_fees', coalesce(sum(platform_fee) filter (where status = 'confirmed'), 0),
    'last30', count(*) filter (where created_at > now() - interval '30 days'),
    'last30_platform', coalesce(sum(platform_fee) filter (where status = 'confirmed' and created_at > now() - interval '30 days'), 0),
    'prescriptions', (select count(*) from public.prescriptions where doctor_id = p_doctor))
    from public.bookings where doctor_id = p_doctor);
end $$;

revoke all on function public.admin_expense_add(jsonb), public.admin_expense_delete(bigint), public.admin_accounts(), public.admin_doctor_stats(bigint) from public, anon;
grant execute on function public.admin_expense_add(jsonb), public.admin_expense_delete(bigint), public.admin_accounts(), public.admin_doctor_stats(bigint) to authenticated;
