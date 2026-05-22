import type { Employee, Transaction } from '../../types';
import { leaveRecordCoversDay, isLaborLeaveRecord } from '../../utils/laborLeaveSpan';
import {
    isHomeSandRoundCloseRow,
    isMacroVehicleId,
    transactionCountsAsVehicleTripMenu,
} from '../Dashboard/dailyStepRecorderUtils';

export type DailyModuleFillStatus = 'pending' | 'incomplete' | 'complete';

const isDedicatedHomeSandWashRow = (t: Transaction): boolean =>
    String(t.description ?? '').includes('ทรายที่ล้างที่บ้าน') && !isHomeSandRoundCloseRow(t);

export const isMacroVehicleTransaction = (t: Transaction): boolean =>
    t.category === 'Vehicle' && isMacroVehicleId(t.vehicleId);

export function transactionAppliesToDashboardDay(t: Transaction, dayKey: string, moduleCategory: string): boolean {
    if (moduleCategory === 'ลางาน') return leaveRecordCoversDay(t, dayKey);
    return String(t.date || '').trim().slice(0, 10) === dayKey.trim();
}

export function transactionIsUtilitiesExpense(t: Transaction): boolean {
    return t.category === 'Utilities' && String(t.type ?? '').trim().toLowerCase() === 'expense';
}

export function transactionIsWizardDailyIncome(t: Transaction): boolean {
    return t.category === 'Income' && String(t.type ?? '').trim().toLowerCase() === 'income';
}

export function resolveIncomeUtilitiesFillStatus(dayKey: string, transactions: Transaction[]): DailyModuleFillStatus {
    let hasUtilities = false;
    let hasIncome = false;
    for (const t of transactions) {
        if (String(t.date || '').trim() !== dayKey.trim()) continue;
        if (transactionIsUtilitiesExpense(t)) hasUtilities = true;
        if (transactionIsWizardDailyIncome(t)) hasIncome = true;
    }
    if (hasUtilities && hasIncome) return 'complete';
    if (hasUtilities || hasIncome) return 'incomplete';
    return 'pending';
}

export function transactionMatchesVehicleTripModuleList(t: Transaction): boolean {
    if (isMacroVehicleTransaction(t)) return false;
    if (String(t.description ?? '').includes('ทรายที่ล้างที่บ้าน')) return false;
    if (t.category === 'Vehicle') return true;
    if (t.category === 'DailyLog' && String(t.subCategory ?? '').trim().toLowerCase() === 'vehicletrip') {
        const hasVid = Boolean(String(t.vehicleId ?? '').trim() || String(t.driverId ?? '').trim());
        return hasVid;
    }
    return false;
}

