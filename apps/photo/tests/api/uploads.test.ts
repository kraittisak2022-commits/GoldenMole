// @vitest-environment node
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { resetFake } from './fakeDb';

vi.mock('../../api/_lib/supabaseAdmin.js', async () => (await import('./fakeDb')).supabaseAdminMock);

vi.mock('../../api/_lib/drive.js', () => ({
  startResumableUpload: vi.fn(async () => 'https://www.googleapis.com/upload/drive/v3/files?upload_id=xyz'),
  getFile: vi.fn(),
}));

process.env.PHOTO_SESSION_SECRET = 'test-secret-for-uploads';
process.env.PHOTO_ALBUM_PIN = '8888';

const { startResumableUpload, getFile } = await import('../../api/_lib/drive.js');
const { createAlbumAccess } = await import('../../api/_lib/albumAccess');
const { POST: start } = await import('../../api/uploads/start');
const { POST: complete } = await import('../../api/uploads/complete');

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

const post = (body: unknown, { pin = true } = {}) =>
  new Request('http://localhost:5190/api/uploads/x', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Origin: 'http://localhost:5190',
      ...(pin ? { 'X-Album-Access': createAlbumAccess(ALBUM.id) } : {}),
    },
    body: JSON.stringify(body),
  });

/** `recentLinkUploads` = link upload starts in the past hour, this one included. */
function setup({ album = ALBUM, recentLinkUploads = 1, existingMedia = null as unknown } = {}) {
  resetFake((q) => {
    if (q.table === 'ph_albums') return { data: q.filters.share_token === album.share_token ? album : null, error: null };
    if (q.table === 'ph_auth_attempts' && q.op === 'insert') return { data: [{ id: 1, scope: 'link_upload', key_hash: 'k' }], error: null };
    if (q.table === 'ph_auth_attempts' && q.op === 'select') return { data: null, error: null, count: recentLinkUploads };
    if (q.table === 'ph_media' && 'drive_file_id' in q.filters) return { data: existingMedia, error: null };
    return { data: null, error: null };
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  process.env.PUBLIC_ORIGIN = 'https://photo.goldenmole.pro';
  setup();
});

describe('POST /api/uploads/start', () => {
  const file = { shareToken: TOKEN, name: 'IMG_1.jpg', mimeType: 'image/jpeg', size: 1_000 };

  it('opens a Drive session in the album folder for a link upload', async () => {
    const res = await start(post(file));
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ uploadUrl: expect.stringContaining('upload_id=') });
    expect(startResumableUpload).toHaveBeenCalledWith(
      expect.objectContaining({ parentId: 'folder-album', name: 'IMG_1.jpg', origin: 'http://localhost:5190' }),
    );
  });

  it('refuses link uploads from a device that has not entered the PIN', async () => {
    const res = await start(post(file, { pin: false }));
    expect(res.status).toBe(403);
    expect(await res.json()).toEqual({ error: 'pin_required' });
    expect(startResumableUpload).not.toHaveBeenCalled();
  });

  it('refuses link uploads when the album has them turned off', async () => {
    setup({ album: { ...ALBUM, allow_link_upload: false } });
    const res = await start(post(file));
    expect(res.status).toBe(403);
    expect(await res.json()).toEqual({ error: 'upload_disabled' });
    expect(startResumableUpload).not.toHaveBeenCalled();
  });

  it('refuses files that are not photos or videos, or too large', async () => {
    const pdf = await start(post({ ...file, mimeType: 'application/pdf' }));
    expect(await pdf.json()).toEqual({ error: 'bad_type' });
    const huge = await start(post({ ...file, size: 51 * 1024 * 1024 }));
    expect(huge.status).toBe(400);
    expect(await huge.json()).toEqual({ error: 'too_large' });
    expect(startResumableUpload).not.toHaveBeenCalled();
  });

  it('rate-limits link uploads per album, counting uploads as they start', async () => {
    setup({ recentLinkUploads: 300 });
    expect((await start(post(file))).status).toBe(200);
    setup({ recentLinkUploads: 301 });
    const res = await start(post(file));
    expect(res.status).toBe(429);
    expect(await res.json()).toEqual({ error: 'rate_limited' });
    expect(startResumableUpload).toHaveBeenCalledTimes(1);
  });

  it('treats an unknown link as not found', async () => {
    const res = await start(post({ ...file, shareToken: 'zzzzzzzzzzzzzzzzzzzzzz' }));
    expect(res.status).toBe(404);
  });

  it('needs exactly one of albumId or shareToken', async () => {
    const res = await start(post({ ...file, albumId: ALBUM.id }));
    expect(res.status).toBe(400);
  });

  it('requires a staff session to upload by album id', async () => {
    const { shareToken: _token, ...rest } = file;
    const res = await start(post({ ...rest, albumId: ALBUM.id }));
    expect(res.status).toBe(401);
  });
});

describe('POST /api/uploads/complete', () => {
  const done = { shareToken: TOKEN, fileId: '1AbCdEfGhIjKlMnOp', width: 4000, height: 3000 };

  it('refuses a Drive file that is not inside the album folder', async () => {
    vi.mocked(getFile).mockResolvedValue({ id: done.fileId, name: 'x.jpg', mimeType: 'image/jpeg', parents: ['someone-else'] });
    const res = await complete(post(done));
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: 'wrong_folder' });
  });

  it('refuses a file already recorded in another album', async () => {
    setup({ existingMedia: { id: 'm1', album_id: 'other-album', drive_file_id: done.fileId } });
    const res = await complete(post(done));
    expect(await res.json()).toEqual({ error: 'wrong_folder' });
    expect(getFile).not.toHaveBeenCalled();
  });

  it('rejects malformed file ids before calling Drive', async () => {
    const res = await complete(post({ ...done, fileId: '../etc' }));
    expect(res.status).toBe(400);
    expect(getFile).not.toHaveBeenCalled();
  });
});
