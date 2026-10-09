const field = (id: string, value: string) => `${id}${String(value.length).padStart(2, '0')}${value}`;

/** CRC-16/CCITT-FALSE as required by EMVCo QR. */
export function crc16(payload: string): string {
  let crc = 0xffff;
  for (let i = 0; i < payload.length; i += 1) {
    crc ^= payload.charCodeAt(i) << 8;
    for (let j = 0; j < 8; j += 1) {
      crc = crc & 0x8000 ? (crc << 1) ^ 0x1021 : crc << 1;
      crc &= 0xffff;
    }
  }
  return crc.toString(16).toUpperCase().padStart(4, '0');
}

/** True for a Thai QR / EMVCo payment payload with a valid checksum. */
export function isThaiQrPayload(payload: string): boolean {
  const p = payload.trim();
  if (!p.startsWith('000201') || p.length < 12 || p.slice(-8, -4) !== '6304') return false;
  return crc16(p.slice(0, -4)) === p.slice(-4).toUpperCase();
}

interface Tlv {
  id: string;
  value: string;
}

function parseTlv(payload: string): Tlv[] | null {
  const out: Tlv[] = [];
  for (let i = 0; i < payload.length; ) {
    const id = payload.slice(i, i + 2);
    const len = Number(payload.slice(i + 2, i + 4));
    if (!/^\d{2}$/.test(id) || !Number.isInteger(len) || i + 4 + len > payload.length) return null;
    out.push({ id, value: payload.slice(i + 4, i + 4 + len) });
    i += 4 + len;
  }
  return out;
}

const joinTlv = (fields: Tlv[]) => fields.map((f) => field(f.id, f.value)).join('');

/** Bank apps only accept A-Z and 0-9 in references; Thai QR allows at most 25 characters there. */
export function qrReference(text: string): string {
  return text.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 25);
}

/**
 * The shop's Thai QR with reference 3 (additional data 62, terminal label 07) set to `ref`,
 * so each bill gets its own QR. Returns the payload unchanged when it is not a valid Thai QR
 * or `ref` has no usable characters.
 */
export function withReference3(payload: string, ref: string): string {
  const p = payload.trim();
  const value = qrReference(ref);
  if (!value || !isThaiQrPayload(p)) return payload;
  const top = parseTlv(p.slice(0, -8));
  if (!top) return payload;
  const extra = top.find((f) => f.id === '62');
  const sub = extra ? parseTlv(extra.value) : [];
  if (!sub) return payload;
  const nextSub = [...sub.filter((f) => f.id !== '07'), { id: '07', value }].sort((a, b) => a.id.localeCompare(b.id));
  const nextTop = [...top.filter((f) => f.id !== '62'), { id: '62', value: joinTlv(nextSub) }].sort((a, b) =>
    a.id.localeCompare(b.id),
  );
  const body = `${joinTlv(nextTop)}6304`;
  return body + crc16(body);
}

/** Normalised PromptPay target, or null when the id is not a mobile number / tax id / e-wallet id. */
export function promptPayTarget(id: string): { tag: '01' | '02' | '03'; value: string } | null {
  const digits = id.replace(/\D/g, '');
  if (digits.length === 10 && digits.startsWith('0')) return { tag: '01', value: `0066${digits.slice(1)}` };
  if (digits.length === 13) return { tag: '02', value: digits };
  if (digits.length === 15) return { tag: '03', value: digits };
  return null;
}

/** EMVCo "Thai QR / PromptPay" payload. Dynamic (one-time amount) when amount > 0. */
export function promptPayPayload(id: string, amount?: number): string | null {
  const target = promptPayTarget(id);
  if (!target) return null;
  const merchant = field('00', 'A000000677010111') + field(target.tag, target.value);
  let payload =
    field('00', '01') +
    field('01', amount && amount > 0 ? '12' : '11') +
    field('29', merchant) +
    field('53', '764') +
    (amount && amount > 0 ? field('54', amount.toFixed(2)) : '') +
    field('58', 'TH');
  payload += '6304';
  return payload + crc16(payload);
}
