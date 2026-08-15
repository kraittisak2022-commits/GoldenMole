import { beforeEach, describe, expect, it, vi } from 'vitest';
import { hashPasswordForStorage } from './passwordAuth';
import { SignInError, signInWithAdminUsers } from './adminAuthService';

const maybeSingle = vi.fn();
const ilike = vi.fn(() => ({ maybeSingle }));
const select = vi.fn(() => ({ ilike }));
const from = vi.fn(() => ({ select }));

vi.mock('../lib/supabase', () => ({
  hasSupabaseConfig: true,
  supabase: {
    from: (table: string) => from(table),
  },
}));

describe('signInWithAdminUsers', () => {
  beforeEach(() => {
    maybeSingle.mockReset();
    ilike.mockClear();
    select.mockClear();
    from.mockClear();
  });

  it('signs in a SuperAdmin with a valid password', async () => {
    const password = await hashPasswordForStorage('Secret123!');
    maybeSingle.mockResolvedValue({
      data: {
        id: 'u1',
        username: 'boss',
        password,
        display_name: 'Boss',
        role: 'SuperAdmin',
      },
      error: null,
    });

    const session = await signInWithAdminUsers('Boss', 'Secret123!');
    expect(session.username).toBe('boss');
    expect(session.role).toBe('SuperAdmin');
    expect(session.displayName).toBe('Boss');
  });

  it('rejects a wrong password', async () => {
    const password = await hashPasswordForStorage('Secret123!');
    maybeSingle.mockResolvedValue({
      data: {
        id: 'u1',
        username: 'boss',
        password,
        display_name: 'Boss',
        role: 'SuperAdmin',
      },
      error: null,
    });

    await expect(signInWithAdminUsers('boss', 'nope')).rejects.toMatchObject({
      code: 'bad_password',
    } satisfies Partial<SignInError>);
  });

  it('rejects non-SuperAdmin roles', async () => {
    const password = await hashPasswordForStorage('Secret123!');
    maybeSingle.mockResolvedValue({
      data: {
        id: 'u2',
        username: 'assistant',
        password,
        display_name: 'Help',
        role: 'Admin',
      },
      error: null,
    });

    await expect(signInWithAdminUsers('assistant', 'Secret123!')).rejects.toMatchObject({
      code: 'forbidden_role',
      message: 'บัญชีนี้ไม่มีสิทธิ์เข้าใช้ FlowAccount',
    });
  });

  it('rejects unknown users', async () => {
    maybeSingle.mockResolvedValue({ data: null, error: null });
    await expect(signInWithAdminUsers('ghost', 'x')).rejects.toMatchObject({
      code: 'user_not_found',
    });
  });
});
