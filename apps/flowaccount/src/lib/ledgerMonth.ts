/** YYYY-MM helpers for ledger monthly views */

const TH_MONTHS = [
  'มกราคม',
  'กุมภาพันธ์',
  'มีนาคม',
  'เมษายน',
  'พฤษภาคม',
  'มิถุนายน',
  'กรกฎาคม',
  'สิงหาคม',
  'กันยายน',
  'ตุลาคม',
  'พฤศจิกายน',
  'ธันวาคม',
] as const;

export function currentMonthKey(now = new Date()): string {
  const y = now.getFullYear();
  const m = String(now.getMonth() + 1).padStart(2, '0');
  return `${y}-${m}`;
}

export function isMonthKey(value: string): boolean {
  return /^\d{4}-\d{2}$/.test(value);
}

export function shiftMonth(monthKey: string, delta: number): string {
  const [y, m] = monthKey.split('-').map(Number);
  const d = new Date(y, m - 1 + delta, 1);
  return currentMonthKey(d);
}

export function formatMonthLabel(monthKey: string): string {
  if (!isMonthKey(monthKey)) return monthKey;
  const [y, m] = monthKey.split('-').map(Number);
  return `${TH_MONTHS[m - 1]} ${y + 543}`;
}

/** Unique YYYY-MM from entry dates, newest first, always includes `fallback`. */
export function collectMonthKeys(dates: string[], fallback: string): string[] {
  const set = new Set<string>();
  if (isMonthKey(fallback)) set.add(fallback);
  for (const date of dates) {
    const key = date.slice(0, 7);
    if (isMonthKey(key)) set.add(key);
  }
  return [...set].sort((a, b) => b.localeCompare(a));
}

export function defaultDateForMonth(monthKey: string, now = new Date()): string {
  const todayKey = currentMonthKey(now);
  if (monthKey === todayKey) {
    const d = String(now.getDate()).padStart(2, '0');
    return `${monthKey}-${d}`;
  }
  return `${monthKey}-01`;
}
