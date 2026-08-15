import { describe, expect, it } from 'vitest';
import { buildCategorySummaries } from './categories';
import type { FaCategory, FaLedgerEntry } from '../types';

describe('buildCategorySummaries', () => {
  const categories: FaCategory[] = [
    { id: 'cat-a', name: 'A', kind: 'expense', archived: false, sortOrder: 1 },
    { id: 'cat-b', name: 'B', kind: 'income', archived: false, sortOrder: 2 },
  ];

  const entries: FaLedgerEntry[] = [
    {
      id: '1',
      date: '2026-07-01',
      description: 'x',
      categoryId: 'cat-a',
      entryType: 'expense',
      amount: 100,
      source: 'manual',
    },
    {
      id: '2',
      date: '2026-07-02',
      description: 'y',
      categoryId: 'cat-a',
      entryType: 'expense',
      amount: 50,
      source: 'manual',
    },
    {
      id: '3',
      date: '2026-07-03',
      description: 'z',
      categoryId: 'cat-b',
      entryType: 'income',
      amount: 200,
      source: 'manual',
    },
  ];

  it('aggregates entry counts and totals per category', () => {
    const rows = buildCategorySummaries(categories, entries);
    expect(rows).toHaveLength(2);
    expect(rows[0]).toMatchObject({
      entryCount: 2,
      incomeTotal: 0,
      expenseTotal: 150,
    });
    expect(rows[1]).toMatchObject({
      entryCount: 1,
      incomeTotal: 200,
      expenseTotal: 0,
    });
  });
});
