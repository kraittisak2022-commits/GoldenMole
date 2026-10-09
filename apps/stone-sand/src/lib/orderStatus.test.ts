import type { Order } from '../types';
import { driverMessage, matchesFilter, matchesSearch, outstanding, statementPaidMap, summarizeOutstanding } from './orderStatus';

const base: Order = {
  id: 'o1',
  orderNo: 'DO6910-0001',
  receiptNo: null,
  source: 'shop',
  orderDate: '2026-10-08',
  customerId: 'c1',
  customer: { name: 'สมชาย ใจดี', phone: '0931234567', address: '', taxId: '' },
  fulfillment: 'delivery',
  deliveryAddress: 'บ้านทุ่งฮั้ว หมู่ 3',
  pinLat: 19.2,
  pinLng: 99.6,
  zoneId: 'thung-hua',
  roadDistanceKm: 1.2,
  truckSize: 5,
  trips: 2,
  driverId: null,
  feePerTrip: 300,
  remoteSurcharge: 0,
  discountType: 'baht',
  discountValue: 0,
  subtotal: 2000,
  deliveryTotal: 600,
  deliveryDiscount: 0,
  discountAmount: 0,
  total: 2600,
  paymentMethod: 'cod',
  paymentStatus: 'unpaid',
  paidAt: null,
  deliveryStatus: 'waiting',
  deliveredAt: null,
  cleared: false,
  clearedAt: null,
  driverWage: 0,
  note: '',
  cancelled: false,
  verifyToken: 't',
  statusLog: [],
  createdBy: null,
  createdAt: '',
  items: [{ productId: 'small-stone', name: 'หินเล็กคละ', unit: 'คิว', unitPrice: 400, quantity: 5, amount: 2000 }],
};

describe('matchesFilter', () => {
  it('classifies payment and delivery state', () => {
    expect(matchesFilter(base, 'unpaid')).toBe(true);
    expect(matchesFilter(base, 'waiting')).toBe(true);
    expect(matchesFilter(base, 'uncleared')).toBe(true);
    expect(matchesFilter(base, 'credit')).toBe(false);
    expect(matchesFilter({ ...base, paymentStatus: 'credit' }, 'credit')).toBe(true);
    expect(matchesFilter({ ...base, paymentStatus: 'credit', cleared: true }, 'credit')).toBe(false);
  });

  it('hides cancelled orders from status filters', () => {
    const c = { ...base, cancelled: true };
    expect(matchesFilter(c, 'unpaid')).toBe(false);
    expect(matchesFilter(c, 'all')).toBe(true);
    expect(matchesFilter(c, 'cancelled')).toBe(true);
    expect(outstanding(c)).toBe(0);
  });
});

describe('matchesSearch', () => {
  it('finds by name, doc number and phone digits', () => {
    expect(matchesSearch(base, 'สมชาย')).toBe(true);
    expect(matchesSearch(base, 'do6910')).toBe(true);
    expect(matchesSearch(base, '093-123')).toBe(true);
    expect(matchesSearch(base, 'สมหญิง')).toBe(false);
  });

  it('finds by the customer ชื่อเรียก', () => {
    expect(matchesSearch({ ...base, customerAliases: ['เสี่ยบาส'] }, 'บาส')).toBe(true);
  });
});

describe('summarizeOutstanding', () => {
  it('groups per customer and separates orders already on a statement', () => {
    const rows = summarizeOutstanding([
      base,
      { ...base, id: 'o2', total: 1000, orderDate: '2026-10-01', statementId: 'stm-1' },
      { ...base, id: 'o3', cleared: true },
      { ...base, id: 'o4', customerId: 'c2', total: 500 },
    ]);
    expect(rows).toHaveLength(2);
    expect(rows[0]).toMatchObject({ customerId: 'c1', total: 3600, count: 2, unbilledTotal: 2600, unbilledCount: 1, oldestDate: '2026-10-01' });
    expect(rows[1]).toMatchObject({ customerId: 'c2', total: 500 });
  });

  it('keeps ร้านวัสดุ and ท่าทราย orders of the same customer in separate rows', () => {
    const rows = summarizeOutstanding([base, { ...base, id: 'o2', source: 'pit', total: 800 }]);
    expect(rows).toHaveLength(2);
    expect(rows.map((r) => [r.customerId, r.source, r.total])).toEqual([
      ['c1', 'shop', 2600],
      ['c1', 'pit', 800],
    ]);
  });

  it('deducts partial payments once per statement', () => {
    const paid = statementPaidMap([
      { id: 'stm-1', status: 'open', paidAmount: 700 },
      { id: 'stm-2', status: 'cleared', paidAmount: 999 },
    ]);
    expect(paid).toEqual({ 'stm-1': 700 });
    const rows = summarizeOutstanding(
      [
        { ...base, id: 'o1', total: 1000, statementId: 'stm-1' },
        { ...base, id: 'o2', total: 500, statementId: 'stm-1' },
        { ...base, id: 'o3', total: 200 },
      ],
      paid,
    );
    expect(rows[0]).toMatchObject({ total: 1000, unbilledTotal: 200, count: 3 });
  });
});

describe('driverMessage', () => {
  it('includes the map link and cash to collect', () => {
    const msg = driverMessage(base, { id: 'thung-hua', name: 'ทุ่งฮั้ว', feeMin: 300, driverFee: 0, driverFee3: 0, sortOrder: 1 }, undefined);
    expect(msg).toContain('https://www.google.com/maps?q=19.200000,99.600000');
    expect(msg).toContain('เก็บเงินปลายทาง');
    expect(msg).toContain('ตำบล: ทุ่งฮั้ว');
    expect(msg).toContain('093-123-4567');
    expect(msg).not.toContain('/d/');
  });

  it('ends with the driver confirm link', () => {
    const msg = driverMessage({ ...base, driverToken: 'abc123' }, undefined, undefined);
    const lines = msg.split('\n');
    expect(lines.at(-1)).toBe('https://order.goldenmole.pro/d/abc123');
    expect(lines.at(-2)).toContain('แจ้งยอดเงินที่เก็บ');
    expect(lines.at(-3)).toBe('');
  });

  it('skips cash to collect when the order is billed on a statement', () => {
    const msg = driverMessage({ ...base, driverToken: 'abc123', statementId: 's1' }, undefined, undefined);
    expect(msg).not.toContain('เก็บเงินปลายทาง');
    expect(msg).not.toContain('แจ้งยอดเงิน');
    expect(msg).toContain('/d/abc123');
  });

  it('has no confirm link for cancelled orders', () => {
    expect(driverMessage({ ...base, driverToken: 'abc123', cancelled: true }, undefined, undefined)).not.toContain('/d/');
  });
});
