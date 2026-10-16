import {
  FEED_PATH_PREFIX,
  FEED_ROOT_FOLDER_NAME,
  folderPath,
  ROOT_FOLDER_NAME,
} from '../../shared/folderPath.js';
import { refreshAccessToken } from './google.js';
import { HttpError } from './http.js';
import { db, must } from './supabaseAdmin.js';

const DRIVE = 'https://www.googleapis.com/drive/v3';
const UPLOAD = 'https://www.googleapis.com/upload/drive/v3';
const FOLDER_MIME = 'application/vnd.google-apps.folder';

export interface DriveFile {
  id: string;
  name: string;
  mimeType: string;
  size?: string;
  parents?: string[];
  trashed?: boolean;
  imageMediaMetadata?: { width?: number; height?: number; rotation?: number };
  videoMediaMetadata?: { width?: number; height?: number };
}

let cachedToken: { refreshToken: string; accessToken: string; expiresAt: number } | null = null;

export async function loadRefreshToken(): Promise<string> {
  const row = must(await db().from('ph_settings').select('google_refresh_token').eq('id', 1).maybeSingle()) as {
    google_refresh_token: string | null;
  } | null;
  if (!row?.google_refresh_token) throw new HttpError('drive_not_connected', 503);
  return row.google_refresh_token;
}

export async function getAccessToken(now = Date.now()): Promise<string> {
  const refreshToken = await loadRefreshToken();
  if (cachedToken && cachedToken.refreshToken === refreshToken && cachedToken.expiresAt - 60_000 > now) {
    return cachedToken.accessToken;
  }
  const { accessToken, expiresIn } = await refreshAccessToken(refreshToken);
  cachedToken = { refreshToken, accessToken, expiresAt: now + expiresIn * 1000 };
  return accessToken;
}

export function forgetAccessToken(): void {
  cachedToken = null;
}

async function driveFetch(url: string, init: RequestInit = {}): Promise<Response> {
  const send = async () => {
    const headers = new Headers(init.headers);
    headers.set('Authorization', `Bearer ${await getAccessToken()}`);
    if (init.body && !headers.has('Content-Type')) headers.set('Content-Type', 'application/json');
    return fetch(url, { ...init, headers });
  };
  let res = await send();
  // A cached access token can be revoked early; only a 401 with a freshly refreshed one means Drive is disconnected.
  if (res.status === 401) {
    forgetAccessToken();
    res = await send();
  }
  if (res.status === 401) {
    forgetAccessToken();
    throw new HttpError('drive_not_connected', 503);
  }
  if (res.status === 404) throw new HttpError('not_found', 404);
  if (!res.ok) {
    console.error('Drive error', res.status, await res.text().catch(() => ''));
    throw new HttpError('drive_error', 502);
  }
  return res;
}

export async function createFolder(name: string, parentId?: string): Promise<string> {
  const res = await driveFetch(`${DRIVE}/files?fields=id&supportsAllDrives=true`, {
    method: 'POST',
    body: JSON.stringify({ name, mimeType: FOLDER_MIME, ...(parentId ? { parents: [parentId] } : {}) }),
  });
  return ((await res.json()) as { id: string }).id;
}

/** Cached folder id for a path key, creating the folder once (a concurrent creator wins; ours is trashed). */
async function ensureFolder(key: string, name: string, parentId?: string): Promise<string> {
  const found = must(await db().from('ph_drive_folders').select('folder_id').eq('path_key', key).maybeSingle()) as {
    folder_id: string;
  } | null;
  if (found) return found.folder_id;
  const created = await createFolder(name, parentId);
  const inserted = must(
    await db()
      .from('ph_drive_folders')
      .upsert({ path_key: key, folder_id: created }, { onConflict: 'path_key', ignoreDuplicates: true })
      .select('folder_id'),
  ) as { folder_id: string }[];
  if (inserted.length) return created;
  await trashFile(created).catch(() => undefined);
  const winner = must(await db().from('ph_drive_folders').select('folder_id').eq('path_key', key).single()) as {
    folder_id: string;
  };
  return winner.folder_id;
}

async function ensureMonthFolder(
  reportDate: string,
  rootName: string,
  pathPrefix: string | null,
): Promise<string> {
  const [year, month] = folderPath(reportDate);
  const rootKey = pathPrefix ? `${pathPrefix}/root` : 'root';
  const yearKey = pathPrefix ? `${pathPrefix}/${year.key}` : year.key;
  const monthKey = pathPrefix ? `${pathPrefix}/${month.key}` : month.key;
  const root = await ensureFolder(rootKey, rootName);
  const yearId = await ensureFolder(yearKey, year.name, root);
  return ensureFolder(monthKey, month.name, yearId);
}

const isNotFound = (err: unknown) => err instanceof HttpError && err.code === 'not_found';

/**
 * Runs `withFolder` with the month folder for a report date. When a cached folder was deleted in Drive,
 * the year/month cache is dropped and rebuilt; if that still fails, the root is rebuilt too.
 */
