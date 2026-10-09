import type { Order } from '../types';
import { billStage, netMargin, stageAction, summarizeBill, totalBills } from './billSummary';

const make = (patch: Partial<Order> = {}): Order =>
  ({
    id: 'o1',
    customerId: 'c1',
    source: 'pit',
    fulfillment: 'delivery',
    driverId: 'drv-a',
    zoneId: 'z1',
    truckSize: 5,
    trips: 2,
    roadDistanceKm: null,
    driverWage: 0,
    driverPayoutId: null,
    deliveryTotal: 800,
    deliveryDiscount: 100,
    total: 5700,
    paymentMethod: 'cash',
    paymentStatus: 'paid',
    deliveryStatus: 'delivered',
    cleared: true,
    cancelled: false,
    statementId: null,
    ...patch,
  }) as Order;

const delivery = { nearKm: 1, customerPerKm: 0, driverPerKm5: 0, driverPerKm3: 0 };
const zoneOf = () => ({ driverFee: 250, driverFee3: 200 });
const sum = (o: Order) => summarizeBill(o, zoneOf, delivery);

describe('summarizeBill', () => {
  it('splits the bill into goods and delivery, and estimates ค่ารถ until the driver is paid', () => {
    const s = sum(make());
    expect(s).toMatchObject({ revenue: 5700, deliveryFee: 700, goods: 5000, driverCost: 500, driverCostEstimated: true });
    expect(s.net).toBe(5200);
    expect(s.deliveryMargin).toBe(200);
  });

  it('uses the amount actually paid to the driver once paid out', () => {
    const s = sum(make({ driverPayoutId: 'dpo-1', driverWage: 900 }));
    expect(s).toMatchObject({ driverCost: 900, driverCostEstimated: false, net: 4800, deliveryMargin: -200 });
  });

  it('has no driver cost for pickup orders', () => {
    const s = sum(make({ fulfillment: 'pickup', deliveryStatus: 'pickup', deliveryTotal: 0, deliveryDiscount: 0, total: 5000 }));
    expect(s).toMatchObject({ goods: 5000, deliveryFee: 0, driverCost: 0, net: 5000 });
  });

  it('counts unpaid money as receivable', () => {
    const s = sum(make({ paymentStatus: 'unpaid', cleared: false }));
    expect(s).toMatchObject({ received: 0, receivable: 5700 });
  });

  it('zeroes cancelled orders and leaves them out of the totals', () => {
    const cancelled = sum(make({ cancelled: true }));
    expect(cancelled).toMatchObject({ revenue: 0, net: 0, stage: 'cancelled' });
    const t = totalBills([sum(make()), cancelled]);
    expect(t).toMatchObject({ count: 1, revenue: 5700, driverCost: 500, driverCostPending: 500, net: 5200 });
  });
});

describe('billStage', () => {
  it('walks driver, delivery, money and driver pay in order', () => {
    expect(billStage(make({ driverId: null, deliveryStatus: 'waiting' }))).toBe('needDriver');
    expect(billStage(make({ deliveryStatus: 'waiting' }))).toBe('onTheWay');
    expect(billStage(make({ deliveryStatus: 'dispatched' }))).toBe('onTheWay');
    expect(billStage(make({ paymentMethod: 'cod', paymentStatus: 'unpaid', cleared: false }))).toBe('driverCash');
    expect(billStage(make({ paymentMethod: 'credit', paymentStatus: 'credit', cleared: false }))).toBe('unbilled');
    expect(billStage(make({ paymentMethod: 'credit', paymentStatus: 'credit', cleared: false, statementId: 's1' }))).toBe('billed');
    expect(billStage(make({ paymentStatus: 'unpaid', cleared: false }))).toBe('awaitPayment');
    expect(billStage(make())).toBe('payDriver');
    expect(billStage(make({ driverPayoutId: 'dpo-1' }))).toBe('done');
  });

  it('closes pickup orders once paid', () => {
    expect(billStage(make({ fulfillment: 'pickup', deliveryStatus: 'pickup', driverId: null }))).toBe('done');
    expect(
      billStage(make({ fulfillment: 'pickup', deliveryStatus: 'pickup', driverId: null, paymentMethod: 'cod', paymentStatus: 'unpaid', cleared: false })),
    ).toBe('awaitPayment');
  });

  it('marks the first unfinished step as current', () => {
    expect(sum(make({ paymentStatus: 'unpaid', cleared: false })).steps.map((s) => s.state)).toEqual([
      'done',
      'done',
      'current',
      'todo',
    ]);
    expect(sum(make({ fulfillment: 'pickup', deliveryStatus: 'pickup' })).steps.map((s) => s.state)).toEqual([
      'done',
      'done',
      'done',
      'skip',
    ]);
  });
});

describe('stageAction / netMargin', () => {
  it('links each stage to the page that moves it on', () => {
    expect(stageAction(make(), 'payDriver')?.to).toBe('/driver-pay?driver=drv-a');
    expect(stageAction(make(), 'unbilled')?.to).toBe('/statements?customer=c1&source=pit');
    expect(stageAction(make({ statementId: 's1' }), 'billed')?.to).toBe('/statements?open=s1');
    expect(stageAction(make(), 'onTheWay')?.to).toBe('/orders/o1');
    expect(stageAction(make(), 'done')).toBeNull();
  });

  it('rounds the margin and skips zero revenue', () => {
    expect(netMargin(5200, 5700)).toBe(91);
    expect(netMargin(0, 0)).toBeNull();
  });
});
