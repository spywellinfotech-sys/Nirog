-- Referral reward becomes Rs 2 per referral, and the first Rs 100 of a user's wallet is used automatically
-- against the platform fee of their bookings and test/facility requests. What is left stays in the wallet.
-- fee_adjust_inr is editable by the admin (0 turns the adjustment off).
alter table public.referral_settings add column if not exists fee_adjust_inr int not null default 100 check (fee_adjust_inr >= 0);
update public.referral_settings set doctor_inr = 2, facility_inr = 2, patient_inr = 2;

alter table public.wallet_ledger drop constraint if exists wallet_ledger_kind_check;
alter table public.wallet_ledger add constraint wallet_ledger_kind_check check (kind in ('referral', 'withdraw', 'refund', 'fee_adjust', 'fee_refund'));

alter table public.bookings add column if not exists fee_adjusted int not null default 0 check (fee_adjusted >= 0);
alter table public.bookings add column if not exists fee_returned boolean not null default false;
alter table public.facility_requests add column if not exists fee_adjusted int not null default 0 check (fee_adjusted >= 0);
alter table public.facility_requests add column if not exists fee_returned boolean not null default false;

-- Wallet money that is still reserved for platform fees (never more than the balance).
create or replace function public.fee_credit_left(p_user uuid) returns int
language sql stable security definer set search_path = public, pg_temp as $$
  select greatest(0, least(
    public.wallet_balance(p_user),
    (select fee_adjust_inr from public.referral_settings)
      + coalesce((select sum(amount_inr) from public.wallet_ledger where user_id = p_user and kind in ('fee_adjust', 'fee_refund')), 0)
  ))::int
$$;
revoke all on function public.fee_credit_left(uuid) from public, anon, authenticated;

-- Takes up to p_fee from the user's reserved credit and returns how much was taken.
create or replace function public.take_fee_credit(p_user uuid, p_fee int) returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare adj int;
begin
  if p_fee is null or p_fee <= 0 then return 0; end if;
  perform 1 from public.profiles where id = p_user for update;
  adj := least(p_fee, public.fee_credit_left(p_user));
  if adj <= 0 then return 0; end if;
  insert into public.wallet_ledger (user_id, amount_inr, kind, note) values (p_user, -adj, 'fee_adjust', 'Adjusted against platform fee');
  return adj;
end $$;
revoke all on function public.take_fee_credit(uuid, int) from public, anon, authenticated;

-- A cancelled or rejected booking/request gives its adjusted credit back.
create or replace function public.return_fee_credit() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := new.patient_id;
begin
  if new.status::text in ('cancelled', 'rejected') and old.status::text not in ('cancelled', 'rejected')
     and new.fee_adjusted > 0 and not new.fee_returned and uid is not null
     and exists (select 1 from public.profiles where id = uid) then
    insert into public.wallet_ledger (user_id, amount_inr, kind, note) values (uid, new.fee_adjusted, 'fee_refund', 'Platform fee credit returned');
    new.fee_returned := true;
  end if;
  return new;
end $$;
revoke all on function public.return_fee_credit() from public, anon, authenticated;
drop trigger if exists bookings_return_fee on public.bookings;
create trigger bookings_return_fee before update of status on public.bookings for each row execute function public.return_fee_credit();
drop trigger if exists facility_requests_return_fee on public.facility_requests;
create trigger facility_requests_return_fee before update of status on public.facility_requests for each row execute function public.return_fee_credit();

-- create_booking: same as 0042, plus the wallet adjustment.
create or replace function public.create_booking(
  p_doctor bigint, p_day date, p_time time, p_mode text,
  p_name text, p_age int, p_sex text, p_phone text, p_reason text default '', p_weight numeric default null)
