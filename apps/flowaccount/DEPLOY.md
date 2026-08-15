# FlowAccount – Vercel deploy checklist

The app code is on `main` under `apps/flowaccount/`.

## Create / configure project (Vercel Dashboard)

1. **Add New Project** → import `kraittisak2022-commits/GoldenMole`
2. **Root Directory:** `apps/flowaccount`
3. **Framework:** Vite
4. **Environment Variables** (same values as `golden-mole`):
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_ANON_KEY`
5. **Ignored Build Step** (optional, Root Directory context):
   ```bash
   git diff --quiet HEAD^ HEAD -- .
   ```
6. Deploy

## Domain

1. Project → Settings → Domains → add `flowaccount.goldenmole.pro`
2. If DNS is already on Vercel for `goldenmole.pro`, it should verify automatically; otherwise add a CNAME to `cname.vercel-dns.com`

## Verify

Open `https://flowaccount.goldenmole.pro/login` and sign in with a **SuperAdmin** account from `admin_users`.
