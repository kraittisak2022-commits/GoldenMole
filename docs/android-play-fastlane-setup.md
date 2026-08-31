# Android Play Store — Fastlane (local)

One-time setup so you (or the agent) can run a single command to **build AAB → upload closed testing → set release name/notes → update Supabase soft-update version**.

## Prerequisites

| Tool | Purpose |
|------|---------|
| Flutter | `flutter build appbundle` |
| Ruby 3.2+ | Fastlane |
| Bundler | `gem install bundler` |
| Node.js 18+ | Supabase version sync script |
| Android signing | `android/key.properties` + `upload-keystore.jks` (already local, not in git) |

### Install Ruby + Fastlane (Windows)

1. Install [Ruby+Devkit 3.2.x (x64)](https://rubyinstaller.org/downloads/) — check **MSYS2** when prompted.
2. Open a new terminal:

```powershell
gem install bundler
cd c:\construction-management-app\mobile-flutter
bundle install
```

Verify:

```powershell
bundle exec fastlane --version
```

## One-time Google Play Console setup

**คู่มือภาษาไทย (UI 2024+ — ไม่มีเมนู API access แล้ว):** [google-play-api-setup-th.md](./google-play-api-setup-th.md)

สรุปสั้น:

1. [Google Cloud](https://console.cloud.google.com/) → Enable **Google Play Android Developer API** → สร้าง **Service Account** → ดาวน์โหลด JSON key
2. [Play Console](https://play.google.com/console) → **Users and permissions** (ระดับบัญชีนักพัฒนา) → **Invite new users** → วางอีเมล service account
3. แท็บ **App permissions** → เลือก **GoldenMole for User** → สิทธิ์ **Release manager** หรือ **Release to testing tracks**
4. JSON เก็บนอก repo เช่น `C:\secrets\goldenmole-play-api.json`
5. **Testing → Closed testing** — track slug มักเป็น `alpha`

Local setup script:

```powershell
cd c:\construction-management-app\mobile-flutter
.\scripts\setup-play-api.ps1 -JsonKeyPath "C:\secrets\goldenmole-play-api.json"
.\scripts\verify-play-api.ps1
```

## Configure secrets locally

```powershell
cd c:\construction-management-app\mobile-flutter
copy .env.play.example .env.play
# Edit .env.play — set PLAY_STORE_JSON_KEY_PATH, PLAY_STORE_TRACK, SUPABASE_SERVICE_ROLE_KEY
```

Never commit `.env.play` or the Play JSON key.

## Release workflow

### 1. Bump version in `pubspec.yaml`

```yaml
version: 1.0.3+4   # name+versionCode (versionCode must increase every upload)
```

### 2. Run closed-test release

From `mobile-flutter`:

```powershell
.\scripts\release-android-closed.ps1 `
  -ReleaseName "1.0.3 — แก้บันทึกน้ำมัน" `
  -ReleaseNotes @"
• บันทึกการใช้น้ำมันรายรถได้แม้ถังติดลบ
• ปรับ UX เพิ่มเติม
"@
```

What the script does:

1. Writes `fastlane/metadata/android/th-TH/changelogs/{versionCode}.txt` (and mirrors to `th/`)
2. Sets **ชื่อรุ่น** via Fastlane `version_name` (`-ReleaseName` or `PLAY_RELEASE_NAME`)
3. Uploads **บันทึกประจำรุ่น** from changelog files (`skip_upload_changelogs: false`)
4. Writes `store/PLAY_RELEASE_{versionName}.md` (copy for records)
5. `flutter build appbundle --release`
6. `bundle exec fastlane android closed_beta` → Play **closed testing** track
7. `node scripts/update-android-soft-version.mjs` → `app_settings.app_defaults`

**Required for each release:**

| Play Console field | Script parameter | Fastlane |
|--------------------|------------------|----------|
| ชื่อรุ่น | `-ReleaseName "1.0.4 — คำอธิบาย"` | `version_name` on upload |
| บันทึกประจำรุ่น | `-ReleaseNotes "• ..."` | `th-TH/changelogs/{versionCode}.txt` |

### Partial runs

```powershell
# Build only (no Play / Supabase)
.\scripts\release-android-closed.ps1 -SkipUpload -SkipSupabase

# Upload existing AAB (skip flutter build)
.\scripts\release-android-closed.ps1 -SkipBuild

# Upload only, no Supabase
.\scripts\release-android-closed.ps1 -SkipBuild -SkipSupabase
```

### Fastlane lanes (manual)

```powershell
cd mobile-flutter
$env:PLAY_STORE_JSON_KEY_PATH = "C:\secrets\goldenmole-play-api.json"
$env:PLAY_RELEASE_NAME = "1.0.3 — คำอธิบาย"
bundle exec fastlane android build_aab
bundle exec fastlane android closed_beta
```

## Agent / chat usage

When you ask the agent to ship Android to Play closed testing, it should:

1. Bump `pubspec.yaml` if needed
2. Fill release name + notes (Thai)
3. Ensure `.env.play` exists locally (you provide service account path once)
4. Run `.\scripts\release-android-closed.ps1 ...`
5. Commit version bump + changelog + `store/PLAY_RELEASE_*.md` (not secrets)

## Troubleshooting

| Error | Fix |
|-------|-----|
| `PLAY_STORE_JSON_KEY_PATH` missing | Create `.env.play` from example |
| `403` / permission denied on upload | Service account needs Release manager on this app |
| `Version code X has already been used` | Increment `+N` in `pubspec.yaml` |
| `Missing changelog` | Pass `-ReleaseNotes` or create `changelogs/{code}.txt` |
| Play processing slow | Normal 15–30 min before testers can install |
| Soft update not showing | Confirm Supabase `androidLatestVersionCode` > installed build number |

## Files

| Path | Role |
|------|------|
| `Gemfile` | Pins Fastlane gem |
| `fastlane/Fastfile` | `build_aab`, `closed_beta`, `release_closed` |
| `fastlane/metadata/android/th-TH/changelogs/` | Release notes per versionCode (primary locale) |
| `fastlane/metadata/android/th/changelogs/` | Mirror locale (auto-synced from th-TH) |
| `scripts/release-android-closed.ps1` | End-to-end release |
| `scripts/update-android-soft-version.mjs` | Supabase `app_defaults` merge |
| `.env.play.example` | Local secrets template |
