import { describe, expect, it } from 'vitest';
import type { Transaction } from '../types';
import {
    FUEL_SAND_SIEVE_SUB_CATEGORY,
    FUEL_STOCK_IN_SUB_CATEGORY,
    FUEL_TRANSFER_SUB_CATEGORY,
    FUEL_VEHICLE_USAGE_SUB_CATEGORY,
    FUEL_WITHDRAW_SUB_CATEGORY,
} from './index';
import {
    buildFuelUsageReport,
    classifyFuelTx,
    fuelKindLabel,
    fuelUsageToCsv,
    monthBoundsFromYmd,
    shiftMonthBounds,
    yearBoundsFromYmd,
} from './fuelUsageReport';

function fuelTx(partial: Partial<Transaction> & Pick<Transaction, 'id' | 'date'>): Transaction {
    return {
        type: 'Expense',
        category: 'Fuel',
        description: 'น้ำมัน',
        amount: 0,
        ...partial,
    };
}

describe('classifyFuelTx', () => {
    it('returns null for non-fuel rows', () => {
        expect(classifyFuelTx({
            id: 'x',
            date: '2026-08-10',
            type: 'Expense',
            category: 'Labor',
            description: 'ค่าแรง',
            amount: 100,
        })).toBeNull();
    });

    it('counts only main-tank stock-in as รับเข้า and skips reserve transfer-in', () => {
        expect(classifyFuelTx(fuelTx({
            id: 'in',
            date: '2026-08-10',
            fuelMovement: 'stock_in',
            subCategory: FUEL_STOCK_IN_SUB_CATEGORY,
            fuelTank: 'main',
            quantity: 12000,
        }))).toBe('stock_in');

        expect(classifyFuelTx(fuelTx({
            id: 'reserve-in',
            date: '2026-08-10',
            fuelMovement: 'stock_in',
            subCategory: FUEL_TRANSFER_SUB_CATEGORY,
            fuelTank: 'reserve',
            workType: 'machine',
            quantity: 600,
        }))).toBeNull();
    });

    it('classifies main→reserve transfer as เบิก (not usage) and car/macro as usage', () => {
        expect(classifyFuelTx(fuelTx({
            id: 'tr-out',
            date: '2026-08-10',
            fuelMovement: 'stock_out',
            subCategory: FUEL_TRANSFER_SUB_CATEGORY,
            fuelTank: 'main',
            workType: 'machine',
            quantity: 600,
        }))).toBe('withdraw');

        expect(classifyFuelTx(fuelTx({
            id: 'machine-legacy',
            date: '2026-08-10',
            fuelMovement: 'stock_out',
            subCategory: FUEL_WITHDRAW_SUB_CATEGORY,
            workType: 'machine',
            quantity: 100,
        }))).toBe('withdraw');

        expect(classifyFuelTx(fuelTx({
            id: 'car',
            date: '2026-08-10',
            fuelMovement: 'stock_out',
            subCategory: FUEL_WITHDRAW_SUB_CATEGORY,
            workType: 'car',
            vehicleId: 'ไมตี้',
            quantity: 20,
        }))).toBe('vehicle');

        expect(classifyFuelTx(fuelTx({
            id: 'gen',
            date: '2026-08-10',
            fuelMovement: 'stock_out',
            subCategory: FUEL_WITHDRAW_SUB_CATEGORY,
            workType: 'generator',
            quantity: 5,
        }))).toBe('other_out');

        expect(classifyFuelTx(fuelTx({
            id: 'other',
            date: '2026-08-10',
            fuelMovement: 'stock_out',
            subCategory: FUEL_WITHDRAW_SUB_CATEGORY,
            workType: 'other',
            quantity: 16,
        }))).toBe('other_out');

        expect(classifyFuelTx(fuelTx({
            id: 'macro',
            date: '2026-08-10',
            fuelMovement: 'stock_out',
            subCategory: FUEL_VEHICLE_USAGE_SUB_CATEGORY,
            fuelTank: 'reserve',
            vehicleId: 'รถแม็คโคร',
            quantity: 40,
        }))).toBe('vehicle');

        expect(classifyFuelTx(fuelTx({
            id: 's',
            date: '2026-08-10',
            fuelMovement: 'stock_out',
            subCategory: FUEL_SAND_SIEVE_SUB_CATEGORY,
            fuelTank: 'reserve',
            quantity: 10,
        }))).toBe('sand_sieve');
    });

    it('treats legacy rows with vehicleId as vehicle usage and without as stock-in', () => {
        expect(classifyFuelTx(fuelTx({
            id: 'legacy-v',
            date: '2026-08-10',
            vehicleId: 'รถแม็คโคร',
            quantity: 30,
        }))).toBe('vehicle');
        expect(classifyFuelTx(fuelTx({
            id: 'legacy-in',
            date: '2026-08-10',
            quantity: 200,
        }))).toBe('stock_in');
    });
});

