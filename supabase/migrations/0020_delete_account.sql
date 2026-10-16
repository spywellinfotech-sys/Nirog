-- Account deletion for patients, doctors and facilities (required by app stores).
-- Personal details are erased or anonymised, open bookings are cancelled, listings are taken down, and the sign-in is closed.
-- Uploaded files are removed by the app through the Storage API before this runs (Supabase blocks direct deletes from storage tables).
-- Staff accounts (admin, sales) are managed by the Yada+ team and cannot use this.
create or replace function public.delete_my_account() returns void
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare uid uuid := auth.uid(); r public.app_role; dids bigint[];
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  select role into r from public.profiles where id = uid;
  if r is null then raise exception 'not_authenticated'; end if;
  if r in ('admin', 'sales') then raise exception 'staff_cannot_delete'; end if;
  select coalesce(array_agg(id), '{}') into dids from public.doctors where user_id = uid;

  update public.bookings set status = 'cancelled', decision_reason = 'Account deleted', updated_at = now()
    where status in ('pending', 'confirmed') and (patient_id = uid or doctor_id = any(dids));
  update public.bookings set patient_name = 'Deleted user', patient_phone = '9000000000', reason = '' where patient_id = uid;
  delete from public.prescriptions where patient_id = uid;
  update public.reviews set patient_name = '', comment = '' where patient_id = uid;
  delete from public.notifications where user_id = uid;
  delete from public.push_tokens where user_id = uid;
  delete from public.patients where id = uid;

  update public.doctors set status = 'rejected', verified = false, review_reason = 'Account deleted', name = 'Deleted doctor',
    about = '', clinic = '', photo_path = null, wa = null where user_id = uid;
  delete from public.doctor_documents where doctor_id = any(dids);
  delete from public.doctor_verification where doctor_id = any(dids);
  delete from public.facilities where user_id = uid;

  update public.profiles set full_name = '', phone = null, email = null where id = uid;
  update auth.users set email = null, phone = null, raw_user_meta_data = '{}'::jsonb, banned_until = 'infinity' where id = uid;
  delete from auth.identities where user_id = uid;
  delete from auth.sessions where user_id = uid;
  delete from auth.refresh_tokens where user_id = uid::text;
end $$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
