import { describe, expect, it, vi } from 'vitest';
import { fetchTransactions, prepareTransactionForDb } from './dataService';
import type { Transaction } from '../types';

const db = vi.hoisted(() => ({
    rows: [] as Array<Record<string, unknown>>,
    rangeCalls: [] as Array<[number, number]>,
}));

vi.mock('../lib/supabase', () => {
    const builder = {
        select: () => builder,
        order: () => builder,
        range: (from: number, to: number) => {
            db.rangeCalls.push([from, to]);
            return Promise.resolve({ data: db.rows.slice(from, to + 1), error: null });
        },
    };
    return { supabase: { from: () => builder } };
});

describe('fetchTransactions', () => {
    it('pages past the 1000-row API cap so old rows (e.g. fuel stock-in) are not dropped', async () => {
        db.rows = Array.from({ length: 2300 }, (_, i) => ({ id: `tx-${i}`, sub_category: 'StockIn' }));
        db.rangeCalls = [];

        const result = await fetchTransactions();

        expect(result).toHaveLength(2300);
        expect(result[2299]).toMatchObject({ id: 'tx-2299', subCategory: 'StockIn' });
        expect(db.rangeCalls).toEqual([[0, 999], [1000, 1999], [2000, 2999]]);
    });
});

describe('prepareTransactionForDb', () => {
    it('drops labor_general_work_notes (UI-only; notes are in description)', () => {
        const t = {
            id: 'lab-1',
            date: '2026-05-22',
            type: 'Expense',
            category: 'Labor',
            subCategory: 'Attendance',
            laborStatus: 'Work',
            description: 'ค่าแรง (2 คน)',
            amount: 1000,
            employeeIds: ['e1', 'e2'],
            workAssignments: { wash1: ['e1'] },
            laborGeneralWorkNotes: 'ทำรั้ว',
        } as Transaction;

        const row = prepareTransactionForDb(t);
        expect(row).not.toHaveProperty('labor_general_work_notes');
        expect(row.work_assignments).toEqual({ wash1: ['e1'] });
        expect(row.labor_status).toBe('Work');
    });

    it('preserves lapTimes camelCase inside work_assignments (count-record mobile)', () => {
        const t = {
            id: 'sand-1',
            date: '2026-07-12',
            type: 'Expense',
            category: 'DailyLog',
            subCategory: 'sand',
            description: 'ร่อนทราย: 3 รอบ',
            amount: 0,
            drumsObtained: 3,
            workAssignments: { lapTimes: ['12/07 08:35:54', '12/07 10:12:18', '12/07 10:12:34'] },
        } as Transaction;

        const row = prepareTransactionForDb(t);
        expect(row.drums_obtained).toBe(3);
        expect(row.sub_category).toBe('sand');
        expect(row.description).toBe('ร่อนทราย: 3 รอบ');
        expect(row.work_assignments).toEqual({
            lapTimes: ['12/07 08:35:54', '12/07 10:12:18', '12/07 10:12:34'],
        });
        expect(row.work_assignments).not.toHaveProperty('lap_times');
    });

    it('allows null work_assignments to clear lap column on save', () => {
        const t = {
            id: 'sand-2',
            date: '2026-07-12',
            type: 'Expense',
            category: 'DailyLog',
            subCategory: 'sand',
            description: 'ร่อนทราย: 0 รอบ',
            amount: 0,
            drumsObtained: 0,
            workAssignments: null,
        } as unknown as Transaction;

        const row = prepareTransactionForDb(t);
        expect(row.work_assignments).toBeNull();
    });
});
