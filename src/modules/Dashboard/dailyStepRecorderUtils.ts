import { normalizeDate } from '../../utils';
import { dailyWageForWorkType } from '../../utils/laborWage';
import type { Employee, Transaction, WorkType } from '../../types';

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

/** แถวบันทึก «ตัดรอบล้างทรายที่บ้าน» — ไม่นับเป็นจำนวนถังที่ล้าง */
export const isHomeSandRoundCloseRow = (t: any): boolean =>
    String(t.description ?? '').includes('ตัดรอบล้างทรายที่บ้าน');

/** แถวบันทึกจาก Quick Input / Wizard สำหรับ “ทรายที่ล้างที่บ้าน” เท่านั้น — ยึดเป็นค่าถังล้างที่บ้านจริง */
const isDedicatedHomeSandRow = (t: any): boolean =>
    String(t.description ?? '').includes('ทรายที่ล้างที่บ้าน') &&
    !isHomeSandRoundCloseRow(t);

/**
 * ถังล้างที่บ้านจากรายการ Sand ของวันเดียวกัน
 *
 * ถ้ามีแถว description มี “ทรายที่ล้างที่บ้าน” ให้ใช้ max จากแถวเหล่านั้นก่อน (ไม่สนใจค่า drumsWashedAtHome บนแถวเครื่องที่อาจผิดพลาดจาก sync เก่า)
 * ไม่งั้นเดิม: เครื่องเก่า/ใหม่ → drums-only → max ทุกแถว
 */
