import { describe, expect, it } from 'vitest';
import { sumAdvancesByEmployee } from './salaryAdvances';
import type { FaSalaryAdvance } from '../types';

const adv = (
  partial: Partial<FaSalaryAdvance> & Pick<FaSalaryAdvance, 'id' | 'employeeId' | 'advanceDate' | 'amount'>,
): FaSalaryAdvance => ({
  employeeName: 'x',
  notes: '',
  ...partial,
});

describe('sumAdvancesByEmployee', () => {
  it('sums amounts for dates in the period only', () => {
    const map = sumAdvancesByEmployee(
      [
        adv({ id: '1', employeeId: 'e1', advanceDate: '2026-08-05', amount: 500 }),
        adv({ id: '2', employeeId: 'e1', advanceDate: '2026-08-20', amount: 200 }),
        adv({ id: '3', employeeId: 'e2', advanceDate: '2026-08-03', amount: 100 }),
      ],
      new Set(['2026-08-01', '2026-08-03', '2026-08-05']),
    );
    expect(map.get('e1')).toBe(500);
    expect(map.get('e2')).toBe(100);
    expect(map.has('e3')).toBe(false);
  });
});
