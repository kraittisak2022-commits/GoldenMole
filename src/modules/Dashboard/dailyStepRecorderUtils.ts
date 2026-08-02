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
    'digHaul',
    'generalWork',
]);

/** กลุ่มพนักงานในขั้นค่าแรง (ไม่รวม «ทั้งหมด») — สอดคล้อง `_LaborEmpPoolKind` บน Android */
export type LaborEmployeePool = 'sifter' | 'excavatorMac' | 'nightWatch' | 'generalLabor';

const MACRO_EXCAVATOR_DRIVER_TITLES = new Set(['คนขับรถแม็คโคร', 'คนขับรถแมคโคร']);

/** รายการตำแหน่งจากฟิลด์ positions + position เดี่ยว */
export const getEmployeePositionTokens = (emp: Employee): string[] => {
    const parts = [...(emp.positions || [])]
        .map(p => String(p).trim())
        .filter(Boolean);
    const single = String(emp.position || '').trim();
    if (single && !parts.includes(single)) parts.push(single);
    return parts;
};

/** คนขับแม็คโคร — เฉพาะตำแหน่งชื่อเต็ม (ไม่ใช่ทุกคนที่มีคำว่าแม็คโครในตำแหน่ง) */
export const isMacroExcavatorDriverEmployee = (emp: Employee): boolean =>
    getEmployeePositionTokens(emp).some(p => MACRO_EXCAVATOR_DRIVER_TITLES.has(p));

export const isSandSievePoolEmployee = (emp: Employee): boolean =>
    getEmployeePositionTokens(emp).some(p => p.includes('ร่อน'));

export const isNightWatchPoolEmployee = (emp: Employee): boolean => {
    const blob = getEmployeePositionTokens(emp).join(' ').toLowerCase();
    return (
        blob.includes('เฝ้ากลางคืน') ||
        blob.includes('เวรกลางคืน') ||
        blob.includes('กลางคืน') ||
        blob.includes('night')
    );
};

export const isGeneralLaborPoolEmployee = (emp: Employee): boolean =>
    getEmployeePositionTokens(emp).some(p => {
        const t = p.trim();
        return t.includes('พนักงานทั่วไป') || t === 'ทั่วไป';
    });

/** จัดกลุ่มพนักงานในขั้นค่าแรง — ลำดับและเงื่อนไขเดียวกับ `_laborEmpPoolKindFor` บน Android */
export const classifyLaborEmployeePool = (emp: Employee): LaborEmployeePool | null => {
    if (isMacroExcavatorDriverEmployee(emp)) return 'excavatorMac';
    if (isSandSievePoolEmployee(emp)) return 'sifter';
    if (isNightWatchPoolEmployee(emp)) return 'nightWatch';
    if (isGeneralLaborPoolEmployee(emp)) return 'generalLabor';
    return null;
};

/** กล่องงานที่แสดงเมื่อเลือกกลุ่ม — คีย์เว็บหลัง `normalizeLaborCanvasKey` */
export const LABOR_POOL_FIXED_CANVAS_IDS: Record<LaborEmployeePool, string[]> = {
    sifter: ['wash1', 'wash2', 'washHome', 'pierWatch'],
    excavatorMac: ['digHaul'],
    nightWatch: ['nightShift'],
    generalLabor: [],
};

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
        case 'nightPatrol':
        case 'night_patrol':
            return 'nightShift';
        case 'digHaul':
        case 'dig_haul':
        case 'excavator_control':
        case 'macro_driver':
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

/** คีย์เช็คชื่อท่าทรายจากมือถือ (แถวแยกจากคนขับรถ) */
export const SAND_YARD_ATTENDANCE_ASSIGNMENT_KEYS = new Set([
    'work',
    'half:morning',
    'half:afternoon',
]);

/** คีย์เช็คชื่อคนขับรถจากมือถือ (แถวแยกจากท่าทราย) — drum:* คือคีย์เดิมก่อนรวมกะเช้า-บ่าย */
export const DRIVER_ATTENDANCE_ASSIGNMENT_KEYS = new Set([
    'macro_driver',
    'drum',
    'drum:morning',
    'drum:afternoon',
]);

