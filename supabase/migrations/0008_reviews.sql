-- Ratings and reviews for doctors. Only the patient of a confirmed, past booking can review it (one review per booking).
create table if not exists public.reviews (
  id bigint generated always as identity primary key,
  booking_id uuid not null unique references public.bookings(id),
  doctor_id bigint not null references public.doctors(id),
  patient_id uuid not null references public.profiles(id),
  patient_name text not null default '',
  rating smallint not null check (rating between 1 and 5),
  comment text not null default '' check (char_length(comment) <= 500),
  created_at timestamptz not null default now()
);
create index if not exists reviews_doctor_idx on public.reviews(doctor_id, created_at desc);
alter table public.reviews enable row level security;
revoke all on public.reviews from anon, authenticated;
grant select on public.reviews to authenticated;
drop policy if exists reviews_own_or_admin on public.reviews;
create policy reviews_own_or_admin on public.reviews for select using (patient_id = auth.uid() or public.is_admin());

-- Public view: no patient id, first name only.
create or replace view public.doctor_reviews as
  select id, doctor_id, rating, comment, patient_name, created_at from public.reviews;
create or replace view public.doctor_ratings as
  select doctor_id, round(avg(rating)::numeric, 1) as avg_rating, count(*)::int as n from public.reviews group by doctor_id;
grant select on public.doctor_reviews, public.doctor_ratings to anon, authenticated;

create or replace function public.submit_review(p_booking uuid, p_rating int, p_comment text default '') returns public.reviews
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid(); b public.bookings; r public.reviews;
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if p_rating is null or p_rating not between 1 and 5 then raise exception 'invalid_rating'; end if;
  if char_length(coalesce(p_comment, '')) > 500 then raise exception 'comment_too_long'; end if;
  select * into b from public.bookings where id = p_booking and patient_id = uid;
  if not found then raise exception 'booking_not_found'; end if;
  if b.status <> 'confirmed' then raise exception 'booking_not_confirmed'; end if;
  if (b.slot_date + b.slot_time) > public.clinic_now() then raise exception 'visit_not_done'; end if;
  insert into public.reviews (booking_id, doctor_id, patient_id, patient_name, rating, comment)
  values (b.id, b.doctor_id, uid, split_part(trim(b.patient_name), ' ', 1), p_rating, trim(coalesce(p_comment, '')))
  on conflict (booking_id) do update set rating = excluded.rating, comment = excluded.comment
  returning * into r;
  return r;
end $$;

create or replace function public.admin_delete_review(p_review bigint) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'admins_only'; end if;
  delete from public.reviews where id = p_review;
  if not found then raise exception 'not_found'; end if;
  return true;
end $$;

revoke all on function public.submit_review(uuid, int, text), public.admin_delete_review(bigint) from public, anon;
grant execute on function public.submit_review(uuid, int, text), public.admin_delete_review(bigint) to authenticated;
