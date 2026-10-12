import { publicOrigin, requireEnv } from './env.js';
import { HttpError } from './http.js';

const AUTH_URL = 'https://accounts.google.com/o/oauth2/v2/auth';
export const TOKEN_URL = 'https://oauth2.googleapis.com/token';
/** drive.file only reaches files this app created; it is a non-sensitive scope (no Google review). */
export const SCOPES = ['https://www.googleapis.com/auth/drive.file', 'openid', 'email'];

export const redirectUri = () => `${publicOrigin()}/api/google/callback`;

export function buildAuthUrl(state: string): string {
  const params = new URLSearchParams({
    client_id: requireEnv('GOOGLE_CLIENT_ID'),
    redirect_uri: redirectUri(),
    response_type: 'code',
    scope: SCOPES.join(' '),
    access_type: 'offline',
    prompt: 'consent',
    include_granted_scopes: 'true',
    state,
  });
  return `${AUTH_URL}?${params}`;
}

export interface CodeExchange {
  refreshToken: string;
  email: string | null;
}

/** The id_token comes straight from Google over TLS, so reading its payload without verifying is fine. */
export function emailFromIdToken(idToken: string | undefined): string | null {
  const payload = idToken?.split('.')[1];
  if (!payload) return null;
  try {
    const data = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as { email?: unknown };
    return typeof data.email === 'string' ? data.email : null;
  } catch {
    return null;
  }
}

export async function exchangeCode(code: string): Promise<CodeExchange> {
  const res = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      code,
      client_id: requireEnv('GOOGLE_CLIENT_ID'),
      client_secret: requireEnv('GOOGLE_CLIENT_SECRET'),
      redirect_uri: redirectUri(),
      grant_type: 'authorization_code',
    }),
  });
  const data = (await res.json().catch(() => ({}))) as { refresh_token?: string; id_token?: string; error?: string };
  if (!res.ok || !data.refresh_token) {
    console.error('Google code exchange failed', res.status, data.error);
    throw new HttpError('drive_error', 502);
  }
  return { refreshToken: data.refresh_token, email: emailFromIdToken(data.id_token) };
}

export async function refreshAccessToken(refreshToken: string): Promise<{ accessToken: string; expiresIn: number }> {
  const res = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      refresh_token: refreshToken,
      client_id: requireEnv('GOOGLE_CLIENT_ID'),
      client_secret: requireEnv('GOOGLE_CLIENT_SECRET'),
      grant_type: 'refresh_token',
    }),
  });
  const data = (await res.json().catch(() => ({}))) as { access_token?: string; expires_in?: number; error?: string };
  if (res.status === 400 || res.status === 401) {
    console.error('Google refresh token rejected', data.error);
    throw new HttpError('drive_not_connected', 503);
  }
  if (!res.ok || !data.access_token) throw new HttpError('drive_error', 502);
  return { accessToken: data.access_token, expiresIn: data.expires_in ?? 3600 };
}
