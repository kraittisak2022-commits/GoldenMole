import type { GoogleStatus } from '../../shared/types.js';
import { json, route } from '../_lib/http.js';
import { requireStaff } from '../_lib/session.js';
import { db, must } from '../_lib/supabaseAdmin.js';

/** GET (staff) → GoogleStatus. Never returns the token itself. */
export const GET = route(async (request) => {
  await requireStaff(request);
  const row = must(
    await db().from('ph_settings').select('google_refresh_token, google_email, connected_at').eq('id', 1).maybeSingle(),
  ) as { google_refresh_token: string | null; google_email: string | null; connected_at: string | null } | null;
  const status: GoogleStatus = {
    connected: !!row?.google_refresh_token,
    email: row?.google_email ?? null,
    connectedAt: row?.connected_at ?? null,
  };
  return json(status);
});
