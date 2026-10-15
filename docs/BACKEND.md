# Applo backend (Supabase): setup, testing and status

**Status: Phase 2 is built but only tested against a fake Supabase server.** The app now runs in backend mode when `config.js` holds a project URL and key (it does: project `rxhanrtoaplwphmwpgqg`). Patients sign in with **Google** (`patientAuth: "google"` in `config.js`). SMS codes (`"sms"`, Twilio) and email codes (`"email"`) are still in the code and can be switched on by changing that one value. doctors and admins sign in with email and password. The following has **not** been verified against the live project or on a phone: sign-in, booking, approval, uploads. Do not call the platform fully working until you have run the manual checklist at the end of the Tests section on two real devices.

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
   - **Phone (patients):** Authentication > Providers > Phone > enable, choose **Twilio Verify** (recommended for India: it handles the sender registration) or **Twilio**. Paste the Account SID, Auth Token and Verify Service SID (or Messaging Service SID / number) from the Twilio console, into Supabase only. Set the OTP length to 6. A Twilio *trial* account can only text numbers you have verified in Twilio, so upgrade it before real patients use the app. Twilio charges per SMS.
   - **Google (patients, optional):** in Google Cloud Console > APIs & Services > Credentials, create an **OAuth client ID** of type *Web application*. Add the authorized redirect URI `https://YOUR-PROJECT-REF.supabase.co/auth/v1/callback`. In Supabase: Authentication > Providers > Google > enable, paste the Client ID and Client Secret (into Supabase only). Then Authentication > URL Configuration > **Redirect URLs**: add `nirog://auth` (the Android app return) and your web address if you use the web app. The Android app opens Google in the phone's browser and returns through `nirog://auth`. iOS is not wired for this yet. To hide the button set `googleLogin: false` in `config.js`.
   - **Email (doctors, labs, admins):** turn **Confirm email OFF** (registration needs an immediate session). Optional: add custom SMTP under Project Settings > Authentication > SMTP Settings.
   - To use email codes for patients instead: set `patientAuth: "email"` in `config.js` and edit the **Confirm signup** and **Magic Link** templates to show `{{ .Token }}` instead of `{{ .ConfirmationURL }}`.
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
1. Phone A: My appointments > enter mobile number > receive an SMS code > sign in.
2. Phone A: book a doctor. It shows "Request sent".
3. Phone B (patient 2, different email): try the same slot. It must be refused or show as taken.
4. Doctor registers in the app (with certificate, ID, photo); you approve the doctor from the admin sign-in; the doctor then appears for patients on both phones.
5. Doctor signs in with email and password, sees the request, approves it with a different time. Phone A gets a notification and sees it confirmed.
6. Phone A cancels; the slot becomes free for Phone B.
7. Turn on airplane mode: the app shows a clear error and does not lose typed details.

## Build and test a debug APK with GitHub Actions

1. Add the repository secrets (step 7 above).
2. Push to `main`, or open **Actions > Build APK > Run workflow**.
3. Download `Applo-v<build>.apk` from the `latest-apk` release or from the run's artifacts.
4. Install it and run the manual checklist above on two phones.

## Incomplete features (be honest about these)

1. **Nothing has been tested against the live project or on a device yet.** See the manual checklist.
2. SMS delivery depends on your Twilio account (trial limits, India sender rules). Not tested live.
3. Now connected but **only tested against a fake server**: lab and hospital registration with uploads and listing, admin review of doctors and facilities, the platform fee and support contacts, sales leads. Still not connected: admin team management (adding sales staff; use SQL or `admin_set_staff` for now) and the revenue/bookings overview charts.
4. The doctor clinic photo gallery is uploaded but not shown to patients; only the profile photo is.
5. Offline: the app shows an error and keeps typed details, but there is no cached read-only browsing.
6. Doctors' mobile numbers are saved on their account but not shown anywhere yet.
7. Patient profile edits (name, age, sex) are kept on the device only; age and sex are sent with each booking.
8. Referral program, online payments, push notifications and email or SMS reminders are not built. In-app notifications are stored in the `notifications` table and refresh about every 30 seconds.
9. The `appointment_slots` table in the original brief was replaced by generating slots on demand (`open_slots`), which avoids stale slot rows. One active booking per slot is still enforced.
10. Account deletion and data export are not built.
11. Existing local demo data is not migrated.

## Update: cities, doctor Google login, uploads
- City dropdown now lists ~135 Indian cities (all-India).
- Doctors can register and sign in with Google (registration form and staff sign-in screen). Facility/lab registration still uses email and password.
- Photo processing was rewritten (object URLs); upload and submit errors now appear above the Submit button with a code. Not yet verified on a real device.
- City fields accept any typed city (with suggestions).

## SMS OTP (apitxt)
- Edge Function `supabase/functions/sms-otp` (deployed, verify_jwt off because it is a public OTP endpoint with its own rate limit: 3 codes per number per 10 min, 5 wrong tries, 5 min expiry; only hashes are stored in `sms_otps`).
- Secrets needed in Supabase (Edge Functions, Secrets): `APITXT_AUTH_KEY`, optional `APITXT_TEMPLATE_ID`.
- Turn on in the app by setting `patientAuth:"sms"` in config.js (Google button stays). Not verified live until the key is set and a real SMS arrives.

