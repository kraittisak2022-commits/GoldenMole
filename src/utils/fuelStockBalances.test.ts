import { describe, expect, it } from 'vitest';
import type { Transaction } from '../types';
import {
    FUEL_SAND_SIEVE_SUB_CATEGORY,
    FUEL_STOCK_IN_SUB_CATEGORY,
    FUEL_TRANSFER_SUB_CATEGORY,
    FUEL_VEHICLE_USAGE_SUB_CATEGORY,
    FUEL_WITHDRAW_SUB_CATEGORY,
    computeFuelStockBalances,
    fuelUsageTankOf,
} from './index';
import { estimateSieveUsageByDay } from './fuelSieveEstimate';

function fuelTx(partial: Partial<Transaction> & Pick<Transaction, 'id' | 'date'>): Transaction {
    return {
        type: 'Expense',
        category: 'Fuel',
        description: 'น้ำมัน',
        amount: 0,
        ...partial,
    };
}

describe('fuelUsageTankOf', () => {
    it('maps VehicleUsage without tank to reserve; others to main', () => {
        expect(fuelUsageTankOf(fuelTx({
            id: 'v',
            date: '2026-08-10',
            subCategory: FUEL_VEHICLE_USAGE_SUB_CATEGORY,
            quantity: 10,
        }))).toBe('reserve');
        expect(fuelUsageTankOf(fuelTx({
            id: 'v2',
            date: '2026-08-10',
            subCategory: FUEL_VEHICLE_USAGE_SUB_CATEGORY,
            fuelTank: 'main',
            quantity: 10,
        }))).toBe('main');
        expect(fuelUsageTankOf(fuelTx({
            id: 'w',
            date: '2026-08-10',
            subCategory: FUEL_WITHDRAW_SUB_CATEGORY,
            quantity: 10,
        }))).toBe('main');
    });
});

