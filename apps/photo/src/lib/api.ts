import type { ApiErrorCode } from '../../shared/types';
import { clearSession, readSession } from './session';

export type ClientErrorCode = ApiErrorCode | 'network';

export class ApiError extends Error {
  constructor(
    readonly code: ClientErrorCode,
    readonly status: number,
  ) {
    super(code);
    this.name = 'ApiError';
  }
}

export const SIGNED_OUT_EVENT = 'photo:signed-out';

interface RequestOptions {
  method?: 'GET' | 'POST' | 'PATCH' | 'DELETE';
  body?: unknown;
  signal?: AbortSignal;
  headers?: Record<string, string>;
}

export async function api<T>(path: string, { method = 'GET', body, signal, headers: extra }: RequestOptions = {}): Promise<T> {
  const session = readSession();
  const headers: Record<string, string> = { ...extra };
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (session) headers.Authorization = `Bearer ${session.token}`;

  let res: Response;
  try {
    res = await fetch(path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), signal });
  } catch (err) {
    if ((err as Error).name === 'AbortError') throw err;
    throw new ApiError('network', 0);
  }
  const data = (await res.json().catch(() => null)) as (T & { error?: ApiErrorCode }) | null;
  if (!res.ok) {
    if (res.status === 401 && session) {
      clearSession();
      window.dispatchEvent(new Event(SIGNED_OUT_EVENT));
    }
    throw new ApiError(data?.error ?? 'server_error', res.status);
  }
  return data as T;
}

export const errorCode = (err: unknown): ClientErrorCode => (err instanceof ApiError ? err.code : 'server_error');
