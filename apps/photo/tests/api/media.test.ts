// @vitest-environment node
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { fake, resetFake } from './fakeDb';

vi.mock('../../api/_lib/supabaseAdmin.js', async () => (await import('./fakeDb')).supabaseAdminMock);
vi.mock('../../api/_lib/session.js', () => ({ requireStaff: vi.fn(async () => ({ id: 'u1' })) }));
vi.mock('../../api/_lib/drive.js', () => ({ renameFile: vi.fn(), trashFile: vi.fn() }));

const { renameFile } = await import('../../api/_lib/drive.js');
const { requireStaff } = await import('../../api/_lib/session.js');
const { PATCH } = await import('../../api/media/[id]');

const MEDIA = {
  id: '7f1c2b9e-0000-4000-8000-0000000000aa',
  album_id: '7f1c2b9e-0000-4000-8000-000000000001',
  drive_file_id: 'file-1',
  kind: 'photo',
  mime: 'image/jpeg',
  name: 'IMG_0001.JPG',
  size_bytes: 1000,
  width: 4000,
  height: 3000,
  taken_at: '2026-10-12T02:00:00.000Z',
  uploaded_by_name: 'สมชาย',
  uploaded_by_staff_id: null,
  created_at: '2026-10-12T03:00:00Z',
};

const patch = (body: unknown) =>
  PATCH(
    new Request(`https://photo.goldenmole.pro/api/media/${MEDIA.id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }),
  );

const updates = () => fake.queries.filter((q) => q.table === 'ph_media' && q.op === 'update');

beforeEach(() => {
  vi.clearAllMocks();
  resetFake((q) => ({ data: q.op === 'update' ? { ...MEDIA, ...(q.payload as object) } : MEDIA, error: null }));
});

describe('PATCH /api/media/:id', () => {
  it('is limited to SuperAdmin', async () => {
    await patch({ name: 'เทปูน' });
    expect(requireStaff).toHaveBeenCalledWith(expect.any(Request), { superAdmin: true });
  });

  it('rejects an empty name or a bad date without touching Drive or the database', async () => {
    expect((await patch({ name: '   ' })).status).toBe(400);
    expect((await patch({ takenAt: 'not a date' })).status).toBe(400);
    expect((await patch({ uploadedByName: 42 })).status).toBe(400);
    expect(renameFile).not.toHaveBeenCalled();
    expect(updates()).toHaveLength(0);
  });

  it('renames the file in Drive and keeps the original extension', async () => {
    const res = await patch({ name: 'เทปูน ชั้น 2' });
    expect(res.status).toBe(200);
    expect(renameFile).toHaveBeenCalledWith('file-1', 'เทปูน ชั้น 2.JPG');
    expect(updates()[0].payload).toEqual({ name: 'เทปูน ชั้น 2.JPG' });
    expect((await res.json()).name).toBe('เทปูน ชั้น 2.JPG');
  });

  it('clears the sender and date taken with null, without renaming in Drive', async () => {
    const res = await patch({ name: 'IMG_0001', uploadedByName: null, takenAt: null });
    expect(res.status).toBe(200);
    expect(renameFile).not.toHaveBeenCalled();
    expect(updates()[0].payload).toEqual({ uploaded_by_name: null, taken_at: null });
    const body = await res.json();
    expect(body.uploadedByName).toBeNull();
    expect(body.takenAt).toBeNull();
  });

  it('stores a new date taken as ISO time', async () => {
    await patch({ takenAt: '2026-10-11T08:30:00+07:00' });
    expect(updates()[0].payload).toEqual({ taken_at: '2026-10-11T01:30:00.000Z' });
  });
});
