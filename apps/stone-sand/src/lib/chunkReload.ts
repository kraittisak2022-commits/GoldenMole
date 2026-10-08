const RELOAD_KEY = 'ss_chunk_reload_at';
/** A second failure within this window means reloading did not help; show the error instead of looping. */
const RELOAD_WINDOW_MS = 15_000;

const CHUNK_ERROR_PATTERNS = [
  'failed to fetch dynamically imported module',
  'error loading dynamically imported module',
  'importing a module script failed',
  'unable to preload css',
  'is not a valid javascript mime type',
  'expected a javascript module script',
];

/** True when a JS/CSS file of an older deploy could not be loaded (it no longer exists after a new deploy). */
export function isChunkLoadError(err: unknown): boolean {
  if (!err) return false;
  const name = (err as { name?: string }).name ?? '';
  const message = String((err as { message?: string }).message ?? err).toLowerCase();
  return name === 'ChunkLoadError' || CHUNK_ERROR_PATTERNS.some((p) => message.includes(p));
}

interface ReloadDeps {
  now?: number;
  storage?: Pick<Storage, 'getItem' | 'setItem'>;
  reload?: () => void;
}

/** Reloads the page to pick up the latest deploy, at most once per window. Returns whether it reloaded. */
export function reloadOnce({ now = Date.now(), storage, reload }: ReloadDeps = {}): boolean {
  const store = storage ?? safeSessionStorage();
  const last = Number(store?.getItem(RELOAD_KEY) || 0);
  if (last && now - last < RELOAD_WINDOW_MS) return false;
  try {
    store?.setItem(RELOAD_KEY, String(now));
  } catch {
    // private mode: still reload once
  }
  (reload ?? (() => window.location.reload()))();
  return true;
}

function safeSessionStorage(): Storage | null {
  try {
    return window.sessionStorage;
  } catch {
    return null;
  }
}

/** Wraps a dynamic import so a stale chunk reloads the page instead of breaking the app. */
export function retryImport<T>(factory: () => Promise<T>, deps?: ReloadDeps): () => Promise<T> {
  return () =>
    factory().catch((err: unknown) => {
      if (isChunkLoadError(err) && reloadOnce(deps)) return new Promise<T>(() => undefined);
      throw err;
    });
}
