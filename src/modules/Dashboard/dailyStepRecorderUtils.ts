import { normalizeDate } from '../../utils';
import type { Transaction } from '../../types';

const toTimeOrNull = (value: string | undefined): number | null => {
    if (!value) return null;
    const t = Date.parse(value);
    return Number.isNaN(t) ? null : t;
};

export const getTransactionRecencyScore = (tx: Transaction, dayItems: Transaction[], idxFallback = -1): number => {
    const createdAtMs = toTimeOrNull(tx.createdAt);
    if (createdAtMs != null) return createdAtMs;
    const dayMs = toTimeOrNull(`${normalizeDate(tx.date)}T00:00:00.000Z`);
    if (dayMs != null) return dayMs + Math.max(0, idxFallback);
    return idxFallback;
};

/**
 * ถังล้างที่บ้านจากรายการ Sand ของวันเดียวกัน
 *
 * เดิมใช้ Math.max ทุกแถว — ถ้ามีแถว drums-only (คิว=0) ค้างจากรอบบันทึกเก่า พร้อมแถวเครื่องเก่า/ใหม่ที่แก้แล้ว
 * ค่าเก่าใน drums-only (เช่น 55) จะทับค่าที่เครื่อง (เช่น 1) ได้
 */
export const persistedSandHomeDrums = (sandTx: Transaction[]): number => {
    if (sandTx.length === 0) return 0;
    const rows = sandTx as any[];
    const withMachine = rows.filter(t => t.sandMachineType === 'Old' || t.sandMachineType === 'New');
    if (withMachine.length > 0) {
        return Math.max(0, ...withMachine.map(t => Number(t.drumsWashedAtHome || 0)));
    }
    const drumsOnly = rows.filter(t => {
        if (t.sandMachineType === 'Old' || t.sandMachineType === 'New') return false;
        return (Number(t.sandMorning || 0) + Number(t.sandAfternoon || 0)) === 0;
    });
    if (drumsOnly.length > 0) {
        return Math.max(0, ...drumsOnly.map(t => Number(t.drumsWashedAtHome || 0)));
    }
    return Math.max(0, ...rows.map(t => Number(t.drumsWashedAtHome || 0)));
};

/** หมวดที่ถือเป็นค่าใช้จ่ายได้ แม้แถวจะไม่มี type (legacy / sync เก่า) */
const WIZARD_SPEND_CATEGORIES_IF_TYPE_MISSING = new Set([
    'Labor',
    'Vehicle',
    'Fuel',
    'Maintenance',
    'Utilities',
    'DailyLog',
]);

/**
 * นับรวมใน "รวมค่าใช้จ่ายวันนี้" ของ Daily Wizard
 * รองรับแถวที่ `type` ว่าง — Android fromMap ใช้ `''` เมื่อคอลัมน์ type ไม่มีค่า
 */
export const countsTowardWizardDailySpend = (t: Transaction): boolean => {
    if (t.type === 'Income') return false;
    const cat = t.category || '';
    if (cat === 'Payroll' || cat === 'PayrollUnlock') return false;
    const typ = String(t.type ?? '').trim();
    if (typ === 'Expense' || typ === 'Leave') return true;
    if (!typ && WIZARD_SPEND_CATEGORIES_IF_TYPE_MISSING.has(cat)) return true;
    return false;
};

export const numericTransactionAmount = (t: Transaction): number => {
    const n = Number(t.amount);
    return Number.isFinite(n) ? n : 0;
};

export const sumWizardDailySpend = (txs: Transaction[]): number =>
    txs.filter(countsTowardWizardDailySpend).reduce((s, t) => s + numericTransactionAmount(t), 0);

export const pickLatestByDayOrder = <T extends Transaction>(items: T[], dayItems: Transaction[]): T | null => {
    if (items.length === 0) return null;
    const lastIndexById = new Map<string, number>();
    dayItems.forEach((tx, idx) => {
        lastIndexById.set(tx.id, idx);
    });
    return items.reduce((latest, current) => {
        const latestIdx = lastIndexById.get(latest.id) ?? -1;
        const currentIdx = lastIndexById.get(current.id) ?? -1;
        const latestScore = getTransactionRecencyScore(latest, dayItems, latestIdx);
        const currentScore = getTransactionRecencyScore(current, dayItems, currentIdx);
        if (currentScore === latestScore) return currentIdx >= latestIdx ? current : latest;
        return currentScore > latestScore ? current : latest;
    });
};