returns public.bookings language plpgsql security definer set search_path = public, pg_temp as $$
declare
  uid uuid := auth.uid(); d public.doctors; ps public.platform_settings; fee int; pf int; adj int := 0; loc bigint; b public.bookings;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.profiles where id = uid and role = 'patient') then raise exception 'patients_only'; end if;
  if length(trim(coalesce(p_name,''))) < 2 then raise exception 'invalid_name'; end if;
  if p_age is null or p_age < 0 or p_age > 120 then raise exception 'invalid_age'; end if;
  if p_sex not in ('Female','Male','Other') then raise exception 'invalid_sex'; end if;
  if p_weight is not null and (p_weight < 1 or p_weight > 400) then raise exception 'invalid_weight'; end if;
  if p_phone !~ '^[6-9][0-9]{9}$' then raise exception 'invalid_phone'; end if;
  if p_mode not in ('clinic','video') then raise exception 'invalid_mode'; end if;
  if (select count(*) from public.bookings where patient_id = uid and status in ('pending','confirmed')) >= 10 then
    raise exception 'too_many_active_bookings'; end if;

  select * into d from public.doctors where id = p_doctor and status = 'approved';
  if not found then raise exception 'doctor_unavailable'; end if;
  if p_mode = 'video' and not d.video then raise exception 'video_not_offered'; end if;

  case public.slot_state(p_doctor, p_day, p_time)
    when 'free' then null;
    when 'busy' then raise exception 'slot_taken';
    else raise exception 'slot_unavailable';
  end case;

  select * into ps from public.platform_settings where id = 1;
  fee := case when p_mode = 'video' then d.video_fee_inr else d.fee_inr end;
  pf  := case when not ps.fee_on or (ps.promo_until is not null and ps.promo_until > now()) then 0 when ps.fee_type = 'flat' then round(ps.fee_value)::int
              else round(fee * ps.fee_value / 100)::int end;
  select id into loc from public.clinic_locations where doctor_id = p_doctor order by id limit 1;
  adj := public.take_fee_credit(uid, pf);
  pf := pf - adj;

  begin
    insert into public.bookings (ref, patient_id, doctor_id, clinic_location_id, slot_date, slot_time, mode,
                                 patient_name, patient_age, patient_sex, patient_phone, reason, doctor_fee, platform_fee, patient_weight, fee_adjusted)
    values (public.new_ref('NR'), uid, p_doctor, loc, p_day, p_time, p_mode,
            trim(p_name), p_age, p_sex, p_phone, left(coalesce(p_reason,''), 300), fee, pf, round(p_weight, 1), adj)
    returning * into b;
  exception when unique_violation then
    raise exception 'slot_taken';
  end;

  update public.patients set age = p_age, sex = p_sex, weight = coalesce(round(p_weight, 1), weight) where id = uid;
  perform public.notify(d.user_id, 'New booking request from ' || trim(p_name) || ' for ' || to_char(p_day, 'DD Mon') || ' ' || to_char(p_time, 'HH12:MI AM') || '. Please approve or reject.');
  perform public.notify(uid, 'Request sent to ' || d.name || '. Waiting for approval.' || case when adj > 0 then ' Rs ' || adj || ' of your wallet was used for the platform fee.' else '' end);
  return b;
end $$;

