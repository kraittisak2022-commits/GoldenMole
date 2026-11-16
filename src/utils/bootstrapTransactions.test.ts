import { describe, expect, it } from 'vitest';
import type { Transaction } from '../types';
import { pickLoadedTransactions } from './bootstrapTransactions';

const row = (id: string, date = '2026-11-01'): Transaction => ({
    id,
    date,
    type: 'Expense',
    category: 'Fuel',
    description: 'น้ำมัน',
    amount: 0,
});

const mockRows = [row('1', '2026-11-16'), row('2', '2026-11-16'), row('3', '2026-11-16')];
const realRows = [row('tx-a'), row('tx-b'), row('tx-c'), row('tx-d')];

describe('pickLoadedTransactions', () => {
    it('keeps a real fetch and allows saving it', () => {
        const picked = pickLoadedTransactions(realRows, mockRows);
        expect(picked.rows).toEqual(realRows);
        expect(picked.persist).toBe(true);
    });

    it('keeps cached records when the fetch times out instead of the 3-row sample', () => {
        const picked = pickLoadedTransactions('failed', realRows);
        expect(picked.rows).toEqual(realRows);
        expect(picked.persist).toBe(false);
    });

    it('persists a genuinely empty fetch over a stale cache', () => {
        const picked = pickLoadedTransactions([], realRows);
        expect(picked.rows).toEqual([]);
        expect(picked.persist).toBe(true);
    });

    it('ignores a cached sample and falls back to the sample only when nothing real loaded', () => {
        const picked = pickLoadedTransactions('failed', mockRows);
        expect(picked.rows).toEqual(mockRows);
        expect(picked.persist).toBe(false);
    });

    it('persists a genuinely empty database', () => {
        const picked = pickLoadedTransactions([], null);
        expect(picked.rows).toEqual([]);
        expect(picked.persist).toBe(true);
    });

    it('returns nothing to save when the first load fails and there is no cache', () => {
        const picked = pickLoadedTransactions('failed', null);
        expect(picked.rows).toEqual([]);
        expect(picked.persist).toBe(false);
    });
});
