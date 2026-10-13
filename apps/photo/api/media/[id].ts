import { MEDIA_COLUMNS, type MediaRow, refreshAlbumStats } from '../_lib/albums.js';
import { trashFile } from '../_lib/drive.js';
import { HttpError, json, lastSegment, route } from '../_lib/http.js';
import { requireStaff } from '../_lib/session.js';
import { db, must } from '../_lib/supabaseAdmin.js';

/** DELETE (SuperAdmin): sends the file to the Drive trash and removes it from the album. */
export const DELETE = route(async (request) => {
  await requireStaff(request, { superAdmin: true });
  const id = lastSegment(request);
  if (!/^[0-9a-f-]{36}$/i.test(id)) throw new HttpError('not_found', 404);
  const media = must(await db().from('ph_media').select(MEDIA_COLUMNS).eq('id', id).maybeSingle()) as MediaRow | null;
  if (!media) throw new HttpError('not_found', 404);
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
