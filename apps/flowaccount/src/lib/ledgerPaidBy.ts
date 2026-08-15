import type { FaLedgerEntry } from '../types';

export type PaidByTotals = {
  /** Full amounts marked as paid by A only */
  A: number;
  /** Full amounts marked as paid by B only */
  B: number;
  /** Full amounts marked as split A และ B */
  AB: number;
  /** Expense amounts with no payer selected */
  unset: number;
  /** A's burden: A-only + half of AB */
  shareA: number;
  /** B's burden: B-only + half of AB */
  shareB: number;
};

export function sumPaidByTotals(entries: FaLedgerEntry[]): PaidByTotals {
  let A = 0;
  let B = 0;
  let AB = 0;
  let unset = 0;

  for (const e of entries) {
    if (e.entryType !== 'expense') continue;
    const amount = Number(e.amount) || 0;
    if (e.paidBy === 'A') A += amount;
    else if (e.paidBy === 'B') B += amount;
    else if (e.paidBy === 'AB') AB += amount;
    else unset += amount;
  }

  return {
    A,
    B,
    AB,
    unset,
    shareA: A + AB / 2,
    shareB: B + AB / 2,
  };
}
