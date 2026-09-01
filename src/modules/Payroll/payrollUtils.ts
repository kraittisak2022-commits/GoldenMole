import type { Employee, SalaryHistoryItem, Transaction, PayrollSnapshot } from '../../types';
import {
    classifyAttendancePositionGroup,
    isSandYardOrMacroDriverEmployee,
    type AttendancePositionGroup,
} from '../../utils/advanceEmployeeFilter';

export type PayrollStatusFilter = 'all' | 'unpaid' | 'paid' | 'review';
export type PayrollGroupFilter = 'all' | AttendancePositionGroup;

export interface PayrollAdjustment {
    bonus: number;
    deduction: number;
    note: string;
}

export interface PayrollRow extends Employee {
    fullDays: number;
    halfDays: number;
    income: number;
    net: number;
    ot: number;
    adv: number;
    special: number;
    driverAllowance: number;
    basePay: number;
    transactions: Transaction[];
    isPaid: boolean;
    customBonus: number;
    customDeduction: number;
    adjNote: string;
    needsWageReview: boolean;
    group: AttendancePositionGroup;
}

export interface PayrollGroupSummary {
    group: AttendancePositionGroup;
    label: string;
    count: number;
    unpaid: number;
    paid: number;
    totalNet: number;
    pendingNet: number;
}

export interface PayrollPeriodSummary {
    totalEmployees: number;
    unpaidCount: number;
    paidCount: number;
    reviewCount: number;
    totalPendingNet: number;
    totalPaidNet: number;
    sandYard: PayrollGroupSummary;
    driver: PayrollGroupSummary;
}

const GROUP_LABELS: Record<AttendancePositionGroup, string> = {
    sandYard: 'พนักงานท่าทราย',
    driver: 'พนักงานขับรถแม็คโคร',
    other: 'อื่นๆ',
};

export const payrollGroupLabel = (group: AttendancePositionGroup) => GROUP_LABELS[group];

/** พนักงานที่มีสิทธิ์ออกเงินเดือน — ท่าทราย + คนขับแม็คโคร ที่ยัง active */
export const employeeEligibleForPayroll = (e: Employee): boolean =>
    !e.inactive && isSandYardOrMacroDriverEmployee(e);

export function getBanknoteBreakdown(amount: number): {
    b1000: number;
    b500: number;
    b100: number;
    remainder: number;
} {
    const a = Math.round(amount);
    const b1000 = Math.floor(a / 1000);
    let r = a % 1000;
    const b500 = Math.floor(r / 500);
    r = r % 500;
    const b100 = Math.floor(r / 100);
    const remainder = r % 100;
    return { b1000, b500, b100, remainder };
}

export function getDailyWageByDate(emp: Employee, date: string): number {
    const base = emp.baseWage ?? 0;
    if (!emp.salaryHistory || emp.salaryHistory.length === 0) {
        return emp.type === 'Monthly' ? base / 30 : base;
    }
    const history = [...emp.salaryHistory]
        .filter((h: SalaryHistoryItem) => !!h?.date)
        .sort((a, b) => a.date.localeCompare(b.date));
    if (history.length === 0) return emp.type === 'Monthly' ? base / 30 : base;
    let wage = history[0].oldWage || base;
    for (const h of history) {
        if (h.date <= date) wage = h.newWage;
        else break;
    }
    return emp.type === 'Monthly' ? wage / 30 : wage;
}

export function checkPayrollOverlap(
    transactions: Transaction[],
    empId: string,
    start: string,
    end: string,
): boolean {
    return transactions.some(
        (t) =>
            t.category === 'Payroll' &&
            t.employeeId === empId &&
            t.payrollPeriod &&
            start <= t.payrollPeriod.end &&
            end >= t.payrollPeriod.start,
    );
}

function isHalfDayForEmployee(t: Transaction, empId: string): boolean {
    if (t.laborStatus !== 'Work') return false;
    if (t.workTypeByEmployee && empId in t.workTypeByEmployee) {
        return t.workTypeByEmployee[empId] === 'HalfDay';
    }
    return t.workType === 'HalfDay';
}

