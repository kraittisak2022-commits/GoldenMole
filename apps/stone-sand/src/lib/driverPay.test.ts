import type { Order } from '../types';
import { codToCollect, driverTripRate, suggestedDriverPay, summarizeDriverDues } from './driverPay';

const make = (patch: Partial<Order>): Order =>
  ({
    id: 'o1',
    driverId: 'drv-a',
    orderDate: '2026-10-05',
    trips: 1,
    roadDistanceKm: null,
    driverWage: 0,
    deliveryTotal: 600,
    deliveryDiscount: 0,
    total: 2000,
    paymentMethod: 'cash',
    paymentStatus: 'unpaid',
    ...patch,
  }) as Order;

const delivery = { nearKm: 0.5, maxKm: 3, roundTo: 50 };
/** Customer pays 240 near the road, up to 340 at 3 km. */
const zone = { feeMin: 240, feeMax: 340, driverFee: 350, driverFee3: 250 };

describe('driverTripRate', () => {
  it('adds the distance surcharge the customer pays to the truck-size rate', () => {
    expect(driverTripRate(zone, 5, 1, delivery)).toEqual({ base: 350, extra: 50, perTrip: 400 });
    expect(driverTripRate(zone, 3, 2, delivery)).toEqual({ base: 250, extra: 100, perTrip: 350 });
  });

  it('has no surcharge near the main road or without a distance', () => {
    expect(driverTripRate(zone, 5, 0.3, delivery).perTrip).toBe(350);
    expect(driverTripRate(zone, 5, null, delivery).perTrip).toBe(350);
  });

  it('is 0 while the rate for the truck size is not set, even with a surcharge', () => {
    expect(driverTripRate({ ...zone, driverFee3: 0 }, 3, 2, delivery).perTrip).toBe(0);
  });
});

describe('suggestedDriverPay', () => {
  it('is (truck-size rate + distance surcharge) times trips, ignoring the wage stored on the order', () => {
    expect(suggestedDriverPay(make({ truckSize: 5, trips: 3, roadDistanceKm: 1, driverWage: 450 }), zone, delivery)).toBe(1200);
    expect(suggestedDriverPay(make({ truckSize: 3, trips: 2, driverWage: 450 }), zone, delivery)).toBe(500);
  });

  it('pays the normal 5-คิว rate when the truck size is unknown', () => {
    expect(suggestedDriverPay(make({ truckSize: null, trips: 2 }), zone, delivery)).toBe(700);
  });

  it('does not use the 5-คิว rate for a 3-คิว truck without its own rate', () => {
    expect(suggestedDriverPay(make({ truckSize: 3, trips: 2 }), { ...zone, driverFee3: 0 }, delivery)).toBe(0);
  });

  it('falls back to the wage stored on the order when the zone has no driver fee', () => {
    expect(suggestedDriverPay(make({ driverWage: 450 }), { ...zone, driverFee: 0, driverFee3: 0 }, delivery)).toBe(450);
    expect(suggestedDriverPay(make({ driverWage: 450 }), undefined, delivery)).toBe(450);
  });

  it('never uses the delivery fee charged to the customer', () => {
    expect(suggestedDriverPay(make({ driverWage: 0, deliveryTotal: 1200 }), undefined, delivery)).toBe(0);
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
  const zones: Record<string, typeof zone> = {
    near: { feeMin: 150, feeMax: 150, driverFee: 300, driverFee3: 200 },
    far: { feeMin: 240, feeMax: 340, driverFee: 1000, driverFee3: 800 },
  };
  const zoneOf = (id: string | null) => (id ? zones[id] : undefined);

  it('groups by driver with count, trips, zone-based pay, COD cash and oldest date', () => {
    const dues = summarizeDriverDues(
      [
        make({ id: 'o1', zoneId: 'near', trips: 2, orderDate: '2026-10-07', paymentMethod: 'cod', total: 1800 }),
        make({ id: 'o2', zoneId: null, trips: 1, driverWage: 250, orderDate: '2026-10-03' }),
        make({ id: 'o3', zoneId: 'far', driverId: 'drv-b', trips: 1, roadDistanceKm: 3, deliveryTotal: 2500 }),
      ],
      zoneOf,
      delivery,
    );
    expect(dues).toEqual([
      { driverId: 'drv-b', count: 1, trips: 1, total: 1100, cash: 0, oldestDate: '2026-10-05' },
      { driverId: 'drv-a', count: 2, trips: 3, total: 850, cash: 1800, oldestDate: '2026-10-03' },
    ]);
  });

  it('skips orders without a driver', () => {
    expect(summarizeDriverDues([make({ driverId: null })], zoneOf, delivery)).toEqual([]);
  });
});
