import GoogleDeliveryMap from './GoogleDeliveryMap';
import { useGoogleMapsFailed } from './googleMapsStatus';
import LeafletDeliveryMap from './LeafletDeliveryMap';

export interface LatLng {
  lat: number;
  lng: number;
}

export interface DeliveryMapProps {
  value: LatLng | null;
  onChange?: (p: LatLng) => void;
  flyTarget?: LatLng | null;
  height?: number;
  readOnly?: boolean;
}

const GOOGLE_MAPS_KEY = import.meta.env.VITE_GOOGLE_MAPS_BROWSER_KEY?.trim() ?? '';

export default function DeliveryMap({ height = 320, ...props }: DeliveryMapProps) {
  const googleFailed = useGoogleMapsFailed();

  return (
    <div className="overflow-hidden rounded border border-border" style={{ height: `min(${height}px, 60dvh)` }}>
      {GOOGLE_MAPS_KEY && !googleFailed ? (
        <GoogleDeliveryMap apiKey={GOOGLE_MAPS_KEY} {...props} />
      ) : (
        <LeafletDeliveryMap {...props} />
      )}
    </div>
  );
}
