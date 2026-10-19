-- Reminds patients of confirmed appointments: one notification about a day before and one about an hour before.
alter table public.bookings add column if not exists reminded_day boolean not null default false;
alter table public.bookings add column if not exists reminded_hour boolean not null default false;

create or replace function public.send_booking_reminders() returns integer
language plpgsql security definer set search_path = public, pg_temp as $$
declare b record; n integer := 0; nowt timestamp := public.clinic_now(); dn text; ts timestamp;
begin
  for b in
    select bk.id, bk.patient_id, bk.slot_date, bk.slot_time, bk.mode, bk.reminded_day, bk.reminded_hour, d.name as dname
    from public.bookings bk join public.doctors d on d.id = bk.doctor_id
    where bk.status = 'confirmed' and (bk.slot_date + bk.slot_time) > nowt and (bk.slot_date + bk.slot_time) <= nowt + interval '24 hours'
  loop
    ts := b.slot_date + b.slot_time; dn := b.dname;
    if not b.reminded_hour and ts <= nowt + interval '1 hour' then
      perform public.notify(b.patient_id, 'Reminder: your ' || case when b.mode = 'video' then 'video call' else 'visit' end || ' with ' || dn || ' is at ' || to_char(ts, 'HH12:MI AM') || ' today.'
        || case when b.mode = 'video' then ' Open the app to join.' else '' end);
      update public.bookings set reminded_hour = true, reminded_day = true where id = b.id; n := n + 1;
    elsif not b.reminded_day and not b.reminded_hour and ts > nowt + interval '23 hours' then
      perform public.notify(b.patient_id, 'Reminder: you have an appointment with ' || dn || ' tomorrow at ' || to_char(ts, 'HH12:MI AM') || '.');
      update public.bookings set reminded_day = true where id = b.id; n := n + 1;
    end if;
  end loop;
  return n;
end $$;
revoke all on function public.send_booking_reminders() from public, anon, authenticated;

-- Runs every 10 minutes when pg_cron is available (Supabase: Database > Extensions > pg_cron).
do $$
begin
  create extension if not exists pg_cron;
  perform cron.schedule('booking-reminders', '*/10 * * * *', 'select public.send_booking_reminders()');
exception when others then
  raise notice 'pg_cron not available, schedule send_booking_reminders() another way: %', sqlerrm;
end $$;
