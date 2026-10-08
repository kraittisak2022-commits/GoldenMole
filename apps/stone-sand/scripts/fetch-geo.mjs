// Fetch the อ.วังเหนือ district outline + main roads from OpenStreetMap (Overpass) into static GeoJSON.
// OSM has no tambon boundaries here — tambons come from scripts/extract-tambons.mjs.
// Usage: node scripts/fetch-geo.mjs   (writes src/data/geo/district.json, main-roads.json)
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { booleanPointInPolygon } from '@turf/boolean-point-in-polygon';

const OUT_DIR = join(dirname(fileURLToPath(import.meta.url)), '..', 'src', 'data', 'geo');
const ENDPOINTS = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
  'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
];
const ROAD_CLASSES = process.env.ROAD_CLASSES || 'trunk|primary|secondary';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function overpass(query) {
  let lastErr;
  for (let attempt = 0; attempt < 3; attempt++) {
    for (const url of ENDPOINTS) {
      try {
        const res = await fetch(url, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            Accept: 'application/json',
            'User-Agent': 'pirasit-stone-sand/0.1 (geo seed script)',
          },
          body: 'data=' + encodeURIComponent(query),
        });
        if (!res.ok) throw new Error(`${url} → HTTP ${res.status}`);
        return await res.json();
      } catch (err) {
        lastErr = err;
        console.warn(String(err));
      }
    }
    await sleep(15000);
  }
  throw lastErr;
}

const r5 = (n) => Math.round(n * 1e5) / 1e5;
const pt = (g) => [r5(g.lon), r5(g.lat)];
const same = (a, b) => a[0] === b[0] && a[1] === b[1];

/** Join way segments into closed rings by matching endpoints. */
function assembleRings(segments) {
  const pool = segments.map((s) => s.slice());
  const rings = [];
  while (pool.length) {
    let ring = pool.shift();
    let extended = true;
    while (!same(ring[0], ring[ring.length - 1]) && extended) {
      extended = false;
      for (let i = 0; i < pool.length; i++) {
        const seg = pool[i];
        const end = ring[ring.length - 1];
        if (same(seg[0], end)) ring = ring.concat(seg.slice(1));
        else if (same(seg[seg.length - 1], end)) ring = ring.concat(seg.slice().reverse().slice(1));
        else if (same(seg[seg.length - 1], ring[0])) ring = seg.concat(ring.slice(1));
        else if (same(seg[0], ring[0])) ring = seg.slice().reverse().concat(ring.slice(1));
        else continue;
        pool.splice(i, 1);
        extended = true;
        break;
      }
    }
    if (ring.length >= 4 && same(ring[0], ring[ring.length - 1])) rings.push(ring);
  }
  return rings;
}

const cleanName = (tags) => (tags['name:th'] || tags.name || '').replace(/^ตำบล/, '').trim();

function relationToFeature(rel) {
  const outer = rel.members
    .filter((m) => m.type === 'way' && m.role !== 'inner' && m.geometry)
    .map((m) => m.geometry.map(pt));
  const rings = assembleRings(outer);
  if (!rings.length) return null;
  return {
    type: 'Feature',
    properties: { name: cleanName(rel.tags), osmId: rel.id },
    geometry:
      rings.length === 1
        ? { type: 'Polygon', coordinates: [rings[0]] }
        : { type: 'MultiPolygon', coordinates: rings.map((r) => [r]) },
  };
}

function bboxOf(fc) {
  let [w, s, e, n] = [180, 90, -180, -90];
  const visit = (c) => {
    if (typeof c[0] === 'number') {
      w = Math.min(w, c[0]); e = Math.max(e, c[0]); s = Math.min(s, c[1]); n = Math.max(n, c[1]);
    } else c.forEach(visit);
  };
  fc.features.forEach((f) => visit(f.geometry.coordinates));
  const pad = 0.02;
  return [s - pad, w - pad, n + pad, e + pad].map((v) => v.toFixed(5)).join(',');
}

mkdirSync(OUT_DIR, { recursive: true });
const districtPath = join(OUT_DIR, 'district.json');

if (!existsSync(districtPath)) {
  const district = await overpass(
    `[out:json][timeout:120];relation["boundary"="administrative"]["admin_level"="6"]["name"="อำเภอวังเหนือ"];out geom;`,
  );
  const features = district.elements.filter((e) => e.type === 'relation').map(relationToFeature).filter(Boolean);
  writeFileSync(districtPath, JSON.stringify({ type: 'FeatureCollection', features }));
  console.log('district features:', features.length);
  await sleep(5000);
}

const districtFc = JSON.parse(readFileSync(districtPath, 'utf8'));
const bbox = bboxOf(districtFc);
console.log('bbox:', bbox);

const districtShape = districtFc.features[0];
const touchesDistrict = (coords) => coords.some((c) => booleanPointInPolygon(c, districtShape));

const roads = await overpass(`[out:json][timeout:180];way["highway"~"^(${ROAD_CLASSES})$"](${bbox});out geom;`);
const roadFeatures = roads.elements
  .filter((e) => e.type === 'way' && e.geometry?.length > 1 && touchesDistrict(e.geometry.map(pt)))
  .map((w) => ({
    type: 'Feature',
    properties: { ref: w.tags.ref || '', name: w.tags.name || '', highway: w.tags.highway },
    geometry: { type: 'LineString', coordinates: w.geometry.map(pt) },
  }));
writeFileSync(join(OUT_DIR, 'main-roads.json'), JSON.stringify({ type: 'FeatureCollection', features: roadFeatures }));
const refs = [...new Set(roadFeatures.map((f) => `${f.properties.highway}:${f.properties.ref || f.properties.name}`))];
console.log('road ways:', roadFeatures.length, refs.join(', '));
