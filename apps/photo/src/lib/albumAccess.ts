import type { UploadTarget } from '../../shared/types';
import { tokenExpiresAt } from './session';

/** Per share link, the token the server gave back for a correct PIN. */
const KEY = 'photo_album_access_v1';

function readAll(): Record<string, string> {
  try {
    const parsed = JSON.parse(localStorage.getItem(KEY) ?? '{}') as unknown;
    return parsed && typeof parsed === 'object' ? (parsed as Record<string, string>) : {};
  } catch {
    return {};
  }
}

function writeAll(all: Record<string, string>) {
  const now = Date.now();
  const live = Object.fromEntries(Object.entries(all).filter(([, token]) => tokenExpiresAt(token) > now));
  try {
    localStorage.setItem(KEY, JSON.stringify(live));
  } catch {
    // private mode: the PIN lasts for this tab only
  }
}

export function readAlbumAccess(shareToken: string): string | null {
  const token = readAll()[shareToken];
  return token && tokenExpiresAt(token) > Date.now() ? token : null;
}

export function saveAlbumAccess(shareToken: string, access: string): void {
  writeAll({ ...readAll(), [shareToken]: access });
}

export function clearAlbumAccess(shareToken: string): void {
  const all = readAll();
  delete all[shareToken];
  writeAll(all);
}

/** Header that proves the PIN was entered, for requests made through a share link. */
export function albumAccessHeaders(target: Pick<UploadTarget, 'shareToken'> | string): Record<string, string> {
  const shareToken = typeof target === 'string' ? target : target.shareToken;
  const access = shareToken ? readAlbumAccess(shareToken) : null;
  return access ? { 'X-Album-Access': access } : {};
}
