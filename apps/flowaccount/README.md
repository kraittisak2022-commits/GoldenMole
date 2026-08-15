# FlowAccount

White, Swiss-minimal accounting web app for GoldenMole.

## Phase 1

- Login against existing `admin_users` (SuperAdmin only)
- Authenticated shell with placeholder nav
- Deployed at `flowaccount.goldenmole.pro`

## Local development

```bash
cd apps/flowaccount
cp .env.example .env   # fill VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY
npm install
npm run dev
```

## Scripts

| Command | Purpose |
|---------|---------|
| `npm run dev` | Vite dev server |
| `npm run lint` | ESLint |
| `npm test` | Vitest |
| `npm run build` | Production build |

## Deploy

Vercel project with **Root Directory** `apps/flowaccount`, same Supabase env vars as GoldenMole.
