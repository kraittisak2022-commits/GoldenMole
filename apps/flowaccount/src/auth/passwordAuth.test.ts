import { describe, expect, it } from 'vitest';
import { hashPasswordForStorage, verifyStoredPassword } from '../auth/passwordAuth';

describe('passwordAuth', () => {
  it('verifies sha256$ hashed passwords', async () => {
    const stored = await hashPasswordForStorage('Secret123!');
    expect(stored.startsWith('sha256$')).toBe(true);
    expect(await verifyStoredPassword(stored, 'Secret123!')).toBe(true);
    expect(await verifyStoredPassword(stored, 'wrong')).toBe(false);
  });

  it('supports legacy plain passwords', async () => {
    expect(await verifyStoredPassword('plain-pass', 'plain-pass')).toBe(true);
    expect(await verifyStoredPassword('plain-pass', 'nope')).toBe(false);
  });
});
