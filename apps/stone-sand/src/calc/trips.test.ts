import { suggestTruckSize, tripsForLoads, truckForLoads } from './trips';

describe('trips', () => {
  it('suggests a 3 คิว truck for small loads', () => {
    expect(suggestTruckSize(1)).toBe(3);
    expect(suggestTruckSize(3)).toBe(3);
    expect(suggestTruckSize(4)).toBe(5);
    expect(suggestTruckSize(12)).toBe(5);
  });

  it('counts the trips the customer asked for', () => {
    expect(tripsForLoads([], 5)).toBe(0);
    expect(tripsForLoads([{ perTrip: 3, trips: 2 }], 5)).toBe(2);
    expect(tripsForLoads([{ perTrip: 3, trips: 2 }], 3)).toBe(2);
    expect(tripsForLoads([{ perTrip: 3, trips: 2 }, { perTrip: 5, trips: 1 }], 5)).toBe(3);
  });

  it('splits a load that does not fit the truck', () => {
    expect(tripsForLoads([{ perTrip: 5, trips: 2 }], 3)).toBe(4);
    expect(tripsForLoads([{ perTrip: 0, trips: 2 }, { perTrip: 3, trips: 0 }], 5)).toBe(0);
  });

  it('picks the truck from the largest load per trip', () => {
    expect(truckForLoads([{ perTrip: 1, trips: 4 }, { perTrip: 3, trips: 1 }])).toBe(3);
    expect(truckForLoads([{ perTrip: 3, trips: 1 }, { perTrip: 5, trips: 1 }])).toBe(5);
  });
});
