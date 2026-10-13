import { signToken } from '../../api/_lib/token';
import type { StaffUser } from '../../shared/types';
import { clearSession, readSession, saveSession, tokenExpiresAt } from './session';

const user: StaffUser = { id: 'u1', username: 'somchai', displayName: 'สมชาย', role: 'Admin' };
const tokenFor = (exp: number) => signToken({ typ: 'session', sub: user.id, exp }, 'test-secret');

afterEach(clearSession);

describe('tokenExpiresAt', () => {
  it('reads the expiry from a server-signed token', () => {
    const exp = Date.now() + 30 * 86_400_000;
    expect(tokenExpiresAt(tokenFor(exp))).toBe(exp);
  });

  it('returns 0 for a token it cannot read', () => {
    expect(tokenExpiresAt('not-a-token')).toBe(0);
  });
});

describe('readSession', () => {
  it('keeps a session until its token expires, however long ago it was saved', () => {
    const now = Date.now();
    saveSession(tokenFor(now + 20 * 86_400_000), user);
    expect(readSession(now + 19 * 86_400_000)?.user.id).toBe('u1');
  });

  it('drops an expired session', () => {
    const now = Date.now();
    saveSession(tokenFor(now + 1000), user);
    expect(readSession(now + 2000)).toBeNull();
    expect(readSession(now)).toBeNull();
  });
});
