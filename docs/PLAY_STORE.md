# Publishing Yada+ on Google Play

## 1. One-time: create the upload key (on your Windows PC)
Needs Java (JDK 17). Open Command Prompt in an empty folder and run:

    keytool -genkeypair -v -keystore upload.keystore -alias yada -keyalg RSA -keysize 2048 -validity 10000

Pick a strong password and remember it (use it for both the store and key password). Keep `upload.keystore` and the password in two safe places (a cloud drive and a USB). If you lose them you can ask Google to reset the upload key, but it takes days.

Convert the file to text (PowerShell):

    [Convert]::ToBase64String([IO.File]::ReadAllBytes("upload.keystore")) | Set-Clipboard

Then add four repository secrets (GitHub repo -> Settings -> Secrets and variables -> Actions -> New repository secret):

| Name | Value |
|---|---|
| KEYSTORE_BASE64 | paste from the clipboard |
| KEYSTORE_PASSWORD | the password |
| KEY_ALIAS | yada |
| KEY_PASSWORD | the same password |

## 2. Build the bundle
GitHub -> Actions -> "Build Play Store bundle" -> Run workflow. When it finishes, download the artifact `yada-play-bundle` (it contains `app-release.aab`).

## 3. Play Console
1. Create the app: name **Yada+**, default language English (India), App, Free.
2. Turn on **Play App Signing** when asked (default).
3. Production or Closed testing -> Create release -> upload `app-release.aab`.
4. A new personal developer account must run a **closed test with 12 testers for 14 days** before it can apply for production. Company accounts skip this.

## 4. Store listing text

**App name:** Yada+

**Short description (80 characters max):**
Find doctors, labs and hospitals near you and book appointments in a few taps.

**Full description:**
Yada+ makes it simple to find the right care and book it.

Find doctors
- Browse doctors by speciality and city, with fees, languages, clinic address and ratings.
- Pick an open slot and book a clinic or video visit. You get a booking reference and a notification when the doctor confirms.
- After your visit, rate your doctor and see your prescription in the app.

Labs, hospitals, pharmacies and more
- Find diagnostic labs and centres, hospitals, pharmacies and other care near you, with opening hours, services and prices.
- Send an appointment request to a lab, diagnostic centre or hospital and get a reply as a notification.
- After a clinic visit is confirmed, open the clinic in Google Maps.

Ambulance
- A floating Ambulance button is always one tap away. National numbers 112, 108 and 102 are shown first, followed by ambulance services in your area. After calling, you can send your location to the service on WhatsApp.

For doctors, labs, hospitals, pharmacies and ambulance services
- Register your practice from the app. Our team verifies your licence before you are listed.
- Manage your schedule, accept or reschedule bookings and issue prescriptions.

Stay informed
- Get appointment updates and announcements as notifications on your phone.

Your privacy matters. We do not sell your data. Sponsored banners placed by Yada+ may appear. You can delete your account any time from Help and support.

Yada+ is a booking and listing service. It does not give medical advice. In an emergency call 112 or 108.

**Category:** Medical (alternative: Health & Fitness)
**Contact email:** spywellinfotech@gmail.com
**Privacy Policy URL:** https://spywellinfotech-sys.github.io/Nirog/privacy.html
**Account deletion URL (Data safety form):** https://spywellinfotech-sys.github.io/Nirog/delete-account.html

## 5. Graphics you need
- App icon 512x512: `web/icons/icon-512.png`
- Feature graphic 1024x500: not made yet. Needs the Yada+ logo on a light blue background.
- Phone screenshots: at least 2, ideally 4 to 8 (home, doctor profile and booking, appointments, facilities, ambulance).

## 6. Forms to fill (suggested answers)
**Data safety**
- Collects data: Yes. Shared with third parties: No (service providers only process data for us). Encrypted in transit: Yes. Users can request deletion: Yes (link above).
- Data types collected and why:
  - Personal info: name, email address, phone number, user IDs. Purpose: app functionality, account management.
  - Health info: reason for visit, prescriptions. Purpose: app functionality.
  - Photos and videos: profile photo, verification documents, facility photos, prescription photos. Purpose: app functionality.
  - Audio: only during video calls, handled live by Jitsi, not stored by Yada+. Purpose: app functionality.
  - Approximate and precise location: optional, only when the user taps a location button. Purpose: app functionality. Patient location sent to an ambulance goes via WhatsApp/SMS from the phone and is not stored by Yada+.
  - Financial info: UPI ID for referral payouts. Purpose: app functionality.
  - App activity: counts of ad views and Call/WhatsApp taps on listings. Purpose: app functionality, analytics for listing owners. No advertising profile.
  - Device or other IDs: push notification token. Purpose: app functionality.

**Health apps declaration:** Yes, the app provides health-related features (appointment booking, medical records). It is not a medical device and gives no diagnosis. 

**Content rating:** Complete the questionnaire. No violence, no user-generated public content (reviews show first name only). Expected: Everyone.

**Target audience:** 18 and over.

**Ads:** Yes, the app contains ads. They are sponsored banners and videos placed by Yada+ itself. There is no third-party ad SDK.

**Government apps / financial features:** No.

**Permissions used:** Notifications (POST_NOTIFICATIONS), Camera and Microphone (video consultations), Location (optional buttons only), Internet. Be ready to explain each one in the Play Console permissions declaration.

## 7. Before you submit
- Test the release build on a real phone, including push, Google sign-in and delete account.
- Keep the web app address and the privacy and deletion pages live.
- Check the name "Yada+" for trademark and Play Store conflicts.
- Rotate the exposed SMS (apitxt) key and the admin password.
- Package name is `com.yadaplus.app`. Remove the demo accounts (demo.*@yadademo.test) before the Play review.
- Give the Play reviewers a test Google account for patient login, and a demo doctor login for the doctor side.
