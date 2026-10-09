import type { Order, Statement } from '../../types';
import { billFromOrder, billFromStatement } from './billData';

const order: Order = {
  id: 'o1',
  orderNo: 'DO6910-0001',
  receiptNo: 'RE6910-0001',
  source: 'shop',
  orderDate: '2026-10-08',
  customerId: 'c1',
  customer: { name: 'สมชาย', phone: '0931234567', address: 'ทุ่งฮั้ว', taxId: '' },
  fulfillment: 'delivery',
  deliveryAddress: 'หมู่ 3',
  pinLat: null,
  pinLng: null,
  zoneId: 'thung-hua',
  roadDistanceKm: null,
  truckSize: 5,
  trips: 2,
  driverId: null,
  feePerCubic: 0,
  feePerTrip: 350,
  remoteSurcharge: 100,
  discountType: 'percent',
  discountValue: 10,
  subtotal: 2000,
  deliveryTotal: 800,
  deliveryDiscount: 0,
  discountAmount: 200,
  total: 2600,
  paymentMethod: 'cash',
  paymentStatus: 'paid',
  paidAt: '2026-10-08T03:00:00Z',
  deliveryStatus: 'waiting',
  deliveredAt: null,
  cleared: true,
  clearedAt: null,
  driverWage: 0,
  note: '',
  cancelled: false,
  verifyToken: 'tok',
  statusLog: [],
  createdBy: 'admin',
  createdAt: '',
  items: [{ productId: 'small-stone', name: 'หินเล็กคละ', unit: 'คิว', unitPrice: 400, quantity: 5, amount: 2000 }],
};

const thungHua = { id: 'thung-hua', name: 'ทุ่งฮั้ว', feePerCubic: 40, driverFee: 0, driverFee3: 0, sortOrder: 1 };

describe('billFromOrder', () => {
  it('adds delivery and surcharge lines that sum to the gross amount', () => {
    const bill = billFromOrder(order, 'delivery', thungHua);
    expect(bill.lines.map((l) => l.amount)).toEqual([2000, 700, 100]);
    expect(bill.lines.reduce((s, l) => s + l.amount, 0)).toBe(bill.gross);
    expect(bill.gross - bill.discountAmount).toBe(bill.total);
    expect(bill.lines[1].description).toBe('ค่าขนส่ง ต.ทุ่งฮั้ว');
    expect(bill.docNo).toBe('DO6910-0001');
    expect(bill.discountLabel).toContain('10%');
  });

  it('charges the tambon fee per คิว and the distance surcharge per trip', () => {
    // 5 คิว × 40 + 2 เที่ยว × 50 + 100 remote
    const perCubic = { ...order, feePerCubic: 40, feePerTrip: 50, deliveryTotal: 400, discountAmount: 0, total: 2400 };
    const bill = billFromOrder(perCubic, 'delivery', thungHua);
    expect(bill.lines.slice(1)).toMatchObject([
      { description: 'ค่าขนส่ง ต.ทุ่งฮั้ว', quantity: 5, unit: 'คิว', unitPrice: 40, amount: 200 },
      { description: 'ค่าขนส่งเพิ่มตามระยะทาง', quantity: 2, unit: 'เที่ยว', unitPrice: 50, amount: 100 },
      { amount: 100 },
    ]);
    expect(bill.lines.reduce((s, l) => s + l.amount, 0)).toBe(bill.gross);

    const near = billFromOrder({ ...perCubic, feePerTrip: 0, deliveryTotal: 300, total: 2300 }, 'delivery', thungHua);
    expect(near.lines.map((l) => l.description)).toEqual(['หินเล็กคละ', 'ค่าขนส่ง ต.ทุ่งฮั้ว', 'ค่าขนส่งเพิ่ม (พื้นที่ห่างไกล)']);
  });

  it('names ส่วนลดค่าส่ง alongside the bill discount', () => {
    const bill = billFromOrder({ ...order, deliveryDiscount: 100, discountAmount: 300, total: 2500 }, 'delivery');
    expect(bill.discountLabel).toBe('ส่วนลดค่าส่ง + ส่วนลด 10% (ค่าสินค้า)');
    expect(bill.gross - bill.discountAmount).toBe(bill.total);
    expect(billFromOrder({ ...order, deliveryDiscount: 100, discountAmount: 100, total: 2700 }, 'delivery').discountLabel).toBe(
      'ส่วนลดค่าส่ง',
    );
  });

  it('a receipt uses the receipt number and references the delivery note', () => {
    const bill = billFromOrder(order, 'receipt');
    expect(bill.docNo).toBe('RE6910-0001');
    expect(bill.refs).toEqual([{ label: 'อ้างอิงใบส่งของ', value: 'DO6910-0001' }]);
  });

  it('dates the delivery note signatures with the delivery date, else the order date', () => {
    expect(billFromOrder(order, 'delivery').signDate).toBe(order.orderDate);
    const delivered = { ...order, deliveredAt: '2026-10-09T07:39:46Z' };
    expect(billFromOrder(delivered, 'delivery').signDate).toBe('2026-10-09T07:39:46Z');
    expect(billFromOrder(delivered, 'receipt').signDate).toBeUndefined();
  });

  it('pickup orders have no delivery line', () => {
    const bill = billFromOrder({ ...order, fulfillment: 'pickup', trips: 0, deliveryTotal: 0 }, 'delivery');
    expect(bill.lines).toHaveLength(1);
    expect(bill.delivery).toBeUndefined();
  });
});

describe('billFromStatement', () => {
  it('lists one line per order', () => {
    const s: Statement = {
      id: 's1',
      statementNo: 'BL6910-0001',
      source: 'shop',
      customerId: 'c1',
      customer: order.customer,
      periodFrom: '2026-10-01',
      periodTo: '2026-10-31',
      total: 5200,
      status: 'open',
      paymentMethod: null,
      clearedAt: null,
      verifyToken: 'st',
      note: '',
      createdBy: null,
      createdAt: '2026-10-31T10:00:00Z',
      orderIds: ['o1', 'o2'],
      payments: [],
      paidAmount: 0,
      balance: 5200,
    };
    const bill = billFromStatement(s, [order, { ...order, id: 'o2', orderNo: 'DO6910-0002' }]);
    expect(bill.lines).toHaveLength(2);
    expect(bill.lines[0].date).toBe('2026-10-08');
    expect(bill.total).toBe(5200);
    expect(bill.paid).toBe(false);
    expect(bill.paidAmount).toBe(0);
    expect(bill.period).toEqual({ from: '2026-10-01', to: '2026-10-31' });

    const partial = billFromStatement(
      {
        ...s,
        paidAmount: 2000,
        balance: 3200,
        payments: [{ id: 'p1', amount: 2000, method: 'transfer', paidAt: '2026-11-02T09:00:00Z', note: '', createdBy: null }],
      },
      [order],
    );
    expect(partial.paidAmount).toBe(2000);
    expect(partial.total).toBe(5200);
  });
});