## Duplicate registrations (migration 0006)
- One Google/email account can register once (the register functions require the patient role and then change it).
- One mobile number maps to one account (unique index on profiles.phone); doctor and facility registration reject a number used by another account with `phone_in_use`.
- Fixed: register_doctor / register_facility take a single `p jsonb`, so the client must send `{p: {...}}` (it was sending the bare object, which PostgREST answered with 404 — the cause of "http_404" on Submit for review).
- Migrations are additive; existing users and data are untouched.
- Admin screens: Full profile, Edit and Delete for doctors and facilities (needs migration 0007 applied in Supabase).

## Ratings and reviews (migration 0008)
- Patients rate a confirmed past visit (1-5 stars, optional comment, one per booking, editable). Doctor page shows the average and reviews (first name only). Admin can delete a review from a doctor's Full profile.
- The app tolerates the migration being missing (no ratings shown, submitting a review shows an error) until it is run.

## Free-booking promo and force update (migration 0009)
- `platform_settings.promo_until`: while it is in the future, `create_booking` records a platform fee of 0. Super admin sets it in Settings (date, fee free through the end of that day, IST). Empty means no promo.
- `platform_settings.min_build`: the Android app adds `NirogApp/<versionCode>` to its user agent. If that number is lower than `min_build`, the app shows an "update" screen linking to `update_url` (default: the latest-apk release). The web app is never blocked. The build number is the run number in `Nirog-v1.0.0.<run>.apk`.

## Prescriptions (migration 0010)
The doctor of a confirmed booking can, from the visit day on, write a prescription (diagnosis, up to 15 medicines, advice, follow-up date) and/or attach up to 4 photos. `save_prescription({p:{...}})` validates and upserts (one per booking) and notifies the patient. Photos go to the private `prescriptions` bucket under `<booking id>/<file>`; the patient, that doctor and admins can read them through signed URLs. Table reads are limited by RLS to the patient, the doctor and admins. Apply `0010_prescriptions.sql` in the SQL editor in small parts if the dashboard paste truncates.

## Broadcast notifications (migrations 0011, 0012)
Super admin > Notify: title, message, optional photo and short video (MP4/WebM, up to 20 MB, 60 s), audience (everyone, patients, doctors, facilities) and an optional city. `admin_send_broadcast({p:{...}})` stores the broadcast, adds a notification row for every target, and users see a popup once per phone. Media sits in the public `broadcast-media` bucket (only admins can upload). City targeting uses `patients.city` (saved when a patient picks a location), `doctors.city` and `facilities.city`; patients with no city are skipped for city sends. `admin_broadcast_reach` returns the audience size before sending. Phone tray push (FCM) is not part of this yet.

## Phone push (Firebase Cloud Messaging)
- Android shell gets an FCM token (`NirogMessagingService`, `NirogNative.pushToken()`); the web app registers it with `register_push_token` after sign-in and drops it on sign-out (`drop_push_token`).
- Table `push_tokens` (migration 0013) is unreadable by clients. `broadcast_tokens(id)` and `remove_push_tokens(text[])` are service-role only.
- Edge Function `send-push`: admin-only (JWT checked against `staff_members`), reads `FIREBASE_SERVICE_ACCOUNT` secret, signs an OAuth JWT, sends via FCM HTTP v1, removes dead tokens. The admin app calls it right after `admin_send_broadcast`.
- Video is shown in the in-app popup; the tray notification carries title, text and optional photo.
- Setup: apply `0013_push_tokens.sql`, deploy `send-push`, set secret `FIREBASE_SERVICE_ACCOUNT`.

## Dashboard counts, revoke, ambulances, pharmacies (migrations 0014 to 0016)
- `admin_dashboard_counts()` (admin only): patients, listed and pending doctors, and facilities per type (lab, centre, hospital, pharmacy, other), doctors by speciality, and phones registered for push (`push_tokens`). App installs is the phone count, so it only covers recent Android builds.
- `admin_revoke_broadcast(id)`: marks a broadcast revoked, hides it from users (popup and bell) and deletes the notification rows it created (`notifications.broadcast_id`). `broadcast_tokens` skips revoked broadcasts. A notification already on a lock screen cannot be recalled.
- Bell: broadcasts show under "Announcements" with photo and video; booking updates stay in the list.
- `ambulance_services`: public read of active rows, admin-only writes through `admin_save_ambulance` and `admin_delete_ambulance`. A blank city means every location. The national numbers 112, 108 and 102 are fixed in the app and shown first.
- Facility type `pharmacy` is its own category (register, review, list, filter). Older "Other care" entries whose type is Pharmacy also show under the Pharmacies filter.

## Ambulance services self-register (migration 0017)
- Facility type `ambulance` goes through the same `register_facility` and admin review as other facilities. The mobile number in `wa` is required for this type and becomes a Call button; `emergency` means available 24x7.
- Approved ambulance facilities are merged into the Ambulance page (per city) with the admin-curated `ambulance_services` list. Pending or rejected ones never show.
