import type { Employee, Transaction } from '../types';
import { hasSupabaseConfig } from '../lib/supabase';
import { decodeAdvanceGm } from '../utils/advanceGmWorkDetails';
import { invokeNotifyAdvanceLine, normalizeLineRecipientId, normalizeLineUserId } from '../utils/lineMessaging';

function formatBahtTh(value: number): string {
    const isInt = Math.abs(value - Math.round(value)) < 1e-9;
    const raw = isInt ? String(Math.round(value)) : value.toFixed(2);
    const [intPart, dec] = raw.split('.');
    const withSep = intPart.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    return dec ? `${withSep}.${dec}` : withSep;
}

const THAI_MONTHS = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'] as const;

function formatDateThaiBE(ymd: string): string {
    const segs = ymd.split('-');
    if (segs.length !== 3) return ymd;
    const y = Number(segs[0]);
    const m = Number(segs[1]);
    const d = Number(segs[2]);
    if (!Number.isFinite(y) || !Number.isFinite(m) || !Number.isFinite(d) || m < 1 || m > 12) return ymd;
    return `${d} ${THAI_MONTHS[m - 1]} ${y + 543}`;
}

function advancePayoutSlotTh(meta: ReturnType<typeof decodeAdvanceGm>): string {
    return meta.payoutSlot === 'evening' ? 'ช่วงเย็น' : 'ช่วงกลางวัน';
}

function advancePaymentTh(meta: ReturnType<typeof decodeAdvanceGm>): string {
    if (meta.paymentMethod === 'transfer') {
        const b = meta.bank.trim();
        const a = meta.accountNumber.trim();
        if (b || a) {
            const parts: string[] = [];
            if (b) parts.push(b);
            if (a) parts.push(`เลข ${a}`);
            return `เงินโอน (${parts.join(' · ')})`;
        }
        return 'เงินโอน';
    }
    return 'เงินสด';
}

/** ข้อความส่ง LINE — จัดรูปแบบอ่านง่าย (ตัดที่ 4800 ตัวอักษร) */
function buildAdvanceLineText(tx: Transaction, employees: Employee[]): string {
    const ids = tx.employeeIds || [];
    const names = ids
        .map((id) => {
            const e = employees.find((x) => x.id === id);
            return (e?.nickname || e?.name || id).trim();
        })
        .filter(Boolean)
        .join(', ');
    const meta = decodeAdvanceGm(tx.workDetails);
    const amt = typeof tx.amount === 'number' ? tx.amount : Number(tx.amount) || 0;
    const per = tx.advanceAmount != null ? Number(tx.advanceAmount) : 0;
    const n = ids.length;
    const namesLine = names || '—';
    const totalStr = formatBahtTh(amt);
    const perStr = formatBahtTh(per);
    const dateLine = `${formatDateThaiBE(tx.date)} (${tx.date})`;
    const lines = [
        '━━━━ GoldenMole ━━━━',
        '',
        'รายการเบิกเงิน',
        '',
        'วันที่ :',
        dateLine,
        '',
        'ชื่อ :',
        namesLine,
        '',
        'จำนวนเงิน :',
        `รวม ${totalStr} บาท (${n} คน × ${perStr} บาท/คน)`,
        '',
        'ต้องการรับเงินช่วง :',
        advancePayoutSlotTh(meta),
        '',
        'ได้เงินเป็น :',
        advancePaymentTh(meta),
    ];
    const raw = lines.join('\n').trim();
    return raw.length > 4800 ? raw.slice(0, 4800) : raw;
}

function leaveKindTh(sub: string | undefined): string {
    const s = (sub || '').trim().toLowerCase();
    if (s === 'sick') return 'ลาป่วย';
    return 'ลากิจ';
}

function formatLeaveDays(d: number | undefined): string {
    if (d == null || !Number.isFinite(d) || d <= 0) return '—';
    if (Math.abs(d - Math.round(d)) < 1e-9) return `${Math.round(d)}`;
    return String(d);
}

function buildLeaveLineText(tx: Transaction, employees: Employee[]): string {
    const ids = tx.employeeIds || [];
    const names = ids
        .map((id) => {
            const e = employees.find((x) => x.id === id);
            return (e?.nickname || e?.name || id).trim();
        })
        .filter(Boolean)
        .join(', ');
    const reasonRaw = (tx.leaveReason || '').trim();
    const reasonLine = reasonRaw || '—';
    const daysStr = formatLeaveDays(tx.leaveDays != null ? Number(tx.leaveDays) : undefined);
    const namesLine = names || '—';
    const dateLine = `${formatDateThaiBE(tx.date)} (${tx.date})`;
    const lines = [
        '━━━━ GoldenMole ━━━━',
        '',
        'บันทึกลางาน',
        '',
        'ประเภท :',
        leaveKindTh(tx.subCategory),
        '',
        'วันที่เริ่มลา :',
        dateLine,
        '',
        'ชื่อ :',
        namesLine,
        '',
        'จำนวนวัน :',
        `${daysStr} วัน`,
        '',
        'เหตุผล :',
        reasonLine,
    ];
    const raw = lines.join('\n').trim();
    return raw.length > 4800 ? raw.slice(0, 4800) : raw;
}

