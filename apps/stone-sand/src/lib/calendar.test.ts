import { monthGrid, sameMonth, shiftMonth, yearMonthOf } from './calendar';

describe('monthGrid', () => {
  it('starts on the Sunday on or before the 1st and spans six weeks', () => {
    const grid = monthGrid({ year: 2026, month: 9 }); // October 2026 starts on a Thursday
    expect(grid).toHaveLength(42);
    expect(grid[0]).toBe('2026-09-27');
    expect(grid[4]).toBe('2026-10-01');
    expect(grid[41]).toBe('2026-11-07');
  });

  it('starts on the 1st when the month begins on a Sunday', () => {
    expect(monthGrid({ year: 2026, month: 1 })[0]).toBe('2026-02-01');
  });
});

describe('shiftMonth', () => {
  it('crosses year boundaries', () => {
    expect(shiftMonth({ year: 2026, month: 11 }, 1)).toEqual({ year: 2027, month: 0 });
    expect(shiftMonth({ year: 2026, month: 0 }, -1)).toEqual({ year: 2025, month: 11 });
  });
});

describe('yearMonthOf / sameMonth', () => {
  it('reads the month of an ISO date', () => {
    expect(yearMonthOf('2026-10-09')).toEqual({ year: 2026, month: 9 });
    expect(sameMonth('2026-10-31', { year: 2026, month: 9 })).toBe(true);
    expect(sameMonth('2026-11-01', { year: 2026, month: 9 })).toBe(false);
  });
});
