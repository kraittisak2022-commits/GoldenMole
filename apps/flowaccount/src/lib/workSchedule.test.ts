import { describe, expect, it } from 'vitest';
import {
  buildAmountByEmployeeDate,
  calcPeriodNet,
  countWorkedDays,
  dateForDay,
  daysForHalf,
  daysInMonth,
  periodKey,
  sumDayAmounts,
} from './workSchedule';
import type { FaWorkLog } from '../types';

const log = (
  partial: Partial<FaWorkLog> & Pick<FaWorkLog, 'id' | 'employeeId' | 'workDate'>,
): FaWorkLog => ({
  workDays: 1,
  amount: 500,
  otAmount: 0,
  notes: '',
  ...partial,
});

describe('workSchedule', () => {
  it('builds Excel-style half-month day lists', () => {
    expect(daysInMonth('2026-08')).toBe(31);
    expect(daysForHalf('2026-08', '1-15')).toEqual([
      1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    ]);
    expect(daysForHalf('2026-08', '16-end')[0]).toBe(16);
    expect(daysForHalf('2026-08', '16-end').at(-1)).toBe(31);
    expect(periodKey('2026-08', '1-15')).toBe('2026-08:1-15');
    expect(dateForDay('2026-08', 3)).toBe('2026-08-03');
  });

  it('sums day amounts, worked days, and net like Excel', () => {
    const logs = [
      log({ id: '1', employeeId: 'e1', workDate: '2026-08-01', amount: 500 }),
      log({ id: '2', employeeId: 'e1', workDate: '2026-08-02', amount: 500, workDays: 0.5 }),
      log({ id: '3', employeeId: 'e1', workDate: '2026-08-03', amount: 0 }),
    ];
    expect(sumDayAmounts(logs)).toBe(1000);
    expect(countWorkedDays(logs)).toBe(1.5);
    expect(calcPeriodNet({ dayTotal: 1000, specialAmount: 200, advanceAmount: 100 })).toBe(1100);

    const indexed = buildAmountByEmployeeDate(logs);
    expect(indexed.get('e1')?.get('2026-08-01')?.amount).toBe(500);
  });
});
