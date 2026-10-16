import { checkUpload } from '../../../shared/limits.js';
import { todayInBangkok } from '../../../shared/folderPath.js';
import { ensureFeedMonthFolder, startResumableUpload } from '../../_lib/drive.js';
import { uploadOrigin } from '../../_lib/env.js';
import { HttpError, json, readJson, route } from '../../_lib/http.js';
import { requireStaff } from '../../_lib/session.js';
import { cleanFileName } from '../../uploads/start.js';

/** POST { name, mimeType, size, date? } → { uploadUrl } — staff-only feed media upload. */
export const POST = route(async (request) => {
  await requireStaff(request);

  const body = await readJson(request);
  const mimeType = typeof body.mimeType === 'string' ? body.mimeType : '';
  const size = typeof body.size === 'number' ? body.size : NaN;
  const check = checkUpload({ mimeType, size });
  if (!check.ok) throw new HttpError(check.error, 400);

  const date =
    typeof body.date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(body.date)
      ? body.date
      : todayInBangkok();

  const parentId = await ensureFeedMonthFolder(date);
  const uploadUrl = await startResumableUpload({
    name: cleanFileName(body.name),
    mimeType,
    size,
    parentId,
    origin: uploadOrigin(request),
  });
  return json({ uploadUrl });
});