describe('month / year bounds', () => {
    it('returns inclusive calendar bounds', () => {
        expect(monthBoundsFromYmd('2026-08-24')).toEqual({ start: '2026-08-01', end: '2026-08-31' });
        expect(monthBoundsFromYmd('2026-02-10')).toEqual({ start: '2026-02-01', end: '2026-02-28' });
        expect(shiftMonthBounds('2026-08-24', -1)).toEqual({ start: '2026-07-01', end: '2026-07-31' });
        expect(yearBoundsFromYmd('2026-08-24')).toEqual({ start: '2026-01-01', end: '2026-12-31' });
    });
});

describe('buildFuelUsageReport', () => {
    const rows: Transaction[] = [
        fuelTx({
            id: 'in-1',
            date: '2026-08-05',
            fuelMovement: 'stock_in',
            subCategory: FUEL_STOCK_IN_SUB_CATEGORY,
            fuelTank: 'main',
            fuelType: 'Diesel',
            quantity: 12000,
            amount: 416280,
            description: 'เพิ่มน้ำมันเข้าถัง',
        }),
        fuelTx({
            id: 'reserve-in',
            date: '2026-08-02',
            fuelMovement: 'stock_in',
            subCategory: FUEL_TRANSFER_SUB_CATEGORY,
            fuelTank: 'reserve',
            workType: 'machine',
            quantity: 600,
            description: 'รับเข้าถังสำรองจากถังหลัก',
        }),
        fuelTx({
            id: 'tr-out',
            date: '2026-08-02',
            fuelMovement: 'stock_out',
            subCategory: FUEL_TRANSFER_SUB_CATEGORY,
            fuelTank: 'main',
            workType: 'machine',
            quantity: 600,
            description: 'เติมเครื่องจักร',
        }),
        fuelTx({
            id: 'v-1',
            date: '2026-08-03',
            fuelMovement: 'stock_out',
            subCategory: FUEL_VEHICLE_USAGE_SUB_CATEGORY,
            fuelType: 'Diesel',
            vehicleId: 'รถดรัมโอเว่น',
            quantity: 60,
            amount: 1800,
            description: 'น้ำมันรถแม็คโคร',
        }),
        fuelTx({
            id: 'v-2',
            date: '2026-08-04',
            fuelMovement: 'stock_out',
            subCategory: FUEL_VEHICLE_USAGE_SUB_CATEGORY,
            fuelType: 'Diesel',
            vehicleId: 'รถดรัมโอเว่น',
            quantity: 40,
            amount: 1200,
        }),
        fuelTx({
            id: 'car-1',
            date: '2026-08-05',
            fuelMovement: 'stock_out',
            subCategory: FUEL_WITHDRAW_SUB_CATEGORY,
            workType: 'car',
            vehicleId: 'ไมตี้',
            fuelTank: 'main',
            quantity: 21,
            description: 'เติมน้ำมันรถยนต์',
        }),
        fuelTx({
            id: 'other-1',
            date: '2026-08-06',
            fuelMovement: 'stock_out',
            subCategory: FUEL_WITHDRAW_SUB_CATEGORY,
            workType: 'other',
            quantity: 16,
            description: 'อื่นระบุ',
        }),
        fuelTx({
            id: 'gal',
            date: '2026-08-06',
            fuelMovement: 'stock_out',
            subCategory: FUEL_VEHICLE_USAGE_SUB_CATEGORY,
            fuelType: 'Benzine',
            vehicleId: 'รถเก๋ง',
            quantity: 1,
            unit: 'gallon',
            amount: 150,
        }),
        fuelTx({
            id: 'out-of-range',
            date: '2026-07-31',
            fuelMovement: 'stock_out',
            subCategory: FUEL_VEHICLE_USAGE_SUB_CATEGORY,
            vehicleId: 'รถดรัมโอเว่น',
            quantity: 999,
            amount: 1,
        }),
        {
            id: 'labor',
            date: '2026-08-03',
            type: 'Expense',
            category: 'Labor',
            description: 'ค่าแรง',
            amount: 500,
        },
    ];

    it('filters by inclusive date range and counts stock-in / เบิก / ใช้ correctly', () => {
        const report = buildFuelUsageReport(rows, { start: '2026-08-01', end: '2026-08-31' });
        expect(report.rows.map(r => r.id).sort()).toEqual(['car-1', 'gal', 'in-1', 'other-1', 'tr-out', 'v-1', 'v-2']);
        expect(report.totals.stockInLiters).toBe(12000);
        expect(report.rows.some(r => r.id === 'reserve-in')).toBe(false);
        expect(report.totals.withdrawLiters).toBe(600);
        expect(report.totals.vehicleLiters).toBeCloseTo(60 + 40 + 21 + 3.785411784, 6);
        expect(report.totals.otherOutLiters).toBe(16);
        // ใช้แล้วไม่รวมเบิกไปถังสำรอง
        expect(report.totals.usageLiters).toBeCloseTo(60 + 40 + 21 + 16 + 3.785411784, 6);
        expect(report.totals.count).toBe(7);
        expect(report.rows.some(r => r.id === 'out-of-range')).toBe(false);
    });

    it('recalculates totals when the selected date range changes', () => {
        const august = buildFuelUsageReport(rows, { start: '2026-08-01', end: '2026-08-31' });
        const july = buildFuelUsageReport(rows, { start: '2026-07-01', end: '2026-07-31' });
        const singleDay = buildFuelUsageReport(rows, { start: '2026-08-03', end: '2026-08-03' });

        expect(july.rows.map(r => r.id)).toEqual(['out-of-range']);
        expect(july.totals.vehicleLiters).toBe(999);
        expect(july.totals.count).toBe(1);

        expect(august.totals.count).toBe(7);
        expect(august.totals.vehicleLiters).not.toBe(july.totals.vehicleLiters);

        expect(singleDay.rows.map(r => r.id).sort()).toEqual(['v-1']);
        expect(singleDay.totals.vehicleLiters).toBe(60);
        expect(singleDay.totals.count).toBe(1);
    });

    it('aggregates by vehicle and can filter to one vehicle', () => {
        const all = buildFuelUsageReport(rows, { start: '2026-08-01', end: '2026-08-31' });
        const owen = all.byVehicle.find(v => v.vehicleId === 'รถดรัมโอเว่น');
        expect(owen?.liters).toBe(100);
        expect(owen?.amount).toBe(3000);
        expect(owen?.count).toBe(2);

        const filtered = buildFuelUsageReport(rows, {
            start: '2026-08-01',
            end: '2026-08-31',
            vehicleId: 'รถดรัมโอเว่น',
        });
        expect(filtered.rows.every(r => r.vehicleId === 'รถดรัมโอเว่น')).toBe(true);
        expect(filtered.totals.vehicleLiters).toBe(100);
        expect(filtered.totals.stockInLiters).toBe(0);
    });

    it('filters by fuel type and kind', () => {
        const benzine = buildFuelUsageReport(rows, {
            start: '2026-08-01',
            end: '2026-08-31',
            fuelType: 'Benzine',
        });
        expect(benzine.rows).toHaveLength(1);
        expect(benzine.totals.vehicleLiters).toBeCloseTo(3.785411784, 6);

        const withdrawOnly = buildFuelUsageReport(rows, {
            start: '2026-08-01',
            end: '2026-08-31',
            kind: 'withdraw',
        });
        expect(withdrawOnly.rows).toHaveLength(1);
        expect(withdrawOnly.totals.withdrawLiters).toBe(600);
        expect(withdrawOnly.totals.usageLiters).toBe(0);
        expect(withdrawOnly.totals.vehicleLiters).toBe(0);
    });

    it('does not count main→reserve เบิก as usage', () => {
        const report = buildFuelUsageReport([
            fuelTx({
                id: 'tr',
                date: '2026-08-10',
                fuelMovement: 'stock_out',
                subCategory: FUEL_TRANSFER_SUB_CATEGORY,
                fuelTank: 'main',
                workType: 'machine',
                quantity: 80,
                amount: 0,
            }),
            fuelTx({
                id: 'v',
                date: '2026-08-10',
                fuelMovement: 'stock_out',
                subCategory: FUEL_VEHICLE_USAGE_SUB_CATEGORY,
                vehicleId: 'รถดรัมโอเว่น',
                quantity: 10,
                amount: 300,
            }),
        ], { start: '2026-08-01', end: '2026-08-31' });
        expect(report.totals.withdrawLiters).toBe(80);
        expect(report.totals.usageLiters).toBe(10);
        expect(report.totals.usageAmount).toBe(300);
    });

    it('includes estimated sand-sieve rows in usage totals', () => {
        const report = buildFuelUsageReport([], {
            start: '2026-08-01',
            end: '2026-08-31',
            estimatedSieveByDay: { '2026-08-01': 144, '2026-08-02': 50 },
        });
        expect(report.rows).toHaveLength(2);
        expect(report.rows.every(r => r.kind === 'sand_sieve' && r.estimated)).toBe(true);
        expect(report.totals.sandSieveLiters).toBe(194);
        expect(report.totals.usageLiters).toBe(194);
    });
});

describe('fuelUsageToCsv', () => {
    it('includes Thai headers and liters-only data rows without cost columns', () => {
        const report = buildFuelUsageReport([
            fuelTx({
                id: 'v-1',
                date: '2026-08-03',
                fuelMovement: 'stock_out',
                subCategory: FUEL_VEHICLE_USAGE_SUB_CATEGORY,
                fuelType: 'Diesel',
                vehicleId: 'รถดรัมโอเว่น',
                quantity: 60,
                amount: 1800,
                description: 'เติมรถ',
            }),
        ], { start: '2026-08-01', end: '2026-08-31' });
        const csv = fuelUsageToCsv(report, { start: '2026-08-01', end: '2026-08-31' });
        expect(csv).toContain('วันที่');
        expect(csv).toContain('รถดรัมโอเว่น');
        expect(csv).toContain(fuelKindLabel('vehicle'));
        expect(csv).toContain('รับเข้า (ถังหลัก)');
        expect(csv).toContain('เบิกไปถังสำรอง');
        expect(csv).toContain('ลิตร');
        expect(csv).not.toContain('บาท');
        expect(csv).not.toContain('ค่าใช้จ่าย');
        expect(csv.startsWith('\ufeff')).toBe(true);
    });
});
