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

type PayOrder = Pick<Order, 'driverWage' | 'trips' | 'truckSize' | 'roadDistanceKm' | 'deliveryTotal' | 'deliveryDiscount'>;

/** zone = tambon rate for the truck size; stored = wage saved on the order; customerFee = what the customer paid for delivery. */
export type DriverPaySource = 'zone' | 'stored' | 'customerFee';

export interface DriverPayBreakdown {
  amount: number;
  source: DriverPaySource;
  rate: DriverTripRate;
}

/** Delivery charged to the customer on the order, after its delivery discount. */
export function customerDeliveryFee(o: Pick<Order, 'deliveryTotal' | 'deliveryDiscount'>): number {
  return Math.max(0, o.deliveryTotal - o.deliveryDiscount);
}

/**
 * Default amount to pay the driver: (tambon rate for the truck size + distance surcharge) × trips.
 * While the tambon has no rate for that truck size it uses the wage stored on the order,
 * and failing that the delivery fee the customer paid for the order.
 */
export function driverPayBreakdown(o: PayOrder, zone: ZoneRates, delivery: DeliverySettings): DriverPayBreakdown {
  const rate = driverTripRate(zone, o.truckSize, o.roadDistanceKm, delivery);
  if (rate.perTrip > 0) return { amount: rate.perTrip * o.trips, source: 'zone', rate };
  if (o.driverWage > 0) return { amount: o.driverWage, source: 'stored', rate };
  return { amount: customerDeliveryFee(o), source: 'customerFee', rate };
}

export function suggestedDriverPay(o: PayOrder, zone: ZoneRates, delivery: DeliverySettings): number {
  return driverPayBreakdown(o, zone, delivery).amount;
}

/**
 * The driver keeps his pay out of the COD money he collected: he hands the rest to the shop,
 * or the shop pays him what the COD money did not cover.
 */
export function settleWithDriver(pay: number, cod: number): { handover: number; topUp: number } {
  return { handover: Math.max(0, cod - pay), topUp: Math.max(0, pay - cod) };
}

/**
 * Cash the driver collected from the customer (เก็บเงินปลายทาง) and still has to hand to the shop.
 * An order billed on a statement is paid through เคลียร์บิล instead, so the driver owes nothing for it.
 */
export function codToCollect(o: Pick<Order, 'paymentMethod' | 'paymentStatus' | 'total' | 'statementId'>): number {
  return o.paymentMethod === 'cod' && o.paymentStatus !== 'paid' && !o.statementId ? o.total : 0;
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
