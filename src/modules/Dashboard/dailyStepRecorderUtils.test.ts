import { describe, expect, it } from 'vitest';
import { persistedSandHomeDrums, sumWizardDailySpend, countsTowardWizardDailySpend } from './dailyStepRecorderUtils';
import type { Transaction } from '../../types';

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
});
