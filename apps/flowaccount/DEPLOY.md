# FlowAccount – Vercel deploy checklist

The app code is on `main` under `apps/flowaccount/`.

**Vercel project:** `goldenmole-flowaccount` (id `prj_rbJ921rOo6hzLGRK2n8OqZS7tD2k`)  
**Root Directory:** `apps/flowaccount` (already set)  
**Git:** `kraittisak2022-commits/GoldenMole` → production branch `main`

## Remaining setup (Dashboard)

1. Open the project → **Settings → Environment Variables** and add (same values as `golden-mole`):
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_ANON_KEY`
2. **Settings → Domains** → add `flowaccount.goldenmole.pro`  
   (If DNS for `goldenmole.pro` is already on Vercel, verification is automatic; otherwise CNAME → `cname.vercel-dns.com`)
3. Optional **Ignored Build Step** (runs in Root Directory):
   ```bash
   git diff --quiet HEAD^ HEAD -- .
   ```
4. **Deployments → Redeploy** the latest production deployment (needed after adding env vars)

## Verify

Open `https://flowaccount.goldenmole.pro/login` (or the `*.vercel.app` URL) and sign in with a **SuperAdmin** from `admin_users`.
