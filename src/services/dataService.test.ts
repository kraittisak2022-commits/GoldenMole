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
});
