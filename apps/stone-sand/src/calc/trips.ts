import type { TruckSize } from '../types';

/** One product ordered as `trips` deliveries of `perTrip` คิว each. */
export interface Load {
  perTrip: number;
  trips: number;
}

const isActive = (l: Load) => l.perTrip > 0 && l.trips > 0;

const largestPerTrip = (loads: Load[]) => Math.max(0, ...loads.filter(isActive).map((l) => l.perTrip));

export function suggestTruckSize(totalQuantity: number): TruckSize {
  return totalQuantity > 0 && totalQuantity <= 3 ? 3 : 5;
}

export function truckForLoads(loads: Load[]): TruckSize {
  return suggestTruckSize(largestPerTrip(loads));
}

export function truckFits(size: TruckSize, loads: Load[]): boolean {
  return size >= largestPerTrip(loads);
}

export function totalTrips(loads: Load[]): number {
  return loads.filter(isActive).reduce((sum, l) => sum + Math.floor(l.trips), 0);
}
