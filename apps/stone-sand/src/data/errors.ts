import type { PostgrestError } from '@supabase/supabase-js';

const FOREIGN_KEY_VIOLATION = '23503';

/** `inUse` replaces the raw message when other rows still reference the deleted one. */
export function throwIfError(error: PostgrestError | null, inUse?: string): void {
  if (!error) return;
  throw new Error(inUse && error.code === FOREIGN_KEY_VIOLATION ? inUse : error.message);
}
