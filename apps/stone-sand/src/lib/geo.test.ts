import { distanceToMainRoad, findTambon, isInDistrict } from './geo';

describe('geo helpers', () => {
  it('finds the tambon of known places', () => {
    // เทศบาลตำบลวังเหนือ (town centre)
    expect(findTambon(19.14533, 99.61872)?.name).toMatch(/วังเหนือ|วังซ้าย/);
    // บ้านร่องเคาะ
    expect(findTambon(18.9898, 99.61652)?.name).toBe('ร่องเคาะ');
  });

  it('returns null outside อ.วังเหนือ', () => {
    // Lampang city
    expect(isInDistrict(18.2888, 99.4908)).toBe(false);
    expect(findTambon(18.2888, 99.4908)).toBeNull();
  });

  it('measures ~0 km on highway 120 in town', () => {
    const d = distanceToMainRoad(19.14407, 99.62455);
    expect(d).not.toBeNull();
    expect(d!.km).toBeLessThan(0.5);
  });

  it('every tambon centre is within reach of a main road', () => {
    const centres: [string, number, number][] = [
      ['ทุ่งฮั้ว', 19.2373, 99.6087],
      ['วังแก้ว', 19.3411, 99.6244],
      ['วังทอง', 19.0675, 99.714],
      ['ร่องเคาะ', 18.9835, 99.5963],
    ];
    for (const [name, lat, lng] of centres) {
      const d = distanceToMainRoad(lat, lng);
      expect(d, name).not.toBeNull();
      expect(d!.km, name).toBeLessThan(10);
    }
  });
});
