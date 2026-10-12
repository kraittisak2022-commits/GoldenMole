import { randomBytes } from 'node:crypto';
import { requireEnv } from '../_lib/env.js';
import { buildAuthUrl } from '../_lib/google.js';
import { json, route } from '../_lib/http.js';
import { requireStaff } from '../_lib/session.js';
import { signToken } from '../_lib/token.js';

/** POST (SuperAdmin) → { url } of the Google consent screen. The signed state ties the callback to this admin. */
export const POST = route(async (request) => {
  const staff = await requireStaff(request, { superAdmin: true });
  const state = signToken(
    { typ: 'oauth', sub: staff.id, nonce: randomBytes(8).toString('hex'), exp: Date.now() + 10 * 60 * 1000 },
    requireEnv('PHOTO_SESSION_SECRET'),
  );
  return json({ url: buildAuthUrl(state) });
});
