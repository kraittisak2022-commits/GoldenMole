import { chargedKm, distanceSurcharge, perKmFor, suggestTripFee } from './deliveryFee';

const delivery = { nearKm: 1, driverPerKm5: 50, driverPerKm3: 30 };

describe('suggestTripFee', () => {
  it('is free within the first km', () => {
    expect(suggestTripFee(0, 5, delivery)).toBe(0);
    expect(suggestTripFee(1, 3, delivery)).toBe(0);
  });

  it('charges the truck size baht/km for every started km beyond the first', () => {
    expect(suggestTripFee(1.4, 5, delivery)).toBe(50); // 0.4 km → 1 km × 50
    expect(suggestTripFee(1.7, 3, delivery)).toBe(30); // 0.7 km → 1 km × 30
    expect(suggestTripFee(2.4, 5, delivery)).toBe(100); // 1.4 km → 2 km × 50
    expect(suggestTripFee(2, 5, delivery)).toBe(50); // exactly 1 km × 50
  });

  it('uses the 5-คิว rate when the truck size is unknown', () => {
    expect(suggestTripFee(2.4, null, delivery)).toBe(100);
  });

  it('has no cap', () => {
    expect(suggestTripFee(10.5, 5, delivery)).toBe(500); // 9.5 km → 10 km × 50
  });

  it('is 0 without a distance or a rate', () => {
    expect(suggestTripFee(null, 5, delivery)).toBe(0);
    expect(suggestTripFee(Number.NaN, 5, delivery)).toBe(0);
    expect(suggestTripFee(5, 3, { ...delivery, driverPerKm3: 0 })).toBe(0);
  });
});

describe('chargedKm', () => {
  it('counts any part of a km as a full km', () => {
    expect(chargedKm(1.01, 1)).toBe(1);
    expect(chargedKm(1.4, 1)).toBe(1);
    expect(chargedKm(2.4, 1)).toBe(2);
    expect(chargedKm(0.8, 1)).toBe(0);
  });

  it('keeps whole km despite floating-point error', () => {
    expect(chargedKm(1.3, 0.3)).toBe(1); // 1.3 − 0.3 = 1.0000000000000002
    expect(chargedKm(3.3, 1.1)).toBe(3); // 2.1999999999999997
  });
});

describe('distanceSurcharge', () => {
  it('is the rate times the charged km', () => {
    expect(distanceSurcharge(2.4, { nearKm: 1, perKm: 50 })).toBe(100);
    expect(distanceSurcharge(1.7, { nearKm: 1, perKm: 30 })).toBe(30);
    expect(distanceSurcharge(2.4, { nearKm: 1, perKm: 0 })).toBe(0);
  });
});

describe('perKmFor', () => {
  it('picks the rate for the truck size', () => {
    expect(perKmFor(3, delivery)).toBe(30);
    expect(perKmFor(5, delivery)).toBe(50);
    expect(perKmFor(undefined, delivery)).toBe(50);
  });
});
