import { isValidReportDate } from '../../shared/folderPath.js';
import { normalizeTitle } from '../../shared/limits.js';
import { ALBUM_COLUMNS, type AlbumRow, coversFor, toAlbumSummary } from '../_lib/albums.js';
import { createAlbumFolder, trashFile } from '../_lib/drive.js';
import { HttpError, json, readJson, route } from '../_lib/http.js';
import { requireStaff } from '../_lib/session.js';
import { db, must } from '../_lib/supabaseAdmin.js';
import { newShareToken } from '../_lib/token.js';

/** GET (staff) → AlbumSummary[], newest report date first. */
export const GET = route(async (request) => {
  await requireStaff(request);
  const rows = must(
    await db()
      .from('ph_albums')
      .select(ALBUM_COLUMNS)
      .is('deleted_at', null)
      .order('report_date', { ascending: false })
      .order('created_at', { ascending: false })
      .limit(1000),
  ) as AlbumRow[];
  const covers = await coversFor(rows);
  return json(rows.map((r) => toAlbumSummary(r, r.cover_media_id ? covers.get(r.cover_media_id) ?? null : null)));
});

/** POST (staff) { title, reportDate } → AlbumSummary. Creates the Drive folder first; anyone with the link may add photos. */
export const POST = route(async (request) => {
  const staff = await requireStaff(request);
  const body = await readJson(request);
  const title = normalizeTitle(body.title);
  const reportDate = body.reportDate;
  if (!title || !isValidReportDate(reportDate)) throw new HttpError('bad_request', 400);

  const folderId = await createAlbumFolder(title, reportDate);
  const result = await db()
    .from('ph_albums')
    .insert({
      title,
      report_date: reportDate,
      drive_folder_id: folderId,
      share_token: newShareToken(),
      allow_link_upload: true,
      created_by: staff.id,
    })
    .select(ALBUM_COLUMNS)
    .single();
  if (result.error) {
    await trashFile(folderId).catch(() => undefined);
    throw new HttpError('server_error', 500, result.error.message);
  }
  return json(toAlbumSummary(result.data as AlbumRow, null), 201);
});
