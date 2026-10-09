import type { DeliverySettings, TruckSize } from '../types';

type KmRates = Pick<DeliverySettings, 'nearKm' | 'driverPerKm5' | 'driverPerKm3'>;

/** Baht per km for the truck size; trucks of unknown size use the normal 5-คิว rate. */
export function perKmFor(truckSize: TruckSize | null | undefined, delivery: KmRates): number {
  return truckSize === 3 ? delivery.driverPerKm3 : delivery.driverPerKm5;
}

/**
 * Suggested delivery fee per trip: the tambon fee, plus the truck size's baht/km for every started km
 * beyond nearKm between the main road and the pin. The customer and the driver share that rate.
 */
export function suggestDeliveryFee(
  zone: { feeMin: number },
  distanceKm: number | null | undefined,
  truckSize: TruckSize | null | undefined,
  delivery: KmRates,
): number {
  return zone.feeMin + distanceSurcharge(distanceKm, { nearKm: delivery.nearKm, perKm: perKmFor(truckSize, delivery) });
}

/** Whole km beyond nearKm, any part of a km counting as a full km (1.4 km past → 2 km). */
export function chargedKm(distanceKm: number | null | undefined, nearKm: number): number {
  if (distanceKm == null || !Number.isFinite(distanceKm) || distanceKm <= nearKm) return 0;
  // Rounded to metres first so 2.0 − 1 stays 1 km despite floating-point error
  return Math.ceil(Math.round((distanceKm - nearKm) * 1000) / 1000);
}

/** Per-trip surcharge: the baht/km for each started km beyond nearKm; 0 without a distance. */
export function distanceSurcharge(distanceKm: number | null | undefined, rate: { nearKm: number; perKm: number }): number {
  if (rate.perKm <= 0) return 0;
  return chargedKm(distanceKm, rate.nearKm) * rate.perKm;
}
