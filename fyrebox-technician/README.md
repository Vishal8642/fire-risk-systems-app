# Fyrebox Technician · 2.0

Flutter Android demonstration with the Fyrebox website palette, logo and Montserrat typography. Open **Demo workspace** to try 20 demo checklists across extinguishers, hose reels, hydrants, detection, sprinklers and suppression. Register equipment, generate a permanent QR label, scan or search equipment, complete checklists with photos/service notes/signatures, resume drafts, produce PDF reports and record corrective work.

Checklist content is illustrative and will be replaced by the client’s approved forms. Connected mode accepts the organisation’s HTTPS API address and technician credentials; shared users, permissions, published checklist versions and manager verification are provided by the separately deployed management platform. Demonstration data stays on the device and is not uploaded automatically.

Build with Flutter 3.47.7, JDK 17 and Android SDK 36. Run `flutter pub get`, `flutter analyze --no-fatal-infos`, `flutter test`, then `flutter build apk --release`. The GitHub Actions workflow builds the installer and verifies its signature/alignment. Android 8.0/API 26 or later is required.

The build runner generates a test signing key; no private signing key is stored in this repository. The demo uses application ID `africa.fyrebox.technician.preview` and installs alongside the earlier APK. Set `FYREBOX_KEYSTORE_FILE`, `FYREBOX_STORE_PASSWORD`, `FYREBOX_KEY_ALIAS`, `FYREBOX_KEY_PASSWORD` and optionally `FYREBOX_APP_ID` to use a client-owned production signing identity. Preserve the production key for future updates.

Version 2 uses a separate demonstration workspace from the earlier WebView demo; older demo records are not migrated. The main interface is Flutter. The camera scanner uses an isolated, local WebView with a bundled QR decoder; photos, encrypted sessions and file sharing use the native Android bridge. Validate camera/gallery/share behaviour on the target physical devices before rollout.

Montserrat and jsQR licenses are included with their assets. No real client checklists, customer records, production credentials or server configuration are included in this demonstration source.
