import type { DeliverySettings, TruckSize } from '../types';

type KmRates = Pick<DeliverySettings, 'nearKm' | 'driverPerKm5' | 'driverPerKm3'>;

/** Baht per km for the truck size; trucks of unknown size use the normal 5-คิว rate. */
export function perKmFor(truckSize: TruckSize | null | undefined, delivery: KmRates): number {
  return truckSize === 3 ? delivery.driverPerKm3 : delivery.driverPerKm5;
}

/**
 * Suggested delivery fee per trip: the tambon fee, plus the truck size's baht/km for every km
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

/** Per-trip surcharge for the distance beyond nearKm, to the nearest baht; 0 without a distance. */
export function distanceSurcharge(distanceKm: number | null | undefined, rate: { nearKm: number; perKm: number }): number {
  const { nearKm, perKm } = rate;
  if (distanceKm == null || !Number.isFinite(distanceKm) || distanceKm <= nearKm || perKm <= 0) return 0;
  return Math.round((distanceKm - nearKm) * perKm);
}
