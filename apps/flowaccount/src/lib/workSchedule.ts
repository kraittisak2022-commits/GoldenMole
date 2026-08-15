import { isMonthKey } from './ledgerMonth';
import type { FaWorkLog, FaWorkPeriodSummary } from '../types';

export type PayHalf = '1-15' | '16-end';

export function daysInMonth(monthKey: string): number {
  if (!isMonthKey(monthKey)) return 0;
  const [y, m] = monthKey.split('-').map(Number);
  return new Date(y, m, 0).getDate();
}

export function dateForDay(monthKey: string, day: number): string {
  return `${monthKey}-${String(day).padStart(2, '0')}`;
}

/** Days included in a pay half (Excel-style 1–15 / 16–end). */
export function daysForHalf(monthKey: string, half: PayHalf): number[] {
  const last = daysInMonth(monthKey);
  if (half === '1-15') {
    const end = Math.min(15, last);
    return Array.from({ length: end }, (_, i) => i + 1);
  }
  if (last < 16) return [];
  return Array.from({ length: last - 15 }, (_, i) => i + 16);
}

export function periodKey(monthKey: string, half: PayHalf): string {
  return `${monthKey}:${half}`;
}

export function buildAmountByEmployeeDate(logs: FaWorkLog[]): Map<string, Map<string, FaWorkLog>> {
  const map = new Map<string, Map<string, FaWorkLog>>();
  for (const log of logs) {
    const byDate = map.get(log.employeeId) || new Map<string, FaWorkLog>();
    byDate.set(log.workDate, log);
    map.set(log.employeeId, byDate);
  }
  return map;
}

export function sumDayAmounts(logs: FaWorkLog[]): number {
  return logs.reduce((s, l) => s + (Number(l.amount) || 0), 0);
}

export function countWorkedDays(logs: FaWorkLog[]): number {
  return logs.reduce((s, l) => {
    const amount = Number(l.amount) || 0;
    if (amount <= 0) return s;
    const days = Number(l.workDays);
    return s + (days > 0 ? days : 1);
  }, 0);
}

export function calcPeriodNet(input: {
  dayTotal: number;
  specialAmount: number;
  advanceAmount: number;
}): number {
  return (Number(input.dayTotal) || 0) + (Number(input.specialAmount) || 0) - (Number(input.advanceAmount) || 0);
}

export function summaryByEmployee(
  rows: FaWorkPeriodSummary[],
): Map<string, FaWorkPeriodSummary> {
  return new Map(rows.map((r) => [r.employeeId, r]));
}
