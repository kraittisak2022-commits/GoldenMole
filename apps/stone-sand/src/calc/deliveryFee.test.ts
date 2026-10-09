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

  it('rounds only the distance surcharge, so a base fee off the 50 grid is kept', () => {
    const wangTai = { feeMin: 240, feeMax: 340 };
    const settings = { nearKm: 0.5, maxKm: 3, roundTo: 50 };
    expect(suggestDeliveryFee(wangTai, 0.4, settings)).toBe(240);
    expect(suggestDeliveryFee(wangTai, 1, settings)).toBe(290);
    expect(suggestDeliveryFee(wangTai, 2, settings)).toBe(340);
    expect(suggestDeliveryFee({ feeMin: 150, feeMax: 150 }, 2, settings)).toBe(150);
  });

  it('respects custom settings', () => {
    expect(suggestDeliveryFee(wangThong, 5, { nearKm: 2, maxKm: 8, roundTo: 100 })).toBe(1400);
    expect(suggestDeliveryFee(wangThong, 5, { nearKm: 2, maxKm: 8, roundTo: 0 })).toBe(1350);
  });
});
