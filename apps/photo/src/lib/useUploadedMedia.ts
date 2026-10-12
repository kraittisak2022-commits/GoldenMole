import { useEffect } from 'react';
import type { MediaItem, UploadTarget } from '../../shared/types';
import { useUploads } from '../components/uploads/UploadProvider';

/** Runs `onMedia` for every finished upload to this album while the page is open. */
export function useUploadedMedia(target: UploadTarget | null, onMedia: (media: MediaItem) => void) {
  const { subscribe } = useUploads();
  const key = target?.albumId ?? target?.shareToken ?? null;
  useEffect(() => {
    if (!target) return;
    return subscribe(target, onMedia);
  }, [key]);
}
