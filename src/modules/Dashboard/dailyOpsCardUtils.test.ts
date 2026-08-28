import { describe, expect, it } from 'vitest';
import type { Employee, Transaction } from '../../types';
import { FUEL_VEHICLE_USAGE_SUB_CATEGORY } from '../../utils';
import { buildAttendanceSummary, buildMacroUsageSummary } from './dailyOpsCardUtils';

const dayKey = '2026-08-28';

const employees: Employee[] = [
    { id: 'e1', name: 'สมชาย', nickname: 'ชาย', type: 'Daily' },
    { id: 'e2', name: 'สมหญิง', nickname: 'หญิง', type: 'Daily' },
    { id: 'e3', name: 'สมศักดิ์', nickname: 'ศักดิ์', type: 'Daily' },
    { id: 'e4', name: 'สมปอง', nickname: 'ปอง', type: 'Daily', inactive: true },
];

describe('buildMacroUsageSummary', () => {
    it('merges work rows and fuel liters per vehicle', () => {
        const transactions: Transaction[] = [
            {
                id: 'v1',
                date: dayKey,
                type: 'Expense',
                category: 'Vehicle',
                description: 'รถ: แม็คโคร 01',
                amount: 0,
                vehicleId: 'แม็คโคร 01',
                driverId: 'e1',
                workDetails: 'ขุดลาน',
                workType: 'FullDay',
            },
            {
                id: 'v2',
                date: dayKey,
                type: 'Expense',
                category: 'Vehicle',
                description: 'รถ: แม็คโคร 02',
                amount: 0,
                vehicleId: 'แม็คโคร 02',
                driverId: 'e2',
                workDetails: 'ถมดิน',
                workType: 'HalfDay',
            },
            {
                id: 'f1',
                date: dayKey,
                type: 'Expense',
                category: 'Fuel',
                subCategory: FUEL_VEHICLE_USAGE_SUB_CATEGORY,
                description: 'ใช้น้ำมันรถ แม็คโคร 01',
                amount: 500,
                quantity: 50,
                unit: 'L',
                vehicleId: 'แม็คโคร 01',
                fuelMovement: 'stock_out',
            },
            {
                id: 'f2',
                date: dayKey,
                type: 'Expense',
                category: 'Fuel',
                subCategory: FUEL_VEHICLE_USAGE_SUB_CATEGORY,
                description: 'ใช้น้ำมันรถ แม็คโคร 03',
                amount: 200,
                quantity: 20,
                unit: 'L',
                vehicleId: 'แม็คโคร 03',
                fuelMovement: 'stock_out',
            },
        ];

        const summary = buildMacroUsageSummary(dayKey, transactions, employees);

        expect(summary.vehicleCount).toBe(2);
        expect(summary.totalLiters).toBe(70);
        expect(summary.rows).toHaveLength(3);

        const macro01 = summary.rows.find((r) => r.vehicleId === 'แม็คโคร 01');
        expect(macro01?.driverLabel).toBe('ชาย');
        expect(macro01?.workType).toBe('FullDay');
        expect(macro01?.workDetails).toBe('ขุดลาน');
        expect(macro01?.liters).toBe(50);

        const macro03 = summary.rows.find((r) => r.vehicleId === 'แม็คโคร 03');
        expect(macro03?.driverLabel).toBe('—');
        expect(macro03?.liters).toBe(20);
    });

    it('returns empty summary when no macro data', () => {
        const summary = buildMacroUsageSummary(dayKey, [], employees);
        expect(summary.rows).toHaveLength(0);
        expect(summary.vehicleCount).toBe(0);
        expect(summary.totalLiters).toBe(0);
    });
});

describe('buildAttendanceSummary', () => {
    it('unions employee ids across multiple labor rows and counts leave/absent', () => {
        const transactions: Transaction[] = [
            {
                id: 'l1',
                date: dayKey,
                type: 'Expense',
                category: 'Labor',
                subCategory: 'Attendance',
                description: 'ค่าแรง',
                amount: 1000,
                laborStatus: 'Work',
                employeeIds: ['e1', 'e2'],
            },
            {
                id: 'l2',
                date: dayKey,
                type: 'Expense',
                category: 'Labor',
                subCategory: 'Attendance',
                description: 'ค่าแรง',
                amount: 500,
                laborStatus: 'Work',
                employeeIds: ['e2', 'e3'],
            },
            {
                id: 'leave1',
                date: dayKey,
                type: 'Leave',
                category: 'Leave',
                description: 'ลาป่วย',
                amount: 0,
                laborStatus: 'Sick',
                employeeIds: ['e4'],
                leaveDays: 1,
            },
        ];

        const summary = buildAttendanceSummary(dayKey, transactions, employees);

        expect(summary.present).toBe(3);
        expect(summary.leave).toBe(1);
        expect(summary.absent).toBe(0);
        expect(summary.presentNames).toHaveLength(3);
        expect(summary.presentNames).toContain('ชาย');
        expect(summary.presentNames).toContain('หญิง');
        expect(summary.presentNames).toContain('ศักดิ์');
    });

    it('includes OT rows in present count', () => {
        const transactions: Transaction[] = [
            {
                id: 'ot1',
                date: dayKey,
                type: 'Expense',
                category: 'Labor',
                description: 'OT',
                amount: 300,
                laborStatus: 'OT',
                employeeIds: ['e3'],
            },
        ];

        const summary = buildAttendanceSummary(dayKey, transactions, employees);
        expect(summary.present).toBe(1);
        expect(summary.presentNames).toEqual(['ศักดิ์']);
    });
});
