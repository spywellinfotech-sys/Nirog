#!/usr/bin/env bash
# Runs the migration and SQL tests against a throwaway local Postgres. Needs postgresql-16 binaries.
set -euo pipefail
cd "$(dirname "$0")"
PGBIN=${PGBIN:-/usr/lib/postgresql/16/bin}
D=$(mktemp -d); trap 'su postgres -c "$PGBIN/pg_ctl -D $D stop -m fast" >/dev/null 2>&1 || true' EXIT
chown postgres "$D"
su postgres -c "$PGBIN/initdb -D $D -A trust >/dev/null"
su postgres -c "$PGBIN/pg_ctl -D $D -o '-p 54399 -k /tmp' -l $D/log -w start" >/dev/null
P="psql -h /tmp -p 54399 -U postgres -v ON_ERROR_STOP=1 -q -t -A -o /dev/null"
$P -c "create database nirog" postgres
P="$P -d nirog"
$P -f tests/harness_setup.sql
$P -f migrations/0001_init.sql
$P -f migrations/0002_storage.sql
$P -f migrations/0003_fix_search_path.sql
$P -f migrations/0004_facility_documents.sql
$P -f migrations/0005_sms_otp.sql
$P -f migrations/0006_unique_mobile.sql
$P -f migrations/0007_admin_profile_delete.sql
$P -f migrations/0008_reviews.sql
$P -f migrations/0009_promo_force_update.sql
$P -f migrations/0010_prescriptions.sql
$P -f migrations/0011_broadcasts.sql
$P -f migrations/0012_broadcast_geo.sql
$P -f migrations/0013_push_tokens.sql
$P -f migrations/0014_dashboard_revoke.sql
$P -f migrations/0015_ambulances.sql
$P -f migrations/0016_pharmacy_kind.sql
$P -f migrations/0017_ambulance_kind.sql
$P -f migrations/0018_lead_doctor.sql
$P -f migrations/0019_lead_city.sql
$P -f migrations/0020_delete_account.sql
$P -f migrations/0021_referrals.sql
$P -f migrations/0022_referral_switch.sql
$P -f migrations/0023_video_link.sql
$P -f migrations/0024_push_on_notification.sql
$P -f migrations/0025_start_call.sql
$P -f migrations/0026_end_call.sql
$P -f migrations/0027_accounts_stats.sql
$P -f migrations/0028_admin_patients.sql
$P -f migrations/0029_admin_delete_patient.sql
$P -f migrations/0030_hide_erased_patients.sql
$P -f migrations/0031_contact_taps.sql
for t in tests/[0-9]*.sql; do echo "== $t"; $P -f "$t" ; done

echo "== concurrency: 12 patients race for one slot"
for i in $(seq 1 12); do
  U=$(printf '00000000-0000-0000-0000-00000000e%03d' $i)
  $P -c "insert into auth.users (id, phone) values ('$U', '9190000010$i')" 
done
SLOT_DAY=$($P -c "select (public.clinic_now()::date + 14)" -o /dev/stdout)
for i in $(seq 1 12); do
  U=$(printf '00000000-0000-0000-0000-00000000e%03d' $i)
  ( psql -h /tmp -p 54399 -U postgres -d nirog -q -t -A -c "select set_config('request.jwt.claim.sub','$U',false); set role authenticated; select public.create_booking(1, public.clinic_now()::date + 14, '12:20', 'clinic', 'Racer $i', 30, 'Male', '9876500000', '')" >/dev/null 2>&1 && echo won >> $D/wins ) &
done
wait
W=$(wc -l < $D/wins)
N=$($P -c "select count(*) from public.bookings where slot_date = public.clinic_now()::date + 14 and slot_time = '12:20' and status in ('pending','confirmed')" -o /dev/stdout)
echo "winners=$W active_bookings=$N"
[ "$W" = "1" ] && [ "$N" = "1" ] || { echo "CONCURRENCY TEST FAILED"; exit 1; }
echo "ALL SQL TESTS PASSED"
