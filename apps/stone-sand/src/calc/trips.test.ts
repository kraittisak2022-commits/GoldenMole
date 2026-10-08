import { suggestTruckSize, totalTrips, truckFits, truckForLoads } from './trips';

describe('trips', () => {
  it('suggests a 3 คิว truck for small loads', () => {
    expect(suggestTruckSize(1)).toBe(3);
    expect(suggestTruckSize(3)).toBe(3);
    expect(suggestTruckSize(4)).toBe(5);
    expect(suggestTruckSize(12)).toBe(5);
  });

  it('counts the trips the customer asked for', () => {
    expect(totalTrips([])).toBe(0);
    expect(totalTrips([{ perTrip: 3, trips: 2 }])).toBe(2);
    expect(totalTrips([{ perTrip: 3, trips: 2 }, { perTrip: 5, trips: 1 }])).toBe(3);
    expect(totalTrips([{ perTrip: 0, trips: 2 }, { perTrip: 3, trips: 0 }])).toBe(0);
  });

  it('picks the smallest truck that carries the largest load per trip', () => {
    expect(truckForLoads([{ perTrip: 1, trips: 4 }, { perTrip: 3, trips: 1 }])).toBe(3);
    expect(truckForLoads([{ perTrip: 3, trips: 1 }, { perTrip: 5, trips: 1 }])).toBe(5);
  });

  it('rejects a truck smaller than a load per trip', () => {
    expect(truckFits(3, [{ perTrip: 3, trips: 2 }])).toBe(true);
    expect(truckFits(5, [{ perTrip: 3, trips: 2 }])).toBe(true);
    expect(truckFits(3, [{ perTrip: 4, trips: 1 }])).toBe(false);
    expect(truckFits(3, [{ perTrip: 5, trips: 0 }])).toBe(true);
  });
});
