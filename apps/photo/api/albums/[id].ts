import { isValidReportDate } from '../../shared/folderPath.js';
import { normalizeTitle } from '../../shared/limits.js';
import type { AlbumDetail } from '../../shared/types.js';
import { ALBUM_COLUMNS, type AlbumRow, loadAlbum, loadMedia, toAlbumSummary, toMediaItem } from '../_lib/albums.js';
import { moveAlbumFolder, renameFile, trashFile } from '../_lib/drive.js';
import { HttpError, json, lastSegment, readJson, route } from '../_lib/http.js';
import { requireStaff } from '../_lib/session.js';
import { db, must } from '../_lib/supabaseAdmin.js';
import { newShareToken } from '../_lib/token.js';

async function detail(album: AlbumRow): Promise<AlbumDetail> {
  const media = await loadMedia(album.id);
  const cover = media.find((m) => m.id === album.cover_media_id) ?? null;
  return { ...toAlbumSummary(album, cover), media: media.map(toMediaItem) };
}

/** GET (staff) → AlbumDetail */
export const GET = route(async (request) => {
  await requireStaff(request);
  return json(await detail(await loadAlbum(lastSegment(request))));
});

/**
 * PATCH (staff) { title?, reportDate?, allowLinkUpload?, regenerateLink?, coverMediaId? } → AlbumDetail.
 * Renames or moves the Drive folder before saving, so Drive and the database stay in step.
 */
export const PATCH = route(async (request) => {
  await requireStaff(request);
  const album = await loadAlbum(lastSegment(request));
  const body = await readJson(request);
  const update: Partial<AlbumRow> = {};

  // Validate everything before touching Drive, so a bad field cannot leave Drive changed and the database not.
  const title = body.title === undefined ? undefined : normalizeTitle(body.title);
  if (title === null) throw new HttpError('bad_request', 400);
  const reportDate = body.reportDate;
  if (reportDate !== undefined && !isValidReportDate(reportDate)) throw new HttpError('bad_request', 400);
  if (typeof body.coverMediaId === 'string') {
    const owned = must(
      await db().from('ph_media').select('id').eq('id', body.coverMediaId).eq('album_id', album.id).maybeSingle(),
    );
    if (!owned) throw new HttpError('bad_request', 400);
    update.cover_media_id = body.coverMediaId;
  }
  if (typeof body.allowLinkUpload === 'boolean') update.allow_link_upload = body.allowLinkUpload;
  if (body.regenerateLink === true) update.share_token = newShareToken();

  if (title !== undefined && title !== album.title) {
    await renameFile(album.drive_folder_id, title);
    update.title = title;
  }
  if (typeof reportDate === 'string' && reportDate !== album.report_date) {
    await moveAlbumFolder(album.drive_folder_id, reportDate);
    update.report_date = reportDate;
  }

  if (!Object.keys(update).length) return json(await detail(album));
  const saved = must(
    await db()
      .from('ph_albums')
      .update({ ...update, updated_at: new Date().toISOString() })
      .eq('id', album.id)
      .select(ALBUM_COLUMNS)
      .single(),
  ) as AlbumRow;
  return json(await detail(saved));
});

/** DELETE (staff): moves the Drive folder to the Drive trash (restorable for 30 days) and hides the album. */
export const DELETE = route(async (request) => {
  await requireStaff(request);
  const album = await loadAlbum(lastSegment(request));
  try {
    await trashFile(album.drive_folder_id);
  } catch (err) {
    if (!(err instanceof HttpError) || err.code !== 'not_found') throw err;
  }
  must(
    await db()
      .from('ph_albums')
      .update({ deleted_at: new Date().toISOString(), updated_at: new Date().toISOString() })
      .eq('id', album.id),
  );
  return json({ ok: true });
});