describe('computeFuelStockBalances', () => {
    it('counts only main-tank stock-in and treats transfer as move not usage', () => {
        const bal = computeFuelStockBalances([
            fuelTx({
                id: 'in',
                date: '2026-08-05',
                fuelMovement: 'stock_in',
                subCategory: FUEL_STOCK_IN_SUB_CATEGORY,
                fuelTank: 'main',
                quantity: 12000,
            }),
            fuelTx({
                id: 'tr-out',
                date: '2026-08-06',
                fuelMovement: 'stock_out',
                subCategory: FUEL_TRANSFER_SUB_CATEGORY,
                fuelTank: 'main',
                workType: 'machine',
                quantity: 1000,
            }),
            fuelTx({
                id: 'tr-in',
                date: '2026-08-06',
                fuelMovement: 'stock_in',
                subCategory: FUEL_TRANSFER_SUB_CATEGORY,
                fuelTank: 'reserve',
                workType: 'machine',
                quantity: 1000,
            }),
        ]);
        expect(bal.Diesel).toBe(11000);
        expect(bal.DieselReserve).toBe(1000);
        expect(bal.reserveShortfallLiters).toBe(0);
    });

    it('deducts generator/mayor/other/car/macro as usage from tagged tank', () => {
        const bal = computeFuelStockBalances([
            fuelTx({
                id: 'in',
                date: '2026-08-01',
                fuelMovement: 'stock_in',
                subCategory: FUEL_STOCK_IN_SUB_CATEGORY,
                fuelTank: 'main',
                quantity: 12000,
            }),
            fuelTx({
                id: 'tr-out',
                date: '2026-08-02',
                fuelMovement: 'stock_out',
                subCategory: FUEL_TRANSFER_SUB_CATEGORY,
                fuelTank: 'main',
                workType: 'machine',
                quantity: 500,
            }),
            fuelTx({
                id: 'tr-in',
                date: '2026-08-02',
                fuelMovement: 'stock_in',
                subCategory: FUEL_TRANSFER_SUB_CATEGORY,
                fuelTank: 'reserve',
                workType: 'machine',
                quantity: 500,
            }),
            fuelTx({
                id: 'gen',
                date: '2026-08-03',
                fuelMovement: 'stock_out',
                subCategory: FUEL_WITHDRAW_SUB_CATEGORY,
                workType: 'generator',
                fuelTank: 'main',
                quantity: 10,
            }),
            fuelTx({
                id: 'mayor',
                date: '2026-08-03',
                fuelMovement: 'stock_out',
                subCategory: FUEL_WITHDRAW_SUB_CATEGORY,
                workType: 'mayor',
                fuelTank: 'main',
                quantity: 100,
            }),
            fuelTx({
                id: 'other',
                date: '2026-08-03',
                fuelMovement: 'stock_out',
                subCategory: FUEL_WITHDRAW_SUB_CATEGORY,
                workType: 'other',
                fuelTank: 'main',
                quantity: 16,
            }),
            fuelTx({
                id: 'car',
                date: '2026-08-03',
                fuelMovement: 'stock_out',
                subCategory: FUEL_WITHDRAW_SUB_CATEGORY,
                workType: 'car',
                fuelTank: 'main',
                vehicleId: 'ไมตี้',
                quantity: 20,
            }),
            fuelTx({
                id: 'macro-main',
                date: '2026-08-04',
                fuelMovement: 'stock_out',
                subCategory: FUEL_VEHICLE_USAGE_SUB_CATEGORY,
                fuelTank: 'main',
                vehicleId: 'แม็คโคร',
                quantity: 50,
            }),
            fuelTx({
                id: 'macro-res',
                date: '2026-08-04',
                fuelMovement: 'stock_out',
                subCategory: FUEL_VEHICLE_USAGE_SUB_CATEGORY,
                fuelTank: 'reserve',
                vehicleId: 'แม็คโคร',
                quantity: 200,
            }),
            fuelTx({
                id: 'macro-legacy',
                date: '2026-08-04',
                fuelMovement: 'stock_out',
                subCategory: FUEL_VEHICLE_USAGE_SUB_CATEGORY,
                vehicleId: 'แม็คโคร',
                quantity: 30,
            }),
        ]);
        // main: 12000 - 500 - 10 - 100 - 16 - 20 - 50 = 11304
        expect(bal.Diesel).toBe(11304);
        // reserve: 500 - 200 - 30 = 270
        expect(bal.DieselReserve).toBe(270);
    });

    it('credits reserve for legacy machine withdraw when no Transfer that day', () => {
        const bal = computeFuelStockBalances([
            fuelTx({
                id: 'in',
                date: '2026-08-01',
                fuelMovement: 'stock_in',
                subCategory: FUEL_STOCK_IN_SUB_CATEGORY,
                fuelTank: 'main',
                quantity: 1000,
            }),
            fuelTx({
                id: 'legacy',
                date: '2026-08-02',
                fuelMovement: 'stock_out',
                subCategory: FUEL_WITHDRAW_SUB_CATEGORY,
                workType: 'machine',
                quantity: 619,
            }),
            fuelTx({
                id: 'macro',
                date: '2026-08-02',
                fuelMovement: 'stock_out',
                subCategory: FUEL_VEHICLE_USAGE_SUB_CATEGORY,
                fuelTank: 'reserve',
                quantity: 100,
            }),
        ]);
        expect(bal.Diesel).toBe(381);
        expect(bal.DieselReserve).toBe(519);
    });

    it('does not double-credit reserve when Transfer exists same day as legacy withdraw', () => {
        const bal = computeFuelStockBalances([
            fuelTx({
                id: 'in',
                date: '2026-08-01',
                fuelMovement: 'stock_in',
                subCategory: FUEL_STOCK_IN_SUB_CATEGORY,
                fuelTank: 'main',
                quantity: 2000,
            }),
            fuelTx({
                id: 'tr-out',
                date: '2026-08-02',
                fuelMovement: 'stock_out',
                subCategory: FUEL_TRANSFER_SUB_CATEGORY,
                fuelTank: 'main',
                workType: 'machine',
                quantity: 400,
            }),
            fuelTx({
                id: 'tr-in',
                date: '2026-08-02',
                fuelMovement: 'stock_in',
                subCategory: FUEL_TRANSFER_SUB_CATEGORY,
                fuelTank: 'reserve',
                workType: 'machine',
                quantity: 400,
            }),
            fuelTx({
                id: 'legacy',
                date: '2026-08-02',
                fuelMovement: 'stock_out',
                subCategory: FUEL_WITHDRAW_SUB_CATEGORY,
                workType: 'machine',
                quantity: 100,
            }),
        ]);
        // main: 2000 - 400 - 100 = 1500; reserve: 400 only (no legacy credit)
        expect(bal.Diesel).toBe(1500);
        expect(bal.DieselReserve).toBe(400);
    });

    it('transfer + macro on reserve does not double-deduct main', () => {
        const bal = computeFuelStockBalances([
            fuelTx({
                id: 'tr-out',
                date: '2026-08-10',
                fuelMovement: 'stock_out',
                subCategory: FUEL_TRANSFER_SUB_CATEGORY,
                fuelTank: 'main',
                workType: 'machine',
                quantity: 580,
            }),
            fuelTx({
                id: 'tr-in',
                date: '2026-08-10',
                fuelMovement: 'stock_in',
                subCategory: FUEL_TRANSFER_SUB_CATEGORY,
                fuelTank: 'reserve',
                workType: 'machine',
                quantity: 580,
            }),
            fuelTx({
                id: 'vu',
                date: '2026-08-10',
                fuelMovement: 'stock_out',
                subCategory: FUEL_VEHICLE_USAGE_SUB_CATEGORY,
                fuelTank: 'reserve',
                vehicleId: 'แม็คโคร',
                quantity: 142,
            }),
        ]);
        expect(bal.Diesel).toBe(-580);
        expect(bal.DieselReserve).toBe(580 - 142);
    });

    it('stock_out with vehicle but not VehicleUsage is not counted as macro', () => {
        const bal = computeFuelStockBalances([
            fuelTx({
                id: 'gen',
                date: '2026-08-10',
                fuelMovement: 'stock_out',
                subCategory: FUEL_WITHDRAW_SUB_CATEGORY,
                workType: 'generator',
                fuelTank: 'main',
                vehicleId: 'แม็คโคร',
                quantity: 50,
            }),
        ]);
        expect(bal.Diesel).toBe(-50);
        expect(bal.DieselReserve).toBe(0);
    });

    it('allows negative reserve and reports shortfall; applies estimated sieve', () => {
        const bal = computeFuelStockBalances(
            [
                fuelTx({
                    id: 'tr-out',
                    date: '2026-08-10',
                    fuelMovement: 'stock_out',
                    subCategory: FUEL_TRANSFER_SUB_CATEGORY,
                    fuelTank: 'main',
                    workType: 'machine',
                    quantity: 100,
                }),
                fuelTx({
                    id: 'tr-in',
                    date: '2026-08-10',
                    fuelMovement: 'stock_in',
                    subCategory: FUEL_TRANSFER_SUB_CATEGORY,
                    fuelTank: 'reserve',
                    workType: 'machine',
                    quantity: 100,
                }),
                fuelTx({
                    id: 'sieve',
                    date: '2026-08-10',
                    fuelMovement: 'stock_out',
                    subCategory: FUEL_SAND_SIEVE_SUB_CATEGORY,
                    fuelTank: 'reserve',
                    quantity: 50,
                }),
            ],
            { estimatedSieveByDay: { '2026-08-11': 80 } }
        );
        // reserve: 100 - 50 - 80 = -30
        expect(bal.DieselReserve).toBe(-30);
        expect(bal.reserveShortfallLiters).toBe(30);
    });
});

