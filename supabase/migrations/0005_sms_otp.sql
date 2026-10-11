-- SMS OTP codes (written only by the sms-otp Edge Function with the service role).
create table if not exists public.sms_otps (
  id bigint generated always as identity primary key,
  mobile text not null check (mobile ~ '^[6-9][0-9]{9}$'),
  code_hash text not null,
  expires_at timestamptz not null,
  attempts smallint not null default 0,
  consumed boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists sms_otps_mobile_idx on public.sms_otps(mobile, created_at desc);
alter table public.sms_otps enable row level security;
revoke all on public.sms_otps from anon, authenticated;
