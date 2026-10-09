import { decodePolyline, pathMidpoint } from './roadRoute';

describe('decodePolyline', () => {
  it('decodes the example from the Google polyline documentation', () => {
    expect(decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@')).toEqual([
      { lat: 38.5, lng: -120.2 },
      { lat: 40.7, lng: -120.95 },
      { lat: 43.252, lng: -126.453 },
    ]);
  });

  it('returns no points for an empty string and throws on truncated input', () => {
    expect(decodePolyline('')).toEqual([]);
    expect(() => decodePolyline('_p~iF~ps|')).toThrow();
  });
});

describe('pathMidpoint', () => {
  it('finds the point halfway along the path', () => {
    const mid = pathMidpoint([
      { lat: 19, lng: 99.6 },
      { lat: 19.01, lng: 99.6 },
      { lat: 19.03, lng: 99.6 },
    ])!;
    expect(mid.lat).toBeCloseTo(19.015, 6);
    expect(mid.lng).toBeCloseTo(99.6, 6);
  });

  it('handles empty and single-point paths', () => {
    expect(pathMidpoint([])).toBeNull();
    expect(pathMidpoint([{ lat: 19, lng: 99 }])).toEqual({ lat: 19, lng: 99 });
  });
});
