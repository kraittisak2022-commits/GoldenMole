import { mediaKindOf } from '../../shared/limits';
import { readExifDate } from './exif';

export interface FileMeta {
  width: number;
  height: number;
  takenAt: string | null;
}

const EXIF_SCAN_BYTES = 128 * 1024;

function imageSize(file: File): Promise<{ width: number; height: number }> {
  return new Promise((resolve) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      resolve({ width: img.naturalWidth, height: img.naturalHeight });
      URL.revokeObjectURL(url);
    };
    img.onerror = () => {
      resolve({ width: 0, height: 0 });
      URL.revokeObjectURL(url);
    };
    img.src = url;
  });
}

function videoSize(file: File): Promise<{ width: number; height: number }> {
  return new Promise((resolve) => {
    const url = URL.createObjectURL(file);
    const video = document.createElement('video');
    const done = (size: { width: number; height: number }) => {
      clearTimeout(timer);
      resolve(size);
      URL.revokeObjectURL(url);
    };
    const timer = setTimeout(() => done({ width: 0, height: 0 }), 8000);
    video.preload = 'metadata';
    video.muted = true;
    video.onloadedmetadata = () => done({ width: video.videoWidth, height: video.videoHeight });
    video.onerror = () => done({ width: 0, height: 0 });
    video.src = url;
  });
}

/**
 * Size (so the grid can lay out before thumbnails exist) and capture time. Formats the browser
 * cannot decode (HEIC on most browsers) return 0×0 and the server falls back to Drive's metadata.
 */
export async function readFileMeta(file: File, mimeType: string): Promise<FileMeta> {
  const kind = mediaKindOf(mimeType);
  if (kind === 'video') {
    const size = await videoSize(file);
    return { ...size, takenAt: file.lastModified ? new Date(file.lastModified).toISOString() : null };
  }
  const [size, takenAt] = await Promise.all([
    imageSize(file),
    /jpe?g$/i.test(mimeType)
      ? file
          .slice(0, EXIF_SCAN_BYTES)
          .arrayBuffer()
          .then(readExifDate)
          .catch(() => null)
      : Promise.resolve(null),
  ]);
  return { ...size, takenAt: takenAt ?? (file.lastModified ? new Date(file.lastModified).toISOString() : null) };
}
