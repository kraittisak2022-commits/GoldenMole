import { sortMedia } from '../../shared/mediaOrder.js';
import { driveFolderUrl, mediaSources } from '../../shared/mediaUrls.js';
import { shareUrl } from '../../shared/shareText.js';
import type { AlbumSummary, MediaItem, MediaKind, SharedAlbum, StaffUser, UploadTarget } from '../../shared/types.js';
import { requireAlbumViewer } from './albumAccess.js';
import { publicOrigin } from './env.js';
import { HttpError } from './http.js';
import { requireStaff } from './session.js';
import { db, must } from './supabaseAdmin.js';

export interface AlbumRow {
  id: string;
  title: string;
  report_date: string;
  drive_folder_id: string;
  share_token: string;
  allow_link_upload: boolean;
  cover_media_id: string | null;
  media_count: number;
  created_by: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
}

export interface MediaRow {
  id: string;
  album_id: string;
  drive_file_id: string;
  kind: MediaKind;
  mime: string;
  name: string;
  size_bytes: number;
  width: number;
  height: number;
  taken_at: string | null;
  uploaded_by_name: string | null;
  uploaded_by_staff_id: string | null;
  created_at: string;
}

export const ALBUM_COLUMNS =
  'id, title, report_date, drive_folder_id, share_token, allow_link_upload, cover_media_id, media_count, created_by, created_at, updated_at, deleted_at';
export const MEDIA_COLUMNS =
  'id, album_id, drive_file_id, kind, mime, name, size_bytes, width, height, taken_at, uploaded_by_name, uploaded_by_staff_id, created_at';

export function toMediaItem(row: MediaRow): MediaItem {
  return {
    id: row.id,
    kind: row.kind,
    mime: row.mime,
    name: row.name,
    width: row.width,
    height: row.height,
    takenAt: row.taken_at,
    createdAt: row.created_at,
    uploadedByName: row.uploaded_by_name,
    src: mediaSources(row.drive_file_id, row.kind),
  };
}

export function toAlbumSummary(row: AlbumRow, cover: Pick<MediaRow, 'drive_file_id' | 'kind'> | null): AlbumSummary {
  return {
    id: row.id,
    title: row.title,
    reportDate: row.report_date,
    mediaCount: row.media_count,
    cover: cover ? mediaSources(cover.drive_file_id, cover.kind) : null,
    allowLinkUpload: row.allow_link_upload,
    shareUrl: shareUrl(publicOrigin(), row.share_token),
    driveFolderUrl: driveFolderUrl(row.drive_folder_id),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export function toSharedAlbum(row: AlbumRow, media: MediaRow[]): SharedAlbum {
  return {
    title: row.title,
    reportDate: row.report_date,
    mediaCount: row.media_count,
    allowLinkUpload: row.allow_link_upload,
    shareUrl: shareUrl(publicOrigin(), row.share_token),
    driveFolderUrl: driveFolderUrl(row.drive_folder_id),
    media: media.map(toMediaItem),
  };
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TOKEN_RE = /^[A-Za-z0-9_-]{16,64}$/;

export async function loadAlbum(id: string): Promise<AlbumRow> {
  if (!UUID_RE.test(id)) throw new HttpError('not_found', 404);
  const row = must(
    await db().from('ph_albums').select(ALBUM_COLUMNS).eq('id', id).is('deleted_at', null).maybeSingle(),
  ) as AlbumRow | null;
  if (!row) throw new HttpError('not_found', 404);
  return row;
}

export async function loadAlbumByToken(token: string): Promise<AlbumRow> {
  if (!TOKEN_RE.test(token)) throw new HttpError('not_found', 404);
  const row = must(
    await db().from('ph_albums').select(ALBUM_COLUMNS).eq('share_token', token).is('deleted_at', null).maybeSingle(),
  ) as AlbumRow | null;
  if (!row) throw new HttpError('not_found', 404);
  return row;
}

export async function loadMedia(albumId: string): Promise<MediaRow[]> {
  return sortMedia(must(await db().from('ph_media').select(MEDIA_COLUMNS).eq('album_id', albumId)) as MediaRow[]);
}

/** Any parseable date string → ISO; anything else → null. */
export function readTakenAt(v: unknown): string | null {
  if (typeof v !== 'string') return null;
  const t = Date.parse(v);
  return Number.isNaN(t) ? null : new Date(t).toISOString();
}

export function readTarget(body: Record<string, unknown>): UploadTarget {
  const albumId = typeof body.albumId === 'string' ? body.albumId : undefined;
  const shareToken = typeof body.shareToken === 'string' ? body.shareToken : undefined;
  if (!!albumId === !!shareToken) throw new HttpError('bad_request', 400);
  return { albumId, shareToken };
}

/**
 * Staff upload by album id (session required) or link upload by share token: the album must allow it and
 * the device must have entered the PIN (or be signed in as staff).
 */
export async function resolveUploadTarget(
  request: Request,
  target: UploadTarget,
): Promise<{ album: AlbumRow; staff: StaffUser | null }> {
  if (target.albumId) {
    const staff = await requireStaff(request);
    return { album: await loadAlbum(target.albumId), staff };
  }
  const album = await loadAlbumByToken(target.shareToken ?? '');
  const staff = await requireAlbumViewer(request, album.id);
  if (!album.allow_link_upload) throw new HttpError('upload_disabled', 403);
  return { album, staff };
}

/**
 * Recounts media and picks a cover (the first item) when the album has none, in one locked statement
 * (`ph_refresh_album_stats`) so parallel uploads and deletes cannot overwrite each other's result.
 */
export async function refreshAlbumStats(albumId: string): Promise<void> {
  must(await db().rpc('ph_refresh_album_stats', { p_album_id: albumId }));
}

export async function coversFor(rows: AlbumRow[]): Promise<Map<string, Pick<MediaRow, 'drive_file_id' | 'kind'>>> {
  const ids = rows.map((r) => r.cover_media_id).filter((id): id is string => !!id);
  if (!ids.length) return new Map();
  const media = must(await db().from('ph_media').select('id, drive_file_id, kind').in('id', ids)) as Pick<
    MediaRow,
    'id' | 'drive_file_id' | 'kind'
  >[];
  return new Map(media.map((m) => [m.id, m]));
}
