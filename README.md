# MoonDrive

Cloud file manager demo with responsive UI and multi-account sidebar.

## Auth Modes

- Demo mode (default): all providers use mock login/password (`123456`).
- Real mode: Google Drive, OneDrive, and Dropbox use OAuth + provider APIs.

## Enable Real Google Auth

1. Create OAuth credentials in Google Cloud Console.
2. Enable Google Drive API.
3. Configure Android app package + SHA-1/SHA-256 fingerprints.
4. (Optional) create a Web client and pass its client id as `GOOGLE_SERVER_CLIENT_ID`.

## Run

```powershell
flutter pub get
flutter run
```

Run with real Google auth enabled:

```powershell
flutter run --dart-define=USE_REAL_AUTH=true --dart-define=GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

## Validate

```powershell
flutter analyze
flutter test
```

## Download Behavior And Play Policy Notes

- Downloads are user-initiated only (file tap -> `Download` action).
- The app shows a disclosure dialog before first download.
- Downloads are handed off to provider/browser links; no hidden background download service is used.

This pattern is generally acceptable for Google Play when paired with a clear privacy policy and accurate Data safety declarations for account/token handling.

"# SkillPath-AI" 
