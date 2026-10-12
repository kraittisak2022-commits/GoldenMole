import { mediaKindOf, normalizeUploaderName } from '../../shared/limits.js';
import { MEDIA_COLUMNS, type MediaRow, readTarget, refreshAlbumStats, resolveUploadTarget, toMediaItem } from '../_lib/albums.js';
import { type DriveFile, getFile } from '../_lib/drive.js';
import { HttpError, json, readJson, route } from '../_lib/http.js';
import { db, must } from '../_lib/supabaseAdmin.js';

const positiveInt = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) && v > 0 ? Math.round(v) : 0);

function readTakenAt(v: unknown): string | null {
  if (typeof v !== 'string') return null;
  const t = Date.parse(v);
  return Number.isNaN(t) ? null : new Date(t).toISOString();
}

/** Width/height from the browser, else from Drive; swapped when Drive reports a quarter-turn rotation. */
export function resolveSize(file: DriveFile, width: number, height: number): { width: number; height: number } {
  if (width && height) return { width, height };
  const meta = file.imageMediaMetadata ?? file.videoMediaMetadata;
  const w = meta?.width ?? 0;
  const h = meta?.height ?? 0;
  const rotated = (file.imageMediaMetadata?.rotation ?? 0) % 2 === 1;
  return rotated ? { width: h, height: w } : { width: w, height: h };
}

/** POST { albumId | shareToken, fileId, width, height, takenAt, uploaderName? } → MediaItem */
export const POST = route(async (request) => {
  const body = await readJson(request);
  const { album, staff } = await resolveUploadTarget(request, readTarget(body));
  const fileId = typeof body.fileId === 'string' ? body.fileId : '';
  if (!/^[A-Za-z0-9_-]{10,200}$/.test(fileId)) throw new HttpError('bad_request', 400);

  const existing = must(await db().from('ph_media').select(MEDIA_COLUMNS).eq('drive_file_id', fileId).maybeSingle()) as MediaRow | null;
  if (existing) {
    if (existing.album_id !== album.id) throw new HttpError('wrong_folder', 400);
    return json(toMediaItem(existing));
  }

  const file = await getFile(fileId);
  if (file.trashed || !file.parents?.includes(album.drive_folder_id)) throw new HttpError('wrong_folder', 400);
  const kind = mediaKindOf(file.mimeType);
  if (!kind) throw new HttpError('bad_type', 400);

  const size = resolveSize(file, positiveInt(body.width), positiveInt(body.height));
  const inserted = await db()
    .from('ph_media')
    .insert({
      album_id: album.id,
      drive_file_id: file.id,
      kind,
      mime: file.mimeType,
      name: file.name,
      size_bytes: Number(file.size ?? 0),
      width: size.width,
      height: size.height,
      taken_at: readTakenAt(body.takenAt),
      uploaded_by_name: staff ? staff.displayName : normalizeUploaderName(body.uploaderName),
      uploaded_by_staff_id: staff?.id ?? null,
    })
    .select(MEDIA_COLUMNS)
    .single();
  if (inserted.error) {
    const again = must(await db().from('ph_media').select(MEDIA_COLUMNS).eq('drive_file_id', fileId).maybeSingle()) as MediaRow | null;
    if (!again) throw new HttpError('server_error', 500, inserted.error.message);
    return json(toMediaItem(again));
  }
  await refreshAlbumStats(album.id);
  return json(toMediaItem(inserted.data as MediaRow), 201);
});