function transactionTouchesDailyModule(t: Transaction, dayKey: string, moduleCategory: string): boolean {
    if (!transactionAppliesToDashboardDay(t, dayKey, moduleCategory)) return false;

    const sandWashTouches = (): boolean => {
        if (String(t.description ?? '').includes('ทรายที่ล้างที่บ้าน')) return false;
        if (String(t.subCategory ?? '').toLowerCase() === 'sand') return true;
        if (t.category.includes('ร่อนทราย')) return true;
        if (Number(t.sandMorning ?? 0) > 0 || Number(t.sandAfternoon ?? 0) > 0) return true;
        if (Number((t as { drumsObtained?: number }).drumsObtained ?? 0) > 0) return true;
        return false;
    };

    const homeSandTouches = (): boolean => {
        if (Number((t as { drumsWashedAtHome?: number }).drumsWashedAtHome ?? 0) > 0) return true;
        if (String(t.description ?? '').includes('ทรายที่ล้างที่บ้าน')) return true;
        return false;
    };

    const vehicleTouches = (): boolean => {
        if (transactionCountsAsVehicleTripMenu(t)) return true;
        if (t.category === 'Vehicle' && !isMacroVehicleTransaction(t)) return true;
        const subRaw = String(t.subCategory ?? '').trim();
        if (subRaw.toLowerCase() === 'vehicletrip') return true;
        if (t.category !== 'DailyLog') return false;
        if (subRaw.toLowerCase() === 'sand') return false;
        if (String(t.description ?? '').includes('ทรายที่ล้างที่บ้าน')) return false;
        return (
            Boolean(String(t.vehicleId ?? '').trim()) ||
            Boolean(String(t.driverId ?? '').trim()) ||
            Boolean(String(t.workDetails ?? '').trim()) ||
            Number((t as { perCarTrips?: number }).perCarTrips ?? 0) > 0 ||
            Number((t as { tripCount?: number }).tripCount ?? 0) > 0 ||
            Number((t as { tripMorning?: number }).tripMorning ?? 0) > 0 ||
            Number((t as { tripAfternoon?: number }).tripAfternoon ?? 0) > 0 ||
            Number((t as { cubicPerTrip?: number }).cubicPerTrip ?? 0) > 0 ||
            Number((t as { totalCubic?: number }).totalCubic ?? 0) > 0
        );
    };

    const fuelTouches = () => t.category === 'Fuel';

    const dailyEventTouches = (): boolean => {
        if (t.category !== 'DailyLog') return false;
        return String(t.subCategory ?? '').trim() === 'Event';
    };

    const macroVehicleTouches = (): boolean =>
        t.category === 'Vehicle' &&
        isMacroVehicleTransaction(t) &&
        (Boolean(String(t.vehicleId ?? '').trim()) ||
            Boolean(String(t.driverId ?? '').trim()) ||
            Boolean(String(t.workDetails ?? '').trim()));

    const laborTouches = (): boolean => {
        if (t.category === 'Leave') return false;
        if (t.category !== 'Labor') return false;
        const ls = String(t.laborStatus ?? '').toLowerCase();
        const sc = String(t.subCategory ?? '').toLowerCase();
        if (sc === 'ot' || ls === 'ot') return false;
        if (sc === 'advance' || ls === 'advance') return false;
        if (ls === 'leave' || ls === 'sick' || ls === 'personal') return false;
        return true;
    };

    const leaveRecordTouches = (): boolean => isLaborLeaveRecord(t);

    const advanceRecordTouches = (): boolean =>
        t.category === 'Labor' &&
        String(t.subCategory ?? '').trim().toLowerCase() === 'advance' &&
        String(t.laborStatus ?? '').trim().toLowerCase() === 'advance';

    const otTouches = (): boolean =>
        t.category === 'Labor' &&
        (String(t.laborStatus ?? '').toUpperCase() === 'OT' || String(t.subCategory ?? '').toLowerCase() === 'ot');

    switch (moduleCategory) {
        case 'บันทึกการร่อนทราย':
            return sandWashTouches();
        case 'ทรายที่ล้างที่บ้าน':
            return homeSandTouches();
        case 'จำนวนเที่ยวรถ':
            return vehicleTouches();
        case 'การใช้รถแม็คโคร':
            return macroVehicleTouches();
        case 'น้ำมัน':
            return fuelTouches();
        case 'เหตุการณ์':
            return dailyEventTouches();
        case 'ค่าแรง':
            return t.category === 'ค่าแรง' || laborTouches();
        case 'บันทึกการทำงาน':
            return laborTouches() || t.category === 'ค่าแรง';
        case 'ลางาน':
            return leaveRecordTouches();
        case 'เบิกเงิน':
            return advanceRecordTouches();
        case 'OT':
            return otTouches();
        case 'รายจ่ายรายรับ':
            return transactionIsUtilitiesExpense(t) || transactionIsWizardDailyIncome(t);
        default:
            if (moduleCategory.includes('ล่วงเวลา')) return otTouches();
            return t.category === moduleCategory;
    }
}

