import { describe, expect, it } from 'vitest';
import { sumPaidByTotals } from './ledgerPaidBy';
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

  it('returns zeros for empty list', () => {
    expect(sumPaidByTotals([])).toEqual({
      A: 0,
      B: 0,
      AB: 0,
      unset: 0,
      shareA: 0,
      shareB: 0,
    });
  });
});
