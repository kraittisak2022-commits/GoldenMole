import { distanceSurcharge, perKmFor, suggestDeliveryFee } from './deliveryFee';

const wangTai = { feeMin: 240 };
const delivery = { nearKm: 0.5, driverPerKm5: 40, driverPerKm3: 30 };

describe('suggestDeliveryFee', () => {
  it('is the tambon fee within the free distance of the main road', () => {
    expect(suggestDeliveryFee(wangTai, 0, 5, delivery)).toBe(240);
    expect(suggestDeliveryFee(wangTai, 0.5, 3, delivery)).toBe(240);
  });

  it('adds the truck size baht per km beyond the free distance, to the nearest baht', () => {
    expect(suggestDeliveryFee(wangTai, 1, 5, delivery)).toBe(260); // 0.5 km × 40
    expect(suggestDeliveryFee(wangTai, 3, 5, delivery)).toBe(340); // 2.5 km × 40
    expect(suggestDeliveryFee(wangTai, 3, 3, delivery)).toBe(315); // 2.5 km × 30
    expect(suggestDeliveryFee(wangTai, 3.12, 3, delivery)).toBe(319); // 2.62 km × 30 = 78.6
  });

  it('uses the 5-คิว rate when the truck size is unknown', () => {
    expect(suggestDeliveryFee(wangTai, 3, null, delivery)).toBe(340);
  });

  it('has no cap', () => {
    expect(suggestDeliveryFee(wangTai, 10.5, 5, delivery)).toBe(640); // 10 km × 40
  });

  it('falls back to the tambon fee without a distance or a rate', () => {
    expect(suggestDeliveryFee(wangTai, null, 5, delivery)).toBe(240);
    expect(suggestDeliveryFee(wangTai, Number.NaN, 5, delivery)).toBe(240);
    expect(suggestDeliveryFee(wangTai, 5, 3, { ...delivery, driverPerKm3: 0 })).toBe(240);
  });
});

describe('distanceSurcharge', () => {
  it('rounds to the nearest baht', () => {
    expect(distanceSurcharge(1.8, { nearKm: 0.5, perKm: 35 })).toBe(46); // 45.5
    expect(distanceSurcharge(1.81, { nearKm: 0.5, perKm: 35 })).toBe(46); // 45.85
  });
});

describe('perKmFor', () => {
  it('picks the rate for the truck size', () => {
    expect(perKmFor(3, delivery)).toBe(30);
    expect(perKmFor(5, delivery)).toBe(40);
    expect(perKmFor(undefined, delivery)).toBe(40);
  });
});
