-- Referral programme and wallet.
--  * Every signed-in user has a referral code.
--  * A new user enters a friend's code once (within 3 days of signing up).
--  * Patient installs earn the referrer a small reward at once; a doctor or facility earns a bigger reward
--    only when the admin APPROVES that registration.
--  * Rewards go to a ledger; the wallet balance is the sum of the ledger. Withdrawals are UPI requests that the
--    admin pays by hand and then marks as paid (money is not moved by the app).
create table public.referral_settings (
  id              boolean primary key default true check (id),
  doctor_inr      int not null default 10 check (doctor_inr >= 0),
  facility_inr    int not null default 10 check (facility_inr >= 0),
  patient_inr     int not null default 1 check (patient_inr >= 0),
  min_withdraw    int not null default 50 check (min_withdraw >= 1),
  patient_daily_cap int not null default 50 check (patient_daily_cap >= 1)
);
insert into public.referral_settings default values;
alter table public.referral_settings enable row level security;

alter table public.profiles add column ref_code text unique;
alter table public.profiles add column referred_by uuid references public.profiles(id) on delete set null;

create table public.wallet_ledger (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  amount_inr int not null check (amount_inr <> 0),
  kind       text not null check (kind in ('referral', 'withdraw', 'refund')),
  note       text not null default '',
  created_at timestamptz not null default now()
);
create index wallet_ledger_user_idx on public.wallet_ledger (user_id, created_at desc);
alter table public.wallet_ledger enable row level security;

create table public.referral_rewards (
  id          bigint generated always as identity primary key,
  referrer_id uuid not null references public.profiles(id) on delete cascade,
  referred_id uuid not null references public.profiles(id) on delete cascade,
  kind        text not null check (kind in ('patient', 'doctor', 'facility')),
  amount_inr  int not null,
  created_at  timestamptz not null default now(),
  unique (referred_id, kind)
);
create index referral_rewards_referrer_idx on public.referral_rewards (referrer_id, created_at desc);
alter table public.referral_rewards enable row level security;

create table public.withdrawals (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  amount_inr  int not null check (amount_inr > 0),
  upi         text not null check (upi ~ '^[a-zA-Z0-9._-]{2,64}@[a-zA-Z0-9]{2,32}$'),
  status      text not null default 'pending' check (status in ('pending', 'paid', 'rejected')),
  utr         text,
  note        text,
  created_at  timestamptz not null default now(),
  decided_at  timestamptz
);
create unique index withdrawals_one_pending on public.withdrawals (user_id) where status = 'pending';
alter table public.withdrawals enable row level security;

-- No direct table access from the app: everything goes through the functions below.
revoke all on public.referral_settings, public.wallet_ledger, public.referral_rewards, public.withdrawals from anon, authenticated;

create or replace function public.wallet_balance(p_user uuid) returns int
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(sum(amount_inr), 0)::int from public.wallet_ledger where user_id = p_user
$$;
revoke all on function public.wallet_balance(uuid) from public, anon, authenticated;

-- The caller's code, wallet, history and withdrawals.
create or replace function public.my_referral() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); c text; s public.referral_settings; n int := 0;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  select ref_code into c from public.profiles where id = uid;
  if c is null then
    loop
      c := 'YD' || substr(upper(md5(random()::text || clock_timestamp()::text)), 1, 6);
      begin
        update public.profiles set ref_code = c where id = uid;
        exit;
      exception when unique_violation then n := n + 1; if n > 10 then raise; end if;
      end;
    end loop;
  end if;
  select * into s from public.referral_settings;
  return jsonb_build_object(
    'code', c,
    'balance', public.wallet_balance(uid),
    'rates', jsonb_build_object('doctor', s.doctor_inr, 'facility', s.facility_inr, 'patient', s.patient_inr),
    'min_withdraw', s.min_withdraw,
    'applied', (select referred_by is not null from public.profiles where id = uid),
    'counts', jsonb_build_object(
      'patient', (select count(*) from public.referral_rewards where referrer_id = uid and kind = 'patient'),
      'doctor', (select count(*) from public.referral_rewards where referrer_id = uid and kind = 'doctor'),
      'facility', (select count(*) from public.referral_rewards where referrer_id = uid and kind = 'facility')),
    'history', coalesce((select jsonb_agg(h order by (h ->> 'at') desc) from (
        select jsonb_build_object('amount', amount_inr, 'kind', kind, 'note', note, 'at', created_at) as h
        from public.wallet_ledger where user_id = uid order by created_at desc limit 50) x), '[]'::jsonb),
    'withdrawals', coalesce((select jsonb_agg(w order by (w ->> 'at') desc) from (
        select jsonb_build_object('id', id, 'amount', amount_inr, 'upi', upi, 'status', status, 'utr', utr, 'note', note, 'at', created_at) as w
        from public.withdrawals where user_id = uid order by created_at desc limit 20) y), '[]'::jsonb));
