-- Admin switch to pause the referral programme. While off: no codes can be applied and no new rewards are paid.
-- Existing wallet balances can still be withdrawn.
alter table public.referral_settings add column enabled boolean not null default true;

create or replace function public.credit_referral(p_user uuid, p_kind text) returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare ref uuid; amt int; s public.referral_settings; got bigint;
begin
  select * into s from public.referral_settings;
  if not s.enabled then return 0; end if;
  select referred_by into ref from public.profiles where id = p_user;
  if ref is null or ref = p_user then return 0; end if;
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

create or replace function public.apply_referral(p_code text) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); me public.profiles; ref uuid;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if not (select enabled from public.referral_settings) then raise exception 'program_off'; end if;
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
      min_withdraw = coalesce((p ->> 'min_withdraw')::int, min_withdraw);
  end if;
  select * into s from public.referral_settings;
  return s;
end $$;
revoke all on function public.admin_referral_settings(jsonb) from public, anon;
grant execute on function public.admin_referral_settings(jsonb) to authenticated;

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
    'enabled', s.enabled,
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

