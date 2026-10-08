import type { TruckSize } from '../types';

export function suggestTruckSize(totalQuantity: number): TruckSize {
  return totalQuantity > 0 && totalQuantity <= 3 ? 3 : 5;
}

export function suggestTrips(totalQuantity: number, truckSize: TruckSize): number {
  if (!(totalQuantity > 0)) return 0;
  return Math.ceil(totalQuantity / truckSize - 1e-9);
}
