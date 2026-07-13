# Goldenmole Dashboard — Native iOS App

Native SwiftUI dashboard app for iOS that connects to the same Supabase backend as the web app. Shows login plus all dashboard views: Overview V.1, Analytics V.2, Calendar V.3, Real-time V.4, Overview V.5, and category reports (ค่าแรง, การใช้รถ, ล้างทราย, น้ำมัน, ที่ดิน, รายรับ).

## Requirements

- iOS 16+
- Xcode 15+ (build on macOS or GitHub Actions `macos-14` runner)
- [Apple Developer Program](https://developer.apple.com/programs/) ($99/year) for App Store / TestFlight
- Supabase project URL + anon key (same as web app)

## Project structure

```
ios-swiftui/
  project.yml          # XcodeGen spec — run `xcodegen generate` on Mac
  Config/
    Secrets.example.xcconfig
    Secrets.xcconfig   # gitignored locally; CI writes from secrets
  Sources/
    App/               # App entry, AppState
    Auth/              # Login, SHA-256 password verify
    Data/              # Models, SupabaseService, aggregations
    Charts/            # Donut, bar, line, scatter
    Dashboard/         # All dashboard views
  Resources/           # Assets, Info.plist, Localizable.strings
  fastlane/            # TestFlight upload
```

## Local setup (Mac)

1. Copy secrets:
   ```bash
   cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
   ```
2. Edit `Config/Secrets.xcconfig` with your `SUPABASE_URL` and `SUPABASE_ANON_KEY` (from web `.env` or Supabase dashboard).
3. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
4. Generate Xcode project:
   ```bash
   cd ios-swiftui
   xcodegen generate
   open GoldenmoleDashboard.xcodeproj
   ```
5. Select your Team in Signing & Capabilities, then Run on simulator or device.

## Windows development

You cannot run Xcode on Windows. Workflow:

1. Edit Swift sources on Windows.
2. Push to GitHub.
3. CI on `macos-14` runs `xcodegen generate` + `fastlane beta` to build and upload TestFlight.

## GitHub Actions secrets

| Secret | Description |
|--------|-------------|
| `SUPABASE_URL` | e.g. `https://xxxx.supabase.co` |
| `SUPABASE_ANON_KEY` | Supabase anon/public key |
| `APP_STORE_CONNECT_API_KEY_ID` | App Store Connect API key ID |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Issuer ID from App Store Connect |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | Base64-encoded `.p8` key contents |
| `MATCH_PASSWORD` | Optional — if using match for certs |
| `FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD` | Optional — legacy upload fallback |

## One-time App Store setup

1. Enroll in [Apple Developer Program](https://developer.apple.com/programs/).
2. Register bundle ID: `com.goldenmole.dashboard` in Certificates, Identifiers & Profiles.
3. Create app record in [App Store Connect](https://appstoreconnect.apple.com/) — name **Goldenmole Dashboard** (Apple ID: `6790311737`).
4. Create App Store Connect API key (Users and Access → Keys) with App Manager role.
5. Follow [docs/codemagic-setup.md](../docs/codemagic-setup.md) for Codemagic (API key + env vars + build).
6. In App Store Connect, add:
   - Privacy policy URL
   - Screenshots (6.7", 6.5", iPad if supporting tablet)
   - App description in Thai
   - Submit for review after TestFlight validation

## Authentication

Uses the same custom `admin_users` login as the web app:

- Fetches users from `admin_users` table
- Verifies password with SHA-256 (`sha256$` prefix) or legacy plain text
- Session stored in UserDefaults (admin id)

## Data tables

| Table | Usage |
|-------|--------|
| `admin_users` | Login |
| `transactions` | All dashboard metrics |
| `employees` | Names in reports / V.4 |
| `app_settings` | Cars, income types, app name (`id = default`) |

## App icon

Icon sourced from `mobile-flutter/assets/branding/app_logo.png` (Golden Mole). Replace `Resources/Assets.xcassets/AppIcon.appiconset/app_logo.png` with a 1024×1024 PNG for production.

## Version

- Marketing version: 1.0.0 (set in `project.yml`)
- Build number: incremented by fastlane on CI

## Scope

- **Read-only** dashboard (no data entry)
- V.4: count-record overview + live/polling refresh (no round manager / share links)
- V.3: read-only calendar (no add/delete entries)
- V.5: CSV export via iOS share sheet
