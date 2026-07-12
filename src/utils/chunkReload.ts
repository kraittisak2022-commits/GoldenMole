const CHUNK_RELOAD_KEY = 'cm_chunk_reload_v1';

const CHUNK_ERROR_RE =
    /Failed to fetch dynamically imported module|Importing a module script failed|error loading dynamically imported module/i;

export function isChunkLoadError(reason: unknown): boolean {
    const msg =
        reason instanceof Error
            ? `${reason.message} ${reason.name}`
            : typeof reason === 'string'
              ? reason
              : String(reason ?? '');
    return CHUNK_ERROR_RE.test(msg);
}

/** After a successful full page load, allow one more auto-reload on the next stale chunk. */
export function clearChunkReloadFlag() {
    try {
        sessionStorage.removeItem(CHUNK_RELOAD_KEY);
    } catch {
        /* ignore */
    }
}

/**
 * Reload once when a lazy Vite chunk 404s after deploy (stale index-*.js in tab/cache).
 * Returns true if a reload was triggered.
 */
export function reloadOnceForStaleChunk(reason: unknown): boolean {
    if (!isChunkLoadError(reason)) return false;
    try {
        if (sessionStorage.getItem(CHUNK_RELOAD_KEY)) return false;
        sessionStorage.setItem(CHUNK_RELOAD_KEY, '1');
    } catch {
        return false;
    }
    window.location.reload();
    return true;
}

export function setupChunkReloadRecovery() {
    window.addEventListener('unhandledrejection', (event) => {
        if (reloadOnceForStaleChunk(event.reason)) {
            event.preventDefault();
        }
    });

    window.addEventListener('load', () => {
        clearChunkReloadFlag();
    });
}
