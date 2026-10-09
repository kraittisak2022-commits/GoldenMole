import type { Order, OrderItem } from '../types';
import { codToCollect, deliveredCubes, suggestedDriverPay, summarizeDriverDues } from './driverPay';

const line = (quantity: number, unit = 'คิว') => ({ unit, quantity }) as OrderItem;

const make = (patch: Partial<Order>): Order =>
  ({
    id: 'o1',
    driverId: 'drv-a',
    orderDate: '2026-10-05',
    trips: 1,
    items: [line(5)],
    driverWage: 0,
    deliveryTotal: 600,
    deliveryDiscount: 0,
    total: 2000,
    paymentMethod: 'cash',
    paymentStatus: 'unpaid',
    ...patch,
  }) as Order;

describe('deliveredCubes', () => {
  it('sums คิว across lines and ignores other units', () => {
    expect(deliveredCubes([line(5), line(2.5), line(3, 'ถุง')])).toBe(7.5);
  });
});

describe('suggestedDriverPay', () => {
  const zone = { driverFee: 60, driverFee3: 70 };

  it('is the zone rate per คิว for the truck size times คิว delivered, ignoring the wage stored on the order', () => {
    expect(suggestedDriverPay(make({ truckSize: 5, items: [line(10), line(5)], driverWage: 450, deliveryTotal: 1800 }), zone)).toBe(900);
    expect(suggestedDriverPay(make({ truckSize: 3, items: [line(6)], driverWage: 450 }), zone)).toBe(420);
  });

  it('rounds to whole baht for part-คิว loads', () => {
    expect(suggestedDriverPay(make({ truckSize: 5, items: [line(2.5)] }), { driverFee: 45, driverFee3: 0 })).toBe(113);
  });

  it('pays the normal 5-คิว rate when the truck size is unknown', () => {
    expect(suggestedDriverPay(make({ truckSize: null, items: [line(10)] }), zone)).toBe(600);
  });

  it('does not use the 5-คิว rate for a 3-คิว truck without its own rate', () => {
    expect(suggestedDriverPay(make({ truckSize: 3, items: [line(6)] }), { driverFee: 60, driverFee3: 0 })).toBe(0);
  });

  it('falls back to the wage stored on the order when the zone has no driver fee', () => {
    expect(suggestedDriverPay(make({ driverWage: 450 }), { driverFee: 0, driverFee3: 0 })).toBe(450);
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
  const zones: Record<string, { driverFee: number; driverFee3: number }> = {
    near: { driverFee: 50, driverFee3: 60 },
    far: { driverFee: 200, driverFee3: 220 },
  };
  const zoneOf = (id: string | null) => (id ? zones[id] : undefined);

  it('groups by driver with count, trips, zone-based pay, COD cash and oldest date', () => {
    const dues = summarizeDriverDues(
      [
        make({ id: 'o1', zoneId: 'near', trips: 2, items: [line(10)], orderDate: '2026-10-07', paymentMethod: 'cod', total: 1800 }),
        make({ id: 'o2', zoneId: null, trips: 1, driverWage: 250, orderDate: '2026-10-03' }),
        make({ id: 'o3', zoneId: 'far', driverId: 'drv-b', trips: 1, deliveryTotal: 2500 }),
      ],
      zoneOf,
    );
    expect(dues).toEqual([
      { driverId: 'drv-b', count: 1, trips: 1, total: 1000, cash: 0, oldestDate: '2026-10-05' },
      { driverId: 'drv-a', count: 2, trips: 3, total: 750, cash: 1800, oldestDate: '2026-10-03' },
    ]);
  });

  it('skips orders without a driver', () => {
    expect(summarizeDriverDues([make({ driverId: null })], zoneOf)).toEqual([]);
  });
});
