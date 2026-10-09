import { distanceSurcharge, suggestDeliveryFee } from './deliveryFee';

const wangTai = { feeMin: 240 };
const settings = { nearKm: 0.5, perKm: 40, roundTo: 50 };

describe('suggestDeliveryFee', () => {
  it('is the tambon fee within the free distance of the main road', () => {
    expect(suggestDeliveryFee(wangTai, 0, settings)).toBe(240);
    expect(suggestDeliveryFee(wangTai, 0.5, settings)).toBe(240);
  });

  it('adds baht per km beyond the free distance, rounded up to 50', () => {
    expect(suggestDeliveryFee(wangTai, 1, settings)).toBe(290); // 0.5 km × 40 = 20 → 50
    expect(suggestDeliveryFee(wangTai, 3, settings)).toBe(340); // 2.5 km × 40 = 100
    expect(suggestDeliveryFee(wangTai, 3.1, settings)).toBe(390); // 2.6 km × 40 = 104 → 150
  });

  it('has no cap', () => {
    expect(suggestDeliveryFee(wangTai, 10.5, settings)).toBe(640); // 10 km × 40 = 400
  });

  it('falls back to the tambon fee without a distance or a rate', () => {
    expect(suggestDeliveryFee(wangTai, null, settings)).toBe(240);
    expect(suggestDeliveryFee(wangTai, Number.NaN, settings)).toBe(240);
    expect(suggestDeliveryFee(wangTai, 5, { ...settings, perKm: 0 })).toBe(240);
  });

  it('respects other rounding', () => {
    expect(distanceSurcharge(1.8, { nearKm: 0.5, perKm: 35, roundTo: 10 })).toBe(50); // 45.5 → 50
    expect(distanceSurcharge(1.8, { nearKm: 0.5, perKm: 35, roundTo: 0 })).toBe(46);
  });
});
