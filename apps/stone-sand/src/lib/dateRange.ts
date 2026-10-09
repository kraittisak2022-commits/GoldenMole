import { toIsoDate } from './format';

export type DateRange = 'today' | '7d' | 'month' | '3m' | 'all';

export const DATE_RANGE_LABEL: Record<DateRange, string> = {
  today: 'วันนี้',
  '7d': '7 วันล่าสุด',
  month: 'เดือนนี้',
  '3m': '3 เดือน',
  all: 'ทั้งหมด',
};

export const DATE_RANGES = Object.keys(DATE_RANGE_LABEL) as DateRange[];

/** First order date in the range; undefined for all time. */
export function rangeFrom(r: DateRange, d = new Date()): string | undefined {
  if (r === 'today') return toIsoDate(d);
  if (r === '7d') return toIsoDate(new Date(d.getFullYear(), d.getMonth(), d.getDate() - 6));
  if (r === 'month') return toIsoDate(new Date(d.getFullYear(), d.getMonth(), 1));
  if (r === '3m') return toIsoDate(new Date(d.getFullYear(), d.getMonth() - 2, 1));
  return undefined;
}

export function parseDateRange(value: string | null, fallback: DateRange = 'month'): DateRange {
  return DATE_RANGES.find((r) => r === value) ?? fallback;
}
