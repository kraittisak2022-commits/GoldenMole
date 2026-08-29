import { describe, expect, it } from 'vitest';
import type { Employee, Transaction } from '../../types';
import { FUEL_VEHICLE_USAGE_SUB_CATEGORY } from '../../utils';
import { buildAttendanceSummary, buildMacroUsageSummary } from './dailyOpsCardUtils';

const dayKey = '2026-08-28';

const employees: Employee[] = [
    { id: 'e1', name: 'สมชาย', nickname: 'ชาย', type: 'Daily', positions: ['พนักงานท่าทราย'] },
    { id: 'e2', name: 'สมหญิง', nickname: 'หญิง', type: 'Daily', positions: ['พนักงานท่าทราย'] },
    { id: 'e3', name: 'สมศักดิ์', nickname: 'ศักดิ์', type: 'Daily', positions: ['คนขับรถแม็คโคร'] },
    { id: 'e4', name: 'สมปอง', nickname: 'ปอง', type: 'Daily', positions: ['พนักงานท่าทราย'], inactive: true },
    { id: 'e5', name: 'สมหมาย', nickname: 'หมาย', type: 'Daily', positions: ['คนขับรถ'] },
    { id: 'e6', name: 'สมจิตร', nickname: 'จิตร', type: 'Daily', positions: ['พนักงานท่าทราย'] },
    { id: 'e7', name: 'สมพร', nickname: 'พร', type: 'Daily', positions: ['คนขับรถแมคโคร'] },
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
    it('counts all Work/OT as present; leave/absent from sand-yard + driver roster', () => {
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
                employeeIds: ['e1', 'e2', 'e5'],
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
                employeeIds: ['e7'],
                leaveDays: 1,
            },
            {
                id: 'leave2',
                date: dayKey,
                type: 'Leave',
                category: 'Leave',
                description: 'ลา (inactive — ละเว้น)',
                amount: 0,
                laborStatus: 'Sick',
                employeeIds: ['e4'],
                leaveDays: 1,
            },
        ];

        const summary = buildAttendanceSummary(dayKey, transactions, employees);

        // present: e1,e2,e3,e5 — roster leave/absent: e1–e3,e5–e7 (e4 inactive)
        expect(summary.present).toBe(4);
        expect(summary.leave).toBe(1);
        expect(summary.absent).toBe(1);
        expect(summary.presentPeople).toHaveLength(4);
        const byId = Object.fromEntries(summary.presentPeople.map((p) => [p.id, p]));
        expect(byId.e1).toMatchObject({ name: 'ชาย', group: 'sandYard', ot: false });
        expect(byId.e2).toMatchObject({ name: 'หญิง', group: 'sandYard', ot: false });
        expect(byId.e3).toMatchObject({ name: 'ศักดิ์', group: 'driver', ot: false });
        expect(byId.e5).toMatchObject({ name: 'หมาย', group: 'driver', ot: false });
        expect(summary.absentPeople.map((p) => p.id)).toEqual(['e6']);
        expect(summary.leavePeople.map((p) => p.id)).toEqual(['e7']);
    });

    it('includes OT rows in present for all employees including drivers', () => {
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
            {
                id: 'ot2',
                date: dayKey,
                type: 'Expense',
                category: 'Labor',
                description: 'OT คนขับรถ',
                amount: 300,
                laborStatus: 'OT',
                employeeIds: ['e5'],
            },
        ];

        const summary = buildAttendanceSummary(dayKey, transactions, employees);
        expect(summary.present).toBe(2);
        expect(summary.presentPeople).toEqual(
            expect.arrayContaining([
                { id: 'e3', name: 'ศักดิ์', ot: true, group: 'driver' },
                { id: 'e5', name: 'หมาย', ot: true, group: 'driver' },
            ]),
        );
    });

    it('groups office staff as other when present', () => {
        const office: Employee = {
            id: 'e8',
            name: 'สมศรี',
            nickname: 'ศรี',
            type: 'Monthly',
            positions: ['บัญชี'],
        };
        const transactions: Transaction[] = [
            {
                id: 'l1',
                date: dayKey,
                type: 'Expense',
                category: 'Labor',
                description: 'ค่าแรง',
                amount: 500,
                laborStatus: 'Work',
                employeeIds: ['e8'],
            },
        ];

        const summary = buildAttendanceSummary(dayKey, transactions, [...employees, office]);
        expect(summary.presentPeople).toEqual([
            { id: 'e8', name: 'ศรี', ot: false, group: 'other' },
        ]);
        expect(summary.absent).toBe(6);
    });
});
