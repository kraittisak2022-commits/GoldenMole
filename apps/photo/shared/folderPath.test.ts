import { describe, expect, it } from 'vitest';
import { folderPath, isValidReportDate, todayInBangkok } from './folderPath';

describe('folderPath', () => {
  it('uses the Buddhist year and a numbered Thai month', () => {
    expect(folderPath('2026-10-12')).toEqual([
      { key: '2569', name: '2569' },
      { key: '2569/10', name: '10-ตุลาคม' },
    ]);
    expect(folderPath('2027-01-01')[1]).toEqual({ key: '2570/01', name: '01-มกราคม' });
  });

  it('rejects malformed or impossible dates', () => {
    expect(() => folderPath('2026-02-30')).toThrow();
    expect(isValidReportDate('2026-2-3')).toBe(false);
    expect(isValidReportDate('2028-02-29')).toBe(true);
    expect(isValidReportDate(20261012)).toBe(false);
  });
});

describe('todayInBangkok', () => {
  it('rolls over at midnight Thai time, not UTC', () => {
    expect(todayInBangkok(new Date('2026-10-11T16:59:59Z'))).toBe('2026-10-11');
    expect(todayInBangkok(new Date('2026-10-11T17:00:00Z'))).toBe('2026-10-12');
  });
});
