import type { Order } from '../types';
import {
  codToCollect,
  driverPayBreakdown,
  driverTripRate,
  settleWithDriver,
  suggestedDriverPay,
  summarizeDriverDues,
} from './driverPay';

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

/** Beyond 0.5 km: 5-คิว 60, 3-คิว 30 baht per km. */
const delivery = { nearKm: 0.5, driverPerKm5: 60, driverPerKm3: 30 };
const zone = { driverFee: 350, driverFee3: 250 };

describe('driverTripRate', () => {
  it('adds the distance surcharge at the per-km rate for the truck size', () => {
    expect(driverTripRate(zone, 5, 1, delivery)).toEqual({ base: 350, extra: 30, perTrip: 380 }); // 0.5 × 60
    expect(driverTripRate(zone, 5, 2, delivery)).toEqual({ base: 350, extra: 90, perTrip: 440 }); // 1.5 × 60
    expect(driverTripRate(zone, 3, 2, delivery)).toEqual({ base: 250, extra: 45, perTrip: 295 }); // 1.5 × 30
  });

  it('has no surcharge while the rate for the truck size is 0', () => {
    expect(driverTripRate(zone, 3, 2, { ...delivery, driverPerKm3: 0 }).extra).toBe(0);
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
    expect(suggestedDriverPay(make({ truckSize: 5, trips: 3, roadDistanceKm: 1, driverWage: 450 }), zone, delivery)).toBe(1140);
    expect(suggestedDriverPay(make({ truckSize: 3, trips: 2, driverWage: 450 }), zone, delivery)).toBe(500);
  });

  it('pays the normal 5-คิว rate when the truck size is unknown', () => {
    expect(suggestedDriverPay(make({ truckSize: null, trips: 2 }), zone, delivery)).toBe(700);
  });

  it('does not use the 5-คิว rate for a 3-คิว truck without its own rate', () => {
    expect(suggestedDriverPay(make({ truckSize: 3, trips: 2 }), { ...zone, driverFee3: 0 }, delivery)).toBe(600);
  });

  it('falls back to the wage stored on the order when the zone has no driver fee', () => {
    expect(suggestedDriverPay(make({ driverWage: 450 }), { ...zone, driverFee: 0, driverFee3: 0 }, delivery)).toBe(450);
    expect(driverPayBreakdown(make({ driverWage: 450 }), undefined, delivery)).toMatchObject({ amount: 450, source: 'stored' });
  });

  it("then falls back to the customer's delivery fee after its delivery discount", () => {
    expect(driverPayBreakdown(make({ deliveryTotal: 250, deliveryDiscount: 50 }), undefined, delivery)).toMatchObject({
      amount: 200,
      source: 'customerFee',
    });
    expect(suggestedDriverPay(make({ deliveryTotal: 0 }), { ...zone, driverFee: 0 }, delivery)).toBe(0);
  });

  it('reports the tambon rate as the source when it is set', () => {
    expect(driverPayBreakdown(make({ truckSize: 5 }), zone, delivery).source).toBe('zone');
  });
});

describe('settleWithDriver', () => {
  it('has the driver hand over the COD money minus his pay', () => {
    expect(settleWithDriver(250, 3050)).toEqual({ handover: 2800, topUp: 0 });
  });

  it('has the shop pay what the COD money does not cover', () => {
    expect(settleWithDriver(450, 200)).toEqual({ handover: 0, topUp: 250 });
    expect(settleWithDriver(450, 0)).toEqual({ handover: 0, topUp: 450 });
    expect(settleWithDriver(300, 300)).toEqual({ handover: 0, topUp: 0 });
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

  it('is zero for an order billed on a statement, which is collected through เคลียร์บิล', () => {
    expect(codToCollect(make({ paymentMethod: 'cod', total: 2130, statementId: 'stm-1' }))).toBe(0);
  });
});

describe('summarizeDriverDues', () => {
  const zones: Record<string, typeof zone> = {
    near: { driverFee: 300, driverFee3: 200 },
    far: { driverFee: 1000, driverFee3: 800 },
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
      { driverId: 'drv-b', count: 1, trips: 1, total: 1150, cash: 0, oldestDate: '2026-10-05' },
      { driverId: 'drv-a', count: 2, trips: 3, total: 850, cash: 1800, oldestDate: '2026-10-03' },
    ]);
  });

  it('skips orders without a driver', () => {
    expect(summarizeDriverDues([make({ driverId: null })], zoneOf, delivery)).toEqual([]);
  });
});
