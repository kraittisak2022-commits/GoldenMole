import type { MediaKind } from './types';

export const MAX_IMAGE_BYTES = 50 * 1024 * 1024;
export const MAX_VIDEO_BYTES = 2 * 1024 * 1024 * 1024;
/** Uploads through the share link, per album, per rolling hour. Staff uploads are not counted. */
export const LINK_UPLOADS_PER_HOUR = 300;
export const MAX_TITLE_LENGTH = 200;
export const MAX_UPLOADER_NAME_LENGTH = 60;

export type UploadCheck =
  | { ok: true; kind: MediaKind }
  | { ok: false; error: 'bad_type' | 'too_large' | 'empty_file' };

export function mediaKindOf(mimeType: string): MediaKind | null {
  const mime = mimeType.toLowerCase();
  if (mime.startsWith('image/')) return 'image';
  if (mime.startsWith('video/')) return 'video';
  return null;
}

const MIME_BY_EXTENSION: Record<string, string> = {
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  png: 'image/png',
  gif: 'image/gif',
  webp: 'image/webp',
  avif: 'image/avif',
  heic: 'image/heic',
  heif: 'image/heif',
  mp4: 'video/mp4',
  m4v: 'video/x-m4v',
  mov: 'video/quicktime',
  webm: 'video/webm',
  mkv: 'video/x-matroska',
  '3gp': 'video/3gpp',
  avi: 'video/x-msvideo',
};

/** Browsers leave `type` empty for some formats (HEIC on Windows, MKV); fall back to the extension. */
export function guessMimeType(name: string, type: string): string {
  if (type) return type;
  const ext = name.split('.').pop()?.toLowerCase() ?? '';
  return MIME_BY_EXTENSION[ext] ?? '';
}

export function checkUpload(file: { mimeType: string; size: number }): UploadCheck {
  const kind = mediaKindOf(file.mimeType || '');
  if (!kind) return { ok: false, error: 'bad_type' };
  if (!Number.isFinite(file.size) || file.size <= 0) return { ok: false, error: 'empty_file' };
  const max = kind === 'image' ? MAX_IMAGE_BYTES : MAX_VIDEO_BYTES;
  if (file.size > max) return { ok: false, error: 'too_large' };
  return { ok: true, kind };
}

/** Collapses whitespace; returns null when empty or too long. */
export function normalizeTitle(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  const title = raw.normalize('NFC').replace(/\s+/g, ' ').trim();
  if (!title || title.length > MAX_TITLE_LENGTH) return null;
  return title;
}

export const MAX_FILE_NAME_LENGTH = 200;

/** "IMG_1.JPG" → ["IMG_1", ".JPG"]; a name without an extension keeps an empty one. */
export function splitExtension(name: string): [string, string] {
  const m = /^(.+?)(\.[A-Za-z0-9]{1,8})$/.exec(name);
  return m ? [m[1], m[2]] : [name, ''];
}

/** New name for an existing file: cleaned, and always ending in the original extension so downloads keep their type. */
export function renamedFileName(raw: unknown, original: string): string | null {
  if (typeof raw !== 'string') return null;
  const [, ext] = splitExtension(original);
  let base = raw.normalize('NFC').replace(/[\u0000-\u001f\u007f]/g, '').replace(/\s+/g, ' ').trim();
  if (ext && base.toLowerCase().endsWith(ext.toLowerCase())) base = base.slice(0, -ext.length).trim();
  if (!base) return null;
  return base.slice(0, MAX_FILE_NAME_LENGTH - ext.length) + ext;
}

export function normalizeUploaderName(raw: unknown): string | null {
  if (typeof raw !== 'string') return null;
  const name = raw.normalize('NFC').replace(/\s+/g, ' ').trim().slice(0, MAX_UPLOADER_NAME_LENGTH);
  return name || null;
}
