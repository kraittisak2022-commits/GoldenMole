# Stone & Sand orders – Vercel deploy checklist

The app code is on `main` under `apps/stone-sand/`. It uses the same Supabase project as GoldenMole / FlowAccount (`cocvespahjymyrvmqzcs`); all tables and RPCs are prefixed `ss_`.

## 1. Database

The schema, RPCs and seed data (products, zones, 12 drivers, settings) live in
`supabase/migrations/20261008100000_ss_stone_sand_schema.sql` and are already applied to the project.
For a fresh project, apply that migration (Supabase SQL editor or `supabase db push`).

## 2. Vercel project (already set up)

**Vercel project:** `stone-sand` (id `prj_bw2ZQEro8irLwZCh1sYSoVt0z8OQ`)  
**Root Directory:** `apps/stone-sand` · **Framework:** Vite  
**Git:** `kraittisak2022-commits/GoldenMole` → production branch `main` (every push deploys)  
**Env vars:** `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` (production, preview, development)  
**Domains:** `order.goldenmole.pro` (primary), `www.order.goldenmole.pro` → 308 redirect to the primary  
**Fallback URL:** `https://stone-sand.vercel.app`

Optional **Ignored Build Step** (runs in Root Directory), so pushes that only touch other apps skip this build:
```bash
git diff --quiet HEAD^ HEAD -- .
```

### DNS (Cloudflare, zone `goldenmole.pro`)

| Type | Name | Target | Proxy |
| --- | --- | --- | --- |
| CNAME | `order` | `cname.vercel-dns.com` | DNS only (grey cloud) |
| CNAME | `www.order` | `cname.vercel-dns.com` | DNS only (grey cloud) |

`www.order` must stay DNS only: Cloudflare's free certificate covers only `*.goldenmole.pro`, not `*.order.goldenmole.pro`, so proxying it breaks HTTPS. Vercel issues the certificates once the records resolve.

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
