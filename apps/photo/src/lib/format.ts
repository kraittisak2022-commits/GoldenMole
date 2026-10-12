const shortDate = new Intl.DateTimeFormat('th-TH', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' });
const longDate = new Intl.DateTimeFormat('th-TH', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'UTC' });
const dayHeading = new Intl.DateTimeFormat('th-TH', {
  weekday: 'short',
  day: 'numeric',
  month: 'short',
  year: 'numeric',
  timeZone: 'Asia/Bangkok',
});
const dateTime = new Intl.DateTimeFormat('th-TH', {
  day: 'numeric',
  month: 'short',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
  timeZone: 'Asia/Bangkok',
});

const asUtcDate = (ymd: string) => new Date(`${ymd}T00:00:00Z`);

/** `2026-10-12` → `12 ต.ค. 2569` */
export const formatReportDate = (ymd: string) => shortDate.format(asUtcDate(ymd));
export const formatReportDateLong = (ymd: string) => longDate.format(asUtcDate(ymd));
export const formatDayHeading = (iso: string) => dayHeading.format(new Date(iso));
export const formatDateTime = (iso: string) => dateTime.format(new Date(iso));

export function formatCount(count: number): string {
  return `${count.toLocaleString('th-TH')} รายการ`;
}

export function formatBytes(bytes: number): string {
  if (bytes < 1024 * 1024) return `${Math.max(1, Math.round(bytes / 1024))} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  return `${(bytes / 1024 / 1024 / 1024).toFixed(2)} GB`;
}

/** Calendar day in Thailand, used to group photos. */
export function bangkokDayKey(iso: string): string {
  return new Date(Date.parse(iso) + 7 * 3600_000).toISOString().slice(0, 10);
}
