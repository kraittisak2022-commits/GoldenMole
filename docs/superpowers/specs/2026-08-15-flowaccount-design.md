# FlowAccount – Account Management System (Phase 1)

**Date:** 2026-08-15  
**Status:** Approved for implementation  
**Scope:** Login shell + subdomain only (no accounting features yet)

## Goal

Ship a separate web app **FlowAccount** at `flowaccount.goldenmole.pro` with:

1. White, clean, Swiss-minimal UI
2. Login that reuses GoldenMole `admin_users` credentials
3. Access limited to `SuperAdmin` only
4. Empty authenticated shell ready for future accounting modules

## Decisions

| Topic | Choice |
|-------|--------|
| Location | `apps/flowaccount/` in the GoldenMole monorepo |
| Deploy | Separate Vercel project, root directory `apps/flowaccount` |
| Domain | `flowaccount.goldenmole.pro` |
| Auth source | Existing Supabase table `admin_users` |
| Password format | Same as GoldenMole (`sha256$<hex>` + legacy plain) |
| Access gate | `role === 'SuperAdmin'` only |
| Fonts | Kanit / Prompt (family consistency with GoldenMole) |
| Theme | Light mode only in Phase 1 |

## Architecture

Standalone Vite + React 18 + Tailwind app (own `package.json` / lockfile). Auth/password helpers are **copied** (not imported from `../../src`) so builds stay independent.

```
apps/flowaccount/
  src/
    lib/supabase.ts
    auth/passwordAuth.ts
    auth/adminAuthService.ts
    auth/session.ts
    auth/AuthProvider.tsx
    auth/RequireAuth.tsx
    pages/LoginPage.tsx
    pages/DashboardPage.tsx
    components/AppShell.tsx
    components/ui/{Button,Input,Field,Card}.tsx
```

## Login flow

1. User submits username + password on `/login`
2. `adminAuthService.signIn` loads matching `admin_users` row from Supabase
3. `verifyStoredPassword` checks the hash
4. If role is not `SuperAdmin` → reject with “บัญชีนี้ไม่มีสิทธิ์เข้าใช้ FlowAccount”
5. On success → persist session (id, username, displayName, role, loginAt) and route to `/`
6. Unauthenticated access to `/` redirects to `/login`

## Design system (Swiss minimal / white)

- Surfaces: page `#F8FAFC`, card `#FFFFFF`, ink `#0F172A`, muted `#64748B`, border `#E2E8F0`
- Accent CTA: `#0369A1`; destructive: `#DC2626`
- 8px spacing rhythm, 8px radius, hairline borders (no heavy shadows/gradients)
- Login: centered single-column card, one primary CTA
- Shell: left sidebar (placeholder nav “เร็วๆ นี้”) + topbar with logout
- A11y: labeled fields, `aria-describedby` errors, ≥44px targets, focus rings, `prefers-reduced-motion`

## Known limitations (document, do not fix in Phase 1)

- Anon key + permissive RLS means `admin_users` (including password hashes) is client-readable — same model as GoldenMole today. Future: Edge Function + service role for login.

## Out of scope (later phases)

- Journals, invoices, chart of accounts, reports
- Dark mode, multi-tenant, Assistant/Admin access
- Sharing auth session cookies across `goldenmole.pro` and the subdomain

## Verification

- `npm run lint` / `npm test` / `npm run build` in `apps/flowaccount`
- Tests: SuperAdmin success, wrong password, non-SuperAdmin rejected, guard redirect, logout clears session
- Preview URL login with a real SuperAdmin before DNS cutover
