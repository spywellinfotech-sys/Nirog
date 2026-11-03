-- Supabase blocks UPDATE without WHERE for API calls ("UPDATE requires a WHERE clause"), so the admin could not save referral amounts.
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
      fee_adjust_inr = coalesce((p ->> 'fee_adjust_inr')::int, fee_adjust_inr)
    where id;
  end if;
  select * into s from public.referral_settings;
  return s;
end $$;
revoke all on function public.admin_referral_settings(jsonb) from public, anon;
grant execute on function public.admin_referral_settings(jsonb) to authenticated;