describe('estimateSieveUsageByDay', () => {
    it('estimates only days with sand laps and no SandSieve row', () => {
        const txs: Transaction[] = [
            {
                id: 'sand-1',
                date: '2026-08-01',
                type: 'Expense',
                category: 'DailyLog',
                subCategory: 'Sand',
                description: 'ร่อนทราย',
                amount: 0,
                workAssignments: {
                    lapTimes: ['01/08 08:00:00', '01/08 17:00:00'],
                } as Transaction['workAssignments'],
            },
            {
                id: 'sand-2',
                date: '2026-08-12',
                type: 'Expense',
                category: 'DailyLog',
                subCategory: 'Sand',
                description: 'ร่อนทราย',
                amount: 0,
                workAssignments: {
                    lapTimes: ['12/08 08:00:00', '12/08 12:00:00'],
                } as Transaction['workAssignments'],
            },
            fuelTx({
                id: 'sieve-12',
                date: '2026-08-12',
                fuelMovement: 'stock_out',
                subCategory: FUEL_SAND_SIEVE_SUB_CATEGORY,
                fuelTank: 'reserve',
                quantity: 50.4,
            }),
        ];
        const est = estimateSieveUsageByDay(txs);
        // 08:00–17:00 minus 1h lunch = 8h × 18 = 144
        expect(est['2026-08-01']).toBe(144);
        expect(est['2026-08-12']).toBeUndefined();
    });
});
