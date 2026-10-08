import { formatDateLongTh, formatDateTh, formatPhone, monthRange, parseDocNo, shiftIsoDate } from './format';

describe('date helpers', () => {
  it('moves across month and year ends', () => {
    expect(shiftIsoDate('2026-10-31', 1)).toBe('2026-11-01');
    expect(shiftIsoDate('2026-01-01', -1)).toBe('2025-12-31');
  });

  it('gives the calendar month of a date', () => {
    expect(monthRange('2026-02-14')).toEqual({ from: '2026-02-01', to: '2026-02-28' });
    expect(monthRange('2028-02-03')).toEqual({ from: '2028-02-01', to: '2028-02-29' });
  });

  it('writes the weekday and Buddhist year', () => {
    expect(formatDateLongTh('2026-10-08')).toBe('พฤหัสบดี 8 ตุลาคม 2569');
  });
});

describe('parseDocNo', () => {
  it('parses the three document types', () => {
    expect(parseDocNo('DO2610-0001')).toEqual({ kind: 'delivery', year: 2026, month: 10, seq: 1 });
    expect(parseDocNo('RE2610-0042')?.kind).toBe('receipt');
    expect(parseDocNo('BL2612-1234')).toEqual({ kind: 'statement', year: 2026, month: 12, seq: 1234 });
  });

  it('rejects malformed numbers', () => {
    expect(parseDocNo('XX2610-0001')).toBeNull();
    expect(parseDocNo('DO2613-0001')).toBeNull();
    expect(parseDocNo('DO2610-01')).toBeNull();
  });
});

describe('format helpers', () => {
  it('formats Buddhist-year dates', () => {
    expect(formatDateTh('2026-10-08')).toBe('08/10/2569');
  });

  it('formats Thai phone numbers', () => {
    expect(formatPhone('0931234567')).toBe('093-123-4567');
    expect(formatPhone('054 123 456')).toBe('05-412-3456');
  });
});