export type AdvanceLineNotifyResult =
    | { kind: 'skipped' }
    | { kind: 'sent' }
    | { kind: 'failed'; message: string };

/** หลังบันทึกเบิกเงินออนไลน์ — เรียก Edge notify-advance-line */
export async function notifyAdvanceLineSaved(
    tx: Transaction,
    employees: Employee[],
): Promise<AdvanceLineNotifyResult> {
    if (!hasSupabaseConfig) return { kind: 'skipped' };
    if (tx.category !== 'Labor' || (tx.subCategory || '').toLowerCase() !== 'advance') {
        return { kind: 'skipped' };
    }

    const ids = tx.employeeIds || [];
    const to = new Set<string>();
    for (const id of ids) {
        const e = employees.find((x) => x.id === id);
        const u = normalizeLineUserId(e?.lineUserId || '');
        if (u) to.add(u);
    }
    const extra = (import.meta.env.VITE_LINE_ADVANCE_NOTIFY_USER_IDS as string | undefined)?.split(',') || [];
    for (const raw of extra) {
        const u = normalizeLineRecipientId(raw) || normalizeLineUserId(raw);
        // รายงานแอดมินเข้ากลุ่ม/ห้องเท่านั้น — ส่วนตัวถาม–ตอบผ่าน webhook
        if (u && (u.startsWith('C') || u.startsWith('R'))) to.add(u);
    }
    if (to.size === 0) return { kind: 'skipped' };

    const text = buildAdvanceLineText(tx, employees);
    try {
        const { data, error } = await invokeNotifyAdvanceLine({
            text,
            to: [...to],
        });
        if (error) {
            console.warn('notifyAdvanceLineSaved:', error.message);
            return { kind: 'failed', message: error.message };
        }
        const d = data as { ok?: boolean; hint_th?: string; message?: string } | null;
        if (d && d.ok === false) {
            const hint = String(d.hint_th || d.message || d.error || 'แจ้ง LINE ไม่สำเร็จ');
            console.warn('notifyAdvanceLineSaved LINE:', hint, d);
            return { kind: 'failed', message: hint };
        }
        return { kind: 'sent' };
    } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        console.warn('notifyAdvanceLineSaved invoke failed', e);
        return { kind: 'failed', message: msg };
    }
}

/** หลังบันทึกลางาน — เรียก Edge notify-advance-line (ผู้รับเดียวกับเบิกเงิน) */
export async function notifyLeaveLineSaved(
    tx: Transaction,
    employees: Employee[],
): Promise<AdvanceLineNotifyResult> {
    if (!hasSupabaseConfig) return { kind: 'skipped' };
    const cat = (tx.category || '').trim();
    if (cat !== 'Leave') return { kind: 'skipped' };

    const ids = tx.employeeIds || [];
    const to = new Set<string>();
    for (const id of ids) {
        const e = employees.find((x) => x.id === id);
        const u = normalizeLineUserId(e?.lineUserId || '');
        if (u) to.add(u);
    }
    const extra = (import.meta.env.VITE_LINE_ADVANCE_NOTIFY_USER_IDS as string | undefined)?.split(',') || [];
    for (const raw of extra) {
        const u = normalizeLineRecipientId(raw) || normalizeLineUserId(raw);
        // รายงานแอดมินเข้ากลุ่ม/ห้องเท่านั้น — ส่วนตัวถาม–ตอบผ่าน webhook
        if (u && (u.startsWith('C') || u.startsWith('R'))) to.add(u);
    }
    if (to.size === 0) return { kind: 'skipped' };

    const text = buildLeaveLineText(tx, employees);
    try {
        const { data, error } = await invokeNotifyAdvanceLine({
            text,
            to: [...to],
        });
        if (error) {
            console.warn('notifyLeaveLineSaved:', error.message);
            return { kind: 'failed', message: error.message };
        }
        const d = data as { ok?: boolean; hint_th?: string; message?: string } | null;
        if (d && d.ok === false) {
            const hint = String(d.hint_th || d.message || d.error || 'แจ้ง LINE ไม่สำเร็จ');
            console.warn('notifyLeaveLineSaved LINE:', hint, d);
            return { kind: 'failed', message: hint };
        }
        return { kind: 'sent' };
    } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        console.warn('notifyLeaveLineSaved invoke failed', e);
        return { kind: 'failed', message: msg };
    }
}
