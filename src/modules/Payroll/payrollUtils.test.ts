import { describe, expect, it } from 'vitest';
import type { Employee, Transaction } from '../../types';
import {
    buildPayrollRows,
    buildPayrollWarnings,
    calculateEmployeePayroll,
    employeeEligibleForPayroll,
    filterPayrollRows,
    summarizePayrollPeriod,
} from './payrollUtils';

const range = { start: '2026-08-01', end: '2026-08-31' };

const employees: Employee[] = [
    { id: 'e1', name: 'สมชาย', nickname: 'ชาย', type: 'Daily', baseWage: 400, positions: ['พนักงานท่าทราย'] },
    { id: 'e2', name: 'สมหญิง', nickname: 'หญิง', type: 'Daily', baseWage: 400, positions: ['พนักงานท่าทราย'], inactive: true },
    { id: 'e3', name: 'สมศักดิ์', nickname: 'ศักดิ์', type: 'Daily', baseWage: 500, positions: ['คนขับรถแม็คโคร'] },
    { id: 'e4', name: 'สมหมาย', nickname: 'หมาย', type: 'Daily', baseWage: 450, positions: ['คนขับรถ'] },
    { id: 'e5', name: 'สมศรี', nickname: 'ศรี', type: 'Monthly', baseWage: 15000, positions: ['บัญชี'] },
];

describe('employeeEligibleForPayroll', () => {
    it('includes sand-yard and macro drivers only', () => {
        expect(employeeEligibleForPayroll(employees[0]!)).toBe(true);
        expect(employeeEligibleForPayroll(employees[2]!)).toBe(true);
    });

    it('excludes inactive, generic drivers, and office staff', () => {
        expect(employeeEligibleForPayroll(employees[1]!)).toBe(false);
        expect(employeeEligibleForPayroll(employees[3]!)).toBe(false);
        expect(employeeEligibleForPayroll(employees[4]!)).toBe(false);
    });
});

describe('buildPayrollRows', () => {
    it('returns only eligible employees sorted by group', () => {
        const rows = buildPayrollRows(employees, [], range);
        expect(rows.map((r) => r.id)).toEqual(['e3', 'e1']);
        expect(rows[0]!.group).toBe('driver');
        expect(rows[1]!.group).toBe('sandYard');
    });
});

describe('calculateEmployeePayroll', () => {
    it('computes daily wage from work transactions', () => {
        const txs: Transaction[] = [
            {
                id: 'w1',
                date: '2026-08-10',
                type: 'Expense',
                category: 'Labor',
                description: 'work',
                amount: 400,
                laborStatus: 'Work',
                employeeIds: ['e1'],
            },
        ];
        const row = calculateEmployeePayroll(employees[0]!, txs, range);
        expect(row.fullDays).toBe(1);
        expect(row.basePay).toBe(400);
        expect(row.net).toBe(400);
        expect(row.needsWageReview).toBe(false);
    });

    it('flags wage review when work exists but pay is zero', () => {
        const zeroWage: Employee = { ...employees[0]!, baseWage: 0 };
        const txs: Transaction[] = [
            {
                id: 'w1',
                date: '2026-08-10',
                type: 'Expense',
                category: 'Labor',
                description: 'work',
                amount: 0,
                laborStatus: 'Work',
                employeeIds: ['e1'],
            },
        ];
        const row = calculateEmployeePayroll(zeroWage, txs, range);
        expect(row.needsWageReview).toBe(true);
    });
});

describe('filterPayrollRows', () => {
    const rows = buildPayrollRows(employees, [], range);

    it('filters by group and status', () => {
        expect(filterPayrollRows(rows, { group: 'driver' }).map((r) => r.id)).toEqual(['e3']);
        expect(filterPayrollRows(rows, { search: 'ชาย' }).map((r) => r.id)).toEqual(['e1']);
    });
});

describe('summarizePayrollPeriod', () => {
    it('aggregates group totals', () => {
        const summary = summarizePayrollPeriod(buildPayrollRows(employees, [], range));
        expect(summary.totalEmployees).toBe(2);
        expect(summary.sandYard.count).toBe(1);
        expect(summary.driver.count).toBe(1);
    });
});

describe('buildPayrollWarnings', () => {
    it('warns when wage review needed', () => {
        const zeroWage: Employee = { ...employees[0]!, baseWage: 0 };
        const txs: Transaction[] = [
            {
                id: 'w1',
                date: '2026-08-10',
                type: 'Expense',
                category: 'Labor',
                description: 'work',
                amount: 0,
                laborStatus: 'Work',
                employeeIds: ['e1'],
            },
        ];
        const rows = buildPayrollRows([zeroWage, ...employees.slice(1)], txs, range);
        const warns = buildPayrollWarnings(rows, txs, range);
        expect(warns.some((w) => w.includes('ค่าแรงเป็น 0'))).toBe(true);
    });
});
