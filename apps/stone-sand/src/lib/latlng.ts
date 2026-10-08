export interface LatLngValue {
  lat: number;
  lng: number;
}

const valid = (lat: number, lng: number) =>
  Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180;

/**
 * Reads "19.15, 99.62", Google Maps URLs (…/@19.15,99.62,15z, ?q=19.15,99.62, !3d19.15!4d99.62).
 * Short links (maps.app.goo.gl) cannot be resolved in the browser and return null.
 */
export function parseLatLng(input: string): LatLngValue | null {
  const s = decodeURIComponent(input.trim());
  if (!s) return null;

  const d34 = /!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)/.exec(s);
  if (d34) {
    const lat = Number(d34[1]);
    const lng = Number(d34[2]);
    if (valid(lat, lng)) return { lat, lng };
  }

  const patterns = [
    /@(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)/,
    /[?&](?:q|query|ll|destination)=(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)/,
    /^(-?\d+(?:\.\d+)?)\s*[, ]\s*(-?\d+(?:\.\d+)?)$/,
  ];
  for (const re of patterns) {
    const m = re.exec(s);
    if (m) {
      const lat = Number(m[1]);
      const lng = Number(m[2]);
      if (valid(lat, lng)) return { lat, lng };
    }
  }
  return null;
}
