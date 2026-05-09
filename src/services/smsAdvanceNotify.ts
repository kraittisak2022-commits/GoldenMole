import type { Employee, Transaction } from '../types';
import { supabase, hasSupabaseConfig } from '../lib/supabase';
import { normalizeThaiPhone } from '../utils/thaiPhone';

function buildAdvanceSmsText(tx: Transaction, employees: Employee[]): string {
    const ids = tx.employeeIds || [];
    const names = ids
        .map((id) => {
            const e = employees.find((x) => x.id === id);
            return (e?.nickname || e?.name || id).trim();
        })
        .filter(Boolean)
        .join(', ');
    const amt = typeof tx.amount === 'number' ? tx.amount : Number(tx.amount) || 0;
    const per = tx.advanceAmount != null ? Number(tx.advanceAmount) : 0;
    const n = ids.length;
    const desc = (tx.description || '').slice(0, 120);
    return `GoldenMole เบิกเงิน วันที่ ${tx.date} ${n}คน รวม${amt}บ คนละ${per}บ ${names ? `(${names})` : ''} ${desc}`.trim().slice(0, 480);
}

/** Fire-and-forget SMS after advance (เบิกเงิน) saved online. Requires Edge Function `send-advance-sms` + SMSOK secrets. */
export async function notifyAdvanceSaved(tx: Transaction, employees: Employee[]): Promise<void> {
    if (!hasSupabaseConfig) return;
    if (tx.category !== 'Labor' || (tx.subCategory || '').toLowerCase() !== 'advance') return;

    const ids = tx.employeeIds || [];
    const phones = new Set<string>();
    for (const id of ids) {
        const e = employees.find((x) => x.id === id);
        const p = normalizeThaiPhone(e?.phone);
        if (p) phones.add(p);
    }
    const extra = (import.meta.env.VITE_SMS_ADVANCE_NOTIFY_EXTRA as string | undefined)?.split(',') || [];
    for (const raw of extra) {
        const p = normalizeThaiPhone(raw.trim());
        if (p) phones.add(p);
    }
    if (phones.size === 0) return;

    const text = buildAdvanceSmsText(tx, employees);
    try {
        const { error } = await supabase.functions.invoke('send-advance-sms', {
            body: {
                text,
                destinations: [...phones],
            },
        });
        if (error) console.warn('notifyAdvanceSaved:', error.message);
    } catch (e) {
        console.warn('notifyAdvanceSaved invoke failed', e);
    }
}
