import { describe, expect, it } from 'vitest';
import {
    computeSandDrumCarryoverEpochStart,
    persistedSandHomeDrums,
    sumWizardDailySpend,
    countsTowardWizardDailySpend,
} from './dailyStepRecorderUtils';
import type { Employee, Transaction } from '../../types';

const sand = (partial: Partial<Transaction> & { id: string }): Transaction =>
    ({
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'Sand',
        date: '2026-05-04',
        amount: 0,
        description: '',
        ...partial,
    }) as Transaction;

describe('persistedSandHomeDrums', () => {
    it('uses machine rows only when Old/New exist (ignores stale drums-only)', () => {
        const txs = [
            sand({
                id: 'orphan',
                description: 'จำนวนถังที่ได้วันนี้',
                sandMorning: 0,
                sandAfternoon: 0,
                drumsObtained: 100,
                drumsWashedAtHome: 55,
            }),
            sand({
                id: 'old',
                sandMachineType: 'Old',
                sandMorning: 10,
                sandAfternoon: 0,
                drumsObtained: 100,
                drumsWashedAtHome: 1,
            }),
            sand({
                id: 'new',
                sandMachineType: 'New',
                sandMorning: 0,
                sandAfternoon: 5,
                drumsObtained: 100,
                drumsWashedAtHome: 1,
            }),
        ];
        expect(persistedSandHomeDrums(txs)).toBe(1);
    });

    it('falls back to drums-only rows when no machine rows', () => {
        const txs = [
            sand({
                id: 'only',
                sandMorning: 0,
                sandAfternoon: 0,
                drumsObtained: 20,
                drumsWashedAtHome: 3,
            }),
        ];
        expect(persistedSandHomeDrums(txs)).toBe(3);
    });
});

describe('sumWizardDailySpend / countsTowardWizardDailySpend', () => {
    it('includes Labor with empty type (Android legacy row)', () => {
        const txs = [
            {
                id: '1',
                date: '2026-05-01',
                type: '' as any,
                category: 'Labor',
                subCategory: 'Attendance',
                description: 'ค่าแรง',
                amount: 4500,
                laborStatus: 'Work',
            } as Transaction,
        ];
        expect(countsTowardWizardDailySpend(txs[0])).toBe(true);
        expect(sumWizardDailySpend(txs)).toBe(4500);
    });

    it('excludes Income', () => {
        const txs = [
            {
                id: '1',
                date: '2026-05-01',
                type: 'Income',
                category: 'Income',
                description: 'ขาย',
                amount: 5000,
            } as Transaction,
        ];
        expect(sumWizardDailySpend(txs)).toBe(0);
    });

    it('includes explicit Expense and ignores zero Leave in sum', () => {
        const txs = [
            { id: 'a', date: '2026-05-01', type: 'Expense', category: 'Fuel', description: 'x', amount: 100 } as Transaction,
            { id: 'b', date: '2026-05-01', type: 'Leave', category: 'Labor', description: 'ลา', amount: 0 } as Transaction,
        ];
        expect(sumWizardDailySpend(txs)).toBe(100);
    });

    it('estimates Labor Attendance when amount is 0 (mobile / Flutter save pattern)', () => {
        const emps: Employee[] = [
            { id: 'a', name: 'A', nickname: 'A', type: 'Daily', baseWage: 500 },
            { id: 'b', name: 'B', nickname: 'B', type: 'Daily', baseWage: 600 },
        ];
        const txs = [
            {
                id: '1',
                date: '2026-05-01',
                type: 'Expense',
                category: 'Labor',
                subCategory: 'Attendance',
                laborStatus: 'Work',
                employeeIds: ['a', 'b'],
                amount: 0,
                description: 'ค่าแรง',
                workTypeByEmployee: { a: 'FullDay', b: 'HalfDay' },
            } as Transaction,
        ];
        expect(sumWizardDailySpend(txs, emps)).toBe(500 + 300);
    });

    it('sums Vehicle driverWage+vehicleWage when amount is 0', () => {
        const txs = [
            {
                id: 'v1',
                date: '2026-05-01',
                type: 'Expense',
                category: 'Vehicle',
                description: 'รถ',
                amount: 0,
                driverWage: 500,
                vehicleWage: 4500,
            } as Transaction,
        ];
        expect(sumWizardDailySpend(txs)).toBe(5000);
    });

    it('estimates OT when amount is 0 but otAmount and otHours are set', () => {
        const txs = [
            {
                id: 'ot1',
                date: '2026-05-01',
                type: 'Expense',
                category: 'Labor',
                subCategory: 'OT',
                laborStatus: 'OT',
                employeeIds: ['a', 'b'],
                amount: 0,
                otAmount: 100,
                otHours: 2,
                description: 'OT',
            } as Transaction,
        ];
        expect(sumWizardDailySpend(txs)).toBe(400);
    });
});

describe('computeSandDrumCarryoverEpochStart', () => {
    const trip = (id: string, date: string, cubic: number): Transaction =>
        ({
            id,
            type: 'Expense',
            category: 'DailyLog',
            subCategory: 'VehicleTrip',
            date,
            amount: 0,
            description: '',
            totalCubic: cubic,
        }) as Transaction;

    it('resets carryover on the day after an auto-completed round (remaining drums 0)', () => {
        const txs: Transaction[] = [
            trip('t1', '2026-05-01', 10),
            sand({ id: 's1', date: '2026-05-01', drumsObtained: 474, drumsWashedAtHome: 0, sandMorning: 1, sandAfternoon: 0 }),
            trip('t2', '2026-05-02', 10),
            sand({ id: 's2', date: '2026-05-02', drumsObtained: 0, drumsWashedAtHome: 200, sandMorning: 1, sandAfternoon: 0 }),
            trip('t3', '2026-05-03', 10),
            sand({ id: 's3', date: '2026-05-03', drumsObtained: 0, drumsWashedAtHome: 274, sandMorning: 1, sandAfternoon: 0 }),
        ];
        expect(computeSandDrumCarryoverEpochStart('2026-05-04', txs, { roundCloseMinDays: 2 })).toBe('2026-05-04');
    });

    it('matches manual_close_round by roundId start date when roundNo differs from a short-range UI', () => {
        const txs: Transaction[] = [
            trip('t1', '2026-05-01', 10),
            sand({ id: 's1', date: '2026-05-01', drumsObtained: 100, drumsWashedAtHome: 0, sandMorning: 1, sandAfternoon: 0 }),
            trip('t2', '2026-05-02', 10),
            sand({ id: 's2', date: '2026-05-02', drumsObtained: 0, drumsWashedAtHome: 100, sandMorning: 1, sandAfternoon: 0 }),
        ];
        const audit = [
            {
                id: 'a1',
                roundId: 'round_9_2026-05-01',
                action: 'manual_close_round' as const,
                createdAt: 'x',
            },
        ];
        expect(
            computeSandDrumCarryoverEpochStart('2026-05-03', txs, {
                sandRoundAuditTrail: audit,
                roundCloseMinDays: 999,
            }),
        ).toBe('2026-05-03');
    });
});
