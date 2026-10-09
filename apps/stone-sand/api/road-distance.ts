/**
 * Driving distance between two points, via Google Routes API.
 * The browser cannot call Routes API directly (no CORS) and the key must stay server-side.
 * POST { from: { lat, lng }, to: { lat, lng } } → { km }
 */

interface LatLng {
  lat: number;
  lng: number;
}

/** อ.วังเหนือ plus ~20 km, so the key cannot be used to route anywhere else. */
const BOUNDS = { minLat: 18.7, maxLat: 19.62, minLng: 99.32, maxLng: 99.98 };

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });

function readPoint(v: unknown): LatLng | null {
  if (!v || typeof v !== 'object') return null;
  const { lat, lng } = v as Record<string, unknown>;
  if (typeof lat !== 'number' || typeof lng !== 'number') return null;
  if (lat < BOUNDS.minLat || lat > BOUNDS.maxLat || lng < BOUNDS.minLng || lng > BOUNDS.maxLng) return null;
  return { lat, lng };
}

const waypoint = (p: LatLng) => ({ location: { latLng: { latitude: p.lat, longitude: p.lng } } });

export async function POST(request: Request): Promise<Response> {
  const key = process.env.GOOGLE_MAPS_API_KEY;
  if (!key) return json({ error: 'not_configured' }, 503);

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad_request' }, 400);
  }
  const from = readPoint(body.from);
  const to = readPoint(body.to);
  if (!from || !to) return json({ error: 'bad_request' }, 400);

  const res = await fetch('https://routes.googleapis.com/directions/v2:computeRoutes', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': key,
      'X-Goog-FieldMask': 'routes.distanceMeters',
    },
    body: JSON.stringify({
      origin: waypoint(from),
      destination: waypoint(to),
      travelMode: 'DRIVE',
      routingPreference: 'TRAFFIC_UNAWARE',
    }),
  });
  if (!res.ok) return json({ error: 'upstream', status: res.status }, 502);
  const data = (await res.json()) as { routes?: { distanceMeters?: number }[] };
  const meters = data.routes?.[0]?.distanceMeters;
  if (typeof meters !== 'number') return json({ error: 'no_route' }, 404);
  return json({ km: Math.round(meters / 10) / 100 });
}
