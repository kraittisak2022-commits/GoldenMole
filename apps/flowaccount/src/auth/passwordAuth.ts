/**
 * Client-side password helpers — stored as SHA-256 hex prefixed with sha256$
 * Matches GoldenMole `src/utils/passwordAuth.ts` so admin_users credentials work here.
 */

const HASH_PREFIX = 'sha256$';
const HASH_PREFIX_ALT = 'sha256:';

function looksLikeSha256Hex(raw: string): boolean {
  return /^[a-f0-9]{64}$/i.test(raw.trim());
}

function extractSha256Hex(raw: string): string | null {
  const s = raw.trim();
  if (looksLikeSha256Hex(s)) return s;
  const m = s.match(/([a-f0-9]{64})/i);
  return m ? m[1] : null;
}

async function sha256Hex(plain: string): Promise<string> {
  const data = new TextEncoder().encode(plain);
  const hash = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

function timingSafeEqualString(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let out = 0;
  for (let i = 0; i < a.length; i++) out |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return out === 0;
}

export function isPasswordHashedFormat(stored: string | undefined | null): boolean {
  if (!stored) return false;
  const s = stored.trim();
  if (s.startsWith(HASH_PREFIX) && s.length > HASH_PREFIX.length + 32) return true;
  if (s.startsWith(HASH_PREFIX_ALT) && s.length > HASH_PREFIX_ALT.length + 32) return true;
  if (extractSha256Hex(s)) return true;
  return false;
}

export async function hashPasswordForStorage(plain: string): Promise<string> {
  const hex = await sha256Hex(plain);
  return `${HASH_PREFIX}${hex}`;
}

export async function verifyStoredPassword(stored: string, inputPlain: string): Promise<boolean> {
  if (!stored) return false;
  const s = stored.trim();
  if (isPasswordHashedFormat(s)) {
    const expectedHexRaw = s.startsWith(HASH_PREFIX)
      ? s.slice(HASH_PREFIX.length)
      : s.startsWith(HASH_PREFIX_ALT)
        ? s.slice(HASH_PREFIX_ALT.length)
        : extractSha256Hex(s) || s;
    const expectedHex = (extractSha256Hex(expectedHexRaw) || expectedHexRaw).toLowerCase();
    const actualHex = await sha256Hex(inputPlain);
    if (timingSafeEqualString(expectedHex, actualHex.toLowerCase())) return true;
    const trimmed = inputPlain.trim();
    if (trimmed !== inputPlain) {
      const actualTrimmed = await sha256Hex(trimmed);
      if (timingSafeEqualString(expectedHex, actualTrimmed.toLowerCase())) return true;
    }
    return false;
  }
  if (timingSafeEqualString(s, inputPlain)) return true;
  return timingSafeEqualString(s, inputPlain.trim());
}
