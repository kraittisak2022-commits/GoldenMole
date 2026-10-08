import { parseLatLng } from './latlng';

describe('parseLatLng', () => {
  it('reads plain coordinates', () => {
    expect(parseLatLng('19.1453, 99.6187')).toEqual({ lat: 19.1453, lng: 99.6187 });
    expect(parseLatLng('19.1453 99.6187')).toEqual({ lat: 19.1453, lng: 99.6187 });
  });

  it('reads Google Maps URLs', () => {
    expect(parseLatLng('https://www.google.com/maps/@19.1453,99.6187,15z')).toEqual({ lat: 19.1453, lng: 99.6187 });
    expect(parseLatLng('https://maps.google.com/?q=19.1453,99.6187')).toEqual({ lat: 19.1453, lng: 99.6187 });
    expect(
      parseLatLng('https://www.google.com/maps/place/x/@19.1,99.6,17z/data=!3m1!4b1!4m5!3m4!1s0x0:0x0!8m2!3d19.1453!4d99.6187'),
    ).toEqual({ lat: 19.1453, lng: 99.6187 });
  });

  it('rejects text and short links', () => {
    expect(parseLatLng('บ้านทุ่งฮั้ว')).toBeNull();
    expect(parseLatLng('https://maps.app.goo.gl/abc123')).toBeNull();
    expect(parseLatLng('200, 99')).toBeNull();
  });
});