export function calculateEmployeePayroll(
    emp: Employee,
    transactions: Transaction[],
    range: { start: string; end: string },
    adjustments: Record<string, PayrollAdjustment> = {},
): PayrollRow {
    const empTrans = transactions.filter(
        (t) =>
            t.date >= range.start &&
            t.date <= range.end &&
            (t.employeeId === emp.id || t.employeeIds?.includes(emp.id) || t.driverId === emp.id),
    );
    const workedTrans = empTrans.filter((t) => t.laborStatus === 'Work');
    const fullDays = workedTrans.filter((t) => !isHalfDayForEmployee(t, emp.id)).length;
    const halfDays = workedTrans.filter((t) => isHalfDayForEmployee(t, emp.id)).length;
    const ot = empTrans.reduce((s, t) => s + (t.otAmount || 0), 0);
    const adv = empTrans.reduce((s, t) => s + (t.advanceAmount || 0), 0);
    const special = empTrans.reduce((s, t) => s + (t.specialAmount || 0), 0);
    const driverAllowance = empTrans.reduce((s, t) => s + (t.driverWage || 0), 0);

    const adj = adjustments[emp.id] || { bonus: 0, deduction: 0, note: '' };

    const base = emp.baseWage ?? 0;
    let basePay = 0;
    if (emp.type === 'Monthly') {
        basePay = base;
    } else {
        basePay = workedTrans.reduce((sum, t) => {
            const dailyWage = getDailyWageByDate(emp, t.date);
            return sum + (isHalfDayForEmployee(t, emp.id) ? dailyWage / 2 : dailyWage);
        }, 0);
    }
    const totalIncome = basePay + ot + special + driverAllowance + adj.bonus;
    const totalDeductions = adv + adj.deduction;
    const netPay = totalIncome - totalDeductions;
    const isPaid = checkPayrollOverlap(transactions, emp.id, range.start, range.end);
    const needsWageReview = workedTrans.length > 0 && basePay <= 0;

    return {
        ...emp,
        fullDays,
        halfDays,
        income: totalIncome,
        net: netPay,
        ot,
        adv,
        special,
        driverAllowance,
        basePay,
        transactions: empTrans,
        isPaid,
        customBonus: adj.bonus,
        customDeduction: adj.deduction,
        adjNote: adj.note,
        needsWageReview,
        group: classifyAttendancePositionGroup(emp),
    };
}

export function buildPayrollRows(
    employees: Employee[],
    transactions: Transaction[],
    range: { start: string; end: string },
    adjustments: Record<string, PayrollAdjustment> = {},
): PayrollRow[] {
    return employees
        .filter(employeeEligibleForPayroll)
        .map((emp) => calculateEmployeePayroll(emp, transactions, range, adjustments))
        .sort((a, b) => {
            const g = a.group.localeCompare(b.group);
            if (g !== 0) return g;
            return (a.nickname || a.name).localeCompare(b.nickname || b.name, 'th');
        });
}

function summarizeGroup(rows: PayrollRow[], group: AttendancePositionGroup): PayrollGroupSummary {
    const inGroup = rows.filter((r) => r.group === group);
    const unpaid = inGroup.filter((r) => !r.isPaid);
    const paid = inGroup.filter((r) => r.isPaid);
    return {
        group,
        label: payrollGroupLabel(group),
        count: inGroup.length,
        unpaid: unpaid.length,
        paid: paid.length,
        totalNet: inGroup.reduce((s, r) => s + r.net, 0),
        pendingNet: unpaid.reduce((s, r) => s + r.net, 0),
    };
}

export function summarizePayrollPeriod(rows: PayrollRow[]): PayrollPeriodSummary {
    const unpaid = rows.filter((r) => !r.isPaid);
    const paid = rows.filter((r) => r.isPaid);
    return {
        totalEmployees: rows.length,
        unpaidCount: unpaid.length,
        paidCount: paid.length,
        reviewCount: rows.filter((r) => r.needsWageReview && !r.isPaid).length,
        totalPendingNet: unpaid.reduce((s, r) => s + r.net, 0),
        totalPaidNet: paid.reduce((s, r) => s + r.net, 0),
        sandYard: summarizeGroup(rows, 'sandYard'),
        driver: summarizeGroup(rows, 'driver'),
    };
}

