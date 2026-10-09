import { useEffect, useMemo } from 'react';
import { APIProvider, Map, Marker, useMap } from '@vis.gl/react-google-maps';
import { DISTRICT_CENTER, districtOutline, mainRoads } from '../../lib/geo';
import { pathMidpoint } from '../../lib/roadRoute';
import type { DeliveryMapProps, LatLng, MapRoute } from './DeliveryMap';
import { markGoogleMapsFailed } from './googleMapsStatus';
import { distanceLabelSvg, PIN_SVG, ROAD_START_COLOR, ROUTE_COLOR } from './pin';

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

function RouteLayer({ route }: { route: MapRoute }) {
  const map = useMap();
  useEffect(() => {
    if (!map || route.path.length < 2) return;
    const line = new google.maps.Polyline({
      map,
      path: route.path,
      clickable: false,
      strokeColor: ROUTE_COLOR,
      strokeWeight: 5,
      strokeOpacity: route.byRoad ? 0.85 : 0,
      icons: route.byRoad
        ? undefined
        : [{ icon: { path: 'M 0,-1 0,1', strokeColor: ROUTE_COLOR, strokeOpacity: 1, strokeWeight: 4, scale: 3 }, offset: '0', repeat: '14px' }],
    });
    const start = new google.maps.Marker({
      map,
      position: route.path[0],
      clickable: false,
      icon: { path: google.maps.SymbolPath.CIRCLE, scale: 6, fillColor: ROAD_START_COLOR, fillOpacity: 1, strokeColor: '#fff', strokeWeight: 2 },
    });
    const mid = pathMidpoint(route.path);
    const { svg, width, height } = distanceLabelSvg(route.label);
    const label = mid
      ? new google.maps.Marker({
          map,
          position: mid,
          clickable: false,
          zIndex: 1000,
          icon: {
            url: `data:image/svg+xml;charset=UTF-8,${encodeURIComponent(svg)}`,
            scaledSize: new google.maps.Size(width, height),
            anchor: new google.maps.Point(width / 2, height / 2),
          },
        })
      : null;

    const bounds = new google.maps.LatLngBounds();
    route.path.forEach((p) => bounds.extend(p));
    const view = map.getBounds();
    if (!view || !view.contains(bounds.getNorthEast()) || !view.contains(bounds.getSouthWest())) {
      map.fitBounds(bounds, 48);
      google.maps.event.addListenerOnce(map, 'idle', () => {
        if ((map.getZoom() ?? 0) > 16) map.setZoom(16);
      });
    }

    return () => {
      line.setMap(null);
      start.setMap(null);
      label?.setMap(null);
    };
  }, [map, route]);
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

export default function GoogleDeliveryMap({ apiKey, value, onChange, flyTarget = null, readOnly, route }: DeliveryMapProps & { apiKey: string }) {
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
        {route ? <RouteLayer route={route} /> : null}
        {value ? <Pin value={value} onChange={onChange} readOnly={readOnly} /> : null}
        <FlyTo target={flyTarget} />
      </Map>
    </APIProvider>
  );
}
