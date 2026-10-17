-- Every in-app notification (new booking request, approval, rejection, cancellation, prescription, referral reward...) is also sent
-- to the person's phone as a push. A trigger calls the send-push Edge Function through pg_net with a private key kept in push_internal.
-- Broadcasts already send their own push, so rows that belong to a broadcast are skipped.
do $$ begin create extension if not exists pg_net with schema extensions; exception when others then null; end $$;

create table public.push_internal (
  id  boolean primary key default true check (id),
  key text not null default replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', ''),
  url text   -- the send-push function URL; push is skipped while this is empty
);
insert into public.push_internal default values;
alter table public.push_internal enable row level security;
revoke all on public.push_internal from anon, authenticated;

create or replace function public.push_on_notification() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare u text; k text;
begin
  if new.broadcast_id is not null then return new; end if;
  select url, key into u, k from public.push_internal;
  if u is null or u = '' then return new; end if;
  if not exists (select 1 from public.push_tokens where user_id = new.user_id) then return new; end if;
  begin
    execute 'select net.http_post(url := $1, body := $2, headers := $3)'
      using u, jsonb_build_object('notification_id', new.id),
            jsonb_build_object('content-type', 'application/json', 'x-push-key', k);
  exception when others then
    null;  -- push is best effort: a failed push must never block a booking
  end;
  return new;
end $$;
revoke all on function public.push_on_notification() from public, anon, authenticated;

create trigger notifications_push after insert on public.notifications
  for each row execute function public.push_on_notification();
