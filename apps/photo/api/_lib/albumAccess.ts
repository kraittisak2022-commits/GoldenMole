import { createHmac, timingSafeEqual } from 'node:crypto';
import type { StaffUser } from '../../shared/types.js';
import { requireEnv } from './env.js';
import { HttpError } from './http.js';
import { optionalStaff } from './session.js';
import { signToken, verifyToken } from './token.js';

/** How long one correct PIN unlocks an album on that device. */
export const ALBUM_ACCESS_TTL_MS = 7 * 24 * 60 * 60 * 1000;
export const ALBUM_ACCESS_HEADER = 'x-album-access';

interface AccessPayload {
  typ: 'album';
  sub: string;
  pv: string;
  exp: number;
}

const hmac = (value: string) => createHmac('sha256', requireEnv('PHOTO_SESSION_SECRET')).update(value).digest();

/** The PIN for share links, from PHOTO_ALBUM_PIN (exactly 4 digits so the keypad can submit on its own). */
function albumPin(): string {
  const pin = requireEnv('PHOTO_ALBUM_PIN');
  if (!/^\d{4}$/.test(pin)) {
    console.error('PHOTO_ALBUM_PIN must be exactly 4 digits');
    throw new HttpError('not_configured', 503);
  }
  return pin;
}

/** Ties access tokens to the current PIN: changing PHOTO_ALBUM_PIN locks every device out again. */
const pinVersion = () => hmac(`pin:${albumPin()}`).toString('base64url').slice(0, 12);

export function pinMatches(input: unknown): boolean {
  const expected = hmac(`check:${albumPin()}`);
  const given = hmac(`check:${typeof input === 'string' ? input.trim() : ''}`);
  return timingSafeEqual(expected, given);
}

export function createAlbumAccess(albumId: string, now = Date.now()): string {
  return signToken({ typ: 'album', sub: albumId, pv: pinVersion(), exp: now + ALBUM_ACCESS_TTL_MS }, requireEnv('PHOTO_SESSION_SECRET'));
}

export function hasAlbumAccess(request: Request, albumId: string): boolean {
  const token = request.headers.get(ALBUM_ACCESS_HEADER)?.trim();
  if (!token) return false;
  const payload = verifyToken<AccessPayload>(token, requireEnv('PHOTO_SESSION_SECRET'));
  return payload?.typ === 'album' && payload.sub === albumId && payload.pv === pinVersion();
}

/** Signed-in staff, or a device that entered the PIN for this album; anyone else gets `pin_required`. */
export async function requireAlbumViewer(request: Request, albumId: string): Promise<StaffUser | null> {
  const staff = await optionalStaff(request);
  if (staff) return staff;
  if (hasAlbumAccess(request, albumId)) return null;
  throw new HttpError('pin_required', 403);
}
