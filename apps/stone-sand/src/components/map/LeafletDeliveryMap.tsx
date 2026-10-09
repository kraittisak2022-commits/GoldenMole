import { useEffect, useMemo } from 'react';
import L from 'leaflet';
import { CircleMarker, GeoJSON, MapContainer, Marker, Polyline, TileLayer, useMap, useMapEvents } from 'react-leaflet';
import { DISTRICT_CENTER, districtOutline, mainRoads } from '../../lib/geo';
import { pathMidpoint } from '../../lib/roadRoute';
import type { DeliveryMapProps, LatLng, MapRoute } from './DeliveryMap';
import { distanceLabelSvg, PIN_SVG, ROAD_START_COLOR, ROUTE_COLOR } from './pin';

const pinIcon = L.divIcon({
  className: '',
  iconSize: [32, 42],
  iconAnchor: [16, 40],
  html: PIN_SVG,
});

function ClickToPin({ onPick }: { onPick: (p: LatLng) => void }) {
  useMapEvents({
    click(e) {
      onPick({ lat: e.latlng.lat, lng: e.latlng.lng });
    },
  });
  return null;
}

function FlyTo({ target }: { target: LatLng | null }) {
  const map = useMap();
  useEffect(() => {
    if (target) map.flyTo([target.lat, target.lng], Math.max(map.getZoom(), 14), { duration: 0.4 });
  }, [target?.lat, target?.lng]);
  return null;
}

function RouteLayer({ route }: { route: MapRoute }) {
  const map = useMap();
  const positions = useMemo(() => route.path.map((p) => [p.lat, p.lng] as [number, number]), [route.path]);
  const mid = useMemo(() => pathMidpoint(route.path), [route.path]);
  const labelIcon = useMemo(() => {
    const { svg, width, height } = distanceLabelSvg(route.label);
    return L.divIcon({ className: '', html: svg, iconSize: [width, height], iconAnchor: [width / 2, height / 2] });
  }, [route.label]);

  useEffect(() => {
    if (positions.length < 2) return;
    const bounds = L.latLngBounds(positions);
    if (!map.getBounds().contains(bounds)) map.fitBounds(bounds.pad(0.2), { maxZoom: 16 });
  }, [map, positions]);

  if (positions.length < 2) return null;
  return (
    <>
      <Polyline
        positions={positions}
        pathOptions={{ color: ROUTE_COLOR, weight: 5, opacity: 0.85, dashArray: route.byRoad ? undefined : '8 8' }}
        interactive={false}
      />
      <CircleMarker
        center={positions[0]}
        radius={6}
        pathOptions={{ color: '#fff', weight: 2, fillColor: ROAD_START_COLOR, fillOpacity: 1 }}
        interactive={false}
      />
      {mid ? <Marker position={[mid.lat, mid.lng]} icon={labelIcon} interactive={false} keyboard={false} zIndexOffset={1000} /> : null}
    </>
  );
}

/** OpenStreetMap fallback, used when no Google Maps browser key is configured or Google rejects it. */
export default function LeafletDeliveryMap({ value, onChange, flyTarget = null, readOnly, route }: DeliveryMapProps) {
  const roadsFc = useMemo(() => ({ type: 'FeatureCollection' as const, features: mainRoads }), []);
  const center = value ?? DISTRICT_CENTER;

  return (
    <MapContainer
      center={[center.lat, center.lng]}
      zoom={value ? 14 : 11}
      scrollWheelZoom={!readOnly}
      style={{ height: '100%', width: '100%' }}
      attributionControl
    >
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
        url="https://tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      {districtOutline ? (
        <GeoJSON
          data={districtOutline}
          style={{ color: '#1e3a5f', weight: 2, fillColor: '#1e3a5f', fillOpacity: 0.04, dashArray: '6 4' }}
          interactive={false}
        />
      ) : null}
      <GeoJSON data={roadsFc} style={{ color: '#d97706', weight: 3, opacity: 0.7 }} interactive={false} />
      {route ? <RouteLayer route={route} /> : null}
      {value ? (
        <Marker
          position={[value.lat, value.lng]}
          icon={pinIcon}
          draggable={!readOnly}
          eventHandlers={{
            dragend(e) {
              const p = (e.target as L.Marker).getLatLng();
              onChange?.({ lat: p.lat, lng: p.lng });
            },
          }}
        />
      ) : null}
      {!readOnly && onChange ? <ClickToPin onPick={onChange} /> : null}
      <FlyTo target={flyTarget} />
    </MapContainer>
  );
}
