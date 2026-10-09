import { useEffect, useMemo } from 'react';
import L from 'leaflet';
import { GeoJSON, MapContainer, Marker, TileLayer, useMap, useMapEvents } from 'react-leaflet';
import { DISTRICT_CENTER, districtOutline, mainRoads } from '../../lib/geo';
import type { DeliveryMapProps, LatLng } from './DeliveryMap';
import { PIN_SVG } from './pin';

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

/** OpenStreetMap fallback, used when no Google Maps browser key is configured or Google rejects it. */
export default function LeafletDeliveryMap({ value, onChange, flyTarget = null, readOnly }: DeliveryMapProps) {
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
