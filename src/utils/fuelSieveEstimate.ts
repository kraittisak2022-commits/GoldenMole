import type { Transaction } from '../types';
import { computeSandWorkDurationSummary } from '../modules/Dashboard/countRecordAnalytics';
import {
    FUEL_SAND_SIEVE_SUB_CATEGORY,
    FUEL_STOCK_CUTOVER_YMD,
    normalizeDate,
} from './index';

/** อัตราใช้น้ำมันเครื่องร่อนทราย (ลิตร/ชั่วโมง) — ตรงกับมือถือ `kFuelSandSieveLitersPerHour` */
export const FUEL_SAND_SIEVE_LITERS_PER_HOUR = 18;

function sandLapTimes(t: Transaction): string[] {
    const raw = t.workAssignments?.lapTimes;
    if (!Array.isArray(raw) || raw.length === 0) return [];
    return raw.map(e => String(e).trim()).filter(Boolean);
}

function isDailyLogSandRow(t: Transaction): boolean {
    return t.category === 'DailyLog' && String(t.subCategory ?? '').trim() === 'Sand';
}

function isFuelSandSieveRow(t: Transaction): boolean {
    return (
        t.category === 'Fuel'
        && t.type === 'Expense'
        && String(t.subCategory ?? '').trim() === FUEL_SAND_SIEVE_SUB_CATEGORY
    );
}

/**
 * ประมาณน้ำมันเครื่องร่อนทรายรายวัน (ลิตร)
 *
 * คิดเฉพาะวันที่มี lap ของ DailyLog/Sand แต่ยังไม่มีแถว Fuel/SandSieve
 * สูตร: ชั่วโมงทำงานจริง (หักพักเที่ยง) × 18 ล./ชม.
 */
export function estimateSieveUsageByDay(
    transactions: Transaction[]
): Record<string, number> {
    const sandSieveDays = new Set<string>();
    const sandByDay = new Map<string, Transaction>();

    for (const t of transactions) {
        const day = normalizeDate(t.date);
        if (!day || day < FUEL_STOCK_CUTOVER_YMD) continue;
        if (isFuelSandSieveRow(t)) {
            sandSieveDays.add(day);
            continue;
        }
        if (!isDailyLogSandRow(t)) continue;
        const laps = sandLapTimes(t);
        if (laps.length === 0) continue;
        const prev = sandByDay.get(day);
        const prevLen = prev ? sandLapTimes(prev).length : 0;
        if (laps.length >= prevLen) sandByDay.set(day, t);
    }

    const out: Record<string, number> = {};
    for (const [day, sandTx] of sandByDay) {
        if (sandSieveDays.has(day)) continue;
        const laps = sandLapTimes(sandTx);
        const hours = computeSandWorkDurationSummary(laps, day)?.totalActiveHours ?? 0;
        if (hours <= 0) continue;
        const liters = Number((hours * FUEL_SAND_SIEVE_LITERS_PER_HOUR).toFixed(2));
        if (liters > 0) out[day] = liters;
    }
    return out;
}
