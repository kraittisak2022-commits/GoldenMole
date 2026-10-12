import { createHash, timingSafeEqual } from 'node:crypto';

/**
 * Server copy of the admin_users password check in apps/stone-sand/src/auth/passwordAuth.ts:
 * passwords are stored as `sha256$<hex>` (older rows: bare hex or plain text).
 */

const HASH_PREFIXES = ['sha256$', 'sha256:'];

const sha256Hex = (plain: string) => createHash('sha256').update(plain, 'utf8').digest('hex');

function extractSha256Hex(raw: string): string | null {
  const m = raw.match(/([a-f0-9]{64})/i);
  return m ? m[1].toLowerCase() : null;
}

function safeEqual(a: string, b: string): boolean {
  const ba = Buffer.from(a);
  const bb = Buffer.from(b);
  return ba.length === bb.length && timingSafeEqual(ba, bb);
}

export function verifyStoredPassword(stored: string | null | undefined, input: string): boolean {
  if (!stored) return false;
  const s = stored.trim();
  const prefix = HASH_PREFIXES.find((p) => s.startsWith(p) && s.length > p.length + 32);
  const rest = prefix ? s.slice(prefix.length) : s;
  const hex = extractSha256Hex(rest);
  const candidates = input.trim() === input ? [input] : [input, input.trim()];
  if (prefix || hex) {
    const expected = hex ?? rest.toLowerCase();
    return candidates.some((c) => safeEqual(expected, sha256Hex(c)));
  }
  return candidates.some((c) => safeEqual(s, c));
}
