# ออเดอร์หิน-ทราย · หจก. พีรสิทธิ์ วัสดุก่อสร้าง

Web app for taking stone and sand orders: pickup or delivery, delivery fee from a map pin, payment / delivery / bill-clearing status, monthly statements for credit customers, and printable bills (delivery note, receipt, statement) with a stamp, a watermark and a verification QR.

## Stack

React 18 + TypeScript + Vite + Tailwind, Supabase (shared GoldenMole project, `ss_*` tables), Leaflet + OpenStreetMap, Vitest.

## Run locally

```bash
cd apps/stone-sand
cp .env.example .env   # SUPABASE_URL / SUPABASE_ANON_KEY (or VITE_* names)
npm install
npm run dev            # http://localhost:5180
```

Sign in with an `admin_users` account.

## Scripts

| Command | What it does |
| --- | --- |
| `npm run dev` | Dev server on port 5180 |
| `npm run build` | Type-check and build to `dist/` |
| `npm run lint` | ESLint, zero warnings allowed |
| `npm test` | Unit tests (pricing, delivery fee, trips, baht text, PromptPay, bill data, wizard) |

## Where things live

- `src/pages/new-order/` – 5-step order wizard (customer → products → pickup/delivery → summary → confirm)
- `src/calc/` – pure pricing, delivery-fee and trip calculations
- `src/lib/geo.ts` + `src/data/geo/` – tambon boundaries and main roads for อ.วังเหนือ (from OpenStreetMap, regenerate with `scripts/fetch-geo.mjs`)
- `src/components/bill/` – bill document, stamp, watermark, QR
- `supabase/migrations/20261008100000_ss_stone_sand_schema.sql` (repo root) – tables, RPCs (order create, mark paid, statements, verify) and seed data

## Delivery fee rule

The pin decides the tambon and the road distance from the nearest main road on the map. Within `nearKm` (5 km) the customer pays the tambon's normal baht/คิว; beyond it each trip adds `customerPerKm` (50 baht) for every started km, whatever the truck size. The driver gets the tambon's per-trip rate plus `driverPerKm5` / `driverPerKm3` per started km beyond the same `nearKm`. All values are editable in Settings. Staff can always override the tambon and fee.

See [DEPLOY.md](DEPLOY.md) for Vercel setup.
