# Nirog backend (Supabase): setup, testing and status

**Status: Phase 1 of 2 is done and tested.** The database, security rules, booking logic, build configuration and tests are in this repository. The app screens still run on local demo data until Phase 2 (wiring the screens to Supabase) is finished and tested against a real project. Do not treat the app as a working multi-user platform before then.

## What exists today

| Area | Where | State |
|---|---|---|
| Schema, RLS, booking functions | `supabase/migrations/0001_init.sql` | Done, 105 automated checks pass on PostgreSQL 16 |
| Storage buckets and policies | `supabase/migrations/0002_storage.sql` | Written; only checked against a local stand-in for Supabase Storage |
| SQL tests (roles, RLS, double booking, 12-way race, persistence) | `supabase/tests/`, `supabase/run_tests.sh` | Passing locally |
| Public config for Android and iOS builds | `scripts/make-config.sh`, `config.js`, `.env.example`, workflows | Done |
| Secret scanning | `scripts/check-no-secrets.sh`, `.github/workflows/db-tests.yml` | Done |
| App screens using Supabase | `index.html` | **Not started** (Phase 2) |

## Security model in one page

- Sign-up always creates a **patient**. Role is never read from client data.
- Admin and sales authority comes only from `staff_members`, a table no client can write. The first admin is created by SQL (step 6 below).
- Clients cannot write `bookings`, `profiles.role`, doctor `status`/`verified` or platform fees directly. They call functions: `create_booking`, `doctor_decide_booking`, `cancel_booking`, `reschedule_booking`, `register_doctor`, `register_facility`, `admin_review_doctor`, `admin_review_facility`, `admin_set_staff`.
- Money is calculated on the server (doctor fee plus platform fee). The app cannot send its own price.
- **Double booking** is blocked by a unique index on (doctor, date, time) for active bookings. A second request gets `slot_taken`. The test starts 12 simultaneous requests for one slot and requires exactly one winner.
- The public directory only exposes safe columns. Registration numbers, certificates, facility contact people and licence numbers are private to the owner and admins.
- The app only ever holds the **anon key**. The service-role key is never used by the app and `scripts/make-config.sh` refuses to write one.

## Step-by-step Supabase setup

1. Create a project at supabase.com (free tier is fine). Choose the region closest to your users, for example Mumbai.
2. **SQL editor** > New query. Paste `supabase/migrations/0001_init.sql` and run it. Then paste and run `0002_storage.sql`.
3. **Authentication > Providers**:
   - Enable **Phone** and connect an SMS provider (Twilio, MessageBird, Vonage or TextLocal). This is what patients use to sign in with an OTP. SMS costs are charged by your provider.
   - Enable **Email** for doctors, facilities and staff. For production, turn on "Confirm email".
4. **Authentication > Rate limits**: keep the defaults or tighten OTP sending limits.
5. **Project Settings > API**: copy the **Project URL** and the **anon public key**. Never copy the `service_role` key into the app or this repository.
6. Create the first admin. Sign up once with your admin email in the app (or **Authentication > Users > Add user**), then in the SQL editor run, replacing the email:
   ```sql
   update public.profiles set role = 'admin' where email = 'you@example.com';
   insert into public.staff_members (user_id, role)
     select id, 'admin' from public.profiles where email = 'you@example.com';
   ```
   After that, add sales staff from the admin screen (`admin_set_staff`).
7. In GitHub: **Settings > Secrets and variables > Actions > New repository secret**. Add `SUPABASE_URL`, `SUPABASE_ANON_KEY` and optionally `GOOGLE_MAPS_API_KEY`.
8. **Google Maps (optional)**: existing Google Maps links keep working with no key. For embedded maps, create a key in Google Cloud, restrict it to the Android app (`com.nirog.app` plus your signing SHA-1) and to the Maps SDK/Embed API only.

## Supplying configuration safely

- `config.js` (in `app/src/main/assets/www/` and `web/`) holds only public values. It is committed empty. `scripts/make-config.sh` fills it from environment variables.
- **Local build:** `cp .env.example .env`, fill it in, then `set -a; source .env; set +a; scripts/make-config.sh`. `.env` is git-ignored.
- **GitHub Actions:** the APK and iOS workflows run `scripts/make-config.sh` with your repository secrets before building. With empty secrets the app builds in local demo mode.
- The anon key ends up inside the APK. That is normal and safe only because every table has Row Level Security. Do not disable RLS.
- This repository is public and the APK is published as a public release. Anyone can read the anon key from it. Keep RLS on and treat the anon key as public.

## Tests

Run everything locally (needs PostgreSQL 16 server binaries):

```
sudo bash supabase/run_tests.sh
```

It starts a throwaway database, applies both migrations and runs:

| File | Covers |
|---|---|
| `1_auth_roles.sql` | New users are patients; patients cannot change role or grant staff; admin and sales limits; deactivated staff; anonymous access blocked |
| `2_booking.sql` | Doctor approval gate; slot validation (off-grid, outside hours, past, day off, blocked); server-side fees; double booking and the database constraint; confirm, retime, reject, cancel, reschedule; privacy between patients and doctors |
| `3_rls_data.sql` | Facility privacy; notifications privacy; platform fee control; leads; doctor self-service limits; data visible on a fresh session |
| `4_storage.sql` | Storage folder ownership and admin read of private documents |
| `run_tests.sh` | 12 parallel patients race for one slot: exactly one wins |

The same suite runs in GitHub Actions as **Database tests** on every change under `supabase/`.

Still to write for Phase 2: end-to-end tests of the app against a real Supabase project (sign-in with a real OTP, booking from two devices).

## Build and test a debug APK with GitHub Actions

1. Add the repository secrets (step 7 above).
2. Push to `main`, or open **Actions > Build APK > Run workflow**.
3. Download `Nirog-debug.apk` from the `latest-apk` release or from the run's artifacts.
4. Install it, and check in the app that you can sign in and see the same data on two phones (this check only works after Phase 2).

## Incomplete features (be honest about these)

1. **App screens are not connected to Supabase yet.** Sign-in, doctor list, booking, doctor approval, admin and sales screens still use local demo data in `index.html`.
2. Real SMS OTP depends on your SMS provider setup.
3. File uploads (certificates, photos) need the client upload code and have only been checked against a local stand-in for Storage.
4. Offline mode: the app needs a connection once it uses the backend. Cached read-only browsing and a clear "you are offline" state are not built yet.
5. Admin screens for staff management, lead assignment and revenue reports need server-side queries (only the `admin_set_staff` function exists).
6. Referral program, online payments, push notifications and email or SMS reminders are not built. In-app notifications are stored in the `notifications` table.
7. The `appointment_slots` table in the brief was replaced by generating slots on demand from the doctor's weekly availability, exceptions and bookings (`open_slots`), because it avoids stale slot rows. Bookings still enforce one active booking per slot.
8. Account deletion and data export are not built.
9. Existing local demo data is not migrated to Supabase.
