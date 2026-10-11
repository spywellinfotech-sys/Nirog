# Nirog backend (Supabase): setup, testing and status

**Status: Phase 2 is built but only tested against a fake Supabase server.** The app now runs in backend mode when `config.js` holds a project URL and key (it does: project `rxhanrtoaplwphmwpgqg`). Patients sign in with an **email one-time code**; doctors and admins sign in with email and password. The following has **not** been verified against the live project or on a phone: sign-in, booking, approval, uploads. Do not call the platform fully working until you have run the manual checklist at the end of the Tests section on two real devices.

## What exists today

| Area | Where | State |
|---|---|---|
| Schema, RLS, booking functions | `supabase/migrations/0001_init.sql` | Done, 105 automated checks pass on PostgreSQL 16 |
| Storage buckets and policies | `supabase/migrations/0002_storage.sql`, `0004_facility_documents.sql` | Written; only checked against a local stand-in for Supabase Storage |
| SQL tests (roles, RLS, double booking, 12-way race, persistence) | `supabase/tests/`, `supabase/run_tests.sh` | Passing locally |
| Public config for Android and iOS builds | `scripts/make-config.sh`, `config.js`, `.env.example`, workflows | Done |
| Secret scanning | `scripts/check-no-secrets.sh`, `.github/workflows/db-tests.yml` | Done |
| Supabase client (plain `fetch`, no vendored library) | `backend.js` | Done; tested against a fake server |
| App wired to Supabase (directory, slots, email OTP, booking, approve/reject, cancel, schedule, notifications, doctor registration with uploads, admin doctor review) | `index.html`, `tests/app/cloud.test.js` | Built; fake-server test passes; **not tested live** |

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
   - **Email** (used by everyone): turn **Confirm email OFF** (doctor registration needs an immediate session). Then go to **Authentication > Emails** and edit both **Confirm signup** and **Magic Link** templates so the body is `<h2>Your Nirog code</h2><p style="font-size:28px;font-weight:bold;letter-spacing:6px">{{ .Token }}</p>` and contains no `{{ .ConfirmationURL }}`. Patients then receive a code instead of a link. Keep the OTP length at 6 to 8 digits.
   - Add your own SMTP under **Project Settings > Authentication > SMTP Settings**. Supabase's built-in sender allows only a few emails per hour.
   - **Phone/SMS is not used.** Mobile OTP would need a provider that can deliver to India (DLT registration), for example Twilio Verify or MSG91. It is not built.
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

- `config.js` (in `app/src/main/assets/www/` and `web/`) holds only public values (project URL and publishable key). It is committed with the live project's values. `scripts/make-config.sh` overwrites it only when `SUPABASE_URL` and `SUPABASE_ANON_KEY` are set; otherwise it leaves the file alone. Empty values give local demo mode.
- **Local build:** `cp .env.example .env`, fill it in, then `set -a; source .env; set +a; scripts/make-config.sh`. `.env` is git-ignored.
- **GitHub Actions:** the APK and iOS workflows run `scripts/make-config.sh` with your repository secrets before building. With no secrets set, the committed `config.js` is used.
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

`node tests/app/cloud.test.js` runs the real `index.html` and `backend.js` against a fake in-memory Supabase: directory load, email-OTP sign-in (wrong and right code), booking, double-booking refusal, doctor sign-in, approval, and that no patient data lands in localStorage.

### Manual checklist (needed before calling it working; needs two phones)
1. Phone A: My appointments > enter email > receive a **code** (not a link) > sign in.
2. Phone A: book a doctor. It shows "Request sent".
3. Phone B (patient 2, different email): try the same slot. It must be refused or show as taken.
4. Doctor registers in the app (with certificate, ID, photo); you approve the doctor from the admin sign-in; the doctor then appears for patients on both phones.
5. Doctor signs in with email and password, sees the request, approves it with a different time. Phone A gets a notification and sees it confirmed.
6. Phone A cancels; the slot becomes free for Phone B.
7. Turn on airplane mode: the app shows a clear error and does not lose typed details.

## Build and test a debug APK with GitHub Actions

1. Add the repository secrets (step 7 above).
2. Push to `main`, or open **Actions > Build APK > Run workflow**.
3. Download `Nirog-debug.apk` from the `latest-apk` release or from the run's artifacts.
4. Install it and run the manual checklist above on two phones.

## Incomplete features (be honest about these)

1. **Nothing has been tested against the live project or on a device yet.** See the manual checklist.
2. **Mobile OTP is not built.** Only email OTP. SMS needs a provider that can deliver in India under DLT rules.
3. Now connected but **only tested against a fake server**: lab and hospital registration with uploads and listing, admin review of doctors and facilities, the platform fee and support contacts, sales leads. Still not connected: admin team management (adding sales staff; use SQL or `admin_set_staff` for now) and the revenue/bookings overview charts.
4. The doctor clinic photo gallery is uploaded but not shown to patients; only the profile photo is.
5. Offline: the app shows an error and keeps typed details, but there is no cached read-only browsing.
6. Doctors' mobile numbers are saved on their account but not shown anywhere yet.
7. Patient profile edits (name, age, sex) are kept on the device only; age and sex are sent with each booking.
8. Referral program, online payments, push notifications and email or SMS reminders are not built. In-app notifications are stored in the `notifications` table and refresh about every 30 seconds.
9. The `appointment_slots` table in the original brief was replaced by generating slots on demand (`open_slots`), which avoids stale slot rows. One active booking per slot is still enforced.
10. Account deletion and data export are not built.
11. Existing local demo data is not migrated.
