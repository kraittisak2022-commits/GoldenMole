/** Drive requires chunk sizes in multiples of 256 KiB (except the last chunk). */
export const CHUNK_SIZE = 32 * 256 * 1024;
const MAX_RETRIES = 6;

export class UploadError extends Error {
  constructor(readonly code: 'upload_expired' | 'upload_failed' | 'canceled') {
    super(code);
    this.name = 'UploadError';
  }
}

/** `bytes=0-1048575` → 1048576 (next byte to send); no header → nothing committed yet. */
export function nextOffsetFromRange(range: string | null): number {
  const m = range ? /bytes=(\d+)-(\d+)/.exec(range) : null;
  return m ? Number(m[2]) + 1 : 0;
}

export const retryDelayMs = (attempt: number) => Math.min(1000 * 2 ** attempt, 30_000);

interface PutResult {
  status: number;
  body: string;
  range: string | null;
}

function put(url: string, body: Blob | null, contentRange: string, onProgress: (loaded: number) => void, signal: AbortSignal): Promise<PutResult> {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    const abort = () => xhr.abort();
    xhr.open('PUT', url);
    xhr.setRequestHeader('Content-Range', contentRange);
    xhr.upload.onprogress = (e) => onProgress(e.loaded);
    xhr.onload = () => {
      signal.removeEventListener('abort', abort);
      resolve({ status: xhr.status, body: xhr.responseText, range: xhr.getResponseHeader('Range') });
    };
    xhr.onerror = () => {
      signal.removeEventListener('abort', abort);
      resolve({ status: 0, body: '', range: null });
    };
    xhr.onabort = () => {
      signal.removeEventListener('abort', abort);
      reject(new UploadError('canceled'));
    };
    signal.addEventListener('abort', abort);
    xhr.send(body);
  });
}

const sleep = (ms: number, signal: AbortSignal) =>
  new Promise<void>((resolve, reject) => {
    const t = setTimeout(resolve, ms);
    signal.addEventListener('abort', () => {
      clearTimeout(t);
      reject(new UploadError('canceled'));
    });
  });

const isDone = (status: number) => status === 200 || status === 201;
const isRetryable = (status: number) => status === 0 || status === 429 || status >= 500;

/**
 * Sends `file` to a Drive resumable session in chunks. After a network error or 5xx it asks Drive
 * how much it already has (`bytes *\/total`) and continues from there. Resolves with the Drive file.
 */
export async function uploadResumable(
  file: Blob,
  url: string,
  { onProgress, signal, chunkSize = CHUNK_SIZE }: { onProgress: (sent: number) => void; signal: AbortSignal; chunkSize?: number },
): Promise<{ id: string }> {
  const total = file.size;
  let offset = 0;
  let attempt = 0;

  while (true) {
    if (signal.aborted) throw new UploadError('canceled');
    const end = Math.min(offset + chunkSize, total);
    const res = await put(url, file.slice(offset, end), `bytes ${offset}-${end - 1}/${total}`, (loaded) => onProgress(offset + loaded), signal);

    if (isDone(res.status)) {
      onProgress(total);
      return JSON.parse(res.body) as { id: string };
    }
    if (res.status === 308) {
      offset = res.range ? nextOffsetFromRange(res.range) : end;
      attempt = 0;
      continue;
    }
    if (res.status === 404 || res.status === 410) throw new UploadError('upload_expired');
    if (!isRetryable(res.status) || attempt >= MAX_RETRIES) throw new UploadError('upload_failed');

    await sleep(retryDelayMs(attempt++), signal);
    const status = await put(url, null, `bytes */${total}`, () => undefined, signal);
    if (isDone(status.status)) {
      onProgress(total);
      return JSON.parse(status.body) as { id: string };
    }
    if (status.status === 404 || status.status === 410) throw new UploadError('upload_expired');
    if (status.status === 308) offset = nextOffsetFromRange(status.range);
  }
}
