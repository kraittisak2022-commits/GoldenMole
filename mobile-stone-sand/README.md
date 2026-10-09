# ระบบจัดการออเดอร์ หิน-ทราย (Flutter)

Native Android/iOS app for the stone-sand order system. It talks to the same Supabase project as the web app
(`apps/stone-sand`); there is no separate backend.

Package / bundle id: `com.goldenmole.stonesand`

## Run

Create `mobile-stone-sand/.env` (gitignored, bundled as an asset):

```
SUPABASE_URL=...
SUPABASE_ANON_KEY=...
```

```
flutter pub get
flutter run
flutter analyze
flutter test
```

CI (`.github/workflows/ci.yml`, job `stone-sand-app`) runs analyze + test with an empty `.env`.

## Android release (Play closed testing)

One-time:

- `android/key.properties` (gitignored) pointing at the upload keystore:
  `storePassword`, `keyPassword`, `keyAlias`, `storeFile`. Without it the release build falls back to debug signing,
  which Play rejects.
- A Google Play service account JSON with access to the app; set `PLAY_STORE_JSON_KEY_PATH` to it.

Each release:

1. Bump `version:` in `pubspec.yaml` (the number after `+` is the versionCode).
2. Add `fastlane/metadata/android/th/changelogs/<versionCode>.txt`.
3. `bundle install` once, then `bundle exec fastlane android release_closed`.

| Variable | Default | Purpose |
| --- | --- | --- |
| `PLAY_STORE_TRACK` | `alpha` | Closed testing track |
| `PLAY_RELEASE_NAME` | `<version> — ออเดอร์หิน-ทราย` | Release name in Play Console |
| `SKIP_FLUTTER_BUILD` | | `1` uploads the existing AAB |
| `SKIP_SOFT_UPDATE_SYNC` | | `1` skips writing the version to Supabase |

`bundle exec fastlane android verify_play_api` checks the credentials without uploading.

## iOS release (TestFlight)

Codemagic workflow `stone-sand-ios` in `codemagic.yaml` (env group `goldenmole_dashboard`) writes `.env`, signs,
runs `flutter build ipa` and uploads to App Store Connect. Optional vars: `STONE_SAND_APP_STORE_APPLE_ID`
(auto-increment build number) and `STONE_SAND_TESTFLIGHT_URL` (link used by the update prompt).

## Soft update

After sign-in the app checks for a newer build once per run (skipped in debug and during the guided tour):

- Android: Play in-app update (flexible) first; otherwise `app_settings.app_defaults` keys
  `stoneSandAndroidLatestVersionCode`, `stoneSandAndroidLatestVersionName`, `stoneSandAndroidStoreURL`.
- iOS: `stoneSandIosLatestBuild`, `stoneSandIosLatestVersion`, `stoneSandIosTestFlightURL`.

The release lanes write these keys automatically (soft-fail). "ใช้งานต่อ" snoozes the prompt for 3 days per build.