export function filterPayrollRows(
    rows: PayrollRow[],
    opts: {
        search?: string;
        status?: PayrollStatusFilter;
        group?: PayrollGroupFilter;
    },
): PayrollRow[] {
    const q = (opts.search ?? '').trim().toLowerCase();
    return rows.filter((r) => {
        if (q && !r.name.toLowerCase().includes(q) && !r.nickname.toLowerCase().includes(q)) return false;
        if (opts.group && opts.group !== 'all' && r.group !== opts.group) return false;
        if (opts.status === 'unpaid' && r.isPaid) return false;
        if (opts.status === 'paid' && !r.isPaid) return false;
        if (opts.status === 'review' && (!r.needsWageReview || r.isPaid)) return false;
        return true;
    });
}

export function buildPayrollWarnings(
    rows: PayrollRow[],
    transactions: Transaction[],
    range: { start: string; end: string },
): string[] {
    const warns: string[] = [];
    const wageMissing = rows.filter((p) => !p.isPaid && p.needsWageReview);
    if (wageMissing.length > 0) {
        const names = wageMissing.slice(0, 5).map((p) => p.nickname || p.name).join(', ');
        warns.push(
            `พบพนักงานมีวันทำงานแต่ค่าแรงเป็น 0: ${names}${wageMissing.length > 5 ? ` (+${wageMissing.length - 5})` : ''} — ต้องแก้ค่าแรงก่อนจ่าย`,
        );
    }
    const hasSource = transactions.some(
        (t) => t.category !== 'Payroll' && t.date >= range.start && t.date <= range.end,
    );
    if (!hasSource) {
        warns.push('ไม่พบข้อมูลบันทึกงาน/ค่าแรงในงวดนี้ (ตรวจสอบช่วงวันที่ก่อนกดจ่าย)');
    }
    return warns;
}

export function buildPayrollSnapshot(row: PayrollRow): PayrollSnapshot {
    return {
        fullDays: row.fullDays,
        halfDays: row.halfDays,
        basePay: row.basePay,
        ot: row.ot,
        special: row.special,
        driverAllowance: row.driverAllowance,
        adv: row.adv,
        customBonus: row.customBonus,
        customDeduction: row.customDeduction,
        adjNote: row.adjNote,
        net: row.net,
    };
}

export function payrollRowsToCsv(
    rows: PayrollRow[],
    range: { start: string; end: string },
): string {
    const header = [
        'กลุ่ม',
        'ชื่อ',
        'ชื่อเล่น',
        'ประเภท',
        'วันเต็ม',
        'ครึ่งวัน',
        'ค่าแรง',
        'OT',
        'พิเศษ',
        'เบี้ยคนขับ',
        'โบนัส',
        'เบิกล่วงหน้า',
        'หักอื่น',
        'สุทธิ',
        'สถานะ',
        'หมายเหตุ',
    ];
    const lines = rows.map((r) =>
        [
            payrollGroupLabel(r.group),
            r.name,
            r.nickname,
            r.type === 'Monthly' ? 'รายเดือน' : 'รายวัน',
            r.fullDays,
            r.halfDays,
            r.basePay,
            r.ot,
            r.special,
            r.driverAllowance,
            r.customBonus,
            r.adv,
            r.customDeduction,
            r.net,
            r.isPaid ? 'จ่ายแล้ว' : r.needsWageReview ? 'ต้องตรวจสอบ' : 'รอจ่าย',
            r.adjNote,
        ]
            .map((v) => `"${String(v).replace(/"/g, '""')}"`)
            .join(','),
    );
    return `\uFEFF${header.join(',')}\n${lines.join('\n')}\n`;
}

export function downloadPayrollCsv(
    rows: PayrollRow[],
    range: { start: string; end: string },
): void {
    const csv = payrollRowsToCsv(rows, range);
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `payroll_${range.start}_${range.end}.csv`;
    a.click();
    URL.revokeObjectURL(url);
}
