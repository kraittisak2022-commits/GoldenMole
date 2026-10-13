import { createContext, ReactNode, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { checkUpload, guessMimeType } from '../../../shared/limits';
import type { MediaItem, UploadTarget } from '../../../shared/types';
import { api } from '../../lib/api';
import { errorMessage, messageFor } from '../../lib/errors';
import { readFileMeta } from '../../lib/fileMeta';
import { UploadError, uploadResumable } from '../../lib/resumable';

export type UploadStatus = 'queued' | 'uploading' | 'done' | 'error' | 'canceled';

export interface UploadItem {
  id: string;
  file: File;
  mimeType: string;
  target: UploadTarget;
  uploaderName: string | null;
  status: UploadStatus;
  progress: number;
  error: string | null;
}

interface UploadsValue {
  items: UploadItem[];
  enqueue: (files: File[], target: UploadTarget, uploaderName?: string | null) => void;
  retry: (id: string) => void;
  cancel: (id: string) => void;
  clearFinished: () => void;
  /** Called with each media item once its upload to `target` completes. Returns an unsubscribe. */
  subscribe: (target: UploadTarget, onMedia: (media: MediaItem) => void) => () => void;
}

const CONCURRENCY = 3;
const UploadsContext = createContext<UploadsValue | null>(null);

const targetKey = (t: UploadTarget) => (t.albumId ? `a:${t.albumId}` : `s:${t.shareToken}`);
let seq = 0;

export function UploadProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<UploadItem[]>([]);
  const controllers = useRef(new Map<string, AbortController>());
  const listeners = useRef(new Map<string, Set<(media: MediaItem) => void>>());

  const update = (id: string, patch: Partial<UploadItem>) =>
    setItems((list) => list.map((i) => (i.id === id ? { ...i, ...patch } : i)));

  const run = async (item: UploadItem) => {
    const ctrl = new AbortController();
    controllers.current.set(item.id, ctrl);
    update(item.id, { status: 'uploading', progress: 0, error: null });
    try {
      const meta = await readFileMeta(item.file, item.mimeType);
      const { uploadUrl } = await api<{ uploadUrl: string }>('/api/uploads/start', {
        method: 'POST',
        body: { ...item.target, name: item.file.name, mimeType: item.mimeType, size: item.file.size },
        signal: ctrl.signal,
      });
      let shown = 0;
      const driveFile = await uploadResumable(item.file, uploadUrl, {
        signal: ctrl.signal,
        onProgress: (sent) => {
          const progress = sent / item.file.size;
          if (progress - shown >= 0.01 || progress === 1) {
            shown = progress;
            update(item.id, { progress });
          }
        },
      });
      const media = await api<MediaItem>('/api/uploads/complete', {
        method: 'POST',
        body: {
          ...item.target,
          fileId: driveFile.id,
          width: meta.width,
          height: meta.height,
          takenAt: meta.takenAt,
          uploaderName: item.uploaderName,
        },
      });
      update(item.id, { status: 'done', progress: 1 });
      listeners.current.get(targetKey(item.target))?.forEach((cb) => cb(media));
    } catch (err) {
      const code = err instanceof UploadError ? err.code : null;
      if (ctrl.signal.aborted || code === 'canceled') {
        update(item.id, { status: 'canceled' });
      } else {
        update(item.id, { status: 'error', error: code ? messageFor(code) : errorMessage(err) });
      }
    } finally {
      controllers.current.delete(item.id);
    }
  };

  useEffect(() => {
    const active = items.filter((i) => i.status === 'uploading').length;
    items
      .filter((i) => i.status === 'queued')
      .slice(0, Math.max(0, CONCURRENCY - active))
      .forEach((item) => void run(item));
  }, [items]);

  const busy = items.some((i) => i.status === 'queued' || i.status === 'uploading');
  useEffect(() => {
    if (!busy) return;
    const warn = (e: BeforeUnloadEvent) => {
      e.preventDefault();
      e.returnValue = '';
    };
    window.addEventListener('beforeunload', warn);
    return () => window.removeEventListener('beforeunload', warn);
  }, [busy]);

  // Phones suspend the page when the screen turns off, which stalls uploads; keep it awake meanwhile.
  useEffect(() => {
    if (!busy || !('wakeLock' in navigator)) return;
    let lock: WakeLockSentinel | null = null;
    let stopped = false;
    const acquire = () => {
      if (document.visibilityState !== 'visible' || lock) return;
      navigator.wakeLock
        .request('screen')
        .then((sentinel) => {
          if (stopped) return void sentinel.release();
          lock = sentinel;
          sentinel.addEventListener('release', () => {
            lock = null;
          });
        })
        .catch(() => undefined);
    };
    acquire();
    document.addEventListener('visibilitychange', acquire);
    return () => {
      stopped = true;
      document.removeEventListener('visibilitychange', acquire);
      void lock?.release();
    };
  }, [busy]);

  const enqueue = useCallback((files: File[], target: UploadTarget, uploaderName: string | null = null) => {
    const added = files.map<UploadItem>((file) => {
      const mimeType = guessMimeType(file.name, file.type);
      const check = checkUpload({ mimeType, size: file.size });
      return {
        id: `u${++seq}`,
        file,
        mimeType,
        target,
        uploaderName,
        status: check.ok ? 'queued' : 'error',
        progress: 0,
        error: check.ok ? null : messageFor(check.error),
      };
    });
    setItems((list) => [...list, ...added]);
  }, []);

  const retry = useCallback((id: string) => update(id, { status: 'queued', progress: 0, error: null }), []);
  const cancel = useCallback((id: string) => {
    const ctrl = controllers.current.get(id);
    if (ctrl) ctrl.abort();
    else update(id, { status: 'canceled' });
  }, []);
  const clearFinished = useCallback(
    () => setItems((list) => list.filter((i) => i.status === 'queued' || i.status === 'uploading')),
    [],
  );
  const subscribe = useCallback((target: UploadTarget, onMedia: (media: MediaItem) => void) => {
    const key = targetKey(target);
    const set = listeners.current.get(key) ?? new Set();
    set.add(onMedia);
    listeners.current.set(key, set);
    return () => set.delete(onMedia);
  }, []);

  const value = useMemo(
    () => ({ items, enqueue, retry, cancel, clearFinished, subscribe }),
    [items, enqueue, retry, cancel, clearFinished, subscribe],
  );
  return <UploadsContext.Provider value={value}>{children}</UploadsContext.Provider>;
}

export function useUploads(): UploadsValue {
  const ctx = useContext(UploadsContext);
  if (!ctx) throw new Error('useUploads outside UploadProvider');
  return ctx;
}
