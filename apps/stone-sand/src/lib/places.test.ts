import { describePin, pinPlaceText } from './places';

describe('describePin', () => {
  it('names the village whose centre the pin is on', () => {
    const p = describePin(19.26998, 99.51045);
    expect(p.village).toEqual({ name: 'บ้านหม้อ', km: 0 });
  });

  it('names the soi a pin dropped on it', () => {
    const p = describePin(19.20684, 99.51763);
    expect(p.road?.name).toMatch(/ซอย\s*14/);
    expect(p.road?.m).toBeLessThanOrEqual(10);
  });

  it('returns nothing far from any village or named road', () => {
    // Lampang city, well outside the bundled area
    expect(describePin(18.2888, 99.4908)).toEqual({ village: null, road: null });
  });
});

describe('pinPlaceText', () => {
  it('joins village and soi', () => {
    expect(pinPlaceText({ village: { name: 'บ้านหม้อ', km: 0.4 }, road: { name: 'ซอย 4', m: 30 } })).toBe(
      'ใกล้บ้านหม้อ · ซอย 4',
    );
    expect(pinPlaceText({ village: null, road: null })).toBe('');
  });
});
