import { useCallback, useEffect, useRef, useState } from 'react';

export interface AsyncState<T> {
  data: T | undefined;
  error: string;
  loading: boolean;
  reload: () => Promise<void>;
  setData: (value: T) => void;
}

/** Last result per cache key, so revisiting a page shows its data at once while it refreshes. */
const cache = new Map<string, unknown>();

export function clearAsyncCache(): void {
  cache.clear();
}

/**
 * Runs `fn` on mount and whenever `deps` change; `reload` re-runs the latest `fn`.
 * With a `cacheKey`, the last result for the same key and deps is shown immediately and then refreshed.
 */
export function useAsync<T>(fn: () => Promise<T>, deps: unknown[], cacheKey?: string): AsyncState<T> {
  const key = cacheKey ? `${cacheKey}:${JSON.stringify(deps)}` : null;
  const [data, setDataState] = useState<T | undefined>(() => (key && cache.has(key) ? (cache.get(key) as T) : undefined));
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const seq = useRef(0);
  const fnRef = useRef(fn);
  const keyRef = useRef(key);

  useEffect(() => {
    fnRef.current = fn;
    keyRef.current = key;
  });

  const run = useCallback(async () => {
    const id = ++seq.current;
    const runKey = keyRef.current;
    setLoading(true);
    setError('');
    try {
      const result = await fnRef.current();
      if (runKey) cache.set(runKey, result);
      if (id === seq.current) setDataState(result);
    } catch (err) {
      if (id === seq.current) setError(err instanceof Error ? err.message : 'เกิดข้อผิดพลาด');
    } finally {
      if (id === seq.current) setLoading(false);
    }
  }, []);

  useEffect(() => {
    keyRef.current = key;
    if (key && cache.has(key)) setDataState(cache.get(key) as T);
    void run();
  }, deps);

  const setData = useCallback((value: T) => {
    if (keyRef.current) cache.set(keyRef.current, value);
    setDataState(value);
  }, []);

  return { data, error, loading, reload: run, setData };
}
