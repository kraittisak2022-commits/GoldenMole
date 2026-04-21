import type { Employee, Transaction, WorkType } from '../types';

/** หลีกเลี่ยง circular import กับ utils/index */
const normDate = (d: string | undefined): string => (d && d.length >= 10 ? d.slice(0, 10) : d || '');

/** ประเภทงานสังเคราะห์สำหรับการลงเวลาผ่านเมนู "ค่าแรง/ลา" ให้สอดคล้องกับ Daily Wizard (workAssignments) */
export const LABOR_MENU_WORK_CATEGORY_ID = 'labor_menu_attendance';
export const LABOR_MENU_WORK_CATEGORY_LABEL = 'ลงเวลา (เมนูค่าแรง/ลา)';

export const isMonthlyEmployee = (emp?: Employee) => {
    if (!emp?.type) return false;
    const normalized = String(emp.type).trim().toLowerCase();
    return normalized === 'monthly' || normalized === 'รายเดือน';
};

/** ค่าแรงต่อวันก่อนหารครึ่งวัน — ตรงกับ Daily Wizard */
export const toDailyWage = (emp: Employee, wage: number) => (isMonthlyEmployee(emp) ? wage / 30 : wage);

export const dailyWageForWorkType = (emp: Employee, wage: number, workType: WorkType) => {
    const daily = toDailyWage(emp, wage);
    return workType === 'HalfDay' ? daily / 2 : daily;
};

/** คนขับที่มีรายการใช้รถในวันนั้น (รวมไม่ซ้ำ) — ใช้รวมกับรายการค่าแรงเหมือน Daily Wizard */
export const getVehicleDriverIdsForDate = (transactions: Transaction[], isoDate: string): string[] => {
    const norm = normDate(isoDate);
    const ids = transactions
        .filter((t) => normDate(t.date) === norm && t.category === 'Vehicle' && t.driverId)
        .map((t) => t.driverId as string);
    return [...new Set(ids)];
};

/** พนักงานที่มีรายการ Labor สถานะมาทำงานหรือ OT แล้วในวันนั้น */
export const getLaborWorkAndOtEmployeeIdsForDate = (
    transactions: Transaction[],
    isoDate: string,
    excludeTransactionId: string | null
): Set<string> => {
    const norm = normDate(isoDate);
    const out = new Set<string>();
    transactions.forEach((t) => {
        if (normDate(t.date) !== norm) return;
        if (t.category !== 'Labor') return;
        if (t.laborStatus !== 'Work' && t.laborStatus !== 'OT') return;
        if (excludeTransactionId && t.id === excludeTransactionId) return;
        (t.employeeIds || []).forEach((id) => out.add(id));
    });
    return out;
};
