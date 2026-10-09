import type { DeliverySettings } from '../types';

export const DEFAULT_DELIVERY_SETTINGS: DeliverySettings = { nearKm: 3, maxKm: 10, roundTo: 50 };

/**
 * Suggested delivery fee per trip for a tambon fee range, from the straight-line distance
 * between the pin and the nearest main road.
 */
export function suggestDeliveryFee(
  zone: { feeMin: number; feeMax: number },
  distanceKm: number | null | undefined,
  settings: DeliverySettings = DEFAULT_DELIVERY_SETTINGS,
): number {
  const { feeMin, feeMax } = zone;
  const { nearKm, maxKm, roundTo } = settings;
  if (distanceKm == null || !Number.isFinite(distanceKm) || distanceKm <= nearKm) return feeMin;
  if (distanceKm >= maxKm || maxKm <= nearKm) return feeMax;

  const extra = ((feeMax - feeMin) * (distanceKm - nearKm)) / (maxKm - nearKm);
  const rounded = roundTo > 0 ? Math.ceil(extra / roundTo) * roundTo : Math.round(extra);
  return Math.min(feeMax, feeMin + rounded);
}
