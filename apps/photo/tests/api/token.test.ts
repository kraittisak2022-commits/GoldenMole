// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { newShareToken, signToken, verifyToken } from '../../api/_lib/token';

describe('signed tokens', () => {
  const secret = 'test-secret';

  it('round-trips the payload until it expires', () => {
    const token = signToken({ sub: 'u1', exp: 2_000 }, secret);
    expect(verifyToken(token, secret, 1_000)).toEqual({ sub: 'u1', exp: 2_000 });
    expect(verifyToken(token, secret, 2_000)).toBeNull();
  });

  it('rejects a wrong secret or a tampered payload', () => {
    const token = signToken({ sub: 'u1', exp: 2_000 }, secret);
    expect(verifyToken(token, 'other', 1_000)).toBeNull();
    const [, sig] = token.split('.');
    const forged = Buffer.from(JSON.stringify({ sub: 'admin', exp: 2_000 })).toString('base64url');
    expect(verifyToken(`${forged}.${sig}`, secret, 1_000)).toBeNull();
    expect(verifyToken(`${token}.x`, secret, 1_000)).toBeNull();
    expect(verifyToken('garbage', secret, 1_000)).toBeNull();
  });
});

describe('newShareToken', () => {
  it('is 22 url-safe characters and unique', () => {
    const a = newShareToken();
    expect(a).toMatch(/^[A-Za-z0-9_-]{22}$/);
    expect(newShareToken()).not.toBe(a);
  });
});
