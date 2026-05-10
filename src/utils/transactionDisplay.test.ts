import { describe, expect, it } from 'vitest';
import { transactionMetaSummary, transactionSearchBlob } from './transactionDisplay';
import type { Transaction } from '../types';

describe('transactionDisplay', () => {
    it('transactionSearchBlob includes OT and assignment text', () => {
        const t: Transaction = {
            id: '1',
            date: '2026-05-01',
            type: 'Expense',
            category: 'Labor',
            description: 'ทำงาน',
            amount: 100,
            otDescription: 'ล่วงเวลาโกดัง',
            workAssignments: { กลุ่ม1: ['emp-a', 'emp-b'] },
        };
        const blob = transactionSearchBlob(t);
        expect(blob).toContain('ล่วงเวลาโกดัง');
        expect(blob).toContain('กลุ่ม1');
        expect(blob).toContain('emp-a');
    });

    it('transactionMetaSummary summarizes trips and income status', () => {
        const t: Transaction = {
            id: '2',
            date: '2026-05-02',
            type: 'Income',
            category: 'Income',
            description: 'ขายทราย',
            amount: 5000,
            tripBillingMode: 'PerTrip',
            tripCount: 4,
            totalCubic: 12,
            incomePaymentStatus: 'Unpaid',
        };
        const s = transactionMetaSummary(t);
        expect(s).toContain('ค่ารถรายเที่ยว');
        expect(s).toContain('เที่ยว');
        expect(s).toContain('ยังไม่รับเงิน');
    });
});
