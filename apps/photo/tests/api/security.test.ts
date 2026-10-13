// @vitest-environment node
import { createHash } from 'node:crypto';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fake, type Query, resetFake } from './fakeDb';

vi.mock('../../api/_lib/supabaseAdmin.js', async () => (await import('./fakeDb')).supabaseAdminMock);
vi.mock('../../api/_lib/attempts.js', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../api/_lib/attempts')>()),
  failureDelay: async () => undefined,
}));

process.env.PHOTO_SESSION_SECRET = 'test-secret-for-security';
process.env.PHOTO_ALBUM_PIN = '8888';

const { GET: viewShare, POST: unlockShare } = await import('../../api/share/[token]');
const { POST: login } = await import('../../api/auth/login');

const hashPassword = (plain: string) => `sha256$${createHash('sha256').update(plain).digest('hex')}`;

const TOKEN = 'abcDEF123_-xyz456789AB';
const ALBUM = {
  id: '7f1c2b9e-0000-4000-8000-000000000001',
  title: 'เทปูน',
  report_date: '2026-10-12',
  drive_folder_id: 'folder-album',
  share_token: TOKEN,
  allow_link_upload: true,
  cover_media_id: null,
  media_count: 0,
  created_by: null,
  created_at: '2026-10-12T00:00:00Z',
  updated_at: '2026-10-12T00:00:00Z',
  deleted_at: null,
};
const USER = {
  id: 'u1',
  username: 'somchai',
  password: hashPassword('right-password'),
  display_name: 'สมชาย',
  role: 'Admin',
  allowed_apps: null,
};

/** `failures` = earlier failed attempts per scope; the lockout count also includes the attempt being made. */
function setup(failures: Partial<Record<string, number>> = {}) {
  let nextId = 1;
  resetFake((q: Query) => {
    if (q.table === 'ph_auth_attempts' && q.op === 'insert') {
      return { data: (q.payload as { scope: string; key_hash: string }[]).map((r) => ({ id: nextId++, ...r })), error: null };
    }
    if (q.table === 'ph_auth_attempts' && q.op === 'select') {
      return { data: null, error: null, count: (failures[String(q.filters.scope)] ?? 0) + 1 };
    }
    if (q.table === 'ph_albums') return { data: q.filters.share_token === TOKEN ? ALBUM : null, error: null };
    if (q.table === 'ph_media') return { data: [], error: null };
    if (q.table === 'admin_users' && q.op === 'select') return { data: USER, error: null };
    return { data: null, error: null };
  });
}

const attemptQueries = () => fake.queries.filter((q) => q.table === 'ph_auth_attempts');
const recordedScopes = () =>
  attemptQueries()
    .filter((q) => q.op === 'insert')
    .flatMap((q) => (q.payload as { scope: string }[]).map((r) => r.scope))
    .sort();
const clearedScopes = () =>
  attemptQueries()
    .filter((q) => q.op === 'delete' && 'scope' in q.filters)
    .map((q) => String(q.filters.scope))
    .sort();

const shareRequest = (method: 'GET' | 'POST', body?: unknown, headers: Record<string, string> = {}, token = TOKEN) =>
  new Request(`https://photo.goldenmole.pro/api/share/${token}`, {
    method,
    headers: { 'Content-Type': 'application/json', 'x-real-ip': '203.0.113.7', ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

const loginRequest = (password: string) =>
  new Request('https://photo.goldenmole.pro/api/auth/login', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-real-ip': '203.0.113.7' },
    body: JSON.stringify({ username: 'somchai', password }),
  });

beforeEach(() => setup());

describe('album PIN', () => {
  it('hides the album, title included, until the PIN is entered', async () => {
    const res = await viewShare(shareRequest('GET'));
    expect(res.status).toBe(403);
    expect(await res.json()).toEqual({ error: 'pin_required' });
  });

  it('gives a device that enters the right PIN access to that album', async () => {
    const unlocked = await unlockShare(shareRequest('POST', { pin: '8888' }));
    expect(unlocked.status).toBe(200);
    const { access } = (await unlocked.json()) as { access: string };

    const res = await viewShare(shareRequest('GET', undefined, { 'X-Album-Access': access }));
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ title: 'เทปูน' });
  });

  it('refuses a wrong PIN and keeps the failure', async () => {
    const res = await unlockShare(shareRequest('POST', { pin: '1234' }));
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: 'bad_pin' });
    expect(recordedScopes()).toEqual(['pin_album', 'pin_ip']);
    expect(clearedScopes()).toEqual([]);
  });

  it('clears earlier failures once the right PIN is entered', async () => {
    setup({ pin_ip: 4 });
    expect((await unlockShare(shareRequest('POST', { pin: '8888' }))).status).toBe(200);
    expect(clearedScopes()).toEqual(['pin_album', 'pin_ip']);
  });

  it('locks PIN entry after too many wrong guesses, even for the right PIN', async () => {
    setup({ pin_ip: 5 });
    const res = await unlockShare(shareRequest('POST', { pin: '8888' }));
    expect(res.status).toBe(429);
    expect(await res.json()).toEqual({ error: 'too_many_attempts' });
    expect(attemptQueries().some((q) => q.op === 'delete' && 'id' in q.filters)).toBe(true);
  });

  it('writes the attempt before counting, so parallel guesses cannot all pass the check', async () => {
    await unlockShare(shareRequest('POST', { pin: '1234' }));
    const ops = attemptQueries().map((q) => q.op);
    expect(ops.indexOf('insert')).toBeLessThan(ops.indexOf('select'));
  });

  it('counts guesses at unknown links against the address', async () => {
    const res = await unlockShare(shareRequest('POST', { pin: '8888' }, {}, 'zzzzzzzzzzzzzzzzzzzzzz'));
    expect(res.status).toBe(404);
    expect(recordedScopes()).toEqual(['pin_ip']);
    expect(clearedScopes()).toEqual([]);
  });

  it('does not accept access issued for another album or a forged token', async () => {
    const { createAlbumAccess } = await import('../../api/_lib/albumAccess');
    const other = createAlbumAccess('another-album-id');
    expect((await viewShare(shareRequest('GET', undefined, { 'X-Album-Access': other }))).status).toBe(403);
    expect((await viewShare(shareRequest('GET', undefined, { 'X-Album-Access': 'e30.forged' }))).status).toBe(403);
  });

  it('locks out every device when the PIN is changed', async () => {
    const { access } = (await (await unlockShare(shareRequest('POST', { pin: '8888' }))).json()) as { access: string };
    process.env.PHOTO_ALBUM_PIN = '2468';
    try {
      expect((await viewShare(shareRequest('GET', undefined, { 'X-Album-Access': access }))).status).toBe(403);
    } finally {
      process.env.PHOTO_ALBUM_PIN = '8888';
    }
  });
});

describe('login lockout', () => {
  it('records a wrong password against the username and the address', async () => {
    const res = await login(loginRequest('wrong'));
    expect(res.status).toBe(401);
    expect(recordedScopes()).toEqual(['login_ip', 'login_user']);
    expect(clearedScopes()).toEqual([]);
  });

  it('refuses even the right password while the account is locked', async () => {
    setup({ login_user: 5 });
    const res = await login(loginRequest('right-password'));
    expect(res.status).toBe(429);
    expect(await res.json()).toEqual({ error: 'too_many_attempts' });
  });

  it('signs in with the right password after a few typos and forgets them', async () => {
    setup({ login_user: 4 });
    const res = await login(loginRequest('right-password'));
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ token: expect.any(String), user: { username: 'somchai' } });
    expect(clearedScopes()).toEqual(['login_ip', 'login_user']);
  });
});