export function transactionMatchesDailyModule(t: Transaction, dayKey: string, moduleCategory: string): boolean {
    if (!transactionAppliesToDashboardDay(t, dayKey, moduleCategory)) return false;

    const sandWashLike = (): boolean => {
        if (String(t.description ?? '').includes('ทรายที่ล้างที่บ้าน')) return false;
        if (String(t.subCategory ?? '').trim() === 'Sand') return true;
        if (t.category.includes('ร่อนทราย')) return true;
        if (Number(t.sandMorning ?? 0) > 0 || Number(t.sandAfternoon ?? 0) > 0) return true;
        const desc = String(t.description ?? '');
        if (
            Number((t as { drumsObtained?: number }).drumsObtained ?? 0) > 0 &&
            (desc.includes('ถัง') || desc.includes('จำนวนถัง'))
        ) {
            return true;
        }
        return false;
    };

    const homeSandLike = (): boolean => {
        if (isHomeSandRoundCloseRow(t)) return true;
        return (
            isDedicatedHomeSandWashRow(t) ||
            (Number((t as { drumsWashedAtHome?: number }).drumsWashedAtHome ?? 0) > 0 &&
                String(t.description ?? '').includes('ล้างที่บ้าน'))
        );
    };

    const vehicleLike = () => transactionMatchesVehicleTripModuleList(t);

    const macroVehicleLike = (): boolean =>
        t.category === 'Vehicle' &&
        isMacroVehicleTransaction(t) &&
        Boolean(String(t.vehicleId ?? '').trim()) &&
        Boolean(String(t.driverId ?? '').trim());

    const fuelLike = () => t.category === 'Fuel';

    const dailyEventLike = (): boolean => {
        if (t.category !== 'DailyLog') return false;
        if (String(t.subCategory ?? '').trim() !== 'Event') return false;
        return String(t.description ?? '').trim().length > 0;
    };

    const laborLike = (): boolean => {
        if (t.category !== 'Labor') return false;
        const ls = String(t.laborStatus ?? '').toLowerCase();
        const sc = String(t.subCategory ?? '').toLowerCase();
        if (sc === 'ot' || ls === 'ot') return false;
        if (sc === 'advance' || ls === 'advance') return false;
        if (ls === 'leave' || ls === 'sick' || ls === 'personal') return false;
        return true;
    };

    const otLike = (): boolean =>
        t.category === 'Labor' &&
        (String(t.laborStatus ?? '').toUpperCase() === 'OT' || String(t.subCategory ?? '').toLowerCase() === 'ot');

    const leaveLike = (): boolean => isLaborLeaveRecord(t) && (t.employeeIds?.length ?? 0) > 0;

    const advanceLike = (): boolean =>
        t.category === 'Labor' &&
        String(t.subCategory ?? '').trim().toLowerCase() === 'advance' &&
        String(t.laborStatus ?? '').trim().toLowerCase() === 'advance' &&
        (t.employeeIds?.length ?? 0) > 0;

    switch (moduleCategory) {
        case 'บันทึกการร่อนทราย':
            return sandWashLike();
        case 'ทรายที่ล้างที่บ้าน':
            return homeSandLike();
        case 'จำนวนเที่ยวรถ':
            return vehicleLike();
        case 'การใช้รถแม็คโคร':
            return macroVehicleLike();
        case 'น้ำมัน':
            return fuelLike();
        case 'เหตุการณ์':
            return dailyEventLike();
        case 'ค่าแรง':
            return t.category === 'ค่าแรง' || laborLike();
        case 'บันทึกการทำงาน':
            return laborLike() || t.category === 'ค่าแรง';
        case 'ลางาน':
            return leaveLike();
        case 'เบิกเงิน':
            return advanceLike();
        case 'OT':
            return otLike();
        case 'รายจ่ายรายรับ':
            return transactionIsUtilitiesExpense(t) || transactionIsWizardDailyIncome(t);
        default:
            if (moduleCategory.includes('ล่วงเวลา')) return otLike();
            return t.category === moduleCategory;
    }
}

export function resolveDailyModuleFillStatus(
    dayKey: string,
    moduleCategory: string,
    transactions: Transaction[],
): DailyModuleFillStatus {
    if (moduleCategory === 'รายจ่ายรายรับ') {
        return resolveIncomeUtilitiesFillStatus(dayKey, transactions);
    }
    let complete = false;
    let touch = false;
    for (const t of transactions) {
        if (!transactionAppliesToDashboardDay(t, dayKey, moduleCategory)) continue;
        if (transactionMatchesDailyModule(t, dayKey, moduleCategory)) {
            complete = true;
            break;
        }
        if (transactionTouchesDailyModule(t, dayKey, moduleCategory)) touch = true;
    }
    if (complete) return 'complete';
    if (touch) {
        const isOtMenu = moduleCategory === 'OT' || moduleCategory.includes('ล่วงเวลา');
        if (isOtMenu) return 'complete';
        return 'incomplete';
    }
    return 'pending';
}

