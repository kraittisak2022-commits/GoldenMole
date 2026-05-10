# Production readiness (GoldenMole / Construction Management)

This document summarizes how the repo is wired today and what to do before treating a deployment as **production-grade**.

## What CI already enforces

| Check | Scope |
|--------|--------|
| `npm run lint` | Web (React + TS) |
| `npm test` (Vitest) | Web unit tests |
| `dart analyze` | Flutter app under `mobile-flutter/` |
| `flutter test` | Flutter widget/unit tests (e.g. `test/widget_test.dart`) |

End-to-end tests (`npm run test:e2e` / Playwright) are **not** run in CI by default (they need a running app + often real or mocked backend). Run them locally or add a separate workflow with secrets and a fixed URL when you are ready.

## Data access model (important)

The shipped SQL in `supabase-schema.sql` enables RLS but uses **permissive policies** (`USING (true)`) so the **anon key** can read/write business tables. That matches a **single-tenant internal tool** where the main gate is your **admin login in the app**, not row-level isolation in Postgres.

**Implications:**

- Anyone who obtains the **anon key** (e.g. from a built frontend bundle) can access data to the extent allowed by those policies.
- For **stronger** isolation you need a deliberate change: see `supabase-rls-hardening.sql` (template) and the notes inside it — it assumes **JWT custom claims** (`auth.jwt() ->> 'role'`, etc.) aligned with how you authenticate to Supabase. The current web app often uses **anonymous Supabase Auth** plus **custom `admin_users` checks**; applying the hardening script without matching JWT claims **will break** reads/writes until auth is aligned.

**Practical production path:**

1. **Short term:** Restrict who can reach the app (VPN, IP allowlist on host, private Supabase project), rotate keys if leaked, never commit `.env` / mobile `.env`.
2. **Medium term:** Either move sensitive writes behind **Edge Functions + service role**, or implement **Supabase Auth + RLS** (or JWT from your IdP) and replace allow-all policies.

## Checklist before “real” production

- [ ] **Change default admin password** (README warns about defaults).
- [ ] **Confirm `.env` / `mobile-flutter/.env`** are only on deploy machines / CI secrets, not in git.
- [ ] **Never expose `service_role`** in client or mobile builds.
- [ ] **Supabase backups / PITR** enabled on the project tier you use.
- [ ] **Review RLS** — decide: keep permissive + network controls, or migrate using `supabase-rls-hardening.sql` after auth design is done.
- [ ] **Run `npm run build`** for web; **`flutter build apk`** / iOS pipeline as needed for mobile.
- [ ] Optionally run **`npm run test:e2e`** against a staging URL before release.

## Related files

- `README.md` — env vars and high-level security warnings  
- `supabase-schema.sql` — baseline schema + current permissive RLS  
- `supabase-rls-hardening.sql` — optional stricter RLS template (manual, after auth alignment)  
- `supabase-anon-client-access-fix.sql` — historical note on anon + RLS  

## Flutter SDK

The app declares `environment: sdk: ^3.10.8` in `mobile-flutter/pubspec.yaml`. CI uses **Flutter stable** from `subos/flutter-action`; if analyze fails after a Flutter upgrade, bump the SDK constraint or pin Flutter in the workflow.
