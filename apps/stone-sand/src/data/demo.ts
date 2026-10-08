import { supabase } from '../lib/supabase';

/** Removes every order, statement and customer created in a guided-tour session. */
export async function deleteDemoSession(session: string): Promise<void> {
  const { error } = await supabase.rpc('ss_delete_demo', { p_session: session });
  if (error) throw new Error(error.message);
}

/** Cleans up tours that were abandoned more than a day ago. */
export async function deleteStaleDemoSessions(): Promise<void> {
  const { error } = await supabase.rpc('ss_delete_stale_demo');
  if (error) throw new Error(error.message);
}
