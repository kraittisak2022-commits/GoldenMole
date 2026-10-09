import { crc16, isThaiQrPayload, promptPayPayload, promptPayTarget } from './promptpay';

describe('crc16', () => {
  it('matches the CRC-16/CCITT-FALSE check value', () => {
    expect(crc16('123456789')).toBe('29B1');
  });
});

describe('promptPayTarget', () => {
  it('normalises phone and tax id', () => {
    expect(promptPayTarget('065-812-4686')).toEqual({ tag: '01', value: '0066658124686' });
    expect(promptPayTarget('0523566002017')).toEqual({ tag: '02', value: '0523566002017' });
    expect(promptPayTarget('12345')).toBeNull();
  });
});

describe('promptPayPayload', () => {
  it('builds a static payload for a phone number', () => {
    const p = promptPayPayload('0801234567')!;
    const body = '000201' + '010211' + '29370016A00000067701011101130066801234567' + '5303764' + '5802TH' + '6304';
    expect(p.slice(0, -4)).toBe(body);
    expect(p.slice(-4)).toBe(crc16(body));
  });

  it('adds a dynamic amount', () => {
    const p = promptPayPayload('0523566002017', 1500)!;
    expect(p).toContain('010212');
    expect(p).toContain('29370016A000000677010111' + '02130523566002017');
    expect(p).toContain('54071500.00');
    expect(p.slice(-4)).toBe(crc16(p.slice(0, -4)));
  });

  it('rejects unknown ids', () => {
    expect(promptPayPayload('abc')).toBeNull();
  });
});

describe('isThaiQrPayload', () => {
  /** Shop QR, Krungthai bill payment. */
  const shopQr =
    '00020101021130730016A0000006770101120115010753700088205021916151060181105030020307PIRASIT53037645802TH620807040000630443A3';

  it('accepts payloads with a valid checksum', () => {
    expect(isThaiQrPayload(shopQr)).toBe(true);
    expect(isThaiQrPayload(promptPayPayload('0801234567')!)).toBe(true);
  });

  it('rejects other text and a wrong checksum', () => {
    expect(isThaiQrPayload('https://example.com')).toBe(false);
    expect(isThaiQrPayload(`${shopQr.slice(0, -4)}0000`)).toBe(false);
  });
});
