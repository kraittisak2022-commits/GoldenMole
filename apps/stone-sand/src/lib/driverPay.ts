import type { Order, TruckSize, Zone } from '../types';

type ZoneDriverFee = Pick<Zone, 'driverFee' | 'driverFee3'> | undefined;

/** Driver fee per trip for the truck size; trucks of unknown size are paid the normal 5-คิว rate. */
export function zoneDriverFee(zone: ZoneDriverFee, truckSize: TruckSize | null | undefined): number {
  if (!zone) return 0;
  return truckSize === 3 ? zone.driverFee3 : zone.driverFee;
}

/**
 * Default amount to pay the driver: the tambon's driver fee for the truck size × trips.
 * Without a rate it falls back to the wage stored on the order, never to the customer's delivery fee.
 */
export function suggestedDriverPay(o: Pick<Order, 'driverWage' | 'trips' | 'truckSize'>, zone: ZoneDriverFee): number {
  const perTrip = zoneDriverFee(zone, o.truckSize);
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

export function summarizeDriverDues(orders: Order[], zoneOf: (id: string | null) => ZoneDriverFee): DriverDue[] {
  const map = new Map<string, DriverDue>();
  for (const o of orders) {
    if (!o.driverId) continue;
    const row = map.get(o.driverId) ?? { driverId: o.driverId, count: 0, trips: 0, total: 0, cash: 0, oldestDate: o.orderDate };
    row.count += 1;
    row.trips += o.trips;
    row.total += suggestedDriverPay(o, zoneOf(o.zoneId));
    row.cash += codToCollect(o);
    if (o.orderDate < row.oldestDate) row.oldestDate = o.orderDate;
    map.set(o.driverId, row);
  }
  return [...map.values()].sort((a, b) => b.total - a.total);
}
