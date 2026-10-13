import { normalizeUploaderName, renamedFileName } from '../../shared/limits.js';
import { MEDIA_COLUMNS, type MediaRow, readTakenAt, refreshAlbumStats, toMediaItem } from '../_lib/albums.js';
import { renameFile, trashFile } from '../_lib/drive.js';
import { HttpError, json, lastSegment, readJson, route } from '../_lib/http.js';
import { requireStaff } from '../_lib/session.js';
import { db, must } from '../_lib/supabaseAdmin.js';

async function loadMediaRow(request: Request): Promise<MediaRow> {
  const id = lastSegment(request);
  if (!/^[0-9a-f-]{36}$/i.test(id)) throw new HttpError('not_found', 404);
  const media = must(await db().from('ph_media').select(MEDIA_COLUMNS).eq('id', id).maybeSingle()) as MediaRow | null;
  if (!media) throw new HttpError('not_found', 404);
  return media;
}

/**
 * PATCH (SuperAdmin) { name?, uploadedByName?, takenAt? } → MediaItem.
 * The name keeps the original extension and is renamed in Drive too; null uploader name or date clears it.
 */
export const PATCH = route(async (request) => {
  await requireStaff(request, { superAdmin: true });
  const media = await loadMediaRow(request);
  const body = await readJson(request);
  const update: Partial<MediaRow> = {};

  if (body.name !== undefined) {
    const name = renamedFileName(body.name, media.name);
    if (!name) throw new HttpError('bad_request', 400);
    if (name !== media.name) update.name = name;
  }
  if (body.uploadedByName !== undefined) {
    if (body.uploadedByName !== null && typeof body.uploadedByName !== 'string') throw new HttpError('bad_request', 400);
    update.uploaded_by_name = normalizeUploaderName(body.uploadedByName);
  }
  if (body.takenAt !== undefined) {
    const takenAt = body.takenAt === null ? null : readTakenAt(body.takenAt);
    if (body.takenAt !== null && !takenAt) throw new HttpError('bad_request', 400);
    update.taken_at = takenAt;
  }

  if (!Object.keys(update).length) return json(toMediaItem(media));
  if (update.name) await renameFile(media.drive_file_id, update.name);
  const saved = must(
    await db().from('ph_media').update(update).eq('id', media.id).select(MEDIA_COLUMNS).single(),
  ) as MediaRow;
  return json(toMediaItem(saved));
});

/** DELETE (SuperAdmin): sends the file to the Drive trash and removes it from the album. */
export const DELETE = route(async (request) => {
  await requireStaff(request, { superAdmin: true });
  const media = await loadMediaRow(request);
  try {
    await trashFile(media.drive_file_id);
  } catch (err) {
    if (!(err instanceof HttpError) || err.code !== 'not_found') throw err;
  }
  must(await db().from('ph_albums').update({ cover_media_id: null }).eq('cover_media_id', media.id));
  must(await db().from('ph_media').delete().eq('id', media.id));
  await refreshAlbumStats(media.album_id);
  return json({ ok: true });
});
