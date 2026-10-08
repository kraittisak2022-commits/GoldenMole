import type { Order } from '../types';
import { suggestedDriverPay, summarizeDriverDues } from './driverPay';

const make = (patch: Partial<Order>): Order =>
  ({
    id: 'o1',
    driverId: 'drv-a',
    orderDate: '2026-10-05',
    trips: 1,
    driverWage: 0,
    deliveryTotal: 600,
    ...patch,
  }) as Order;

describe('suggestedDriverPay', () => {
  it('uses the wage set on the order', () => {
    expect(suggestedDriverPay(make({ driverWage: 450 }))).toBe(450);
  });

  it('falls back to the delivery fee charged when no wage is set', () => {
    expect(suggestedDriverPay(make({ driverWage: 0, deliveryTotal: 1200 }))).toBe(1200);
  });
});

describe('summarizeDriverDues', () => {
  it('groups by driver with count, trips, suggested total and oldest date', () => {
    const dues = summarizeDriverDues([
      make({ id: 'o1', trips: 2, deliveryTotal: 1000, orderDate: '2026-10-07' }),
      make({ id: 'o2', trips: 1, driverWage: 300, orderDate: '2026-10-03' }),
      make({ id: 'o3', driverId: 'drv-b', trips: 1, deliveryTotal: 2500 }),
    ]);
    expect(dues).toEqual([
      { driverId: 'drv-b', count: 1, trips: 1, total: 2500, oldestDate: '2026-10-05' },
      { driverId: 'drv-a', count: 2, trips: 3, total: 1300, oldestDate: '2026-10-03' },
    ]);
  });

  it('skips orders without a driver', () => {
    expect(summarizeDriverDues([make({ driverId: null })])).toEqual([]);
  });
});
