import { randomUUID } from 'node:crypto';
import { sortMedia } from '../shared/mediaOrder';
import type { AlbumDetail, MediaItem, MediaSources } from '../shared/types';

/** In-memory stand-in for api/*.ts so the UI can be checked without Google or Supabase (PHOTO_MOCK_API=1). */

const ORIGIN = 'http://localhost:5190';
const user = { id: 'mock-admin', username: 'admin', displayName: 'ผู้ดูแลทดสอบ', role: 'SuperAdmin' as const };

const picsum = (seed: string, w: number, h: number): MediaSources => {
  const scale = (max: number) => {
    const f = max / Math.max(w, h);
    return `${Math.round(w * f)}/${Math.round(h * f)}`;
  };
  return {
    thumb: `https://picsum.photos/seed/${seed}/${scale(640)}`,
    thumbFallback: `https://picsum.photos/seed/${seed}/${scale(640)}`,
    large: `https://picsum.photos/seed/${seed}/${scale(2048)}`,
    download: `https://picsum.photos/seed/${seed}/${w}/${h}`,
    preview: null,
  };
};

const SIZES: [number, number][] = [
  [4000, 3000],
  [3000, 4000],
  [1920, 1080],
  [3000, 3000],
  [4000, 2250],
  [2250, 4000],
  [3600, 2400],
];

function makeMedia(prefix: string, count: number, day: string): MediaItem[] {
  return Array.from({ length: count }, (_, i) => {
    const [w, h] = SIZES[i % SIZES.length];
    const hour = String(8 + Math.floor(i / 4)).padStart(2, '0');
    const at = `${day}T${hour}:${String((i * 7) % 60).padStart(2, '0')}:00+07:00`;
    return {
      id: randomUUID(),
      kind: 'image',
      mime: 'image/jpeg',
      name: `IMG_${prefix}_${String(i + 1).padStart(4, '0')}.jpg`,
      width: w,
      height: h,
      takenAt: new Date(at).toISOString(),
      createdAt: new Date(at).toISOString(),
      uploadedByName: i % 3 ? 'ช่างสมชาย' : null,
      src: picsum(`${prefix}${i}`, w, h),
    };
  });
}

interface MockAlbum extends AlbumDetail {
  token: string;
}

function album(title: string, reportDate: string, unsorted: MediaItem[], allowLinkUpload = true): MockAlbum {
  const media = sortMedia(unsorted);
  const token = randomUUID().replace(/-/g, '').slice(0, 22);
  const now = new Date().toISOString();
  return {
    id: randomUUID(),
    title,
    reportDate,
    mediaCount: media.length,
    cover: media[0]?.src ?? null,
    allowLinkUpload,
    shareUrl: `${ORIGIN}/a/${token}`,
    driveFolderUrl: 'https://drive.google.com/drive/my-drive',
    createdAt: now,
    updatedAt: now,
    media,
    token,
  };
}

const albums: MockAlbum[] = [
  album('เทปูนชั้น 2 อาคาร A', '2026-10-12', [...makeMedia('a', 9, '2026-10-12'), ...makeMedia('b', 6, '2026-10-11')]),
  album('ตรวจรับงานเหล็กเสริม โครงการบ้านพักครู', '2026-10-08', makeMedia('c', 7, '2026-10-08')),
  album('ส่งหินคลุก หน้างานวังเหนือ', '2026-09-28', makeMedia('d', 4, '2026-09-28'), false),
  album('อัลบั้มว่าง', '2026-09-20', []),
];

const uploads = new Map<string, { albumId: string; name: string; mime: string }>();

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
const summary = ({ media: _m, token: _t, ...rest }: MockAlbum) => ({ ...rest, mediaCount: _m.length, cover: rest.cover ?? _m[0]?.src ?? null });
const detail = ({ token: _t, ...rest }: MockAlbum) => ({ ...rest, mediaCount: rest.media.length });
const shared = (a: MockAlbum) => ({
  title: a.title,
  reportDate: a.reportDate,
  mediaCount: a.media.length,
  allowLinkUpload: a.allowLinkUpload,
  shareUrl: a.shareUrl,
  driveFolderUrl: a.driveFolderUrl,
  media: a.media,
});

