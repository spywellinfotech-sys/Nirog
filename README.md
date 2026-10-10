# Nirog for Android

Nirog is a doctor appointment app with a patient booking flow, doctor registration with a Google Maps location,
doctor-set time slots, and staff dashboards. This project wraps the web app in a native Android shell.
The whole app is bundled inside, so it opens without a server.

I could not compile this project where it was written, so it has not been built or run on a phone yet.
The first build is the real test. If Gradle reports anything, send me the message and I will fix it.

## Get the APK (no Android Studio needed)

1. Create a new empty repository on GitHub.
2. Upload everything in this folder to it, including the hidden `.github` folder.
3. Open the **Actions** tab, choose **Build APK**, and wait for the green tick (about 4 minutes).
4. Open the finished run and download **nirog-apk**. Unzip it to get `app-debug.apk`.
5. Copy the file to your phone and open it. Android will ask you to allow installs from that source.

## Or build it in Android Studio

1. Open this folder in Android Studio (Koala or newer).
2. Wait for Gradle sync, then choose **Build > Build Bundle(s) / APK(s) > Build APK(s)**.
3. The file is at `app/build/outputs/apk/debug/app-debug.apk`.

## Or build it from a terminal

You need JDK 17 and the Android SDK (platform 34).

    ./gradlew assembleDebug

## Updating the app

Replace `app/src/main/assets/www/index.html` with the new version of the page and build again.
Raise `versionCode` in `app/build.gradle.kts` for each release you hand out.

## Good to know

- The debug APK is signed with a debug key. It installs fine for testing and sharing, but Google Play needs a release
  build signed with your own keystore.
- Patient sign-in uses a mobile number and a one-time code. In this build the code is shown on screen (demo mode) because no SMS service is connected. Bookings, sign-ins and registered doctors are stored on the phone only. A shared backend is needed before real
  patients and clinics use it together.
- Google Maps links open in the Google Maps app. The Back button steps back inside the app before it exits.
- Application id: `com.nirog.app`. Minimum Android version: 7.0 (API 24).

## Web app (web/ folder)

`web/` is the same Nirog app as a website. It is a Progressive Web App: on a phone, open the site in Chrome and choose Add to Home screen (or Install app) and it opens full screen like an app, and works offline once loaded.

Publish it free with GitHub Pages:
1. Upload this whole project to your repository (keep the `web` and `.github` folders).
2. Repository Settings -> Pages -> Source: **GitHub Actions**.
3. Actions tab -> **Deploy web app** -> Run workflow. The address is shown on the finished run, usually `https://<your-username>.github.io/<repository>/`.

Or drag the `web` folder onto any static host (Netlify Drop, Cloudflare Pages, Firebase Hosting, your own server).

Deep links: add `#staff` (staff sign-in), `#register` (doctor sign-up) or `#facility` (lab, centre and hospital sign-up) to the end of the web address.

Note: data (bookings, doctors, profiles, uploads) is saved in each visitor's own browser, not on a server. A real launch needs a backend.
