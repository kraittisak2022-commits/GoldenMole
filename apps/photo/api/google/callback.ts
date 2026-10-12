import { publicOrigin, requireEnv } from '../_lib/env.js';
import { forgetAccessToken } from '../_lib/drive.js';
import { exchangeCode } from '../_lib/google.js';
import { db, must } from '../_lib/supabaseAdmin.js';
import { verifyToken } from '../_lib/token.js';

const back = (result: 'connected' | 'denied' | 'error') =>
  new Response(null, { status: 302, headers: { Location: `${publicOrigin()}/settings?google=${result}`, 'Cache-Control': 'no-store' } });

/** Google redirects here after consent: stores the refresh token and returns to /settings. */
export async function GET(request: Request): Promise<Response> {
  try {
    const params = new URL(request.url).searchParams;
    if (params.get('error')) return back('denied');
    const state = verifyToken<{ typ: string; sub: string; exp: number }>(
      params.get('state') ?? '',
      requireEnv('PHOTO_SESSION_SECRET'),
    );
    const code = params.get('code');
    if (!state || state.typ !== 'oauth' || !code) return back('error');

    const admin = must(await db().from('admin_users').select('role').eq('id', state.sub).maybeSingle()) as {
      role: string;
    } | null;
    if (admin?.role !== 'SuperAdmin') return back('error');

    const { refreshToken, email } = await exchangeCode(code);
    const previous = must(await db().from('ph_settings').select('google_email').eq('id', 1).maybeSingle()) as {
      google_email: string | null;
    } | null;
    must(
      await db().from('ph_settings').upsert({
        id: 1,
        google_refresh_token: refreshToken,
        google_email: email,
        connected_at: new Date().toISOString(),
        connected_by: state.sub,
      }),
    );
    if (previous?.google_email && previous.google_email !== email) {
      must(await db().from('ph_drive_folders').delete().neq('path_key', ''));
    }
    forgetAccessToken();
    return back('connected');
  } catch (err) {
    console.error('Google callback failed', err);
    return back('error');
  }
}
