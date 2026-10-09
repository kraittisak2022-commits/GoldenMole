import type { DeliverySettings, TruckSize } from '../types';

type DriverKmRates = Pick<DeliverySettings, 'driverPerKm5' | 'driverPerKm3'>;
type CustomerKmRate = Pick<DeliverySettings, 'nearKm' | 'customerPerKm'>;

/** Driver baht per km for the truck size; trucks of unknown size use the normal 5-คิว rate. */
export function perKmFor(truckSize: TruckSize | null | undefined, delivery: DriverKmRates): number {
  return truckSize === 3 ? delivery.driverPerKm3 : delivery.driverPerKm5;
}

/**
 * Suggested customer fee per trip on top of the tambon's baht/คิว: customerPerKm for every started km
 * beyond nearKm between the main road and the pin, whatever the truck size.
 */
export function suggestTripFee(distanceKm: number | null | undefined, delivery: CustomerKmRate): number {
  return distanceSurcharge(distanceKm, { nearKm: delivery.nearKm, perKm: delivery.customerPerKm });
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
