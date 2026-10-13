// @vitest-environment node
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { resetFake } from './fakeDb';

vi.mock('../../api/_lib/supabaseAdmin.js', async () => (await import('./fakeDb')).supabaseAdminMock);
vi.mock('../../api/_lib/session.js', () => ({ requireStaff: async () => ({ id: 'u1' }) }));
vi.mock('../../api/_lib/drive.js', () => ({ renameFile: vi.fn(), moveAlbumFolder: vi.fn(), trashFile: vi.fn() }));

const { renameFile, moveAlbumFolder } = await import('../../api/_lib/drive.js');
const { PATCH } = await import('../../api/albums/[id]');

const ALBUM = {
  id: '7f1c2b9e-0000-4000-8000-000000000001',
  title: 'เทปูน',
  report_date: '2026-10-12',
  drive_folder_id: 'folder-album',
  share_token: 'abcDEF123_-xyz456789AB',
  allow_link_upload: true,
  cover_media_id: null,
  media_count: 0,
  created_by: null,
  created_at: '2026-10-12T00:00:00Z',
  updated_at: '2026-10-12T00:00:00Z',
  deleted_at: null,
};

const patch = (body: unknown) =>
  PATCH(
    new Request(`https://photo.goldenmole.pro/api/albums/${ALBUM.id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }),
  );

beforeEach(() => {
  vi.clearAllMocks();
  resetFake((q) => (q.table === 'ph_albums' ? { data: ALBUM, error: null } : { data: [], error: null }));
});

describe('PATCH /api/albums/:id', () => {
  it('rejects a bad date before renaming anything in Drive', async () => {
    const res = await patch({ title: 'ชื่อใหม่', reportDate: '2026-13-45' });
    expect(res.status).toBe(400);
    expect(renameFile).not.toHaveBeenCalled();
    expect(moveAlbumFolder).not.toHaveBeenCalled();
  });

  it('rejects a cover from another album before renaming anything in Drive', async () => {
    resetFake((q) => (q.table === 'ph_albums' ? { data: ALBUM, error: null } : { data: null, error: null }));
    const res = await patch({ title: 'ชื่อใหม่', coverMediaId: 'someone-elses-photo' });
    expect(res.status).toBe(400);
    expect(renameFile).not.toHaveBeenCalled();
  });

  it('renames and moves the Drive folder for valid changes', async () => {
    const res = await patch({ title: 'ชื่อใหม่', reportDate: '2026-11-01' });
    expect(res.status).toBe(200);
    expect(renameFile).toHaveBeenCalledWith('folder-album', 'ชื่อใหม่');
    expect(moveAlbumFolder).toHaveBeenCalledWith('folder-album', '2026-11-01');
  });
});
