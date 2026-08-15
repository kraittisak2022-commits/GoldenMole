import type { FaLedgerEntry, LedgerPaidBy } from '../types';

export type PaidByTotals = {
  /** Expense total assigned to A alone (company to be reimbursed by A) */
  A: number;
  /** Expense total assigned to B alone */
  B: number;
  /** Expense total assigned to A และ B (split half each) */
  AB: number;
  /** Expense amounts with no assignee */
  unset: number;
  /** Amount A must cover: A-only + half of AB */
  shareA: number;
  /** Amount B must cover: B-only + half of AB */
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

/** Expense lines tagged to a party, newest date first. */
export function listExpensesByPaidBy(
  entries: FaLedgerEntry[],
  paidBy: LedgerPaidBy,
): FaLedgerEntry[] {
  return entries
    .filter((e) => e.entryType === 'expense' && e.paidBy === paidBy)
    .slice()
    .sort((a, b) => b.date.localeCompare(a.date) || b.id.localeCompare(a.id));
}
