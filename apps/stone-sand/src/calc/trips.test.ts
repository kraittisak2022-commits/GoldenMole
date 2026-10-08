import { suggestTrips, suggestTruckSize } from './trips';

describe('trips', () => {
  it('suggests a 3 คิว truck for small orders', () => {
    expect(suggestTruckSize(1)).toBe(3);
    expect(suggestTruckSize(3)).toBe(3);
    expect(suggestTruckSize(4)).toBe(5);
    expect(suggestTruckSize(12)).toBe(5);
  });

  it('rounds trips up', () => {
    expect(suggestTrips(0, 5)).toBe(0);
    expect(suggestTrips(3, 3)).toBe(1);
    expect(suggestTrips(5, 5)).toBe(1);
    expect(suggestTrips(6, 5)).toBe(2);
    expect(suggestTrips(10, 5)).toBe(2);
    expect(suggestTrips(10, 3)).toBe(4);
  });
});
