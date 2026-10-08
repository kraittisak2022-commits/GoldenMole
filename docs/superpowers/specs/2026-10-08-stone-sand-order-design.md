# Stone and Sand Order System — Design

**Date:** 2026-10-08
**App:** `apps/stone-sand`
**Owner business:** ห้างหุ้นส่วนจำกัด พีรสิทธิ์ วัสดุก่อสร้าง (PIRASIT CONSTRUCTION MATERIALS LIMITED PARTNERSHIP), 132 หมู่ที่ 2 ต.วังแก้ว อ.วังเหนือ จ.ลำปาง 52140, tax ID 0523566002017, tel 065-8124686

## Goal

Sales staff take stone/sand orders on a phone or desktop through a 5-step wizard, the app
works out product price and delivery fee, tracks payment / delivery / bill clearing, and
issues a printable, hard-to-forge bill.

## Decisions

| Topic | Decision |
|-------|----------|
| Hosting | Standalone Vite + React + Tailwind app in `apps/stone-sand`, same Supabase project as GoldenMole, Vercel root `apps/stone-sand` |
| Login | Existing `admin_users` table (roles SuperAdmin, Admin) — same flow as `apps/flowaccount` |
| VAT | None. Bills are ใบส่งของ / ใบเสร็จรับเงิน / ใบวางบิล, marked "ไม่ใช่ใบกำกับภาษี" |
| Delivery fee | Per trip × number of trips |
| Fee calculation | Pin on map → tambon by point-in-polygon → straight-line km to nearest main road |

## Pricing

Products are priced per คิว (the 3 คิว and 5 คิว prices given by the business are exact multiples):

| Product | Per คิว |
|---------|---------|
| หินเล็กคละ เบอร์ 1-3 | 400 |
| หินคละใหญ่ เบอร์ 4-6 | 300 |
| ทรายถม (ทรายขี้เป็ด) | 220 |
| ทรายก่อ/เท | 300 |

Order total = Σ(items) + fee per trip × trips + remote surcharge (ค่ากันดาร) − discount.
Discount is either baht or percent of the product subtotal; it can never push the total below 0.

## Delivery fee rule

For a tambon with fee range `[min, max]`, distance `d` (km) from pin to nearest main road,
and setting `maxKm` (default 10):

- `d <= 3` → `min`
- `3 < d < maxKm` → `min + (max − min) × (d − 3) / (maxKm − 3)`, rounded **up** to the next 50 baht, capped at `max`
- `d >= maxKm` → `max`

Seed ranges: ทุ่งฮั้ว 300-400, วังแก้ว 500-700, วังเหนือ 800-1000, วังซ้าย 800-1000,
วังใต้ 1000-1200, วังทรายคำ 1000-1200, วังทอง 1200-1500, ร่องเคาะ 1200-1500.

Staff can always override the suggested fee and add a remote surcharge. Pins outside
อ.วังเหนือ show a warning and require choosing a tambon manually.

Suggested trips = `ceil(total คิว / truck size)` (truck size 3 or 5), editable.

## Order statuses

Three independent fields on each order:

- `payment_status`: `unpaid` | `paid` | `credit` (monthly account)
- `delivery_status`: `pickup` (customer collects) | `waiting` | `dispatched` | `delivered`
- `cleared`: boolean — set when paid in full, or when the monthly statement containing it is cleared

Every change records time and user.

## Monthly bill clearing

For regular pickup customers: pick customer + date range → list uncleared orders →
create statement (ใบวางบิล `BL`) → print → "เคลียร์บิลแล้ว" records a payment and marks all
orders in the statement `paid` + `cleared`.

## Documents

| Type | Prefix | Example |
|------|--------|---------|
| ใบส่งของ (delivery note) | DO | DO2610-0001 |
| ใบเสร็จรับเงิน (receipt) | RE | RE2610-0001 |
| ใบวางบิล (statement) | BL | BL2610-0001 |

`YYMM` is the Gregorian year and month for sortability (Oct 2026 → `2610`). Numbers come from Postgres `ss_next_doc_no(prefix)` with a row lock,
so concurrent staff never collide.

Bill layout (A4): header with company details, document title + ต้นฉบับ/สำเนา, number,
date, customer, delivery info, items, totals with Thai baht text, payment method boxes,
signature lines, SVG company stamp, diagonal watermark, microtext border, and a QR code
linking to the public `/v/:token` verify page.

Anti-copy: the QR verify page is the real protection (shows the true number, date, total,
status from the database). Watermark, stamp, microtext and disabled text selection add
friction; no web page can fully prevent a photocopy.

## Data model (prefix `ss_`)

`ss_products`, `ss_zones`, `ss_drivers`, `ss_customers`, `ss_orders`, `ss_order_items`,
`ss_payments`, `ss_statements`, `ss_statement_orders`, `ss_doc_counters`, `ss_settings`.
RPCs: `ss_next_doc_no(prefix)`, `ss_verify_document(token)`.

RLS follows the existing permissive pattern used by `fa_*` tables. **Known risk:** anyone
with the anon key can read customer data; tightening is a separate task.

## Screens

- Login
- Dashboard (today, waiting deliveries, unpaid, uncleared credit, month summary)
- New order wizard: ลูกค้า → สินค้า → รับสินค้า → สรุป → ยืนยัน & ออกบิล
- Orders list (filter chips) and order detail (status toggles, driver wage, driver message)
- Bill page (print, PNG)
- Customers (history, outstanding balance)
- Statements (เคลียร์บิล)
- Drivers (12 seeded drivers in 3 route groups)
- Settings (prices, zone fees, maxKm, company header, PromptPay)
- Public verify page `/v/:token`

## Design system

White minimal (ui-ux-pro-max): background `#FFFFFF`/`#F8FAFC`, ink `#0F172A`, primary navy
`#1E3A5F`, success green `#059669`, destructive `#DC2626`, border `#E4E7EB`.
Font Noto Sans Thai. Icons lucide-react. Mobile-first, 44px touch targets, motion 150-250ms
with `prefers-reduced-motion` respected.

## Testing

Vitest for pure calc: pricing, delivery fee, trips, discount, baht text, document number
format. Manual browser check of wizard, bill print preview, verify page.
