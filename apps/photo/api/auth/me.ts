import { json, route } from '../_lib/http.js';
import { createSessionToken, requireStaff } from '../_lib/session.js';

/** GET → { user, token } for a valid session (token is a renewed session), 401/403 otherwise. */
export const GET = route(async (request) => {
  const user = await requireStaff(request);
  return json({ user, token: createSessionToken(user.id) });
});
