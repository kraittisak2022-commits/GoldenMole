import { createHmac } from 'node:crypto';
import type { ApiErrorCode } from '../../shared/types.js';
import { requireEnv } from './env.js';
import { HttpError } from './http.js';
import { db } from './supabaseAdmin.js';

export type AttemptScope = 'login_ip' | 'login_user' | 'pin_ip' | 'pin_album' | 'link_upload';

export interface AttemptLimit {
  scope: AttemptScope;
  key: string;
  /** Failures allowed inside the window before every attempt (even a correct one) is refused. */
  max: number;
  windowMs: number;
}

const MINUTE = 60_000;

export const loginLimits = (ip: string, username: string): AttemptLimit[] => [
  { scope: 'login_ip', key: ip, max: 20, windowMs: 15 * MINUTE },
  { scope: 'login_user', key: username, max: 5, windowMs: 15 * MINUTE },
];

/** The share token is already a 128-bit secret; the PIN is a second factor, so a slow trickle is enough. */
export const pinIpLimit = (ip: string): AttemptLimit => ({ scope: 'pin_ip', key: ip, max: 5, windowMs: 15 * MINUTE });
export const pinAlbumLimit = (albumId: string): AttemptLimit => ({ scope: 'pin_album', key: albumId, max: 30, windowMs: 60 * MINUTE });

/** Vercel sets x-real-ip / x-forwarded-for itself, so clients cannot spoof them. */
export function clientIp(request: Request): string {
  return (
    request.headers.get('x-real-ip')?.trim() ||
    request.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ||
    'unknown'
  );
}

const keyHash = (limit: AttemptLimit) =>
  createHmac('sha256', requireEnv('PHOTO_SESSION_SECRET')).update(`${limit.scope}:${limit.key}`).digest('hex').slice(0, 40);

export interface Attempt {
  rows: { id: number; scope: AttemptScope; key_hash: string }[];
}

/**
 * Writes this attempt as a failure first, then counts failures in each window including it, so a burst of
 * parallel requests cannot all pass the check before any failure is recorded. Over a limit → the row is
 * removed again (waiting out the window is enough) and the request is refused.
 * Call `attemptSucceeded` when the attempt turns out to be valid; otherwise the failure stays.
 */
export async function beginAttempt(
  limits: AttemptLimit[],
  { error = 'too_many_attempts', now = Date.now() }: { error?: ApiErrorCode; now?: number } = {},
): Promise<Attempt> {
  const inserted = await db()
    .from('ph_auth_attempts')
    .insert(limits.map((limit) => ({ scope: limit.scope, key_hash: keyHash(limit), success: false })))
    .select('id, scope, key_hash');
  if (inserted.error) throw new HttpError('server_error', 500, inserted.error.message);
  const attempt: Attempt = { rows: (inserted.data ?? []) as Attempt['rows'] };
  if (Math.random() < 0.05) {
    await db().from('ph_auth_attempts').delete().lt('created_at', new Date(now - 7 * 24 * 60 * MINUTE).toISOString());
  }

  const counts = await Promise.all(
    limits.map(async (limit) => {
      const { count, error: countError } = await db()
        .from('ph_auth_attempts')
        .select('id', { count: 'exact', head: true })
        .eq('scope', limit.scope)
        .eq('key_hash', keyHash(limit))
        .eq('success', false)
        .gte('created_at', new Date(now - limit.windowMs).toISOString());
      if (countError) throw new HttpError('server_error', 500, countError.message);
      return count ?? 0;
    }),
  );
  if (counts.some((count, i) => count > limits[i].max)) {
    await db().from('ph_auth_attempts').delete().in('id', attempt.rows.map((r) => r.id));
    throw new HttpError(error, 429);
  }
  return attempt;
}

/** A valid attempt clears earlier failures for the same keys, so one typo does not count against the next day. */
export async function attemptSucceeded(attempt: Attempt): Promise<void> {
  await Promise.all(
    attempt.rows.map((r) => db().from('ph_auth_attempts').delete().eq('scope', r.scope).eq('key_hash', r.key_hash).eq('success', false)),
  );
}

/** Slows each wrong guess down a little more without holding a function open for long. */
export const failureDelay = () => new Promise((resolve) => setTimeout(resolve, 400 + Math.random() * 400));
