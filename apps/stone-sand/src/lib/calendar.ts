import { toIsoDate } from './format';

export interface YearMonth {
  year: number;
  /** 0 = January */
  month: number;
}

export const TH_WEEKDAYS_SHORT = ['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส'];

export function yearMonthOf(iso: string): YearMonth {
  const [y, m] = iso.split('-').map(Number);
  return { year: y, month: m - 1 };
}

export function shiftMonth({ year, month }: YearMonth, by: number): YearMonth {
  const d = new Date(year, month + by, 1);
  return { year: d.getFullYear(), month: d.getMonth() };
}

export function sameMonth(iso: string, ym: YearMonth): boolean {
  const { year, month } = yearMonthOf(iso);
  return year === ym.year && month === ym.month;
}

/** Six weeks of ISO dates, Sunday first, that cover the month. */
export function monthGrid({ year, month }: YearMonth): string[] {
  const first = new Date(year, month, 1);
  return Array.from({ length: 42 }, (_, i) => toIsoDate(new Date(year, month, 1 - first.getDay() + i)));
}
