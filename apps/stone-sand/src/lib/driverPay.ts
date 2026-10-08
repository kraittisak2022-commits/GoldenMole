import type { Order } from '../types';

/** Default amount to pay the driver: the wage set on the order, else the delivery fee the customer was charged. */
export function suggestedDriverPay(o: Pick<Order, 'driverWage' | 'deliveryTotal'>): number {
  return o.driverWage > 0 ? o.driverWage : o.deliveryTotal;
}

export interface DriverDue {
  driverId: string;
  count: number;
  trips: number;
  total: number;
  oldestDate: string;
}

export function summarizeDriverDues(orders: Order[]): DriverDue[] {
  const map = new Map<string, DriverDue>();
  for (const o of orders) {
    if (!o.driverId) continue;
    const row = map.get(o.driverId) ?? { driverId: o.driverId, count: 0, trips: 0, total: 0, oldestDate: o.orderDate };
    row.count += 1;
    row.trips += o.trips;
    row.total += suggestedDriverPay(o);
    if (o.orderDate < row.oldestDate) row.oldestDate = o.orderDate;
    map.set(o.driverId, row);
  }
  return [...map.values()].sort((a, b) => b.total - a.total);
}
