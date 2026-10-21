# FRS Technician Demo APK

Technician-only Android packaging of the Fire Risk Systems end-to-end prototype. The prototype is bundled into the APK; no website login, server or internet connection is needed to open its sample workflows.

Includes assigned equipment, real QR decoding, sample scans, inspections, required answers, browser-local drafts, photo selection/camera integration, signatures, submissions, linked corrective actions, asset history and native PDF downloads.

All data and the 20 checklist templates are demonstration content. This is a review APK, not the production Flutter/backend implementation. Records stay on the device and are removed when the app's data is cleared or it is uninstalled. Manager functions remain in the separate web prototype. A technician can mark actions Resolved; management verifies and closes them in the production workflow.

Android 8.0 or later with a current Android System WebView is required. Camera use requests Android permission. On Android 10 and later, reports save under Downloads/FireRiskSystems; Android 8/9 uses the system Save document dialog. No broad storage permission is requested.

## Build

Install JDK 17, Android SDK Platform 35 and Build Tools 35.0.0. Unzip `web-assets.zip` into `android/assets/`, set `ANDROID_HOME`, and run `bash android/build.sh`.

The output is signed with a demonstration key for sideload testing. The key is unrelated to production signing or app-store publication.

`verify_android.py` installs the APK into an Android emulator and checks the actual embedded WebView: login, technician restriction, inspection answers, draft, sample photo, signature, submission, corrective action and native PDF download. Screenshots and logs are retained as CI artifacts. Live physical-camera testing is separate.

Third-party web dependency licenses are bundled with the assets. The Android shell uses Android platform APIs without external runtime libraries.
