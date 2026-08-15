import { describe, expect, it } from 'vitest';
import {
  collectMonthKeys,
  currentMonthKey,
  defaultDateForMonth,
  formatMonthLabel,
  shiftMonth,
} from './ledgerMonth';

describe('ledgerMonth', () => {
  it('shifts months across year boundaries', () => {
    expect(shiftMonth('2026-01', -1)).toBe('2025-12');
    expect(shiftMonth('2025-12', 1)).toBe('2026-01');
  });

  it('formats Thai Buddhist year labels', () => {
    expect(formatMonthLabel('2026-07')).toBe('กรกฎาคม 2569');
  });

  it('collects unique months newest first and keeps fallback', () => {
    expect(collectMonthKeys(['2026-07-01', '2026-08-05', '2026-07-31'], '2026-08')).toEqual([
      '2026-08',
      '2026-07',
    ]);
  });

  it('defaults new entry date to today within current month', () => {
    const now = new Date(2026, 7, 15); // Aug 15
    expect(currentMonthKey(now)).toBe('2026-08');
    expect(defaultDateForMonth('2026-08', now)).toBe('2026-08-15');
    expect(defaultDateForMonth('2026-07', now)).toBe('2026-07-01');
  });
});
