# Photo Albums — Design

**Date:** 2026-10-12
**App:** `apps/photo`
**Domain:** `photo.goldenmole.pro`

## Goal

A Google Photos-style web app for site reports. Staff create an album per report, people upload photos
and videos into it, and a Copy button puts the report name and the share link on the clipboard so it can
be pasted into a group chat. Every file is stored in one Google Drive account: one album is one folder,
filed under year and month folders.

## Decisions

| Topic | Decision |
|-------|----------|
| Hosting | Standalone Vite + React + Tailwind app in `apps/photo`, Vercel functions in `api/`, same Supabase project as GoldenMole (tables prefixed `ph_`) |
| Who creates albums | Staff signed in with `admin_users` (site key `photo`, default roles SuperAdmin and Admin) |
| Who views / adds | Anyone with the album link can view, download and add photos or videos. Each album has an on/off switch for adding through the link |
| Share link | `https://photo.goldenmole.pro/a/<token>` (128-bit random token), plus a button that opens the album's Drive folder |
| Drive layout | `GoldenMole Photos / <Buddhist year> / <MM>-<Thai month> / <album title>`, e.g. `GoldenMole Photos / 2569 / 10-ตุลาคม / เทปูนชั้น 2` |
| Year/month source | The album's report date (chosen on create, defaults to today). Changing it moves the folder |
| Copy text | Two lines: album title, then the share link |

## Architecture

- Every Google Drive call runs in a Vercel function. The Google refresh token and the Supabase
  service-role key never reach the browser.
- The Drive account is connected once by a SuperAdmin (OAuth, scope `drive.file` plus `openid email`).
  The refresh token is stored in `ph_settings`, which has RLS on and no policies.
- Uploads: the function creates a Drive resumable upload session (with the browser's `Origin`, so CORS
  works) and returns its URL. The browser PUTs 8 MB chunks straight to Google, then calls `complete`,
  which checks that the file's parent is the album folder before inserting the `ph_media` row.
- Viewing: album folders get the Drive permission "anyone with the link: reader". Thumbnails and large
  images load from `lh3.googleusercontent.com/d/<id>=w<size>` (falling back to
  `drive.google.com/thumbnail`), videos play in the Drive `/preview` iframe, downloads use
  `drive.google.com/uc?export=download`.
- Staff sign-in is checked on the server; it returns an HMAC-signed token (12 hours). Staff endpoints
  verify the token and re-check the account's site access on every request.

## Data

- `ph_albums` — title, report_date, drive_folder_id, share_token, allow_link_upload, cover_media_id,
  media_count, created_by, timestamps, deleted_at (soft delete)
- `ph_media` — album_id, drive_file_id, kind, mime, name, size_bytes, width, height, taken_at,
  uploaded_by_name, uploaded_by_staff_id, created_at
- `ph_drive_folders` — path key (`root`, `2569`, `2569/10`) to Drive folder id, so year/month folders
  are not created twice
- `ph_settings` — single row: Google refresh token, account email, connected_at, connected_by

## Limits for uploads through the link

- `image/*` and `video/*` only
- Up to 50 MB per image and 2 GB per video
- Up to 300 link uploads per album per hour

## UI

Material 3 look modeled on Google Photos: white surfaces, Google blue accent, rounded 12-16 px corners,
dark theme following the system, Noto Sans Thai, `lucide-react` icons.

- `/login` — staff sign-in
- `/` — album grid with search and a create button
- Create dialog — title, report date, link-upload switch; on success a share card with Copy and Drive
- `/albums/:id` — header actions (Copy, Drive, Add, Settings), justified grid grouped by day,
  selection to download or delete, drag-and-drop upload
- `/a/:token` — public view: grid, viewer, add photos when allowed (optional uploader name), Drive
- `/settings` — Google Drive connection (SuperAdmin)
- Upload tray in the bottom-right corner with per-file progress, retry and cancel

## Error handling

- Drive not connected: creating an album or uploading returns `drive_not_connected`; the UI says so and
  links SuperAdmins to Settings.
- Upload chunk failures retry with backoff, asking Google for the committed offset before resuming.
- Thumbnails Drive has not generated yet (new videos) show a placeholder and retry later.

## Testing

Vitest for the pure helpers (folder path, share text, justified rows, limits, session token, range
parsing, EXIF date, site access) and for the upload API handlers with Drive and Supabase mocked.