export async function handleMock(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const parts = url.pathname.replace(/^\/api\//, '').split('/');
  const body = request.method === 'POST' || request.method === 'PATCH' ? ((await request.json().catch(() => ({}))) as Record<string, any>) : {};
  const [a, b] = parts;

  if (a === 'auth' && b === 'login') return json({ token: 'mock', user });
  if (a === 'auth' && b === 'me') return json({ user });
  if (a === 'google' && b === 'status') return json({ connected: true, email: 'goldenmole.photos@gmail.com', connectedAt: '2026-10-12T03:00:00Z' });
  if (a === 'google' && b === 'connect') return json({ url: `${ORIGIN}/settings?google=connected` });

  if (a === 'albums' && !b) {
    if (request.method === 'POST') {
      const created = album(String(body.title), String(body.reportDate), [], body.allowLinkUpload !== false);
      albums.unshift(created);
      return json(summary(created), 201);
    }
    return json(albums.map(summary));
  }
  if (a === 'albums' && b) {
    const found = albums.find((x) => x.id === b);
    if (!found) return json({ error: 'not_found' }, 404);
    if (request.method === 'DELETE') {
      albums.splice(albums.indexOf(found), 1);
      return json({ ok: true });
    }
    if (request.method === 'PATCH') {
      if (typeof body.title === 'string') found.title = body.title;
      if (typeof body.reportDate === 'string') found.reportDate = body.reportDate;
      if (typeof body.allowLinkUpload === 'boolean') found.allowLinkUpload = body.allowLinkUpload;
      if (body.regenerateLink) {
        found.token = randomUUID().replace(/-/g, '').slice(0, 22);
        found.shareUrl = `${ORIGIN}/a/${found.token}`;
      }
      if (typeof body.coverMediaId === 'string') found.cover = found.media.find((m) => m.id === body.coverMediaId)?.src ?? found.cover;
    }
    return json(detail(found));
  }
  if (a === 'share') {
    const found = albums.find((x) => x.token === b);
    return found ? json(shared(found)) : json({ error: 'not_found' }, 404);
  }
  if (a === 'media' && request.method === 'DELETE') {
    albums.forEach((x) => (x.media = x.media.filter((m) => m.id !== b)));
    return json({ ok: true });
  }
  if (a === 'uploads' && b === 'start') {
    const target = albums.find((x) => x.id === body.albumId || x.token === body.shareToken);
    if (!target) return json({ error: 'not_found' }, 404);
    if (body.shareToken && !target.allowLinkUpload) return json({ error: 'upload_disabled' }, 403);
    const id = randomUUID();
    uploads.set(id, { albumId: target.id, name: String(body.name), mime: String(body.mimeType) });
    return json({ uploadUrl: `${ORIGIN}/api/mock-upload/${id}` });
  }
  if (a === 'mock-upload' && request.method === 'PUT') {
    await request.arrayBuffer();
    const range = /bytes (\d+)-(\d+)\/(\d+)/.exec(request.headers.get('content-range') ?? '');
    if (range && Number(range[2]) + 1 < Number(range[3])) {
      return new Response(null, { status: 308, headers: { Range: `bytes=0-${range[2]}` } });
    }
    return json({ id: `mock${b.replace(/-/g, '')}` });
  }
  if (a === 'uploads' && b === 'complete') {
    const upload = uploads.get(String(body.fileId).replace(/^mock/, '').replace(/^(.{8})(.{4})(.{4})(.{4})(.{12})$/, '$1-$2-$3-$4-$5'));
    const target = albums.find((x) => x.id === upload?.albumId);
    if (!upload || !target) return json({ error: 'wrong_folder' }, 400);
    const w = Number(body.width) || 1600;
    const h = Number(body.height) || 1200;
    const item: MediaItem = {
      id: randomUUID(),
      kind: upload.mime.startsWith('video/') ? 'video' : 'image',
      mime: upload.mime,
      name: upload.name,
      width: w,
      height: h,
      takenAt: body.takenAt ?? null,
      createdAt: new Date().toISOString(),
      uploadedByName: body.uploaderName ?? user.displayName,
      src: picsum(String(body.fileId), w, h),
    };
    target.media = sortMedia([...target.media, item]);
    return json(item, 201);
  }
  return json({ error: 'not_found' }, 404);
}
