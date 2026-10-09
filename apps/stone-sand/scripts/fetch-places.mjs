// Fetch village names and named roads/soi in อ.วังเหนือ from OpenStreetMap (Overpass) into static JSON,
// so a dropped pin can be described as "บ้าน… · ซอย…" without any API call.
// Usage: node scripts/fetch-places.mjs   (needs src/data/geo/district.json from fetch-geo.mjs; writes places.json)
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { booleanPointInPolygon } from '@turf/boolean-point-in-polygon';

const OUT_DIR = join(dirname(fileURLToPath(import.meta.url)), '..', 'src', 'data', 'geo');
const ENDPOINTS = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
  'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
];
const PLACE_KINDS = 'village|hamlet|isolated_dwelling|neighbourhood|quarter|suburb|town';

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
const nameOf = (tags) => (tags['name:th'] || tags.name || '').trim();

const district = JSON.parse(readFileSync(join(OUT_DIR, 'district.json'), 'utf8')).features[0];
let [w, s, e, n] = [180, 90, -180, -90];
const visit = (c) => {
  if (typeof c[0] === 'number') {
    w = Math.min(w, c[0]); e = Math.max(e, c[0]); s = Math.min(s, c[1]); n = Math.max(n, c[1]);
  } else c.forEach(visit);
};
visit(district.geometry.coordinates);
const pad = 0.03;
const bbox = [s - pad, w - pad, n + pad, e + pad].map((v) => v.toFixed(5)).join(',');
/** Keep places just outside the border too: a pin near the edge should still find its nearest village. */
const near = ([lng, lat]) => lat >= s - pad && lat <= n + pad && lng >= w - pad && lng <= e + pad;

const placeData = await overpass(`[out:json][timeout:120];node["place"~"^(${PLACE_KINDS})$"](${bbox});out;`);
await sleep(5000);
const roadData = await overpass(`[out:json][timeout:180];way["highway"]["name"](${bbox});out tags geom;`);

const villages = [];
const roads = [];
for (const el of [...placeData.elements, ...roadData.elements]) {
  const name = nameOf(el.tags || {});
  if (!name) continue;
  if (el.type === 'node') {
    villages.push({ name, kind: el.tags.place, lat: r5(el.lat), lng: r5(el.lon) });
  } else if (el.type === 'way' && el.geometry?.length > 1) {
    const coords = el.geometry.map((g) => [r5(g.lon), r5(g.lat)]);
    if (!coords.some(near) || /^(ถนน|ซอย|road)$/i.test(name)) continue;
    roads.push({ name, highway: el.tags.highway, ref: el.tags.ref || '', coords });
  }
}

writeFileSync(join(OUT_DIR, 'places.json'), JSON.stringify({ villages, roads }));
const inside = villages.filter((v) => booleanPointInPolygon([v.lng, v.lat], district)).length;
console.log(`villages: ${villages.length} (${inside} inside the district) · named roads: ${roads.length}`);
console.log('road kinds:', [...new Set(roads.map((r) => r.highway))].join(', '));
