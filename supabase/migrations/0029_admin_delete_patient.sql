-- Super admin can erase a patient. Same erasure as the patient's own "Delete account": open bookings are cancelled, personal details
-- are wiped from bookings, prescriptions, reviews and the profile, and the sign-in is closed. Only patient accounts can be erased here.
create or replace function public.admin_delete_patient(p_user uuid) returns boolean
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare r public.app_role;
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  select role into r from public.profiles where id = p_user;
  if r is null then raise exception 'not_found'; end if;
  if r <> 'patient' then raise exception 'not_a_patient'; end if;
  if exists (select 1 from public.doctors where user_id = p_user) or exists (select 1 from public.facilities where user_id = p_user) then raise exception 'not_a_patient'; end if;

  update public.bookings set status = 'cancelled', decision_reason = 'Account deleted', updated_at = now()
    where status in ('pending', 'confirmed') and patient_id = p_user;
  update public.bookings set patient_name = 'Deleted user', patient_phone = '9000000000', reason = '' where patient_id = p_user;
  delete from public.prescriptions where patient_id = p_user;
  update public.reviews set patient_name = '', comment = '' where patient_id = p_user;
  delete from public.notifications where user_id = p_user;
  delete from public.push_tokens where user_id = p_user;
  delete from public.patients where id = p_user;
  update public.profiles set full_name = '', phone = null, email = null where id = p_user;
  update auth.users set email = null, phone = null, raw_user_meta_data = '{}'::jsonb, banned_until = 'infinity' where id = p_user;
  delete from auth.identities where user_id = p_user;
  delete from auth.sessions where user_id = p_user;
  delete from auth.refresh_tokens where user_id = p_user::text;
  return true;
end $$;
revoke all on function public.admin_delete_patient(uuid) from public, anon;
grant execute on function public.admin_delete_patient(uuid) to authenticated;
