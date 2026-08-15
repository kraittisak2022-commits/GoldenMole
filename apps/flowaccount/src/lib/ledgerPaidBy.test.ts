import { describe, expect, it } from 'vitest';
import { listExpensesByPaidBy, sumPaidByTotals } from './ledgerPaidBy';
import type { FaLedgerEntry } from '../types';

function entry(partial: Partial<FaLedgerEntry> & Pick<FaLedgerEntry, 'id' | 'amount'>): FaLedgerEntry {
  return {
    date: '2026-07-01',
    description: 'x',
    categoryId: 'cat',
    entryType: 'expense',
    quantity: 1,
    source: 'manual',
    ...partial,
  };
}

describe('sumPaidByTotals', () => {
  it('sums A, B, and AB buckets and splits AB half for personal shares', () => {
    const totals = sumPaidByTotals([
      entry({ id: '1', amount: 1000, paidBy: 'A' }),
      entry({ id: '2', amount: 400, paidBy: 'B' }),
      entry({ id: '3', amount: 200, paidBy: 'AB' }),
      entry({ id: '4', amount: 50, paidBy: null }),
      entry({ id: '5', amount: 999, entryType: 'income', paidBy: 'A' }),
    ]);

    expect(totals).toEqual({
      A: 1000,
      B: 400,
      AB: 200,
      unset: 50,
      shareA: 1100,
      shareB: 500,
    });
  });

  it('splits a 200 baht company expense marked A และ B into 100 each', () => {
    const totals = sumPaidByTotals([
      entry({
        id: 'ofuse',
        amount: 200,
        description: 'ของใช้ทั่วไป',
        paidBy: 'AB',
      }),
    ]);

    expect(totals.AB).toBe(200);
    expect(totals.shareA).toBe(100);
    expect(totals.shareB).toBe(100);
  });

  it('lists expense lines for one party newest first', () => {
    const rows = listExpensesByPaidBy(
      [
        entry({ id: '1', amount: 100, paidBy: 'A', date: '2026-07-01' }),
        entry({ id: '2', amount: 50, paidBy: 'B', date: '2026-07-02' }),
        entry({ id: '3', amount: 200, paidBy: 'A', date: '2026-07-10' }),
        entry({ id: '4', amount: 9, paidBy: 'A', entryType: 'income', date: '2026-07-11' }),
      ],
      'A',
    );
    expect(rows.map((r) => r.id)).toEqual(['3', '1']);
  });
});
