import { normalizeDate } from '../../utils';
import { dailyWageForWorkType } from '../../utils/laborWage';
import type { AppDefaults, Employee, Transaction, WorkType } from '../../types';

const TZ_TH = 'Asia/Bangkok';

/** วันถัดไปในรูปแบบ YYYY-MM-DD (เขต Asia/Bangkok) — สอดคล้อง DataVerificationModule */
export const addOneCalendarDayTH = (ymd: string): string => {
    const d = new Date(`${ymd}T12:00:00`);
    d.setDate(d.getDate() + 1);
    return d.toLocaleDateString('en-CA', { timeZone: TZ_TH });
};

export type SandRoundDailyRow = {
    date: string;
    transported: number;
    washed: number;
    obtained: number;
    home: number;
};

/** สรุปรายวันเดียวกับ sandRoundOverview (ทุกวันที่มีธุรกรรมที่เกี่ยวข้อง — ไม่จำกัดช่วงรายงาน) */
export const buildSandRoundDailyRows = (transactions: Transaction[]): SandRoundDailyRow[] => {
    const dailyMap = new Map<string, { transported: number; washed: number; obtained: number; home: number }>();

    transactions.forEach(t => {
        const d = normalizeDate(t.date);
        if (!d) return;
        const daily = dailyMap.get(d) || { transported: 0, washed: 0, obtained: 0, home: 0 };

        if (t.category === 'DailyLog' && t.subCategory === 'VehicleTrip') {
            const tripCubic = Number(t.totalCubic || t.quantity || 0);
            daily.transported += Math.max(0, tripCubic);
        }

        if (t.category === 'DailyLog' && t.subCategory === 'Sand') {
            const washed = (Number(t.sandMorning) || 0) + (Number(t.sandAfternoon) || 0);
            daily.washed += Math.max(0, washed);
            const obtained = Math.max(0, Number((t as any).drumsObtained || 0));
            daily.obtained = Math.max(daily.obtained, obtained);
            const homeFromSand = Math.max(0, Number((t as any).drumsWashedAtHome || 0));
            daily.home = Math.max(daily.home, homeFromSand);
        }

        if (t.category === 'Labor') {
            const homeFromLabor = Math.max(0, Number((t as any).drumsWashedAtHome || 0));
            if (homeFromLabor > 0) {
                daily.home = Math.max(daily.home, homeFromLabor);
            }
        }
        dailyMap.set(d, daily);
    });

    return Array.from(dailyMap.entries())
        .map(([date, v]) => ({ date, ...v }))
        .sort((a, b) => a.date.localeCompare(b.date));
};

type SandRoundAuditEntry = NonNullable<AppDefaults['sandRoundAuditTrail']>[number];

const parseRoundStartDateFromRoundId = (roundId: string): string | null => {
    const m = /^round_\d+_(\d{4}-\d{2}-\d{2})$/.exec(String(roundId || '').trim());
    return m ? m[1] : null;
};

const maxYmd = (a: string, b: string) => (a >= b ? a : b);

type InternalSandRound = {
    id: string;
    roundNo: number;
    startDate: string;
    endDate: string;
    obtainedDrums: number;
    washedHomeDrums: number;
    remainingDrums: number;
    completed: boolean;
    days: SandRoundDailyRow[];
};

const buildSandRoundsFromDailyRows = (
    dailyRows: SandRoundDailyRow[],
    sandRoundAuditTrail: SandRoundAuditEntry[] | undefined,
    roundCloseMinDays: number,
): InternalSandRound[] => {
    const manualClosedIds = new Set(
        (sandRoundAuditTrail || []).filter(a => a.action === 'manual_close_round').map(a => a.roundId),
    );
    const manualClosedStartDates = new Set(
        (sandRoundAuditTrail || [])
            .filter(a => a.action === 'manual_close_round')
            .map(a => parseRoundStartDateFromRoundId(a.roundId))
            .filter((d): d is string => Boolean(d)),
    );

    const rounds: InternalSandRound[] = [];
    let roundNo = 0;
    let current: InternalSandRound | null = null;

    dailyRows.forEach(r => {
        const active = r.transported > 0 || r.washed > 0 || r.obtained > 0 || r.home > 0;
        if (!active) return;
        if (!current) {
            roundNo += 1;
            current = {
                id: `round_${roundNo}_${r.date}`,
                roundNo,
                startDate: r.date,
                endDate: r.date,
                obtainedDrums: 0,
                washedHomeDrums: 0,
                remainingDrums: 0,
                completed: false,
                days: [],
            };
        }

        current.endDate = r.date;
        current.obtainedDrums += r.obtained;
        current.washedHomeDrums += r.home;
        current.remainingDrums = Math.max(0, current.obtainedDrums - current.washedHomeDrums);
        current.days.push(r);

        const isAutoCompleted =
            current.remainingDrums === 0 &&
            current.obtainedDrums > 0 &&
            current.days.length >= Math.max(1, roundCloseMinDays);
        /** ระหว่างเดินรายวันใช้เฉพาะ roundId ตรงกัน — อย่าใช้แค่วันที่เริ่มรอบเพราะจะปิดรอบหลังวันแรกผิด */
        const isForceClosed = manualClosedIds.has(current.id);
        const isCompleted = isAutoCompleted || isForceClosed;

        if (isCompleted) {
            current.completed = true;
            rounds.push(current);
            current = null;
        }
    });

    if (current) {
        rounds.push(current);
    }

    /** ปิดรอบด้วยสิทธิ์: roundId จาก UI อาจเป็น round_9_YYYY-MM-DD ขณะที่ global walk ได้ round_1_... — จับคู่ด้วยวันเริ่มรอบหลังรวมวันครบแล้ว */
    for (const r of rounds) {
        if (r.completed) continue;
        const byExact = manualClosedIds.has(r.id);
        const byStart = manualClosedStartDates.has(r.startDate);
        if (byExact || byStart) {
            r.completed = true;
        }
    }

    return rounds;
};

