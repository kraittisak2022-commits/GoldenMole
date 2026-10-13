import { canAccessSite } from '../../shared/siteAccess.js';
import type { AdminRole, StaffUser } from '../../shared/types.js';
import { requireEnv } from './env.js';
import { HttpError } from './http.js';
import { db, must } from './supabaseAdmin.js';
import { signToken, verifyToken } from './token.js';

/**
 * Renewed on every /api/auth/me call, so staff who open the site within this window stay signed in.
 * Access is still checked against admin_users on each request, so removing an account cuts it off at once.
 */
export const SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000;

interface SessionPayload {
  typ: 'session';
  sub: string;
  exp: number;
}

export interface AdminUserRow {
  id: string;
  username: string;
  password?: string;
  display_name: string;
  role: AdminRole;
  allowed_apps: string[] | null;
}

export function toStaffUser(row: AdminUserRow): StaffUser {
  return { id: row.id, username: row.username, displayName: row.display_name, role: row.role };
}

export function createSessionToken(userId: string, now = Date.now()): string {
  return signToken({ typ: 'session', sub: userId, exp: now + SESSION_TTL_MS }, requireEnv('PHOTO_SESSION_SECRET'));
}

export function readSessionUserId(request: Request): string | null {
  const auth = request.headers.get('authorization') ?? '';
  const token = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
  if (!token) return null;
  const payload = verifyToken<SessionPayload>(token, requireEnv('PHOTO_SESSION_SECRET'));
  return payload?.typ === 'session' && typeof payload.sub === 'string' ? payload.sub : null;
}

/** Valid token and the account still exists and may use this site; otherwise 401/403. */
export async function requireStaff(request: Request, opts: { superAdmin?: boolean } = {}): Promise<StaffUser> {
  const id = readSessionUserId(request);
  if (!id) throw new HttpError('unauthorized', 401);
  const row = must(
    await db().from('admin_users').select('id, username, display_name, role, allowed_apps').eq('id', id).maybeSingle(),
  ) as AdminUserRow | null;
  if (!row) throw new HttpError('unauthorized', 401);
  if (!canAccessSite(row, 'photo')) throw new HttpError('forbidden', 403);
  if (opts.superAdmin && row.role !== 'SuperAdmin') throw new HttpError('forbidden', 403);
  return toStaffUser(row);
}

/** Staff when a valid session is sent, otherwise null (never throws for a missing token). */
export async function optionalStaff(request: Request): Promise<StaffUser | null> {
  if (!request.headers.get('authorization')) return null;
  try {
    return await requireStaff(request);
  } catch {
    return null;
  }
}
