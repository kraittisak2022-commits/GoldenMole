import { suggestDeliveryFee } from './deliveryFee';

const thungHua = { feeMin: 300, feeMax: 400 };
const wangThong = { feeMin: 1200, feeMax: 1500 };

describe('suggestDeliveryFee', () => {
  it('uses the lowest fee within 3 km of the main road', () => {
    expect(suggestDeliveryFee(thungHua, 0)).toBe(300);
    expect(suggestDeliveryFee(thungHua, 2.4)).toBe(300);
    expect(suggestDeliveryFee(thungHua, 3)).toBe(300);
  });

  it('scales between 3 km and maxKm, rounded up to 50', () => {
    expect(suggestDeliveryFee(thungHua, 4)).toBe(350);
    expect(suggestDeliveryFee(thungHua, 6.5)).toBe(350);
    expect(suggestDeliveryFee(thungHua, 7)).toBe(400);
    expect(suggestDeliveryFee(wangThong, 6.5)).toBe(1350);
  });

  it('uses the highest fee at or beyond maxKm', () => {
    expect(suggestDeliveryFee(thungHua, 10)).toBe(400);
    expect(suggestDeliveryFee(wangThong, 25)).toBe(1500);
  });

  it('falls back to the lowest fee without a distance', () => {
    expect(suggestDeliveryFee(thungHua, null)).toBe(300);
    expect(suggestDeliveryFee(thungHua, Number.NaN)).toBe(300);
  });

  it('respects custom settings', () => {
    expect(suggestDeliveryFee(wangThong, 5, { nearKm: 2, maxKm: 8, roundTo: 100 })).toBe(1400);
    expect(suggestDeliveryFee(wangThong, 5, { nearKm: 2, maxKm: 8, roundTo: 0 })).toBe(1350);
  });
});
