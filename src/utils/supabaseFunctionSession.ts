import { supabase, hasSupabaseConfig } from '../lib/supabase';

/**
 * Web ล็อกอินผ่านตาราง admin_users — ใช้เมื่อไม่มี VITE_NOTIFY_ADVANCE_INVOKER_SECRET
 * ใช้ Anonymous sign-in หรือตั้ง VITE_NOTIFY_ADVANCE_INVOKER_SECRET แทน
 */
export async function ensureSupabaseSessionForEdgeFunctions(): Promise<void> {
    if (!hasSupabaseConfig) return;

    const {
        data: { session: existing },
    } = await supabase.auth.getSession();
    if (existing?.access_token) return;

    const { data, error } = await supabase.auth.signInAnonymously();
    if (error || !data.session?.access_token) {
        throw new Error(
            error?.message ??
                'Anonymous sign-in failed — set VITE_NOTIFY_ADVANCE_INVOKER_SECRET matching Edge NOTIFY_ADVANCE_INVOKER_SECRET, or enable Anonymous in Supabase Auth',
        );
    }
}
