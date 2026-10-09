import { booleanPointInPolygon } from '@turf/boolean-point-in-polygon';
import { nearestPointOnLine } from '@turf/nearest-point-on-line';
import { pointToLineDistance } from '@turf/point-to-line-distance';
import type { Feature, FeatureCollection, LineString, MultiPolygon, Polygon } from 'geojson';
import districtJson from '../data/geo/district.json';
import roadsJson from '../data/geo/main-roads.json';
import tambonsJson from '../data/geo/tambons.json';

type AreaFeature = Feature<Polygon | MultiPolygon, { name: string }>;
type RoadFeature = Feature<LineString, { ref: string; name: string; highway: string }>;

const district = (districtJson as unknown as FeatureCollection<Polygon | MultiPolygon>).features[0];
const tambons = (tambonsJson as unknown as FeatureCollection<Polygon | MultiPolygon, { name: string }>)
  .features as AreaFeature[];
const roads = (roadsJson as unknown as FeatureCollection<LineString, RoadFeature['properties']>)
  .features as RoadFeature[];

/** Map centre used when no pin is set (middle of อ.วังเหนือ). */
export const DISTRICT_CENTER = { lat: 19.158, lng: 99.632 };

export const districtOutline = district;
export const mainRoads = roads;

function centroid(f: AreaFeature): [number, number] {
  const pts = (f.geometry.type === 'Polygon' ? f.geometry.coordinates : f.geometry.coordinates.flat()).flat();
  const lng = pts.reduce((s, p) => s + p[0], 0) / pts.length;
  const lat = pts.reduce((s, p) => s + p[1], 0) / pts.length;
  return [lng, lat];
}

const tambonCentroids = tambons.map((f) => ({ name: f.properties.name, c: centroid(f) }));

export function isInDistrict(lat: number, lng: number): boolean {
  return !!district && booleanPointInPolygon([lng, lat], district);
}

export interface TambonMatch {
  name: string;
  /** exact = inside a tambon polygon; nearest = inside the district but between coarse tambon outlines */
  method: 'exact' | 'nearest';
}

/** Tambon name for a pin, or null when the pin is outside อ.วังเหนือ. */
export function findTambon(lat: number, lng: number): TambonMatch | null {
  const hit = tambons.find((f) => booleanPointInPolygon([lng, lat], f));
  if (hit) return { name: hit.properties.name, method: 'exact' };
  if (!isInDistrict(lat, lng) || !tambonCentroids.length) return null;
  let best = tambonCentroids[0];
  let bestD = Infinity;
  for (const t of tambonCentroids) {
    const d = (t.c[0] - lng) ** 2 + (t.c[1] - lat) ** 2;
    if (d < bestD) {
      bestD = d;
      best = t;
    }
  }
  return { name: best.name, method: 'nearest' };
}

export interface RoadDistance {
  km: number;
  roadLabel: string;
  /** Closest point on that main road, where a road route to the pin starts. */
  point: { lat: number; lng: number };
}

/** Straight-line distance from a pin to the nearest main road in the district. */
export function distanceToMainRoad(lat: number, lng: number): RoadDistance | null {
  let best: { km: number; road: RoadFeature } | null = null;
  for (const road of roads) {
    const km = pointToLineDistance([lng, lat], road, { units: 'kilometers', method: 'planar' });
    if (!best || km < best.km) best = { km, road };
  }
  if (!best) return null;
  const p = best.road.properties;
  const [pLng, pLat] = nearestPointOnLine(best.road, [lng, lat]).geometry.coordinates;
  return {
    km: Math.round(best.km * 100) / 100,
    roadLabel: p.ref ? `ถนน ${p.ref}` : p.name || 'ถนนสายหลัก',
    point: { lat: pLat, lng: pLng },
  };
}
