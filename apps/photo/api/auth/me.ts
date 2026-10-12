import { json, route } from '../_lib/http.js';
import { requireStaff } from '../_lib/session.js';

/** GET → { user } for a valid session, 401/403 otherwise. */
export const GET = route(async (request) => json({ user: await requireStaff(request) }));
