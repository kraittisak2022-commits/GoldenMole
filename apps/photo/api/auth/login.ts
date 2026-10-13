import { canAccessSite } from '../../shared/siteAccess.js';
import { attemptSucceeded, beginAttempt, clientIp, failureDelay, loginLimits } from '../_lib/attempts.js';
import { HttpError, json, readJson, route } from '../_lib/http.js';
import { verifyStoredPassword } from '../_lib/password.js';
import { type AdminUserRow, createSessionToken, toStaffUser } from '../_lib/session.js';
import { db, must } from '../_lib/supabaseAdmin.js';

const normalizeUsername = (raw: string) => raw.normalize('NFKC').replace(/\s+/g, ' ').trim().toLowerCase();

/**
 * POST { username, password } → { token, user }.
 * Locked for 15 minutes after 5 wrong passwords for one username or 20 from one address; while locked
 * even the right password is refused, so guessing cannot continue in the background.
 */
export const POST = route(async (request) => {
  const body = await readJson(request);
  const username = typeof body.username === 'string' ? normalizeUsername(body.username).slice(0, 100) : '';
  const password = typeof body.password === 'string' ? body.password.slice(0, 200) : '';
  if (!username || !password) throw new HttpError('bad_request', 400);

  const attempt = await beginAttempt(loginLimits(clientIp(request), username));

  const escaped = username.replace(/[\\%_]/g, (c) => `\\${c}`);
  const row = must(
    await db()
      .from('admin_users')
      .select('id, username, password, display_name, role, allowed_apps')
      .ilike('username', escaped)
      .maybeSingle(),
  ) as AdminUserRow | null;

  if (!row || normalizeUsername(row.username) !== username || !verifyStoredPassword(row.password, password)) {
    await failureDelay();
    throw new HttpError('bad_credentials', 401);
  }
  if (!canAccessSite(row, 'photo')) throw new HttpError('forbidden', 403);

  await attemptSucceeded(attempt);
  await db().from('admin_users').update({ last_login: new Date().toISOString() }).eq('id', row.id);
  return json({ token: createSessionToken(row.id), user: toStaffUser(row) });
});
