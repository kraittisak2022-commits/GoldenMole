import { distanceSurcharge } from '../calc/deliveryFee';
import type { DeliverySettings, Order, TruckSize, Zone } from '../types';

type ZoneRates = Pick<Zone, 'driverFee' | 'driverFee3'> | undefined;

export interface DriverTripRate {
  /** Rate for the truck size; trucks of unknown size get the normal 5-คิว rate. 0 = not set. */
  base: number;
  /** Distance surcharge per trip at the driver's baht/km rate for the truck size. */
  extra: number;
  /** base + extra, or 0 while the base rate is not set. */
  perTrip: number;
}

export function driverTripRate(
  zone: ZoneRates,
  truckSize: TruckSize | null | undefined,
  roadDistanceKm: number | null | undefined,
  delivery: DeliverySettings,
): DriverTripRate {
  if (!zone) return { base: 0, extra: 0, perTrip: 0 };
  const small = truckSize === 3;
  const base = small ? zone.driverFee3 : zone.driverFee;
  const extra = distanceSurcharge(roadDistanceKm, {
    nearKm: delivery.nearKm,
    perKm: small ? delivery.driverPerKm3 : delivery.driverPerKm5,
    roundTo: delivery.roundTo,
  });
  return { base, extra, perTrip: base > 0 ? base + extra : 0 };
}

/**
 * Default amount to pay the driver: (tambon rate for the truck size + distance surcharge) × trips.
 * Without a rate it falls back to the wage stored on the order, never to the customer's delivery fee.
 */
export function suggestedDriverPay(
  o: Pick<Order, 'driverWage' | 'trips' | 'truckSize' | 'roadDistanceKm'>,
  zone: ZoneRates,
  delivery: DeliverySettings,
): number {
  const { perTrip } = driverTripRate(zone, o.truckSize, o.roadDistanceKm, delivery);
  return perTrip > 0 ? perTrip * o.trips : o.driverWage;
}

/** Cash the driver collected from the customer (เก็บเงินปลายทาง) and still has to hand to the shop. */
export function codToCollect(o: Pick<Order, 'paymentMethod' | 'paymentStatus' | 'total'>): number {
  return o.paymentMethod === 'cod' && o.paymentStatus !== 'paid' ? o.total : 0;
}

export interface DriverDue {
  driverId: string;
  count: number;
  trips: number;
  total: number;
  cash: number;
  oldestDate: string;
}

export function summarizeDriverDues(
  orders: Order[],
  zoneOf: (id: string | null) => ZoneRates,
  delivery: DeliverySettings,
): DriverDue[] {
  const map = new Map<string, DriverDue>();
  for (const o of orders) {
    if (!o.driverId) continue;
    const row = map.get(o.driverId) ?? { driverId: o.driverId, count: 0, trips: 0, total: 0, cash: 0, oldestDate: o.orderDate };
    row.count += 1;
    row.trips += o.trips;
    row.total += suggestedDriverPay(o, zoneOf(o.zoneId), delivery);
    row.cash += codToCollect(o);
    if (o.orderDate < row.oldestDate) row.oldestDate = o.orderDate;
    map.set(o.driverId, row);
  }
  return [...map.values()].sort((a, b) => b.total - a.total);
}
