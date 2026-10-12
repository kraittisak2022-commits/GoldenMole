import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto';

const b64 = (buf: Buffer | string) => Buffer.from(buf).toString('base64url');

/** `<payload>.<signature>`, both base64url. `exp` is epoch milliseconds. */
export function signToken(payload: { exp: number } & Record<string, unknown>, secret: string): string {
  const body = b64(JSON.stringify(payload));
  const sig = b64(createHmac('sha256', secret).update(body).digest());
  return `${body}.${sig}`;
}

export function verifyToken<T extends { exp: number }>(token: string, secret: string, now = Date.now()): T | null {
  const [body, sig, extra] = token.split('.');
  if (!body || !sig || extra !== undefined) return null;
  const expected = createHmac('sha256', secret).update(body).digest();
  const given = Buffer.from(sig, 'base64url');
  if (given.length !== expected.length || !timingSafeEqual(given, expected)) return null;
  try {
    const payload = JSON.parse(Buffer.from(body, 'base64url').toString('utf8')) as T;
    if (typeof payload?.exp !== 'number' || payload.exp <= now) return null;
    return payload;
  } catch {
    return null;
  }
}

/** 22 url-safe characters (128 bits): hard to guess, short enough for a chat message. */
export function newShareToken(): string {
  return randomBytes(16).toString('base64url');
}