export function calendarEmployeeDisplayName(id: string, employees: Employee[]): string {
    for (const e of employees) {
        if (e.id === id) {
            if (String(e.nickname ?? '').trim()) return String(e.nickname).trim();
            if (String(e.name ?? '').trim()) return String(e.name).trim();
            break;
        }
    }
    return id.trim() || 'ไม่ทราบชื่อ';
}

export function dailyLeaveEmployeeNamesOnDay(
    dayKey: string,
    transactions: Transaction[],
    employees: Employee[],
): string[] {
    const rows = transactions.filter(t => leaveRecordCoversDay(t, dayKey));
    const ids = new Set<string>();
    for (const row of rows) {
        for (const id of row.employeeIds || []) ids.add(id);
    }
    return [...ids].map(id => calendarEmployeeDisplayName(id, employees));
}

function formatSandCubicForCard(v: number): string {
    if (v <= 0) return '0';
    if (Math.abs(v - Math.round(v)) < 1e-9) return String(Math.round(v));
    return v.toFixed(1);
}

export function isSandWashMachineProductionRow(t: Transaction): boolean {
    const desc = String(t.description ?? '');
    if (desc.includes('ทรายที่ล้างที่บ้าน')) return false;
    if (isHomeSandRoundCloseRow(t)) return false;
    const morning = Number(t.sandMorning ?? 0);
    const afternoon = Number(t.sandAfternoon ?? 0);
    if (morning > 0 || afternoon > 0) return true;
    const mt = String(t.sandMachineType ?? '').trim().toLowerCase();
    if (mt === 'old' || mt === 'new') return true;
    if (desc.includes('เครื่องร่อน')) return true;
    return false;
}

export function summarizeSandWashCubicForDay(
    dayKey: string,
    transactions: Transaction[],
): { morning: number; afternoon: number } {
    let morning = 0;
    let afternoon = 0;
    for (const t of transactions) {
        if (!transactionAppliesToDashboardDay(t, dayKey, 'บันทึกการร่อนทราย')) continue;
        if (!isSandWashMachineProductionRow(t)) continue;
        morning += Number(t.sandMorning ?? 0);
        afternoon += Number(t.sandAfternoon ?? 0);
    }
    return { morning, afternoon };
}

/** ข้อความการ์ดเมนู «บันทึกการร่อนทราย» — คิวเช้า/บ่าย/รวม (เครื่องใหม่+เก่า) */
export function dailySandWashModuleStatusLabel(
    dayKey: string,
    transactions: Transaction[],
): string {
    const { morning, afternoon } = summarizeSandWashCubicForDay(dayKey, transactions);
    const total = morning + afternoon;
    if (total <= 0) return '';
    return `เช้า ${formatSandCubicForCard(morning)} · บ่าย ${formatSandCubicForCard(afternoon)} · รวม ${formatSandCubicForCard(total)} คิว`;
}

export function dailyLeaveModuleStatusLabel(
    dayKey: string,
    transactions: Transaction[],
    employees: Employee[],
    maxNames = 2,
): string {
    const names = dailyLeaveEmployeeNamesOnDay(dayKey, transactions, employees);
    const n = names.length;
    if (n === 0) return 'ยังไม่มีรายการลา';
    const head = `ลา ${n} คน`;
    if (n <= maxNames) return `${head} · ${names.join(', ')}`;
    return `${head} · ${names.slice(0, maxNames).join(', ')} +${n - maxNames}`;
}

export function filterTransactionsForDay(dayKey: string, transactions: Transaction[]): Transaction[] {
    const dayRows = transactions.filter(t => String(t.date || '').trim().slice(0, 10) === dayKey);
    const seen = new Set(dayRows.map(t => t.id));
    const overlappingLeave = transactions.filter(t => leaveRecordCoversDay(t, dayKey) && !seen.has(t.id));
    return [...dayRows, ...overlappingLeave];
}
