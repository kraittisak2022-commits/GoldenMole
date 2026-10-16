import { mediaKindOf } from '../../../shared/limits.js';
import { mediaSources } from '../../../shared/mediaUrls.js';
import { todayInBangkok } from '../../../shared/folderPath.js';
import { ensureFeedMonthFolder, getFile, shareWithAnyoneReader } from '../../_lib/drive.js';
import { HttpError, json, readJson, route } from '../../_lib/http.js';
import { requireStaff } from '../../_lib/session.js';
import { resolveSize } from '../../uploads/complete.js';

const positiveInt = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) && v > 0 ? Math.round(v) : 0);

/**
 * POST { fileId, width?, height?, date? } →
 * { driveFileId, kind, mimeType, width, height, src }
 *
 * Verifies the file sits in today's (or provided) GoldenMole Feed month folder,
 * shares it as anyone-with-link reader, and returns media descriptors for the feed post.
 */
export const POST = route(async (request) => {
  await requireStaff(request);
  const body = await readJson(request);
  const fileId = typeof body.fileId === 'string' ? body.fileId : '';
  if (!/^[A-Za-z0-9_-]{10,200}$/.test(fileId)) throw new HttpError('bad_request', 400);

  const date =
    typeof body.date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(body.date)
      ? body.date
      : todayInBangkok();

  const folderId = await ensureFeedMonthFolder(date);
  const file = await getFile(fileId);
  if (file.trashed || !file.parents?.includes(folderId)) throw new HttpError('wrong_folder', 400);

  const kind = mediaKindOf(file.mimeType);
  if (!kind) throw new HttpError('bad_type', 400);

  await shareWithAnyoneReader(file.id);
  const size = resolveSize(file, positiveInt(body.width), positiveInt(body.height));

  return json(
    {
      driveFileId: file.id,
      kind,
      mimeType: file.mimeType,
      width: size.width,
      height: size.height,
      src: mediaSources(file.id, kind),
    },
    201,
  );
});
