import { chargedKm, distanceSurcharge, perKmFor, suggestDeliveryFee } from './deliveryFee';

const wangTai = { feeMin: 240 };
const delivery = { nearKm: 1, driverPerKm5: 50, driverPerKm3: 30 };

describe('suggestDeliveryFee', () => {
  it('is the tambon fee within the free first km', () => {
    expect(suggestDeliveryFee(wangTai, 0, 5, delivery)).toBe(240);
    expect(suggestDeliveryFee(wangTai, 1, 3, delivery)).toBe(240);
  });

  it('adds the truck size baht/km for every started km beyond the first', () => {
    expect(suggestDeliveryFee(wangTai, 1.4, 5, delivery)).toBe(290); // 0.4 km → 1 km × 50
    expect(suggestDeliveryFee(wangTai, 1.7, 3, delivery)).toBe(270); // 0.7 km → 1 km × 30
    expect(suggestDeliveryFee(wangTai, 2.4, 5, delivery)).toBe(340); // 1.4 km → 2 km × 50
    expect(suggestDeliveryFee(wangTai, 2, 5, delivery)).toBe(290); // exactly 1 km × 50
  });

  it('uses the 5-คิว rate when the truck size is unknown', () => {
    expect(suggestDeliveryFee(wangTai, 2.4, null, delivery)).toBe(340);
  });

  it('has no cap', () => {
    expect(suggestDeliveryFee(wangTai, 10.5, 5, delivery)).toBe(740); // 9.5 km → 10 km × 50
  });

  it('falls back to the tambon fee without a distance or a rate', () => {
    expect(suggestDeliveryFee(wangTai, null, 5, delivery)).toBe(240);
    expect(suggestDeliveryFee(wangTai, Number.NaN, 5, delivery)).toBe(240);
    expect(suggestDeliveryFee(wangTai, 5, 3, { ...delivery, driverPerKm3: 0 })).toBe(240);
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