const pushUniqueIds = (target: string[], ids: string[]) => {
    const seen = new Set(target);
    for (const raw of ids) {
        const id = String(raw || '').trim();
        if (!id || seen.has(id)) continue;
        seen.add(id);
        target.push(id);
    }
};

/** รวม workAssignments จากหลายแถว Labor Attendance/Work — union รายชื่อต่อคีย์ */
export const mergeAttendanceWorkAssignments = (
    rows: Array<Pick<Transaction, 'workAssignments'> | Transaction>,
): Record<string, string[]> => {
    const out: Record<string, string[]> = {};
    for (const row of rows) {
        const wa = row.workAssignments;
        if (!wa || typeof wa !== 'object') continue;
        for (const [key, ids] of Object.entries(wa)) {
            const k = String(key || '').trim();
            if (!k || !Array.isArray(ids) || ids.length === 0) continue;
            if (!out[k]) out[k] = [];
            pushUniqueIds(out[k], ids);
        }
    }
    return out;
};

/** รวม workTypeByEmployee จากหลายแถว — ค่าจากแถวหลังทับของเดิมเมื่อซ้ำ */
export const mergeAttendanceWorkTypeByEmployee = (
    rows: Array<{ workTypeByEmployee?: Record<string, string> } | Transaction>,
): Record<string, string> => {
    const out: Record<string, string> = {};
    for (const row of rows) {
        const wte = (row as { workTypeByEmployee?: Record<string, string> }).workTypeByEmployee;
        if (!wte || typeof wte !== 'object') continue;
        for (const [id, wt] of Object.entries(wte)) {
            const empId = String(id || '').trim();
            if (!empId || wt == null) continue;
            out[empId] = String(wt);
        }
    }
    return out;
};

const transactionHasOwnField = (tx: Transaction, field: string): boolean => {
    const rec = tx as unknown as Record<string, unknown>;
    if (!Object.prototype.hasOwnProperty.call(rec, field)) return false;
    return rec[field] !== undefined && rec[field] !== null;
};

/** เลือกแถวล่าสุดที่มีฟิลด์นั้นตั้งค่าจริง (เช่น drumsWashedAtHome) — ไม่ใช้แค่ Attendance ล่าสุด */
export const pickLatestWithDefinedField = <T extends Transaction>(
    items: T[],
    dayItems: Transaction[],
    field: string,
): T | null => {
    const withField = items.filter(t => transactionHasOwnField(t, field));
    if (withField.length === 0) return null;
    return pickLatestByDayOrder(withField, dayItems);
};

const laborAttendanceAssignmentKeys = (t: Transaction): Set<string> => {
    const keys = new Set<string>();
    const wa = t.workAssignments;
    if (!wa || typeof wa !== 'object') return keys;
    for (const [key, ids] of Object.entries(wa)) {
        const k = String(key || '').trim();
        if (!k || !Array.isArray(ids) || ids.length === 0) continue;
        keys.add(k);
    }
    return keys;
};

export type LaborAttendanceSection = 'sandYard' | 'driver' | 'other';

/** จัดประเภทแถว Attendance ตามคีย์ workAssignments ของมือถือ (ท่าทราย vs คนขับรถ) */
export const classifyLaborAttendanceSection = (t: Transaction): LaborAttendanceSection => {
    const keys = laborAttendanceAssignmentKeys(t);
    if (keys.size === 0) return 'other';
    let sand = 0;
    let driver = 0;
    let other = 0;
    keys.forEach((k) => {
        if (SAND_YARD_ATTENDANCE_ASSIGNMENT_KEYS.has(k)) sand += 1;
        else if (DRIVER_ATTENDANCE_ASSIGNMENT_KEYS.has(k)) driver += 1;
        else other += 1;
    });
    if (sand > 0 && driver === 0 && other === 0) return 'sandYard';
    if (driver > 0 && sand === 0 && other === 0) return 'driver';
    return 'other';
};

/** สองแถวเป็นคู่ intentional จากมือถือ (ท่าทราย + คนขับรถ) — คีย์ไม่ทับกัน */
export const laborAttendanceRowsAreSectionSeparated = (a: Transaction, b: Transaction): boolean => {
    const sa = classifyLaborAttendanceSection(a);
    const sb = classifyLaborAttendanceSection(b);
    return (sa === 'sandYard' && sb === 'driver') || (sa === 'driver' && sb === 'sandYard');
};