async function monthFolderForRoot(
  reportDate: string,
  rootName: string,
  pathPrefix: string | null,
  withFolder: (folderId: string) => Promise<string>,
): Promise<string> {
  const [year, month] = folderPath(reportDate);
  const rootKey = pathPrefix ? `${pathPrefix}/root` : 'root';
  const yearKey = pathPrefix ? `${pathPrefix}/${year.key}` : year.key;
  const monthKey = pathPrefix ? `${pathPrefix}/${month.key}` : month.key;
  const yearLike = pathPrefix ? `${pathPrefix}/${year.key}%` : `${year.key}%`;

  try {
    return await withFolder(await ensureMonthFolder(reportDate, rootName, pathPrefix));
  } catch (err) {
    if (!isNotFound(err)) throw err;
  }
  must(await db().from('ph_drive_folders').delete().in('path_key', [yearKey, monthKey]));
  try {
    return await withFolder(await ensureMonthFolder(reportDate, rootName, pathPrefix));
  } catch (err) {
    if (!isNotFound(err)) throw err;
  }
  must(await db().from('ph_drive_folders').delete().like('path_key', yearLike));
  must(await db().from('ph_drive_folders').delete().eq('path_key', rootKey));
  return withFolder(await ensureMonthFolder(reportDate, rootName, pathPrefix));
}

export async function monthFolderFor(
  reportDate: string,
  withFolder: (folderId: string) => Promise<string>,
): Promise<string> {
  return monthFolderForRoot(reportDate, ROOT_FOLDER_NAME, null, withFolder);
}

/** Month folder under `GoldenMole Feed / <พ.ศ.> / <MM-เดือน>`. */
export async function feedMonthFolderFor(
  reportDate: string,
  withFolder: (folderId: string) => Promise<string>,
): Promise<string> {
  return monthFolderForRoot(reportDate, FEED_ROOT_FOLDER_NAME, FEED_PATH_PREFIX, withFolder);
}

/** Resolves (and caches) today's feed month folder id. */
export async function ensureFeedMonthFolder(reportDate: string): Promise<string> {
  return feedMonthFolderFor(reportDate, async (id) => id);
}

export async function shareWithAnyoneReader(fileId: string): Promise<void> {
  await driveFetch(`${DRIVE}/files/${encodeURIComponent(fileId)}/permissions?supportsAllDrives=true`, {
    method: 'POST',
    body: JSON.stringify({ role: 'reader', type: 'anyone', allowFileDiscovery: false }),
  });
}

/** `GoldenMole Photos/<year>/<month>/<title>`, readable by anyone with the link. */
export async function createAlbumFolder(title: string, reportDate: string): Promise<string> {
  const folderId = await monthFolderFor(reportDate, (monthId) => createFolder(title, monthId));
  await shareWithAnyoneReader(folderId);
  return folderId;
}

export async function getFile(fileId: string): Promise<DriveFile> {
  const fields = 'id,name,mimeType,size,parents,trashed,imageMediaMetadata(width,height,rotation),videoMediaMetadata(width,height)';
  const res = await driveFetch(`${DRIVE}/files/${encodeURIComponent(fileId)}?fields=${fields}&supportsAllDrives=true`);
  return (await res.json()) as DriveFile;
}

export async function renameFile(fileId: string, name: string): Promise<void> {
  await driveFetch(`${DRIVE}/files/${encodeURIComponent(fileId)}?supportsAllDrives=true`, {
    method: 'PATCH',
    body: JSON.stringify({ name }),
  });
}

export async function moveAlbumFolder(folderId: string, reportDate: string): Promise<void> {
  const current = await getFile(folderId);
  await monthFolderFor(reportDate, async (monthId) => {
    if (current.parents?.includes(monthId)) return monthId;
    const params = new URLSearchParams({ addParents: monthId, removeParents: (current.parents ?? []).join(','), supportsAllDrives: 'true' });
    await driveFetch(`${DRIVE}/files/${encodeURIComponent(folderId)}?${params}`, { method: 'PATCH', body: '{}' });
    return monthId;
  });
}

export async function trashFile(fileId: string): Promise<void> {
  await driveFetch(`${DRIVE}/files/${encodeURIComponent(fileId)}?supportsAllDrives=true`, {
    method: 'PATCH',
    body: JSON.stringify({ trashed: true }),
  });
}

/** Resumable upload session URL. The browser PUTs the bytes to it directly; `origin` enables CORS on it. */
export async function startResumableUpload(args: {
  name: string;
  mimeType: string;
  size: number;
  parentId: string;
  origin: string;
}): Promise<string> {
  const res = await driveFetch(`${UPLOAD}/files?uploadType=resumable&supportsAllDrives=true&fields=id,name,mimeType,size,parents`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json; charset=UTF-8',
      'X-Upload-Content-Type': args.mimeType,
      'X-Upload-Content-Length': String(args.size),
      Origin: args.origin,
    },
    body: JSON.stringify({ name: args.name, mimeType: args.mimeType, parents: [args.parentId] }),
  });
  const location = res.headers.get('location');
  if (!location) throw new HttpError('drive_error', 502);
  return location;
}
