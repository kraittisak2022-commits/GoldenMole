export const ROOT_FOLDER_NAME = 'GoldenMole Photos';

export const THAI_MONTHS = [
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

const DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;

export function isValidReportDate(raw: unknown): raw is string {
  if (typeof raw !== 'string') return false;
  const m = DATE_RE.exec(raw);
  if (!m) return false;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const date = new Date(Date.UTC(y, mo - 1, d));
  return date.getUTCFullYear() === y && date.getUTCMonth() === mo - 1 && date.getUTCDate() === d;
}

export interface FolderLevel {
  /** Unique key in ph_drive_folders, e.g. `2569` or `2569/10`. */
  key: string;
  name: string;
}

/** Year and month folders for a report date: `2569` then `10-ตุลาคม` (Buddhist year, Thai month). */
export function folderPath(reportDate: string): [FolderLevel, FolderLevel] {
  if (!isValidReportDate(reportDate)) throw new Error(`Invalid report date: ${reportDate}`);
  const [year, month] = reportDate.split('-').map(Number);
  const be = String(year + 543);
  const mm = String(month).padStart(2, '0');
  return [
    { key: be, name: be },
    { key: `${be}/${mm}`, name: `${mm}-${THAI_MONTHS[month - 1]}` },
  ];
}

/** Today in Thailand as YYYY-MM-DD. */
export function todayInBangkok(now = new Date()): string {
  return new Date(now.getTime() + 7 * 3600_000).toISOString().slice(0, 10);
}
