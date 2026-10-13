import { createHmac } from 'node:crypto';
import { requireEnv } from './env.js';
import { HttpError } from './http.js';
import { db } from './supabaseAdmin.js';

export type AttemptScope = 'login_ip' | 'login_user' | 'pin_ip' | 'pin_album';

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
export const pinLimits = (ip: string, albumId: string | null): AttemptLimit[] => [
  { scope: 'pin_ip', key: ip, max: 5, windowMs: 15 * MINUTE },
  ...(albumId ? [{ scope: 'pin_album' as const, key: albumId, max: 30, windowMs: 60 * MINUTE }] : []),
];

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

/** 429 when any limit already has `max` failures in its window. */
export async function assertNotLocked(limits: AttemptLimit[], now = Date.now()): Promise<void> {
  const counts = await Promise.all(
    limits.map(async (limit) => {
      const { count, error } = await db()
        .from('ph_auth_attempts')
        .select('id', { count: 'exact', head: true })
        .eq('scope', limit.scope)
        .eq('key_hash', keyHash(limit))
        .eq('success', false)
        .gte('created_at', new Date(now - limit.windowMs).toISOString());
      if (error) throw new HttpError('server_error', 500, error.message);
      return { limit, count: count ?? 0 };
    }),
  );
  if (counts.some(({ limit, count }) => count >= limit.max)) throw new HttpError('too_many_attempts', 429);
}

/** Logs the attempt; a success clears earlier failures so one typo does not count against the next day. */
export async function recordAttempt(limits: AttemptLimit[], success: boolean): Promise<void> {
  const rows = limits.map((limit) => ({ scope: limit.scope, key_hash: keyHash(limit), success }));
  await db().from('ph_auth_attempts').insert(rows);
  if (success) {
    await Promise.all(
      rows.map((r) => db().from('ph_auth_attempts').delete().eq('scope', r.scope).eq('key_hash', r.key_hash).eq('success', false)),
    );
  }
  if (Math.random() < 0.05) {
    await db().from('ph_auth_attempts').delete().lt('created_at', new Date(Date.now() - 7 * 24 * 60 * MINUTE).toISOString());
  }
}

/** Slows each wrong guess down a little more without holding a function open for long. */
export const failureDelay = () => new Promise((resolve) => setTimeout(resolve, 400 + Math.random() * 400));