end $$;

-- Credits the referrer of p_user (if any) once per kind. Returns the amount credited.
create or replace function public.credit_referral(p_user uuid, p_kind text) returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare ref uuid; amt int; s public.referral_settings; got bigint;
begin
  select referred_by into ref from public.profiles where id = p_user;
  if ref is null or ref = p_user then return 0; end if;
  select * into s from public.referral_settings;
  amt := case p_kind when 'doctor' then s.doctor_inr when 'facility' then s.facility_inr else s.patient_inr end;
  if amt <= 0 then return 0; end if;
  if p_kind = 'patient' and (select count(*) from public.referral_rewards
        where referrer_id = ref and kind = 'patient' and created_at > now() - interval '1 day') >= s.patient_daily_cap then
    return 0;
  end if;
  insert into public.referral_rewards (referrer_id, referred_id, kind, amount_inr)
  values (ref, p_user, p_kind, amt) on conflict (referred_id, kind) do nothing returning id into got;
  if got is null then return 0; end if;
  insert into public.wallet_ledger (user_id, amount_inr, kind, note)
  values (ref, amt, 'referral', case p_kind when 'doctor' then 'Doctor joined through your invite'
                                            when 'facility' then 'Facility joined through your invite'
                                            else 'New user installed through your invite' end);
  perform public.notify(ref, 'You earned Rs ' || amt || ' from your referral.');
  return amt;
end $$;
revoke all on function public.credit_referral(uuid, text) from public, anon, authenticated;

-- A new user enters a friend's code. Allowed once, within 3 days of signing up, never for staff or yourself.
create or replace function public.apply_referral(p_code text) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); me public.profiles; ref uuid;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  select * into me from public.profiles where id = uid;
  if me.role in ('admin', 'sales') then raise exception 'not_allowed'; end if;
  if me.referred_by is not null then raise exception 'already_applied'; end if;
  if me.created_at < now() - interval '3 days' then raise exception 'too_late'; end if;
  select id into ref from public.profiles where ref_code = upper(trim(p_code));
  if ref is null then raise exception 'invalid_code'; end if;
  if ref = uid then raise exception 'own_code'; end if;
  update public.profiles set referred_by = ref where id = uid;
  perform public.credit_referral(uid, 'patient');
  return true;
end $$;

create or replace function public.request_withdrawal(p_amount int, p_upi text) returns bigint
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); s public.referral_settings; wid bigint; v text := lower(trim(p_upi));
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  select * into s from public.referral_settings;
  if v !~ '^[a-z0-9._-]{2,64}@[a-z0-9]{2,32}$' then raise exception 'invalid_upi'; end if;
  perform 1 from public.profiles where id = uid for update;   -- serialise requests of one user
  if p_amount is null or p_amount < s.min_withdraw then raise exception 'below_minimum'; end if;
  if exists (select 1 from public.withdrawals where user_id = uid and status = 'pending') then raise exception 'pending_exists'; end if;
  if p_amount > public.wallet_balance(uid) then raise exception 'insufficient_balance'; end if;
  insert into public.withdrawals (user_id, amount_inr, upi) values (uid, p_amount, v) returning withdrawals.id into wid;
  insert into public.wallet_ledger (user_id, amount_inr, kind, note) values (uid, -p_amount, 'withdraw', 'Withdrawal to ' || v);
  return wid;
end $$;

-- Admin: list requests with the requester's name and phone so the payout can be made.
create or replace function public.admin_withdrawals(p_status text default 'pending') returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'amount', w.amount_inr, 'upi', w.upi, 'status', w.status,
            'utr', w.utr, 'note', w.note, 'at', w.created_at, 'name', p.full_name, 'phone', p.phone, 'role', p.role) order by w.created_at)
          from public.withdrawals w join public.profiles p on p.id = w.user_id
          where p_status = 'all' or w.status = p_status), '[]'::jsonb);
end $$;

