# Stone & Sand orders – Vercel deploy checklist

The app code is on `main` under `apps/stone-sand/`. It uses the same Supabase project as GoldenMole / FlowAccount (`cocvespahjymyrvmqzcs`); all tables and RPCs are prefixed `ss_`.

## 1. Database

The schema, RPCs and seed data (products, zones, 12 drivers, settings) live in
`supabase/migrations/20261008100000_ss_stone_sand_schema.sql` and are already applied to the project.
For a fresh project, apply that migration (Supabase SQL editor or `supabase db push`).

## 2. Vercel project (Dashboard)

1. **Add New → Project** → import `kraittisak2022-commits/GoldenMole`.
2. **Root Directory:** `apps/stone-sand`
3. **Framework Preset:** Vite (build `npm run build`, output `dist` — the defaults).
4. **Settings → Environment Variables** (same values as `golden-mole` / `goldenmole-flowaccount`):
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_ANON_KEY`
5. Optional **Ignored Build Step** (runs in Root Directory):
   ```bash
   git diff --quiet HEAD^ HEAD -- .
   ```
6. Optional **Settings → Domains** → e.g. `stone.goldenmole.pro`.
7. **Deployments → Redeploy** after adding env vars.

`vercel.json` already rewrites every path to `index.html`, so deep links such as `/v/<token>` (bill verification QR) work.

## 3. After the first deploy

1. Sign in with an `admin_users` account (same accounts as FlowAccount).
2. **ตั้งค่า (Settings)**:
   - Check product prices and per-tambon delivery fees.
   - Enter the PromptPay number (phone or 13-digit tax ID) so unpaid bills show a payment QR.
   - Bank account text is optional.
3. **รถ / คนขับ (Drivers)** → set each driver's wage per trip if you want wage totals on the dashboard.

## Verify

- Open `/login`, sign in, create a test order and open its bill.
- Scan the QR at the bottom of the bill: it should open `/v/<token>` on the production domain and show "เอกสารถูกต้อง".
- Cancel the test order afterwards (order page → ยกเลิกออเดอร์) so it does not count in reports.
