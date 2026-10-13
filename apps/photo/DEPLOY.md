# GoldenMole Photos – deploy checklist

Photo and video albums at `photo.goldenmole.pro`. Code: `apps/photo/` (Vite + React, Vercel functions in `api/`).
Files are stored in one Google Drive account as `GoldenMole Photos / <พ.ศ.> / <MM-เดือน> / <album title>`;
the database only keeps the index. Same Supabase project as the other apps (`cocvespahjymyrvmqzcs`); tables are prefixed `ph_`.

## 1. Database

`supabase/migrations/20261012100000_ph_photo_albums.sql` is already applied to the project.
For a fresh project, apply it in the Supabase SQL editor or with `supabase db push`.

Staff sign in with their `admin_users` account. The site key is `photo`: SuperAdmin and Admin have it by default;
grant it to other accounts in the main app's admin page (edit user → เว็บไซต์ที่เข้าใช้ได้ → อัลบั้มรูป).

## 2. Google Cloud (once)

1. In [Google Cloud Console](https://console.cloud.google.com/), create a project (e.g. `goldenmole-photos`) and enable **Google Drive API**.
2. **OAuth consent screen**: user type External, app name `GoldenMole Photos`, support email, and under App domain:
   - Home page `https://photo.goldenmole.pro`
   - Privacy policy `https://photo.goldenmole.pro/privacy`
   - Terms of service `https://photo.goldenmole.pro/terms`
   - Authorized domain `goldenmole.pro`
   Scopes: `.../auth/drive.file`, `openid`, `email` (all non-sensitive, so no Google review is needed).
3. **Publish the app** (Publishing status → *In production*). While it is in *Testing*, Google revokes the refresh token after 7 days and uploads stop.
4. **Credentials → Create OAuth client ID → Web application**:
   - Authorized redirect URI: `https://photo.goldenmole.pro/api/google/callback`
   - Copy the client ID and secret into the Vercel env vars below.

`drive.file` lets the app see only the files and folders it created, not the rest of the Drive.

## 3. Vercel project

Create a new project from `kraittisak2022-commits/GoldenMole`:

- **Project name:** `photo` · **Root Directory:** `apps/photo` · **Framework:** Vite
- **Production branch:** `main`
- **Env vars** (Production and Preview, all server-only, never prefix with `VITE_`):

| Name | Value |
| --- | --- |
| `SUPABASE_URL` | `https://cocvespahjymyrvmqzcs.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | *Copy the key itself, not this text:* Supabase dashboard, Project Settings, API Keys, the `service_role` (secret) key. It starts with `eyJ` or `sb_secret_`. |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | *Copy from step 2.* The ID ends with `.apps.googleusercontent.com`; the secret starts with `GOCSPX-`. |
| `PHOTO_SESSION_SECRET` | *Generate one:* output of `openssl rand -base64 48` (or any 40+ random characters, no spaces). |
| `PUBLIC_ORIGIN` | `https://photo.goldenmole.pro` |
| `ALLOWED_ORIGINS` (optional) | extra origins allowed to upload, comma-separated, e.g. `https://photo.vercel.app` |

Changing `PHOTO_SESSION_SECRET` signs everyone out; it does not affect share links.
If a value contains spaces or non-ASCII characters (for example a pasted label with "→"), the API answers
"ระบบยังตั้งค่าไม่ครบ" and the Vercel logs name the variable. Redeploy after editing env vars.

Optional **Ignored Build Step**, so pushes that only touch other apps skip this build:

```bash
git diff --quiet HEAD^ HEAD -- .
```

### DNS (Cloudflare, zone `goldenmole.pro`)

| Type | Name | Target | Proxy |
| --- | --- | --- | --- |
| CNAME | `photo` | `cname.vercel-dns.com` | DNS only (grey cloud) |

Then add `photo.goldenmole.pro` under the Vercel project's Domains. Vercel issues the certificate once the record resolves.

## 4. After the first deploy

1. Sign in at `https://photo.goldenmole.pro/login` with a **SuperAdmin** account.
2. **ตั้งค่า → เชื่อมต่อ Google Drive** and sign in with the Google account that should hold the files
   (a dedicated account such as `goldenmole.photos@gmail.com` is easiest to hand over).
3. Back on the settings page you should see "เชื่อมต่อกับ <that email>".

Storage: a free Gmail account has 15 GB shared with Gmail and Google Photos. Videos fill it quickly; upgrade the account
to Google One if needed. Uploads fail with a Drive error when it is full.

## Verify

- Create an album, add a few photos and a short video, and check that the folder appears in Drive under the right year and month.
- Press **คัดลอกชื่อรายงาน + ลิงก์**, paste into a chat: two lines, the title and `https://photo.goldenmole.pro/a/<token>`.
- Open the link in a private window (not signed in): photos show, download works, **เปิดใน Google Drive** opens the folder.
- Turn off "ให้คนที่มีลิงก์เพิ่มรูปได้" in the album settings: the public page no longer shows **เพิ่มรูป**.
- Delete the test album afterwards (its Drive folder goes to the Drive trash).

## Local development

```bash
cd apps/photo
npm install
npm run dev:mock   # in-memory sample data, no Google or Supabase needed (http://localhost:5190)
npm run dev        # real API: copy .env.example to .env and fill it in
npm test && npm run lint && npm run build
```

With `npm run dev`, Google redirects to `PUBLIC_ORIGIN`, so connect Drive from production, or add
`http://localhost:5190/api/google/callback` as a second redirect URI and set `PUBLIC_ORIGIN=http://localhost:5190` locally.