create or replace function public.admin_decide_withdrawal(p_id bigint, p_decision text, p_utr text default null, p_note text default null)
returns boolean language plpgsql security definer set search_path = public, pg_temp as $$
declare w public.withdrawals;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  select * into w from public.withdrawals where id = p_id for update;
  if not found then raise exception 'not_found'; end if;
  if w.status <> 'pending' then raise exception 'already_decided'; end if;
  if p_decision = 'paid' then
    if coalesce(trim(p_utr), '') = '' then raise exception 'utr_required'; end if;
    update public.withdrawals set status = 'paid', utr = left(trim(p_utr), 40), note = left(p_note, 200), decided_at = now() where id = p_id;
    perform public.notify(w.user_id, 'Rs ' || w.amount_inr || ' was sent to ' || w.upi || '.');
  elsif p_decision = 'reject' then
    update public.withdrawals set status = 'rejected', note = left(p_note, 200), decided_at = now() where id = p_id;
    insert into public.wallet_ledger (user_id, amount_inr, kind, note) values (w.user_id, w.amount_inr, 'refund', 'Withdrawal rejected, amount returned');
    perform public.notify(w.user_id, 'Your withdrawal of Rs ' || w.amount_inr || ' was not paid' || coalesce(': ' || left(p_note, 200), '.') || ' The amount is back in your wallet.');
  else raise exception 'invalid_decision'; end if;
  return true;
end $$;

create or replace function public.admin_referral_settings(p jsonb default null) returns public.referral_settings
language plpgsql security definer set search_path = public, pg_temp as $$
declare s public.referral_settings;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  if p is not null then
    update public.referral_settings set
      doctor_inr = coalesce((p ->> 'doctor_inr')::int, doctor_inr),
      facility_inr = coalesce((p ->> 'facility_inr')::int, facility_inr),
      patient_inr = coalesce((p ->> 'patient_inr')::int, patient_inr),
      min_withdraw = coalesce((p ->> 'min_withdraw')::int, min_withdraw);
  end if;
  select * into s from public.referral_settings;
  return s;
end $$;

-- Approval now also pays the referrer.
create or replace function public.admin_review_doctor(p_doctor bigint, p_decision text, p_verified boolean default true, p_reason text default null)
returns public.doctors language plpgsql security definer set search_path = public, pg_temp as $$
declare d public.doctors;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  if p_decision = 'approve' then
    update public.doctors set status = 'approved', verified = coalesce(p_verified, true), review_reason = null where id = p_doctor returning * into d;
  elsif p_decision = 'reject' then
    update public.doctors set status = 'rejected', verified = false, review_reason = left(p_reason, 200) where id = p_doctor returning * into d;
  else raise exception 'invalid_decision'; end if;
  if not found then raise exception 'doctor_not_found'; end if;
  perform public.notify(d.user_id, case when d.status = 'approved' then 'Your profile was approved and is now visible to patients.'
                                        else 'Your profile was not approved' || coalesce(': ' || d.review_reason, '.') end);
  if d.status = 'approved' then perform public.credit_referral(d.user_id, 'doctor'); end if;
  return d;
end $$;

create or replace function public.admin_review_facility(p_facility bigint, p_decision text, p_verified boolean default true, p_reason text default null)
returns public.facilities language plpgsql security definer set search_path = public, pg_temp as $$
declare f public.facilities;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  if p_decision = 'approve' then
    update public.facilities set status = 'approved', verified = coalesce(p_verified, true), review_reason = null where id = p_facility returning * into f;
  elsif p_decision = 'reject' then
    update public.facilities set status = 'rejected', verified = false, review_reason = left(p_reason, 200) where id = p_facility returning * into f;
  else raise exception 'invalid_decision'; end if;
  if not found then raise exception 'facility_not_found'; end if;
  perform public.notify(f.user_id, case when f.status = 'approved' then 'Your listing was approved and is now visible.'
                                        else 'Your listing was not approved' || coalesce(': ' || f.review_reason, '.') end);
  if f.status = 'approved' then perform public.credit_referral(f.user_id, 'facility'); end if;
  return f;
end $$;

revoke all on function public.my_referral(), public.apply_referral(text), public.request_withdrawal(int, text),
  public.admin_withdrawals(text), public.admin_decide_withdrawal(bigint, text, text, text), public.admin_referral_settings(jsonb) from public, anon;
grant execute on function public.my_referral(), public.apply_referral(text), public.request_withdrawal(int, text),
  public.admin_withdrawals(text), public.admin_decide_withdrawal(bigint, text, text, text), public.admin_referral_settings(jsonb) to authenticated;
