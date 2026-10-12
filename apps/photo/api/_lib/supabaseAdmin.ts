import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { requireEnv } from './env.js';
import { HttpError } from './http.js';

let client: SupabaseClient | null = null;

export function db(): SupabaseClient {
  if (!client) {
    client = createClient(requireEnv('SUPABASE_URL'), requireEnv('SUPABASE_SERVICE_ROLE_KEY'), {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  }
  return client;
}

/** Throws a 500 for a Supabase error, so callers can write `must(await query)`. */
export function must<T>(result: { data: T; error: { message: string } | null }): T {
  if (result.error) {
    console.error('Supabase error', result.error.message);
    throw new HttpError('server_error', 500);
  }
  return result.data;
}
