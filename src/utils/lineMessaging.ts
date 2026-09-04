/** LINE Messaging API: User U… / Group C… / Room R… (normalized) */
import { supabase } from '../lib/supabase';
import { ensureSupabaseSessionForEdgeFunctions } from './supabaseFunctionSession';

export function normalizeLineUserId(raw: string): string | undefined {
    const m = String(raw || '').trim().match(/^U([a-f0-9]{32})$/i);
    if (!m) return undefined;
    return `U${m[1].toLowerCase()}`;
}

/** ผู้รับแจ้งเตือนรวมกลุ่ม/ห้อง — ใช้ใน env ผู้ดูแล */
export function normalizeLineRecipientId(raw: string): string | undefined {
    const m = String(raw || '').trim().match(/^([UCR])([a-f0-9]{32})$/i);
    if (!m) return undefined;
    return `${m[1].toUpperCase()}${m[2].toLowerCase()}`;
}

export function parseLineUserIdsField(raw: string): string[] {
    const out = new Set<string>();
    for (const part of raw.split(/[\s,]+/)) {
        const u = normalizeLineRecipientId(part) || normalizeLineUserId(part);
        if (u) out.add(u);
    }
    return [...out];
}

const NOTIFY_INVOKER_HEADER = 'x-cm-notify-advance-secret';

/**
 * เรียก Edge notify-advance-line
 * - ถ้ามี VITE_NOTIFY_ADVANCE_INVOKER_SECRET ไม่ต้องเปิด Anonymous
 * - ไม่มี secret ใช้ JWT จาก session (ต้องเปิด Anonymous หรือ Supabase Auth)
 */
export async function invokeNotifyAdvanceLine(body: {
    text: string;
    to: string[];
}): Promise<{ data: unknown; error: Error | null }> {
    const invokeSecret = (import.meta.env.VITE_NOTIFY_ADVANCE_INVOKER_SECRET ?? '').trim();

    const run = (headers: Record<string, string>) =>
        supabase.functions.invoke('notify-advance-line', {
            body,
            headers: {
                'Content-Type': 'application/json',
                ...headers,
            },
        });

    if (invokeSecret) {
        const anon = (import.meta.env.VITE_SUPABASE_ANON_KEY ?? '').trim();
        if (!anon) {
            return {
                data: null,
                error: new Error(
                    'มี VITE_NOTIFY_ADVANCE_INVOKER_SECRET แต่ไม่มี VITE_SUPABASE_ANON_KEY — ตรวจไฟล์ .env',
                ),
            };
        }
        const { data, error } = await run({
            Authorization: `Bearer ${anon}`,
            [NOTIFY_INVOKER_HEADER]: invokeSecret,
        });
        return { data, error: error as Error | null };
    }

    try {
        await ensureSupabaseSessionForEdgeFunctions();
    } catch (e) {
        const msg = e instanceof Error ? e.message : 'ไม่สามารถสร้าง session สำหรับเรียกฟังก์ชันได้';
        return {
            data: null,
            error: new Error(
                `${msg} — ตั้ง VITE_NOTIFY_ADVANCE_INVOKER_SECRET ให้ตรงกับ Edge secret NOTIFY_ADVANCE_INVOKER_SECRET หรือเปิด Anonymous sign-in`,
            ),
        };
    }

    const {
        data: { session },
        error: sessErr,
    } = await supabase.auth.getSession();
    if (sessErr || !session?.access_token) {
        return {
            data: null,
            error: new Error(
                'ยังไม่มี JWT — ตั้ง VITE_NOTIFY_ADVANCE_INVOKER_SECRET ใน .env ให้ตรงกับ Edge หรือเปิด Anonymous sign-in',
            ),
        };
    }

    let { data, error } = await run({
        Authorization: `Bearer ${session.access_token}`,
    });
    const ctxStatus = (error as { context?: { status?: number } } | null)?.context?.status;
    const looks401 =
        !!error &&
        (ctxStatus === 401 ||
            /401/i.test(error.message) ||
            /Non-2xx status code: 401/i.test(error.message));

    const looks400Gateway =
        !!error &&
        (ctxStatus === 400 || /Non-2xx status code: 400/i.test(error.message));

    if (looks401 || looks400Gateway) {
        await supabase.auth.refreshSession();
        const {
            data: { session: s2 },
        } = await supabase.auth.getSession();
        if (s2?.access_token) {
            ({ data, error } = await run({
                Authorization: `Bearer ${s2.access_token}`,
            }));
        }
    }

    return { data, error: error as Error | null };
}
