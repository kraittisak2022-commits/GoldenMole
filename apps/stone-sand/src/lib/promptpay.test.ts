import { billQrPayload, crc16, isThaiQrPayload, promptPayPayload, promptPayTarget, qrReference } from './promptpay';

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

describe('billQrPayload', () => {
  const shopQr =
    '00020101021130730016A0000006770101120115010753700088205021916151060181105030020307PIRASIT53037645802TH620807040000630443A3';
  const merchant = '30730016A0000006770101120115010753700088205021916151060181105030020307PIRASIT';
  const head = `000201010211${merchant}53037645802TH`;

  it("replaces the shop QR's reference 3 with the bill number and re-signs it", () => {
    const p = billQrPayload(shopQr, { ref: 'DO2610-0005' });
    expect(p.slice(0, -4)).toBe(`${head}6214` + '0710DO26100005' + '6304');
    expect(isThaiQrPayload(p)).toBe(true);
  });

  it('adds the amount to pay as a one-time QR', () => {
    const p = billQrPayload(shopQr, { ref: 'DO2610-0005', amount: 2130 });
    expect(p.slice(0, -4)).toBe(
      `000201010212${merchant}5303764` + '54072130.00' + '5802TH' + '6214' + '0710DO26100005' + '6304',
    );
    expect(isThaiQrPayload(p)).toBe(true);
  });

  it('replaces an amount already in the QR and ignores a zero amount', () => {
    const withAmount = billQrPayload(shopQr, { ref: 'X', amount: 100 });
    expect(billQrPayload(withAmount, { ref: 'X', amount: 1234.5 })).toContain('54071234.50' + '5802TH');
    expect(billQrPayload(shopQr, { ref: 'DO1', amount: 0 })).toContain('010211');
  });

  it('adds reference 3 to a QR without additional data and keeps the field order', () => {
    const p = billQrPayload(promptPayPayload('0801234567')!, { ref: 'BL2610-0004' });
    expect(p).toContain('5802TH' + '6214' + '0710BL26100004' + '6304');
    expect(isThaiQrPayload(p)).toBe(true);
  });

  it('keeps other additional data fields', () => {
    const base = `${head}62140503ABC07030006304`;
    const p = billQrPayload(base + crc16(base), { ref: 'RC1' });
    expect(p).toContain('6214' + '0503ABC' + '0703RC1' + '6304');
  });

  it('leaves the payload alone when it is not a Thai QR or there is nothing to set', () => {
    expect(billQrPayload('https://example.com', { ref: 'DO1', amount: 50 })).toBe('https://example.com');
    expect(billQrPayload(shopQr, { ref: '--' })).toBe(shopQr);
  });
});

describe('qrReference', () => {
  it('keeps A-Z and 0-9 only, up to 25 characters', () => {
    expect(qrReference('do2610-0005')).toBe('DO26100005');
    expect(qrReference('X'.repeat(30))).toHaveLength(25);
  });
});
