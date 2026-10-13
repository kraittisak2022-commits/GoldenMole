import { HttpError } from './http.js';

type EnvName =
  | 'SUPABASE_URL'
  | 'SUPABASE_SERVICE_ROLE_KEY'
  | 'GOOGLE_CLIENT_ID'
  | 'GOOGLE_CLIENT_SECRET'
  | 'PHOTO_SESSION_SECRET'
  | 'PHOTO_ALBUM_PIN'
  | 'PUBLIC_ORIGIN';

export function requireEnv(name: EnvName): string {
  const value = process.env[name]?.trim();
  if (!value) {
    console.error(`Missing environment variable ${name}`);
    throw new HttpError('not_configured', 503);
  }
  // Keys, secrets and URLs are plain ASCII without spaces; anything else is a pasted label, not the value.
  if (!/^[\x21-\x7e]+$/.test(value)) {
    console.error(`Environment variable ${name} contains spaces or non-ASCII characters; paste the value itself`);
    throw new HttpError('not_configured', 503);
  }
  return value;
}

export function publicOrigin(): string {
  return (process.env.PUBLIC_ORIGIN?.trim() || 'https://photo.goldenmole.pro').replace(/\/+$/, '');
}

/**
 * Origin given to Drive for the resumable upload's CORS. The browser's own origin when it is ours
 * (production, ALLOWED_ORIGINS, or localhost outside production), otherwise the public origin.
 */
export function uploadOrigin(request: Request): string {
  const origin = request.headers.get('origin')?.replace(/\/+$/, '') ?? '';
  const main = publicOrigin();
  if (!origin || origin === main) return main;
  const extra = (process.env.ALLOWED_ORIGINS ?? '')
    .split(',')
    .map((s) => s.trim().replace(/\/+$/, ''))
    .filter(Boolean);
  if (extra.includes(origin)) return origin;
  if (process.env.VERCEL_ENV !== 'production' && /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(origin)) return origin;
  return main;
}
