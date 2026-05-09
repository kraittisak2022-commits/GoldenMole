import type { Transaction } from '../types';
import { normalizeDate } from './index';

/** ธุรกรรม «ลา» ที่มีผลในแผนประจำวัน (ให้หมดกับฟิลเตอร์มือถือ) */
export function isLaborLeaveRecord(t: Transaction): boolean {
    const n = (t.employeeIds || []).filter(Boolean).length;
    if (n === 0) return false;
    if (t.category === 'Leave' || t.type === 'Leave') return true;
    const ls = (t.laborStatus || '').toLowerCase();
    return t.category === 'Labor' && (ls === 'leave' || ls === 'sick' || ls === 'personal');
}

function addDaysToYmd(ymd: string, deltaDays: number): string {
    const base = normalizeDate(ymd);
    const [yy, mm, dd] = base.split('-').map((x) => parseInt(x, 10));
    if (!yy || !mm || !dd) return base;
    const ms = Date.UTC(yy, mm - 1, dd + deltaDays);
    const d = new Date(ms);
    const y = d.getUTCFullYear();
    const m = String(d.getUTCMonth() + 1).padStart(2, '0');
    const day = String(d.getUTCDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
}

/** start date = t.date inclusive, leaveDays defaults 1, span uses ceil เช่น 1.5 วัน → 2 วัน */
export function leaveRecordCoversDay(t: Transaction, dayYmd: string): boolean {
    if (!isLaborLeaveRecord(t)) return false;
    const start = normalizeDate(t.date);
    const needle = normalizeDate(dayYmd);
    const span = Math.max(1, Math.ceil(Number(t.leaveDays ?? 1)));
    const end = addDaysToYmd(start, span - 1);
    return needle >= start && needle <= end;
}
