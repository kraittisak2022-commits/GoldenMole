const DIGITS = ['ศูนย์', 'หนึ่ง', 'สอง', 'สาม', 'สี่', 'ห้า', 'หก', 'เจ็ด', 'แปด', 'เก้า'];
const PLACES = ['', 'สิบ', 'ร้อย', 'พัน', 'หมื่น', 'แสน'];

/** Reads up to 6 digits (no leading zeros). `hasHigher` = a higher group (ล้าน) precedes it. */
function readGroup(digits: string, hasHigher: boolean): string {
  let out = '';
  const len = digits.length;
  for (let i = 0; i < len; i++) {
    const d = Number(digits[i]);
    const place = len - i - 1;
    if (d === 0) continue;
    if (place === 1 && d === 1) out += 'สิบ';
    else if (place === 1 && d === 2) out += 'ยี่สิบ';
    else if (place === 0 && d === 1 && (len > 1 || hasHigher)) out += 'เอ็ด';
    else out += DIGITS[d] + PLACES[place];
  }
  return out;
}

function readInteger(n: number, hasHigher = false): string {
  const s = String(n);
  if (s.length <= 6) return readGroup(s, hasHigher);
  const head = Number(s.slice(0, s.length - 6));
  const tail = Number(s.slice(-6));
  return readInteger(head, hasHigher) + 'ล้าน' + (tail ? readGroup(String(tail), true) : '');
}

/** Thai amount in words, e.g. 11875 → "หนึ่งหมื่นหนึ่งพันแปดร้อยเจ็ดสิบห้าบาทถ้วน". */
export function bahtText(amount: number): string {
  if (!Number.isFinite(amount)) return '';
  const negative = amount < 0;
  const totalSatang = Math.round(Math.abs(amount) * 100);
  const baht = Math.floor(totalSatang / 100);
  const satang = totalSatang % 100;

  if (baht === 0 && satang === 0) return 'ศูนย์บาทถ้วน';

  let out = baht > 0 ? readInteger(baht) + 'บาท' : '';
  out += satang > 0 ? readInteger(satang) + 'สตางค์' : 'ถ้วน';
  return (negative ? 'ลบ' : '') + out;
}
