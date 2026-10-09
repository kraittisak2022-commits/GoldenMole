import type { DeliverySettings } from '../types';

type SurchargeRate = Pick<DeliverySettings, 'nearKm' | 'perKm' | 'roundTo'>;

export const DEFAULT_DELIVERY_SETTINGS: SurchargeRate = { nearKm: 0.5, perKm: 0, roundTo: 50 };

/**
 * Suggested delivery fee per trip: the tambon fee, plus perKm for every km beyond nearKm
 * between the main road and the pin. Only the surcharge is rounded up, and it has no cap.
 */
export function suggestDeliveryFee(
  zone: { feeMin: number },
  distanceKm: number | null | undefined,
  settings: SurchargeRate = DEFAULT_DELIVERY_SETTINGS,
): number {
  return zone.feeMin + distanceSurcharge(distanceKm, settings);
}

/** Per-trip surcharge for the distance beyond nearKm; 0 without a distance. */
export function distanceSurcharge(distanceKm: number | null | undefined, settings: SurchargeRate): number {
  const { nearKm, perKm, roundTo } = settings;
  if (distanceKm == null || !Number.isFinite(distanceKm) || distanceKm <= nearKm || perKm <= 0) return 0;
  const extra = (distanceKm - nearKm) * perKm;
  return roundTo > 0 ? Math.ceil(extra / roundTo) * roundTo : Math.round(extra);
}
