export interface LatLngPoint {
  lat: number;
  lng: number;
}

export interface RoadRoute {
  km: number;
  /** Driving path from the main road to the pin; empty when Google returned no line. */
  path: LatLngPoint[];
}

/** Driving route from `/api/road-distance`, or null when it cannot be measured (no key, offline, no route). */
export async function fetchRoadRoute(from: LatLngPoint, to: LatLngPoint, signal?: AbortSignal): Promise<RoadRoute | null> {
  try {
    const res = await fetch('/api/road-distance', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ from, to }),
      signal,
    });
    if (!res.ok) return null;
    const data = (await res.json()) as { km?: unknown; polyline?: unknown };
    if (typeof data.km !== 'number' || !Number.isFinite(data.km)) return null;
    let path: LatLngPoint[] = [];
    if (typeof data.polyline === 'string' && data.polyline) {
      try {
        path = decodePolyline(data.polyline);
      } catch {
        path = [];
      }
    }
    return { km: data.km, path };
  } catch {
    return null;
  }
}

/** Google encoded polyline (precision 5) to points. */
export function decodePolyline(encoded: string): LatLngPoint[] {
  const points: LatLngPoint[] = [];
  let index = 0;
  let lat = 0;
  let lng = 0;
  const next = () => {
    let result = 0;
    let shift = 0;
    let byte: number;
    do {
      if (index >= encoded.length) throw new Error('Truncated polyline');
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    return result & 1 ? ~(result >> 1) : result >> 1;
  };
  while (index < encoded.length) {
    lat += next();
    lng += next();
    points.push({ lat: lat / 1e5, lng: lng / 1e5 });
  }
  return points;
}

/** Point halfway along the path (by distance), for placing the distance label. */
export function pathMidpoint(path: LatLngPoint[]): LatLngPoint | null {
  if (!path.length) return null;
  if (path.length === 1) return path[0];
  const segLen = (a: LatLngPoint, b: LatLngPoint) => {
    const dx = (b.lng - a.lng) * Math.cos(((a.lat + b.lat) / 2) * (Math.PI / 180));
    return Math.hypot(dx, b.lat - a.lat);
  };
  const lengths = path.slice(1).map((p, i) => segLen(path[i], p));
  let remaining = lengths.reduce((s, l) => s + l, 0) / 2;
  for (let i = 0; i < lengths.length; i += 1) {
    if (remaining <= lengths[i] && lengths[i] > 0) {
      const t = remaining / lengths[i];
      return { lat: path[i].lat + (path[i + 1].lat - path[i].lat) * t, lng: path[i].lng + (path[i + 1].lng - path[i].lng) * t };
    }
    remaining -= lengths[i];
  }
  return path[path.length - 1];
}