const sortedEmployeeIdSignature = (t: Transaction): string =>
    [...(t.employeeIds || [])].map(id => String(id).trim()).filter(Boolean).sort().join(',');

/** ซ้ำจริง: คีย์ทับกัน หรือชุดพนักงานเหมือนกันโดยไม่ใช่คู่แยก section */
export const areLaborAttendanceRowsTrueDuplicates = (a: Transaction, b: Transaction): boolean => {
    if (a.id === b.id) return false;
    if (laborAttendanceRowsAreSectionSeparated(a, b)) return false;
    const keysA = laborAttendanceAssignmentKeys(a);
    const keysB = laborAttendanceAssignmentKeys(b);
    for (const k of keysA) {
        if (keysB.has(k)) return true;
    }
    const empA = sortedEmployeeIdSignature(a);
    const empB = sortedEmployeeIdSignature(b);
    if (empA && empB && empA === empB) return true;
    return false;
};

/** รายการ Attendance ที่ซ้ำจริงในวันเดียวกัน (ไม่รวมคู่ท่าทราย+คนขับรถ) */
export const collectTrueDuplicateLaborAttendanceItems = (items: Transaction[]): Transaction[] => {
    if (items.length <= 1) return [];
    const flagged = new Set<string>();
    for (let i = 0; i < items.length; i += 1) {
        for (let j = i + 1; j < items.length; j += 1) {
            if (!areLaborAttendanceRowsTrueDuplicates(items[i], items[j])) continue;
            flagged.add(items[i].id);
            flagged.add(items[j].id);
        }
    }
    return items.filter(t => flagged.has(t.id));
};

/** รถหกล้อ / สิบล้อ */
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

/** รถดั๊ม / ดรัม (ชื่อในการตั้งค่ามักเป็น «รถดรัม…») */
export const isDumpTruckVehicleName = (raw?: string | null): boolean => {
    const s = (raw ?? '').trim();
    if (!s) return false;
    const compact = s.toLowerCase().replace(/\s+/g, '');
    if (compact.includes('ดั๊ม') || compact.includes('ดั้ม') || compact.includes('ดรัม')) return true;
    if (compact.includes('dump')) return true;
    return false;
};

/** รถที่เลือกได้ในเมนูบันทึกรถดรัมและจำนวนเที่ยว — ดรัม + หกล้อ/สิบล้อ (ไม่รวมแม็คโคร) */
export const isVehicleTripDrumCarName = (raw?: string | null): boolean => {
    const s = (raw ?? '').trim();
    if (!s) return false;
    const compact = s.toLowerCase().replace(/\s+/g, '');
    if (compact.includes('แม็คโคร') || compact.includes('แมคโคร') || compact.includes('excavator') || compact.includes('backhoe')) {
        return false;
    }
    return isDumpTruckVehicleName(s) || isSixOrTenWheelVehicleName(s);
};

/** รายการรถใน dropdown เที่ยวรถ — ดรัม + หกล้อ/สิบล้อ (คงรถที่เลือกอยู่ถ้าโหลดจากประวัติ) */
export const vehicleTripDrumCarOptions = (
    cars: string[],
    includeVehicle = '',
): string[] => {
    const seen = new Set<string>();
    const out: string[] = [];
    const extra = includeVehicle.trim();
    if (extra && seen.add(extra)) out.push(extra);
    for (const c of cars) {
        if (!isVehicleTripDrumCarName(c)) continue;
        if (seen.has(c)) continue;
        seen.add(c);
        out.push(c);
    }
    return out;
};

/** รถแม็คโคร — แยกจากรถดรัม/เที่ยว (สอดคล้อง mobile) */
export const isMacroVehicleId = (raw?: string | null): boolean => {
    const s = (raw ?? '').trim().toLowerCase();
    if (!s) return false;
    return (
        s.includes('แม็คโคร') ||
        s.includes('แมคโคร') ||
        s.includes('excavator') ||
        s.includes('backhoe')
    );
};

/**
 * ธุรกรรม «เที่ยวรถ» / รถดรัมจากมือถือ (category Vehicle ไม่มีค่าจ้างรถ)
 * ไม่รวมแม็คโคร หรือขั้น «การใช้รถ» ที่มีค่าจ้าง/ยอดเงิน
 */
