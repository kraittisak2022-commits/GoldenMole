import type { Order } from '../types';

/** Default amount to pay the driver: the wage set on the order, else the delivery fee the customer was charged. */
export function suggestedDriverPay(o: Pick<Order, 'driverWage' | 'deliveryTotal'>): number {
  return o.driverWage > 0 ? o.driverWage : o.deliveryTotal;
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

export function summarizeDriverDues(orders: Order[]): DriverDue[] {
  const map = new Map<string, DriverDue>();
  for (const o of orders) {
    if (!o.driverId) continue;
    const row = map.get(o.driverId) ?? { driverId: o.driverId, count: 0, trips: 0, total: 0, cash: 0, oldestDate: o.orderDate };
    row.count += 1;
    row.trips += o.trips;
    row.total += suggestedDriverPay(o);
    row.cash += codToCollect(o);
    if (o.orderDate < row.oldestDate) row.oldestDate = o.orderDate;
    map.set(o.driverId, row);
  }
  return [...map.values()].sort((a, b) => b.total - a.total);
}
