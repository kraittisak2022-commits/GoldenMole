const moneyFmt = new Intl.NumberFormat('th-TH', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const intFmt = new Intl.NumberFormat('th-TH', { maximumFractionDigits: 2 });

export const formatMoney = (n: number) => moneyFmt.format(n || 0);
export const formatNumber = (n: number) => intFmt.format(n || 0);
export const formatBaht = (n: number) => `${intFmt.format(n || 0)} บาท`;

const TH_MONTHS_SHORT = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];

function toDate(value: string | Date): Date | null {
  if (value instanceof Date) return value;
  if (!value) return null;
  // Plain YYYY-MM-DD is a local calendar date, not UTC midnight
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  const d = m ? new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])) : new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

/** dd/mm/yyyy in the Buddhist year (2569). */
export function formatDateTh(value: string | Date): string {
  const d = toDate(value);
  if (!d) return '-';
  const dd = String(d.getDate()).padStart(2, '0');
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  return `${dd}/${mm}/${d.getFullYear() + 543}`;
}

/** e.g. 8 ต.ค. 69 */
export function formatDateShort(value: string | Date): string {
  const d = toDate(value);
  if (!d) return '-';
  return `${d.getDate()} ${TH_MONTHS_SHORT[d.getMonth()]} ${String(d.getFullYear() + 543).slice(-2)}`;
}

export function formatDateTime(value: string | Date): string {
  const d = toDate(value);
  if (!d) return '-';
  const hh = String(d.getHours()).padStart(2, '0');
  const mi = String(d.getMinutes()).padStart(2, '0');
  return `${formatDateShort(d)} ${hh}:${mi} น.`;
}

/** Local YYYY-MM-DD for <input type="date">. */
export function toIsoDate(d: Date = new Date()): string {
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}`;
}

export function shiftIsoDate(iso: string, days: number): string {
  const d = toDate(iso) ?? new Date();
  return toIsoDate(new Date(d.getFullYear(), d.getMonth(), d.getDate() + days));
}

export function monthRange(iso: string): { from: string; to: string } {
  const d = toDate(iso) ?? new Date();
  return {
    from: toIsoDate(new Date(d.getFullYear(), d.getMonth(), 1)),
    to: toIsoDate(new Date(d.getFullYear(), d.getMonth() + 1, 0)),
  };
}

const TH_WEEKDAYS = ['อาทิตย์', 'จันทร์', 'อังคาร', 'พุธ', 'พฤหัสบดี', 'ศุกร์', 'เสาร์'];
export const TH_MONTHS = ['มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน', 'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'];

/** e.g. พฤหัสบดี 8 ตุลาคม 2569 */
export function formatDateLongTh(value: string | Date): string {
  const d = toDate(value);
  if (!d) return '-';
  return `${TH_WEEKDAYS[d.getDay()]} ${d.getDate()} ${TH_MONTHS[d.getMonth()]} ${d.getFullYear() + 543}`;
}

export function digitsOnly(phone: string): string {
  return phone.replace(/\D/g, '');
}

/** 0931234567 → 093-123-4567 */
export function formatPhone(phone: string): string {
  const d = digitsOnly(phone);
  if (d.length === 10) return `${d.slice(0, 3)}-${d.slice(3, 6)}-${d.slice(6)}`;
  if (d.length === 9) return `${d.slice(0, 2)}-${d.slice(2, 5)}-${d.slice(5)}`;
  return phone.trim();
}

export type DocKind = 'delivery' | 'receipt' | 'statement';

export const DOC_TITLE: Record<DocKind, { th: string; en: string }> = {
  delivery: { th: 'ใบส่งของ', en: 'DELIVERY NOTE' },
  receipt: { th: 'ใบเสร็จรับเงิน', en: 'RECEIPT' },
  statement: { th: 'ใบวางบิล / ใบแจ้งยอด', en: 'BILLING STATEMENT' },
};

const DOC_NO_RE = /^(DO|TS|RE|BL)(\d{2})(\d{2})-(\d{4,})$/;

export function parseDocNo(docNo: string): { kind: DocKind; year: number; month: number; seq: number } | null {
  const m = DOC_NO_RE.exec(docNo.trim());
  if (!m) return null;
  const month = Number(m[3]);
  if (month < 1 || month > 12) return null;
  const kind: DocKind = m[1] === 'DO' || m[1] === 'TS' ? 'delivery' : m[1] === 'RE' ? 'receipt' : 'statement';
  return { kind, year: 2000 + Number(m[2]), month, seq: Number(m[4]) };
}

export function googleMapsUrl(lat: number, lng: number): string {
  return `https://www.google.com/maps?q=${lat.toFixed(6)},${lng.toFixed(6)}`;
}

/** Links sent outside the app must point at production, wherever the message was copied from. */
export const PUBLIC_APP_URL = 'https://order.goldenmole.pro';

export function driverJobUrl(token: string): string {
  return `${PUBLIC_APP_URL}/d/${token}`;
}