export const transactionCountsAsVehicleTripMenu = (t: Transaction): boolean => {
    const subRaw = (t.subCategory ?? '').trim();
    if (t.category === 'Vehicle') {
        if (isMacroVehicleId(t.vehicleId)) return false;
        const amount = Number(t.amount || 0);
        const vehicleWage = Number((t as any).vehicleWage ?? 0);
        if (amount > 0 || vehicleWage > 0) return false;
        return true;
    }
    if (t.category !== 'DailyLog') return false;
    if (subRaw.toLowerCase() === 'sand') return false;
    if (String(t.description ?? '').includes('ทรายที่ล้างที่บ้าน')) return false;
    if (subRaw.toLowerCase() !== 'vehicletrip') return false;
    const hasVid = Boolean((t.vehicleId ?? '').trim() || (t.driverId ?? '').trim());
    if (!hasVid) return false;
    const mode = String((t as any).tripBillingMode ?? '').trim();
    const isLumpSum = mode.toLowerCase() === 'lumpsum' || mode === 'เหมา';
    if (isLumpSum) {
        const cubic = Number((t as any).perCarCubic ?? (t as any).totalCubic ?? 0);
        return cubic > 0;
    }
    const trips = Number((t as any).perCarTrips ?? (t as any).tripCount ?? 0);
    return trips > 0;
};

/** ขั้น Wizard «การใช้รถ» — ค่าจ้างรถ/เบี้ยคนขับ (ไม่ใช่เที่ยวดรัม/แม็คโคร) */
export const countsAsWizardVehicleUsageRecord = (t: Transaction): boolean =>
    t.category === 'Vehicle' &&
    !isMacroVehicleId(t.vehicleId) &&
    !transactionCountsAsVehicleTripMenu(t);

/** แถวล้างทรายเครื่องร่อน (ไม่นับแถวถังอย่างเดียว / ทรายที่บ้าน / ตัดรอบ) */
export const countsAsWizardSandWashRecord = (t: Transaction): boolean => {
    if (t.category !== 'DailyLog' || (t.subCategory ?? '').trim() !== 'Sand') return false;
    if (isDedicatedHomeSandRow(t)) return false;
    if (isHomeSandRoundCloseRow(t)) return false;
    const desc = String(t.description ?? '').trim();
    if (desc.includes('จำนวนถัง')) return false;
    const morning = Number(t.sandMorning ?? 0);
    const afternoon = Number(t.sandAfternoon ?? 0);
    if (morning + afternoon > 0) return true;
    const mt = String((t as any).sandMachineType ?? '').trim();
    return mt === 'Old' || mt === 'New';
};

export const sumWizardSandWashCubic = (txs: Transaction[]): number =>
    txs
        .filter(countsAsWizardSandWashRecord)
        .reduce((acc, t) => acc + Number(t.sandMorning || 0) + Number(t.sandAfternoon || 0), 0);

export type DayWizardStepStats = {
    laborCount: number;
    vehicleUsageCount: number;
    tripCount: number;
    sandWashCount: number;
    sandWashCubic: number;
    fuelCount: number;
    incomeCount: number;
    eventCount: number;
};

/** สรุปจำนวนรายการต่อขั้น Wizard — ใช้ใน «พบข้อมูลวันที่นี้», สรุปวันนี้, ขั้นตรวจสอบ */
export const computeDayWizardStepStats = (dayTransactions: Transaction[]): DayWizardStepStats => ({
    laborCount: dayTransactions.filter(t => t.category === 'Labor').length,
    vehicleUsageCount: dayTransactions.filter(countsAsWizardVehicleUsageRecord).length,
    tripCount: dayTransactions.filter(transactionCountsAsVehicleTripMenu).length,
    sandWashCount: dayTransactions.filter(countsAsWizardSandWashRecord).length,
    sandWashCubic: sumWizardSandWashCubic(dayTransactions),
    fuelCount: dayTransactions.filter(t => t.category === 'Fuel').length,
    incomeCount: dayTransactions.filter(t => t.category === 'Income' && t.type === 'Income').length,
    eventCount: dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'Event').length,
});
