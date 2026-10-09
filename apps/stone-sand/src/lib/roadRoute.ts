export interface LatLngPoint {
  lat: number;
  lng: number;
}

/** Driving distance in km from `/api/road-distance`, or null when it cannot be measured (no key, offline, no route). */
export async function fetchRoadDistanceKm(from: LatLngPoint, to: LatLngPoint, signal?: AbortSignal): Promise<number | null> {
  try {
    const res = await fetch('/api/road-distance', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ from, to }),
      signal,
    });
    if (!res.ok) return null;
    const data = (await res.json()) as { km?: unknown };
    return typeof data.km === 'number' && Number.isFinite(data.km) ? data.km : null;
  } catch {
    return null;
  }
}
