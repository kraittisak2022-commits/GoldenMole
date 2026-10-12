import type { MediaKind, MediaSources } from './types';

/** These URLs only work because album folders are shared "anyone with the link: reader". */
export function mediaSources(driveFileId: string, kind: MediaKind): MediaSources {
  const id = encodeURIComponent(driveFileId);
  return {
    thumb: `https://lh3.googleusercontent.com/d/${id}=s640`,
    thumbFallback: `https://drive.google.com/thumbnail?id=${id}&sz=w640`,
    large: `https://lh3.googleusercontent.com/d/${id}=s2048`,
    download: `https://drive.google.com/uc?export=download&id=${id}`,
    preview: kind === 'video' ? `https://drive.google.com/file/d/${id}/preview` : null,
  };
}

export function driveFolderUrl(folderId: string): string {
  return `https://drive.google.com/drive/folders/${encodeURIComponent(folderId)}`;
}
