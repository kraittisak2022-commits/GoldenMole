import { useEffect, useMemo } from 'react';
import L from 'leaflet';
import { GeoJSON, MapContainer, Marker, TileLayer, useMap, useMapEvents } from 'react-leaflet';
import { DISTRICT_CENTER, districtOutline, mainRoads } from '../../lib/geo';

export interface LatLng {
  lat: number;
  lng: number;
}

const pinIcon = L.divIcon({
  className: '',
  iconSize: [32, 42],
  iconAnchor: [16, 40],
  html: `<svg width="32" height="42" viewBox="0 0 32 42" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
    <path d="M16 1C8 1 2 7 2 15c0 10.5 14 26 14 26s14-15.5 14-26C30 7 24 1 16 1z" fill="#1e3a5f" stroke="#fff" stroke-width="2"/>
    <circle cx="16" cy="15" r="5.5" fill="#fff"/></svg>`,
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

interface DeliveryMapProps {
  value: LatLng | null;
  onChange?: (p: LatLng) => void;
  flyTarget?: LatLng | null;
  height?: number;
  readOnly?: boolean;
}

export default function DeliveryMap({ value, onChange, flyTarget = null, height = 320, readOnly }: DeliveryMapProps) {
  const roadsFc = useMemo(() => ({ type: 'FeatureCollection' as const, features: mainRoads }), []);
  const center = value ?? DISTRICT_CENTER;

  return (
    <div className="overflow-hidden rounded border border-border" style={{ height }}>
      <MapContainer
        center={[center.lat, center.lng]}
        zoom={value ? 14 : 11}
        scrollWheelZoom={!readOnly}
        style={{ height: '100%', width: '100%' }}
        attributionControl
      >
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
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
    </div>
  );
}
