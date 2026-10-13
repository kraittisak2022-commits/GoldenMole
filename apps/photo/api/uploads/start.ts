import { checkUpload, LINK_UPLOADS_PER_HOUR } from '../../shared/limits.js';
import { readTarget, resolveUploadTarget } from '../_lib/albums.js';
import { beginAttempt } from '../_lib/attempts.js';
import { startResumableUpload } from '../_lib/drive.js';
import { uploadOrigin } from '../_lib/env.js';
import { HttpError, json, readJson, route } from '../_lib/http.js';

/** Drive rejects names with control characters; keep the name readable and bounded. */
export function cleanFileName(raw: unknown): string {
  const name = typeof raw === 'string' ? raw.replace(/[\u0000-\u001f\u007f]/g, '').trim() : '';
  return (name || 'file').slice(0, 200);
}

/** POST { albumId | shareToken, name, mimeType, size } → { uploadUrl } (a Drive resumable session). */
export const POST = route(async (request) => {
  const body = await readJson(request);
  const { album, staff } = await resolveUploadTarget(request, readTarget(body));

  const mimeType = typeof body.mimeType === 'string' ? body.mimeType : '';
  const size = typeof body.size === 'number' ? body.size : NaN;
  const check = checkUpload({ mimeType, size });
  if (!check.ok) throw new HttpError(check.error, 400);

  // Counted when the upload starts, not when it completes, so uploads that never call `complete` still count.
  if (!staff) {
    await beginAttempt([{ scope: 'link_upload', key: album.id, max: LINK_UPLOADS_PER_HOUR, windowMs: 3600_000 }], {
      error: 'rate_limited',
    });
  }

  const uploadUrl = await startResumableUpload({
    name: cleanFileName(body.name),
    mimeType,
    size,
    parentId: album.drive_folder_id,
    origin: uploadOrigin(request),
  });
  return json({ uploadUrl });
});
