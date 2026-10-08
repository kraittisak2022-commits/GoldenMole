import type { TruckSize } from '../types';

/** One product ordered as `trips` deliveries of `perTrip` คิว each. */
export interface Load {
  perTrip: number;
  trips: number;
}

const isActive = (l: Load) => l.perTrip > 0 && l.trips > 0;

export function suggestTruckSize(totalQuantity: number): TruckSize {
  return totalQuantity > 0 && totalQuantity <= 3 ? 3 : 5;
}

export function truckForLoads(loads: Load[]): TruckSize {
  return suggestTruckSize(Math.max(0, ...loads.filter(isActive).map((l) => l.perTrip)));
}

export function tripsForLoads(loads: Load[], truckSize: TruckSize): number {
  return loads
    .filter(isActive)
    .reduce((sum, l) => sum + Math.ceil(l.perTrip / truckSize - 1e-9) * Math.floor(l.trips), 0);
}
