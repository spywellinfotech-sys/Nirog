-- Push notifications to phones (Firebase Cloud Messaging). Each phone registers its token for the signed-in user.
-- Tokens are only reachable through these functions; the send-push Edge Function reads them with the service role.
create table if not exists public.push_tokens (
  token text primary key check (char_length(token) between 20 and 400),
  user_id uuid not null references public.profiles(id) on delete cascade,
  platform text not null default 'android',
  updated_at timestamptz not null default now()
);
create index if not exists push_tokens_user_idx on public.push_tokens (user_id);
alter table public.push_tokens enable row level security;
revoke all on public.push_tokens from anon, authenticated;

create or replace function public.register_push_token(p_token text) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if p_token is null or char_length(p_token) < 20 or char_length(p_token) > 400 then raise exception 'invalid_token'; end if;
  insert into public.push_tokens (token, user_id) values (p_token, uid)
  on conflict (token) do update set user_id = uid, updated_at = now();
  -- keep at most 5 phones per user
  delete from public.push_tokens where user_id = uid and token not in (
    select token from public.push_tokens where user_id = uid order by updated_at desc limit 5);
  return true;
end $$;

create or replace function public.drop_push_token(p_token text) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  delete from public.push_tokens where token = p_token and user_id = auth.uid();
  return true;
end $$;

-- Service role only: the tokens of everyone a broadcast was addressed to.
create or replace function public.broadcast_tokens(p_broadcast bigint) returns table (token text)
language sql stable security definer set search_path = public, pg_temp as $$
  select t.token from public.broadcasts b
  join lateral public.broadcast_targets(b.audience, b.city) x on true
  join public.push_tokens t on t.user_id = x.uid
  where b.id = p_broadcast
$$;
create or replace function public.remove_push_tokens(p_tokens text[]) returns integer
language plpgsql security definer set search_path = public, pg_temp as $$
declare n integer;
begin
  delete from public.push_tokens where token = any(p_tokens);
  get diagnostics n = row_count;
  return n;
end $$;

revoke all on function public.register_push_token(text), public.drop_push_token(text) from public, anon;
grant execute on function public.register_push_token(text), public.drop_push_token(text) to authenticated;
revoke all on function public.broadcast_tokens(bigint), public.remove_push_tokens(text[]) from public, anon, authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.broadcast_tokens(bigint), public.remove_push_tokens(text[]) to service_role;
  end if;
end $$;
