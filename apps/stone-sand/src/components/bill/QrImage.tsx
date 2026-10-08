import { useEffect, useState } from 'react';
import QRCode from 'qrcode';

export default function QrImage({ value, size = 96, label }: { value: string; size?: number; label: string }) {
  const [src, setSrc] = useState('');

  useEffect(() => {
    let alive = true;
    QRCode.toDataURL(value, { margin: 0, width: size * 3, errorCorrectionLevel: 'M', color: { dark: '#0f172a', light: '#ffffff' } })
      .then((url) => {
        if (alive) setSrc(url);
      })
      .catch(() => setSrc(''));
    return () => {
      alive = false;
    };
  }, [value, size]);

  return src ? (
    <img src={src} width={size} height={size} alt={label} style={{ imageRendering: 'pixelated' }} />
  ) : (
    <div style={{ width: size, height: size }} className="bg-subtle" aria-label={label} />
  );
}