/**
 * วันแรกที่นับ “คงเหลือถังสะสม” ใหม่หลังรอบล้างทรายที่ปิดแล้ว (รวมถึงรอบที่ปิดด้วยสิทธิ์ผู้ดูแล)
 * ใช้ logic เดียวกับ DataVerificationModule.sandRoundOverview แต่ดูธุรกรรมทุกวัน
 */
export const computeSandDrumCarryoverEpochStart = (
    selectedDate: string,
    transactions: Transaction[],
    options?: { sandRoundAuditTrail?: SandRoundAuditEntry[]; roundCloseMinDays?: number },
): string => {
    const norm = normalizeDate(selectedDate);
    const roundCloseMinDays = Math.max(1, Number(options?.roundCloseMinDays ?? 2) || 2);
    const dailyRows = buildSandRoundDailyRows(transactions);
    const rounds = buildSandRoundsFromDailyRows(dailyRows, options?.sandRoundAuditTrail, roundCloseMinDays);

    let epochStart = '0000-01-01';
    const completedBefore = rounds.filter(r => r.completed && r.endDate < norm);
    if (completedBefore.length > 0) {
        const last = completedBefore[completedBefore.length - 1];
        epochStart = addOneCalendarDayTH(last.endDate);
    }

    const openContaining = rounds.find(
        r => !r.completed && r.startDate <= norm && r.endDate >= norm,
    );
    if (openContaining) {
        epochStart = maxYmd(epochStart, openContaining.startDate);
    }

    return epochStart;
};

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

/** ค่าแรงมาทำงาน: แอปมือถือบันทึก amount=0 — ประมาณจาก baseWage + ครึ่งวัน/เต็มวัน */
const inferredLaborAttendanceTotal = (t: Transaction, employees: Employee[]): number => {
    const ids = t.employeeIds || [];
    if (ids.length === 0) return 0;
    const wte = t.workTypeByEmployee as Record<string, WorkType> | undefined;
    let sum = 0;
    for (const id of ids) {
        const emp = employees.find(e => e.id === id);
        if (!emp) continue;
        const wage = Number(emp.baseWage);
        if (!Number.isFinite(wage)) continue;
        const wt: WorkType = wte?.[id] === 'HalfDay' ? 'HalfDay' : 'FullDay';
        sum += dailyWageForWorkType(emp, wage, wt);
    }
    return sum;
};

const inferredVehicleSpend = (t: Transaction): number => {
    const a = Number(t.amount);
    if (Number.isFinite(a) && a > 0) return a;
    const d = Number((t as any).driverWage);
    const v = Number((t as any).vehicleWage);
    return (Number.isFinite(d) ? d : 0) + (Number.isFinite(v) ? v : 0);
};

const inferredOtSpend = (t: Transaction): number => {
    const a = Number(t.amount);
    if (Number.isFinite(a) && a > 0) return a;
    const rate = Number((t as any).otAmount);
    const hours = Number((t as any).otHours);
    const n = Math.max(1, (t.employeeIds || []).length);
    if (!Number.isFinite(rate) || !Number.isFinite(hours) || rate <= 0 || hours <= 0) return 0;
    return rate * hours * n;
};

/**
 * มูลค่าที่ใช้แสดง "รวมค่าใช้จ่ายวันนี้" — ใช้ amount ก่อน ถ้าเป็น 0 ค่อยประมาณจากฟิลด์อื่น (พฤติกรรมแอปมือถือ)
 */
export const wizardMonetaryAmount = (t: Transaction, employees?: Employee[]): number => {
    const base = numericTransactionAmount(t);
    if (base > 0) return base;

    if (t.category === 'Labor') {
        if (t.subCategory === 'Attendance' && t.laborStatus === 'Work' && employees && employees.length > 0) {
            const inferred = inferredLaborAttendanceTotal(t, employees);
            if (inferred > 0) return inferred;
        }
        if (t.laborStatus === 'OT' || t.subCategory === 'OT') {
            const ot = inferredOtSpend(t);
            if (ot > 0) return ot;
        }
    }

    if (t.category === 'Vehicle') {
        const v = inferredVehicleSpend(t);
        if (v > 0) return v;
    }

    return 0;
};

export const sumWizardDailySpend = (txs: Transaction[], employees?: Employee[]): number =>
    txs.filter(countsTowardWizardDailySpend).reduce((s, t) => s + wizardMonetaryAmount(t, employees), 0);

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
