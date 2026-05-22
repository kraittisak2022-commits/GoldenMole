import { describe, expect, it } from 'vitest';
import {
    computeDayWizardStepStats,
    computeSandDrumStockSummary,
    countsAsWizardSandWashRecord,
    countsAsWizardVehicleUsageRecord,
    isDumpTruckVehicleName,
    isSixOrTenWheelVehicleName,
    isVehicleTripDrumCarName,
    mergeLaborCanvasAssignments,
    normalizeLaborCanvasKey,
    persistedSandHomeDrums,
    sumWizardDailySpend,
    countsTowardWizardDailySpend,
    transactionCountsAsVehicleTripMenu,
    vehicleTripDrumCarOptions,
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

    it('prefers dedicated ทรายที่ล้างที่บ้าน rows over machine drumsWashedAtHome', () => {
        const txs = [
            sand({
                id: 'old',
                sandMachineType: 'Old',
                sandMorning: 10,
                sandAfternoon: 0,
                drumsObtained: 26,
                drumsWashedAtHome: 55,
            }),
            sand({
                id: 'home',
                description: 'ทรายที่ล้างที่บ้าน',
                drumsObtained: 0,
                drumsWashedAtHome: 10,
                sandMorning: 0,
                sandAfternoon: 0,
            }),
        ];
        expect(persistedSandHomeDrums(txs)).toBe(10);
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

describe('computeSandDrumStockSummary', () => {
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

    it('accumulates 26 → 52 → 78 across three days (single open sand round)', () => {
        const all: Transaction[] = [
            trip('v4', '2026-01-04', 10),
            sand({
                id: 's4',
                date: '2026-01-04',
                drumsObtained: 27,
                drumsWashedAtHome: 1,
                sandMorning: 1,
                sandAfternoon: 0,
            }),
            trip('v5', '2026-01-05', 10),
            sand({
                id: 's5',
                date: '2026-01-05',
                drumsObtained: 26,
                drumsWashedAtHome: 0,
                sandMorning: 1,
                sandAfternoon: 0,
            }),
            trip('v6', '2026-01-06', 10),
            sand({
                id: 's6',
                date: '2026-01-06',
                drumsObtained: 26,
                drumsWashedAtHome: 0,
                sandMorning: 1,
                sandAfternoon: 0,
            }),
        ];

        const day4 = computeSandDrumStockSummary('2026-01-04', all.slice(0, 2), {});
        expect(day4.cumulativeBeforeToday).toBe(0);
        expect(day4.cumulativeRemaining).toBe(26);

        const day5 = computeSandDrumStockSummary('2026-01-05', all.slice(0, 4), {});
        expect(day5.cumulativeBeforeToday).toBe(26);
        expect(day5.cumulativeRemaining).toBe(52);

        const day6 = computeSandDrumStockSummary('2026-01-06', all, {});
        expect(day6.cumulativeBeforeToday).toBe(52);
        expect(day6.cumulativeRemaining).toBe(78);
    });

    /** สเปกจากผู้ใช้: วันที่ 4–6 ได้ถังละ 26 ไม่ล้างที่บ้าน → คงเหลือหลังวัน 26 / 52 / 78 */
    it('26 drums obtained each day, 0 washed at home: before 0,26,52 and remaining 26,52,78', () => {
        const d4 = sand({
            id: 'home4',
            date: '2026-05-04',
            drumsObtained: 26,
            drumsWashedAtHome: 0,
            sandMorning: 1,
            sandAfternoon: 0,
            sandMachineType: 'Old',
        });
        const d5 = sand({
            id: 'home5',
            date: '2026-05-05',
            drumsObtained: 26,
            drumsWashedAtHome: 0,
            sandMorning: 1,
            sandAfternoon: 0,
            sandMachineType: 'Old',
        });
        const d6 = sand({
            id: 'home6',
            date: '2026-05-06',
            drumsObtained: 26,
            drumsWashedAtHome: 0,
            sandMorning: 1,
            sandAfternoon: 0,
            sandMachineType: 'Old',
        });
        const all = [d4, d5, d6];

        const s4 = computeSandDrumStockSummary('2026-05-04', all.slice(0, 1), {});
        expect(s4.cumulativeBeforeToday).toBe(0);
        expect(s4.todayObtained).toBe(26);
        expect(s4.cumulativeRemaining).toBe(26);

        const s5 = computeSandDrumStockSummary('2026-05-05', all.slice(0, 2), {});
        expect(s5.cumulativeBeforeToday).toBe(26);
        expect(s5.todayObtained).toBe(26);
        expect(s5.cumulativeRemaining).toBe(52);

        const s6 = computeSandDrumStockSummary('2026-05-06', all, {});
        expect(s6.cumulativeBeforeToday).toBe(52);
        expect(s6.todayObtained).toBe(26);
        expect(s6.cumulativeRemaining).toBe(78);
    });

    it('26 obtained per day with home wash 0, 10, 20: before 0,26,42 and remaining 26,42,48', () => {
        const d4 = sand({
            id: 'h4',
            date: '2026-05-04',
            drumsObtained: 26,
            drumsWashedAtHome: 0,
            sandMorning: 1,
            sandAfternoon: 0,
            sandMachineType: 'Old',
        });
        const d5 = sand({
            id: 'h5',
            date: '2026-05-05',
            drumsObtained: 26,
            drumsWashedAtHome: 10,
            sandMorning: 1,
            sandAfternoon: 0,
            sandMachineType: 'Old',
        });
        const d6 = sand({
            id: 'h6',
            date: '2026-05-06',
            drumsObtained: 26,
            drumsWashedAtHome: 20,
            sandMorning: 1,
            sandAfternoon: 0,
            sandMachineType: 'Old',
        });
        const all = [d4, d5, d6];

        const s4 = computeSandDrumStockSummary('2026-05-04', all.slice(0, 1), {});
        expect(s4.cumulativeBeforeToday).toBe(0);
        expect(s4.todayHome).toBe(0);
        expect(s4.cumulativeRemaining).toBe(26);

        const s5 = computeSandDrumStockSummary('2026-05-05', all.slice(0, 2), {});
        expect(s5.cumulativeBeforeToday).toBe(26);
        expect(s5.todayHome).toBe(10);
        expect(s5.cumulativeRemaining).toBe(42);

        const s6 = computeSandDrumStockSummary('2026-05-06', all, {});
        expect(s6.cumulativeBeforeToday).toBe(42);
        expect(s6.todayHome).toBe(20);
        expect(s6.cumulativeRemaining).toBe(48);
    });
});

describe('normalizeLaborCanvasKey', () => {
    it('maps Android keys to web canvas ids', () => {
        expect(normalizeLaborCanvasKey('wash_old')).toBe('wash1');
        expect(normalizeLaborCanvasKey('wash_new')).toBe('wash2');
        expect(normalizeLaborCanvasKey('sand_watch')).toBe('pierWatch');
        expect(normalizeLaborCanvasKey('night_shift')).toBe('nightShift');
        expect(normalizeLaborCanvasKey('night_patrol')).toBe('nightPatrol');
        expect(normalizeLaborCanvasKey('dig_haul')).toBe('digHaul');
    });

    it('keeps washHome separate from general work', () => {
        expect(normalizeLaborCanvasKey('wash_home')).toBe('washHome');
        expect(normalizeLaborCanvasKey('wash_yard_house')).toBe('washHome');
        expect(
            mergeLaborCanvasAssignments({ wash_home: ['e1'], generalWork: ['e2'] })
        ).toEqual({ washHome: ['e1'], generalWork: ['e2'] });
    });
});

describe('computeDayWizardStepStats', () => {
    const trip = (id: string, vehicleId: string, trips = 2): Transaction =>
        ({
            id,
            type: 'Expense',
            category: 'DailyLog',
            subCategory: 'VehicleTrip',
            date: '2026-05-01',
            amount: 0,
            description: 'trip',
            vehicleId,
            driverId: 'd1',
            tripCount: trips,
        }) as Transaction;

    const mobileDrum = (id: string, vehicleId: string): Transaction =>
        ({
            id,
            type: 'Expense',
            category: 'Vehicle',
            date: '2026-05-01',
            amount: 0,
            description: `รถ: ${vehicleId}`,
            vehicleId,
            driverId: 'd1',
            workType: 'FullDay',
        }) as Transaction;

    const vehicleWage = (id: string): Transaction =>
        ({
            id,
            type: 'Expense',
            category: 'Vehicle',
            date: '2026-05-01',
            amount: 5000,
            description: 'ค่าจ้างรถ',
            vehicleId: 'รถดรัม A',
            driverId: 'd1',
            vehicleWage: 4500,
        }) as Transaction;

    const sandMachine = (id: string, machine: 'Old' | 'New', cubic: number): Transaction =>
        ({
            id,
            type: 'Expense',
            category: 'DailyLog',
            subCategory: 'Sand',
            date: '2026-05-01',
            amount: 0,
            description: `ล้างทราย เครื่องร่อน ${machine === 'Old' ? '1' : '2'}`,
            sandMorning: cubic,
            sandAfternoon: 0,
            sandMachineType: machine,
        }) as Transaction;

    it('separates vehicle usage, trips, and sand wash rows', () => {
        const txs = [
            vehicleWage('w1'),
            mobileDrum('m1', 'รถดรัม A'),
            trip('t1', 'รถดรัม A', 3),
            sandMachine('s1', 'Old', 10),
            sandMachine('s2', 'New', 8),
            {
                id: 'drums',
                type: 'Expense',
                category: 'DailyLog',
                subCategory: 'Sand',
                date: '2026-05-01',
                amount: 0,
                description: 'จำนวนถังที่ได้วันนี้',
                drumsObtained: 20,
            } as Transaction,
        ];
        expect(computeDayWizardStepStats(txs)).toEqual({
            laborCount: 0,
            vehicleUsageCount: 1,
            tripCount: 2,
            sandWashCount: 2,
            sandWashCubic: 18,
            fuelCount: 0,
            incomeCount: 0,
            eventCount: 0,
        });
    });

    it('classifies helpers correctly', () => {
        const drum = mobileDrum('m1', 'รถสิบล้อ 01');
        const wage = vehicleWage('w1');
        const sand = sandMachine('s1', 'Old', 5);
        expect(transactionCountsAsVehicleTripMenu(drum)).toBe(true);
        expect(countsAsWizardVehicleUsageRecord(drum)).toBe(false);
        expect(countsAsWizardVehicleUsageRecord(wage)).toBe(true);
        expect(transactionCountsAsVehicleTripMenu(wage)).toBe(false);
        expect(countsAsWizardSandWashRecord(sand)).toBe(true);
    });
});

describe('vehicleTripDrumCarOptions', () => {
    const cars = [
        'รถหกล้อ 01',
        'รถ 6 ล้อ 02',
        'รถสิบล้อ A',
        '10ล้อ-B',
        'รถดรัมโอเว่น',
        'รถแม็คโคร SK200',
    ];

    it('includes dump, six- and ten-wheel names', () => {
        expect(vehicleTripDrumCarOptions(cars)).toEqual([
            'รถหกล้อ 01',
            'รถ 6 ล้อ 02',
            'รถสิบล้อ A',
            '10ล้อ-B',
            'รถดรัมโอเว่น',
        ]);
    });

    it('classifies dump and ten-wheel for trip drum menu', () => {
        expect(isDumpTruckVehicleName('รถดรัมโอเว่น')).toBe(true);
        expect(isSixOrTenWheelVehicleName('รถดรัมโอเว่น')).toBe(false);
        expect(isVehicleTripDrumCarName('รถดรัมโอเว่น')).toBe(true);
        expect(isVehicleTripDrumCarName('รถสิบล้อ A')).toBe(true);
        expect(isVehicleTripDrumCarName('รถแม็คโคร SK200')).toBe(false);
    });

    it('keeps a legacy selected vehicle for edit', () => {
        expect(vehicleTripDrumCarOptions(cars, 'รถแม็คโคร SK200')).toContain('รถแม็คโคร SK200');
    });
});
