import { pointToLineDistance } from '@turf/point-to-line-distance';
import { lineString } from '@turf/helpers';
import placesJson from '../data/geo/places.json';

interface Village {
  name: string;
  kind: string;
  lat: number;
  lng: number;
}

interface NamedRoad {
  name: string;
  highway: string;
  ref: string;
  coords: [number, number][];
}

const data = placesJson as unknown as { villages: Village[]; roads: NamedRoad[] };
const roads = data.roads.map((r) => ({ name: r.name, line: lineString(r.coords) }));

/** Beyond this the closest village centre says little about where the pin is. */
const VILLAGE_MAX_KM = 4;
/** A named road/soi further than this is not "the soi the site is on". */
const ROAD_MAX_KM = 0.25;

export interface PinPlace {
  village: { name: string; km: number } | null;
  road: { name: string; m: number } | null;
}

function kmBetween(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const kx = 111.32 * Math.cos(((lat1 + lat2) / 2) * (Math.PI / 180));
  return Math.hypot((lng2 - lng1) * kx, (lat2 - lat1) * 110.57);
}

/** Nearest village and named road/soi around a pin, from bundled OpenStreetMap data. */
export function describePin(lat: number, lng: number): PinPlace {
  let village: PinPlace['village'] = null;
  for (const v of data.villages) {
    const km = kmBetween(lat, lng, v.lat, v.lng);
    if (km <= VILLAGE_MAX_KM && (!village || km < village.km)) village = { name: v.name, km };
  }

  let road: { name: string; km: number } | null = null;
  for (const r of roads) {
    const km = pointToLineDistance([lng, lat], r.line, { units: 'kilometers', method: 'planar' });
    if (km <= ROAD_MAX_KM && (!road || km < road.km)) road = { name: r.name, km };
  }

  return {
    village: village && { name: village.name, km: Math.round(village.km * 10) / 10 },
    road: road && { name: road.name, m: Math.round((road.km * 1000) / 10) * 10 },
  };
}

/** Short text for the address field, e.g. "ใกล้บ้านหม้อ · ซอย 4". */
export function pinPlaceText(p: PinPlace): string {
  return [p.village ? `ใกล้${p.village.name}` : '', p.road?.name ?? ''].filter(Boolean).join(' · ');
}