export const persistedSandHomeDrums = (sandTx: Transaction[]): number => {
    if (sandTx.length === 0) return 0;
    const rows = sandTx as any[];
    const dedicatedHome = rows.filter(isDedicatedHomeSandRow);
    if (dedicatedHome.length > 0) {
        return Math.max(0, ...dedicatedHome.map(t => Number(t.drumsWashedAtHome || 0)));
    }
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

/** ค่าจากช่อง Wizard (ว่าง = ใช้จากธุรกรรมที่บันทึกแล้วของวันนั้น) */
export type SandDrumStockDrafts = {
    sandDrumsObtained?: string;
    drumsWashedAtHome?: string;
};

/**
 * คงเหลือถัง “ทรายที่ล้างที่บ้าน” — logic เดียวกับ `drumStockSummary` ใน DailyStepRecorder
 */
export const computeSandDrumStockSummary = (
    selectedDate: string,
    transactions: Transaction[],
    drafts: SandDrumStockDrafts,
): {
    cumulativeBeforeToday: number;
    todayObtained: number;
    todayHome: number;
    todayNet: number;
    cumulativeRemaining: number;
} => {
    const selectedDateNorm = normalizeDate(selectedDate);
    const perDay = new Map<string, { obtained: number; home: number }>();
    const sandByDay = new Map<string, Transaction[]>();
    transactions
        .filter(t => t.category === 'DailyLog' && t.subCategory === 'Sand')
        .forEach((t) => {
            const d = normalizeDate(t.date);
            const arr = sandByDay.get(d) || [];
            arr.push(t);
            sandByDay.set(d, arr);
        });
    sandByDay.forEach((txs, d) => {
        const obtained = Math.max(0, ...txs.map(tx => Number((tx as any).drumsObtained || 0)));
        const home = persistedSandHomeDrums(txs);
        perDay.set(d, { obtained, home });
    });

    const sortedBeforeToday = Array.from(perDay.entries())
        .filter(([d]) => d < selectedDateNorm)
        .sort(([a], [b]) => a.localeCompare(b));
    let cumulativeBeforeToday = 0;
    sortedBeforeToday.forEach(([, v]) => {
        cumulativeBeforeToday = Math.max(0, cumulativeBeforeToday + v.obtained - v.home);
    });

    const savedToday = perDay.get(selectedDateNorm) || { obtained: 0, home: 0 };
    const obDraft = String(drafts.sandDrumsObtained ?? '').trim();
    const todayObtained = obDraft === '' ? savedToday.obtained : Math.max(0, Number(obDraft) || 0);
    const homeDraft = String(drafts.drumsWashedAtHome ?? '').trim();
    const todayHome = homeDraft === '' ? savedToday.home : Math.max(0, Number(homeDraft) || 0);
    const todayNet = todayObtained - todayHome;
    const cumulativeRemaining = Math.max(0, cumulativeBeforeToday + todayNet);

    return { cumulativeBeforeToday, todayObtained, todayHome, todayNet, cumulativeRemaining };
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

export const GENERAL_WORK_ASSIGNMENT_PREFIX = 'general:';

/** คีย์ canvas ค่าแรงบนเว็บ (สอดคล้องขั้นล้างทราย wash1/wash2) */
export const WEB_LABOR_CANVAS_CATEGORY_IDS = new Set([
    'wash1',
    'wash2',
    'washHome',
    'pierWatch',
    'nightShift',
    'nightPatrol',
    'digHaul',
    'generalWork',
]);

/**
 * แปลงคีย์จากแอปมือถือ / ข้อมูลเก่า → คีย์มาตรฐานบนเว็บ (สอดคล้อง `_normalizeLaborCanvasKey` ใน Flutter)
 */
export const normalizeLaborCanvasKey = (key: string): string => {
    const k = String(key || '').trim();
    if (!k) return 'generalWork';
    if (k.startsWith(GENERAL_WORK_ASSIGNMENT_PREFIX)) return k;
    if (['wash_home', 'wash_yard_house', 'sift_home', 'washHome'].includes(k)) return 'washHome';
    switch (k) {
        case 'wash1':
        case 'wash_old':
            return 'wash1';
        case 'wash2':
        case 'wash_new':
            return 'wash2';
        case 'pierWatch':
        case 'sand_watch':
            return 'pierWatch';
        case 'nightShift':
        case 'night_shift':
            return 'nightShift';
        case 'nightPatrol':
        case 'night_patrol':
            return 'nightPatrol';
        case 'digHaul':
        case 'dig_haul':
        case 'excavator_control':
            return 'digHaul';
        case 'generalWork':
        case 'general':
            return 'generalWork';
        default:
            if (WEB_LABOR_CANVAS_CATEGORY_IDS.has(k)) return k;
            return 'generalWork';
    }
};

/** รวม workAssignments จาก DB/มือถือ — คีย์ล้างที่บ้านไม่ถูกยุบเข้างานทั่วไป */
export const mergeLaborCanvasAssignments = (
    raw: Record<string, string[]> | undefined | null,
): Record<string, string[]> => {
    if (!raw || typeof raw !== 'object') return {};
    const out: Record<string, string[]> = {};
    const pushUnique = (key: string, ids: string[]) => {
        const list = (ids || []).map(id => String(id).trim()).filter(Boolean);
        if (list.length === 0) return;
        if (!out[key]) out[key] = [];
        const seen = new Set(out[key]);
        for (const id of list) {
            if (!seen.has(id)) {
                seen.add(id);
                out[key].push(id);
            }
        }
    };
    for (const [k, ids] of Object.entries(raw)) {
        const canon = normalizeLaborCanvasKey(k);
        if (canon.startsWith(GENERAL_WORK_ASSIGNMENT_PREFIX)) {
            pushUnique(canon, ids);
        } else if (WEB_LABOR_CANVAS_CATEGORY_IDS.has(canon)) {
            pushUnique(canon, ids);
        } else {
            pushUnique('generalWork', ids);
        }
    }
    return out;
};

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

/** รถหกล้อ / สิบล้อ — ใช้ในเมนูบันทึกรถดรัมและจำนวนเที่ยว */
export const isSixOrTenWheelVehicleName = (raw?: string | null): boolean => {
    const s = (raw ?? '').trim();
    if (!s) return false;
    const compact = s.toLowerCase().replace(/\s+/g, '');
    if (compact.includes('หกล้อ') || compact.includes('6ล้อ')) return true;
    if (/6\s*ล้อ/i.test(s)) return true;
    if (compact.includes('สิบล้อ') || compact.includes('10ล้อ')) return true;
    if (/10\s*ล้อ/i.test(s)) return true;
    return false;
};

/** รายการรถใน dropdown เที่ยวรถ — หกล้อ/สิบล้อเท่านั้น (คงรถที่เลือกอยู่ถ้าโหลดจากประวัติ) */
export const vehicleTripDrumCarOptions = (
    cars: string[],
    includeVehicle = '',
): string[] => {
    const seen = new Set<string>();
    const out: string[] = [];
    const extra = includeVehicle.trim();
    if (extra && seen.add(extra)) out.push(extra);
    for (const c of cars) {
        if (!isSixOrTenWheelVehicleName(c)) continue;
        if (seen.has(c)) continue;
        seen.add(c);
        out.push(c);
    }
    return out;
};
