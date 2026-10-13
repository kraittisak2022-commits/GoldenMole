// @vitest-environment node
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { resetFake } from './fakeDb';

vi.mock('../../api/_lib/supabaseAdmin.js', async () => (await import('./fakeDb')).supabaseAdminMock);
vi.mock('../../api/_lib/google.js', () => ({
  refreshAccessToken: vi.fn(async () => ({ accessToken: 'fresh-access-token', expiresIn: 3600 })),
}));

const { getFile } = await import('../../api/_lib/drive');
const { refreshAccessToken } = await import('../../api/_lib/google.js');

const realFetch = globalThis.fetch;
const fileResponse = () => new Response(JSON.stringify({ id: 'f1', name: 'a.jpg', mimeType: 'image/jpeg' }), { status: 200 });

beforeEach(() => {
  vi.clearAllMocks();
  resetFake(() => ({ data: { google_refresh_token: 'refresh' }, error: null }));
});
afterEach(() => {
  globalThis.fetch = realFetch;
});

describe('Drive requests', () => {
  it('retries once with a fresh token when Drive rejects the cached one', async () => {
    globalThis.fetch = vi.fn().mockResolvedValueOnce(new Response('', { status: 401 })).mockImplementationOnce(async () => fileResponse());
    await expect(getFile('f1')).resolves.toMatchObject({ id: 'f1' });
    expect(globalThis.fetch).toHaveBeenCalledTimes(2);
    expect(refreshAccessToken).toHaveBeenCalled();
  });

  it('reports Drive as disconnected only when a fresh token is rejected too', async () => {
    globalThis.fetch = vi.fn(async () => new Response('', { status: 401 }));
    await expect(getFile('f1')).rejects.toMatchObject({ code: 'drive_not_connected' });
    expect(globalThis.fetch).toHaveBeenCalledTimes(2);
  });
});
