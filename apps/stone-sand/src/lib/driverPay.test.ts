import type { Order } from '../types';
import { codToCollect, suggestedDriverPay, summarizeDriverDues } from './driverPay';

const make = (patch: Partial<Order>): Order =>
  ({
    id: 'o1',
    driverId: 'drv-a',
    orderDate: '2026-10-05',
    trips: 1,
    driverWage: 0,
    deliveryTotal: 600,
    deliveryDiscount: 0,
    total: 2000,
    paymentMethod: 'cash',
    paymentStatus: 'unpaid',
    ...patch,
  }) as Order;

describe('suggestedDriverPay', () => {
  it('is the zone driver fee times trips, ignoring the wage stored on the order', () => {
    expect(suggestedDriverPay(make({ trips: 3, driverWage: 450, deliveryTotal: 1800 }), { driverFee: 350 })).toBe(1050);
  });

  it('falls back to the wage stored on the order when the zone has no driver fee', () => {
    expect(suggestedDriverPay(make({ driverWage: 450 }), { driverFee: 0 })).toBe(450);
    expect(suggestedDriverPay(make({ driverWage: 450 }), undefined)).toBe(450);
  });

  it('never uses the delivery fee charged to the customer', () => {
    expect(suggestedDriverPay(make({ driverWage: 0, deliveryTotal: 1200 }), undefined)).toBe(0);
  });
});

describe('codToCollect', () => {
  it('is the order total for an unpaid cash-on-delivery order', () => {
    expect(codToCollect(make({ paymentMethod: 'cod', total: 3060 }))).toBe(3060);
  });

  it('is zero once paid, or for other payment methods', () => {
    expect(codToCollect(make({ paymentMethod: 'cod', paymentStatus: 'paid' }))).toBe(0);
    expect(codToCollect(make({ paymentMethod: 'credit', paymentStatus: 'credit' }))).toBe(0);
  });
});

describe('summarizeDriverDues', () => {
  const zones: Record<string, { driverFee: number }> = { near: { driverFee: 300 }, far: { driverFee: 1000 } };
  const zoneOf = (id: string | null) => (id ? zones[id] : undefined);

  it('groups by driver with count, trips, zone-based pay, COD cash and oldest date', () => {
    const dues = summarizeDriverDues(
      [
        make({ id: 'o1', zoneId: 'near', trips: 2, orderDate: '2026-10-07', paymentMethod: 'cod', total: 1800 }),
        make({ id: 'o2', zoneId: null, trips: 1, driverWage: 250, orderDate: '2026-10-03' }),
        make({ id: 'o3', zoneId: 'far', driverId: 'drv-b', trips: 1, deliveryTotal: 2500 }),
      ],
      zoneOf,
    );
    expect(dues).toEqual([
      { driverId: 'drv-b', count: 1, trips: 1, total: 1000, cash: 0, oldestDate: '2026-10-05' },
      { driverId: 'drv-a', count: 2, trips: 3, total: 850, cash: 1800, oldestDate: '2026-10-03' },
    ]);
  });

  it('skips orders without a driver', () => {
    expect(summarizeDriverDues([make({ driverId: null })], zoneOf)).toEqual([]);
  });
});
