import { formatDateTh, formatPhone, parseDocNo } from './format';

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