-- create_facility_request: same as 0042, plus the wallet adjustment.
create or replace function public.create_facility_request(p_facility bigint, p_item text, p_date date, p_name text, p_phone text, p_note text default '')
returns text language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); f record; r text; n int; ps public.platform_settings; price int; pf int := 0; adj int := 0; e jsonb; nm text;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from public.profiles where id = uid and role = 'patient') then raise exception 'not_a_patient'; end if;
  select id, user_id, name, kind, services into f from public.facilities where id = p_facility and status = 'approved' and kind in ('lab','centre','hospital');
  if f.id is null then raise exception 'facility_unavailable'; end if;
  if char_length(btrim(coalesce(p_item,''))) < 2 then raise exception 'invalid_item'; end if;
  if char_length(btrim(coalesce(p_name,''))) < 2 then raise exception 'invalid_name'; end if;
  if coalesce(p_phone,'') !~ '^[6-9][0-9]{9}$' then raise exception 'invalid_phone'; end if;
  if p_date is null or p_date < public.clinic_now()::date or p_date > public.clinic_now()::date + 60 then raise exception 'invalid_date'; end if;
  select count(*) into n from public.facility_requests where patient_id = uid and status = 'pending';
  if n >= 5 then raise exception 'too_many_requests'; end if;
  if jsonb_typeof(f.services) = 'array' then
    for e in select * from jsonb_array_elements(f.services) loop
      nm := case when jsonb_typeof(e) = 'array' then e ->> 0 when jsonb_typeof(e) = 'object' then e ->> 'name' else null end;
      if nm is not null and lower(btrim(nm)) = lower(btrim(p_item)) then
        price := case when jsonb_typeof(e) = 'array' then nullif(e ->> 1, '')::int when jsonb_typeof(e) = 'object' then nullif(e ->> 'price', '')::int else null end;
        exit;
      end if;
    end loop;
  end if;
  select * into ps from public.platform_settings where id = 1;
  if price is not null and ps.test_fee_on and not (ps.promo_until is not null and ps.promo_until > now()) then
    pf := round(price * ps.test_fee_pct / 100)::int;
  end if;
  adj := public.take_fee_credit(uid, pf);
  pf := pf - adj;
  r := public.new_ref('FR');
  insert into public.facility_requests (ref, facility_id, patient_id, patient_name, patient_phone, item, preferred_date, note, item_price, platform_fee, fee_adjusted)
    values (r, f.id, uid, left(btrim(p_name),80), p_phone, left(btrim(p_item),120), p_date, left(btrim(coalesce(p_note,'')),300), price, pf, adj);
  perform public.notify(f.user_id, 'New appointment request ' || r || ': ' || left(btrim(p_item),60) || ' on ' || to_char(p_date,'DD Mon'));
  return r;
end $$;

-- Withdrawals can only use money that is not reserved for platform fees.
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
  if p_amount > public.wallet_balance(uid) - public.fee_credit_left(uid) then raise exception 'insufficient_balance'; end if;
  insert into public.withdrawals (user_id, amount_inr, upi, mobile) values (uid, p_amount, v, m) returning withdrawals.id into wid;
  insert into public.wallet_ledger (user_id, amount_inr, kind, note) values (uid, -p_amount, 'withdraw', 'Withdrawal to ' || v);
  return wid;
end $$;
revoke all on function public.request_withdrawal(int, text, text) from public, anon;
grant execute on function public.request_withdrawal(int, text, text) to authenticated;

-- Admin can change the amount reserved for platform fees.
create or replace function public.admin_referral_settings(p jsonb default null) returns public.referral_settings
language plpgsql security definer set search_path = public, pg_temp as $$
declare s public.referral_settings;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  if p is not null then
    update public.referral_settings set
      enabled = coalesce((p ->> 'enabled')::boolean, enabled),
      doctor_inr = coalesce((p ->> 'doctor_inr')::int, doctor_inr),
      facility_inr = coalesce((p ->> 'facility_inr')::int, facility_inr),
      patient_inr = coalesce((p ->> 'patient_inr')::int, patient_inr),
      min_withdraw = coalesce((p ->> 'min_withdraw')::int, min_withdraw),
      fee_adjust_inr = coalesce((p ->> 'fee_adjust_inr')::int, fee_adjust_inr);
  end if;
  select * into s from public.referral_settings;
  return s;
end $$;
revoke all on function public.admin_referral_settings(jsonb) from public, anon;
grant execute on function public.admin_referral_settings(jsonb) to authenticated;

-- my_referral: same as 0022, plus fee_adjust, fee_credit and withdrawable.
create or replace function public.my_referral() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); c text; s public.referral_settings; n int := 0; bal int; cr int;
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
  bal := public.wallet_balance(uid); cr := public.fee_credit_left(uid);
  return jsonb_build_object(
    'code', c,
    'enabled', s.enabled,
    'balance', bal,
    'fee_adjust', s.fee_adjust_inr,
    'fee_credit', cr,
    'withdrawable', bal - cr,
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
