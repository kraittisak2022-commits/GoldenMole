import { existsSync, readdirSync } from 'node:fs';
import type { IncomingMessage, ServerResponse } from 'node:http';
import path from 'node:path';
import type { Plugin, ViteDevServer } from 'vite';
import { handleMock } from './mockApi';

type Handler = (request: Request) => Promise<Response> | Response;

/** Maps /api/a/b to api/a/b.ts, api/a/b/index.ts, or api/a/[param].ts — the same lookup Vercel does. */
export function resolveApiFile(apiDir: string, pathname: string): string | null {
  const segments = pathname.replace(/^\/api\/?/, '').split('/').filter(Boolean);
  const exact = path.join(apiDir, ...segments) + '.ts';
  if (existsSync(exact)) return exact;
  const index = path.join(apiDir, ...segments, 'index.ts');
  if (existsSync(index)) return index;
  if (segments.length === 0) return null;
  const dir = path.join(apiDir, ...segments.slice(0, -1));
  if (!existsSync(dir)) return null;
  const dynamic = readdirSync(dir).find((f) => /^\[[^\]]+\]\.ts$/.test(f));
  return dynamic ? path.join(dir, dynamic) : null;
}

async function toRequest(req: IncomingMessage, origin: string): Promise<Request> {
  const chunks: Buffer[] = [];
  for await (const chunk of req) chunks.push(chunk as Buffer);
  const headers = new Headers();
  for (const [key, value] of Object.entries(req.headers)) {
    if (Array.isArray(value)) value.forEach((v) => headers.append(key, v));
    else if (value !== undefined) headers.set(key, value);
  }
  const body = chunks.length && req.method !== 'GET' && req.method !== 'HEAD' ? Buffer.concat(chunks) : undefined;
  return new Request(new URL(req.url ?? '/', origin), { method: req.method, headers, body });
}

async function send(res: ServerResponse, response: Response): Promise<void> {
  res.statusCode = response.status;
  response.headers.forEach((value, key) => res.setHeader(key, value));
  res.end(Buffer.from(await response.arrayBuffer()));
}

/** Serves api/*.ts during `vite dev` (or an in-memory mock with PHOTO_MOCK_API=1). Vercel serves them in production. */
export function devApi({ mock }: { mock: boolean }): Plugin {
  let server: ViteDevServer;
  return {
    name: 'photo-dev-api',
    apply: 'serve',
    configureServer(s) {
      server = s;
      server.middlewares.use(async (req, res, next) => {
        if (!req.url?.startsWith('/api/')) return next();
        try {
          const request = await toRequest(req, `http://${req.headers.host ?? 'localhost'}`);
          if (mock) return await send(res, await handleMock(request));
          const file = resolveApiFile(path.resolve(server.config.root, 'api'), new URL(request.url).pathname);
          if (!file) return await send(res, new Response('Not found', { status: 404 }));
          const mod = (await server.ssrLoadModule(file)) as Record<string, Handler | undefined>;
          const handler = mod[req.method ?? 'GET'];
          if (!handler) return await send(res, new Response('Method not allowed', { status: 405 }));
          await send(res, await handler(request));
        } catch (err) {
          console.error(err);
          await send(res, new Response(JSON.stringify({ error: 'server_error' }), { status: 500 }));
        }
      });
    },
  };
}
