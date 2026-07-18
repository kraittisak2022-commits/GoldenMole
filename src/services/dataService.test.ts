import { describe, expect, it } from 'vitest';
import { prepareTransactionForDb } from './dataService';
import type { Transaction } from '../types';

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
