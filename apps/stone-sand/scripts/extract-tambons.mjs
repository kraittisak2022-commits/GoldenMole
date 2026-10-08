// Tambon polygons for อ.วังเหนือ from chingchai/OpenGISData-Thailand (OSM has no tambon boundaries here).
// Usage: node scripts/extract-tambons.mjs [path-to-subdistricts.geojson]
// Without a path the file is downloaded (~11 MB).
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const SOURCE_URL = 'https://raw.githubusercontent.com/chingchai/OpenGISData-Thailand/master/subdistricts.geojson';
const OUT = join(dirname(fileURLToPath(import.meta.url)), '..', 'src', 'data', 'geo', 'tambons.json');

const r5 = (n) => Math.round(n * 1e5) / 1e5;
const roundCoords = (c) => (typeof c[0] === 'number' ? [r5(c[0]), r5(c[1])] : c.map(roundCoords));

const raw = process.argv[2]
  ? readFileSync(process.argv[2], 'utf8')
  : await (await fetch(SOURCE_URL)).text();
const fc = JSON.parse(raw);

const features = fc.features
  .filter((f) => f.properties.amp_th?.includes('วังเหนือ') && f.properties.pro_th?.includes('ลำปาง'))
  .map((f) => ({
    type: 'Feature',
    properties: { name: f.properties.tam_th.replace(/^ตำบล/, '').trim(), code: f.properties.tam_code },
    geometry: { type: f.geometry.type, coordinates: roundCoords(f.geometry.coordinates) },
  }));

writeFileSync(OUT, JSON.stringify({ type: 'FeatureCollection', features }));
console.log('saved', features.length, 'tambons:', features.map((f) => f.properties.name).join(', '));
const sample = features[0]?.geometry.coordinates.flat(3).slice(0, 2);
console.log('sample coord (lng, lat):', sample);
