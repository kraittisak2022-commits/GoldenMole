import { isChunkLoadError, reloadOnce, retryImport } from './chunkReload';

const memoryStorage = () => {
  const data = new Map<string, string>();
  return { getItem: (k: string) => data.get(k) ?? null, setItem: (k: string, v: string) => void data.set(k, v) };
};

describe('isChunkLoadError', () => {
  it('recognises stale chunk errors from Chrome, Safari and Firefox', () => {
    expect(isChunkLoadError(new TypeError('Failed to fetch dynamically imported module: https://x/assets/NewOrderPage-abc.js'))).toBe(true);
    expect(isChunkLoadError(new TypeError('Importing a module script failed.'))).toBe(true);
    expect(isChunkLoadError(new TypeError('error loading dynamically imported module'))).toBe(true);
    expect(isChunkLoadError(new Error('Unable to preload CSS for /assets/index-abc.css'))).toBe(true);
  });

  it('ignores ordinary errors', () => {
    expect(isChunkLoadError(new Error('ไม่พบออเดอร์'))).toBe(false);
    expect(isChunkLoadError(null)).toBe(false);
  });
});

describe('reloadOnce', () => {
  it('reloads once, then refuses again within the window so it never loops', () => {
    const storage = memoryStorage();
    const reload = vi.fn();
    expect(reloadOnce({ now: 1_000, storage, reload })).toBe(true);
    expect(reloadOnce({ now: 5_000, storage, reload })).toBe(false);
    expect(reload).toHaveBeenCalledTimes(1);
    expect(reloadOnce({ now: 60_000, storage, reload })).toBe(true);
    expect(reload).toHaveBeenCalledTimes(2);
  });
});

describe('retryImport', () => {
  it('reloads the page on a stale chunk instead of rejecting', async () => {
    const reload = vi.fn();
    const load = retryImport(() => Promise.reject(new TypeError('Failed to fetch dynamically imported module')), {
      now: 1_000,
      storage: memoryStorage(),
      reload,
    });
    const result = await Promise.race([load().then(() => 'resolved', () => 'rejected'), new Promise((r) => setTimeout(() => r('pending'), 20))]);
    expect(result).toBe('pending');
    expect(reload).toHaveBeenCalledTimes(1);
  });

  it('rethrows other errors', async () => {
    const load = retryImport(() => Promise.reject(new Error('boom')), { storage: memoryStorage(), reload: vi.fn() });
    await expect(load()).rejects.toThrow('boom');
  });
});
