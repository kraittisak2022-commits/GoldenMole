import { useEffect, useMemo } from 'react';
import { APIProvider, Map, Marker, useMap } from '@vis.gl/react-google-maps';
import { DISTRICT_CENTER, districtOutline, mainRoads } from '../../lib/geo';
import type { DeliveryMapProps, LatLng } from './DeliveryMap';
import { markGoogleMapsFailed } from './googleMapsStatus';
import { PIN_SVG } from './pin';

function Overlays() {
  const map = useMap();
  useEffect(() => {
    if (!map) return;
    const district = new google.maps.Data({
      map,
      style: { strokeColor: '#1e3a5f', strokeWeight: 2, fillColor: '#1e3a5f', fillOpacity: 0.04, clickable: false },
    });
    if (districtOutline) district.addGeoJson(districtOutline);
    const roads = new google.maps.Data({
      map,
      style: { strokeColor: '#d97706', strokeWeight: 3, strokeOpacity: 0.8, clickable: false },
    });
    roads.addGeoJson({ type: 'FeatureCollection', features: mainRoads });
    return () => {
      district.setMap(null);
      roads.setMap(null);
    };
  }, [map]);
  return null;
}

function FlyTo({ target }: { target: LatLng | null }) {
  const map = useMap();
  useEffect(() => {
    if (!map || !target) return;
    map.panTo(target);
    map.setZoom(Math.max(map.getZoom() ?? 0, 14));
  }, [map, target?.lat, target?.lng]);
  return null;
}

function Pin({ value, onChange, readOnly }: Pick<DeliveryMapProps, 'onChange' | 'readOnly'> & { value: LatLng }) {
  const icon = useMemo<google.maps.Icon>(
    () => ({
      url: `data:image/svg+xml;charset=UTF-8,${encodeURIComponent(PIN_SVG)}`,
      scaledSize: new google.maps.Size(32, 42),
      anchor: new google.maps.Point(16, 40),
    }),
    [],
  );
  return (
    <Marker
      position={value}
      icon={icon}
      draggable={!readOnly}
      onDragEnd={(e) => {
        if (e.latLng) onChange?.({ lat: e.latLng.lat(), lng: e.latLng.lng() });
      }}
    />
  );
}

export default function GoogleDeliveryMap({ apiKey, value, onChange, flyTarget = null, readOnly }: DeliveryMapProps & { apiKey: string }) {
  const center = value ?? DISTRICT_CENTER;
  const canPick = !readOnly && !!onChange;

  return (
    <APIProvider apiKey={apiKey} language="th" region="TH" authReferrerPolicy="origin" onError={markGoogleMapsFailed}>
      <Map
        style={{ height: '100%', width: '100%' }}
        defaultCenter={center}
        defaultZoom={value ? 14 : 11}
        mapTypeControl
        mapTypeControlOptions={{ mapTypeIds: ['roadmap', 'hybrid'] }}
        streetViewControl={false}
        fullscreenControl={false}
        clickableIcons={false}
        gestureHandling={readOnly ? 'cooperative' : 'greedy'}
        onClick={
          canPick
            ? (e) => {
                if (e.detail.latLng) onChange(e.detail.latLng);
              }
            : undefined
        }
      >
        <Overlays />
        {value ? <Pin value={value} onChange={onChange} readOnly={readOnly} /> : null}
        <FlyTo target={flyTarget} />
      </Map>
    </APIProvider>
  );
}
