import type { ApiErrorCode } from '../../shared/types.js';

export class HttpError extends Error {
  constructor(
    readonly code: ApiErrorCode,
    readonly status: number,
    message?: string,
  ) {
    super(message ?? code);
    this.name = 'HttpError';
  }
}

export const json = (body: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', ...headers },
  });

export const errorResponse = (code: ApiErrorCode, status: number) => json({ error: code }, status);

export async function readJson(request: Request): Promise<Record<string, unknown>> {
  try {
    const body = await request.json();
    if (body && typeof body === 'object' && !Array.isArray(body)) return body as Record<string, unknown>;
  } catch {
    // fall through
  }
  throw new HttpError('bad_request', 400);
}

/** Turns thrown HttpErrors into JSON error responses; anything else is logged and becomes a 500. */
export function route(handler: (request: Request) => Promise<Response>) {
  return async (request: Request): Promise<Response> => {
    try {
      return await handler(request);
    } catch (err) {
      if (err instanceof HttpError) return errorResponse(err.code, err.status);
      console.error(err);
      return errorResponse('server_error', 500);
    }
  };
}

/** Last path segment, for files named api/<x>/[id].ts. */
export function lastSegment(request: Request): string {
  const parts = new URL(request.url).pathname.split('/').filter(Boolean);
  return decodeURIComponent(parts[parts.length - 1] ?? '');
}
