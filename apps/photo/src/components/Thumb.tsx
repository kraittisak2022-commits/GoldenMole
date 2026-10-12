import { useEffect, useState } from 'react';
import { Film } from 'lucide-react';
import type { MediaSources } from '../../shared/types';

const RETRY_MS = 20_000;
const MAX_RETRIES = 6;

/**
 * Drive thumbnail with a fallback URL. Drive needs a while to make thumbnails for new videos,
 * so when both fail it shows a placeholder and tries again every 20 s.
 */
export default function Thumb({ src, alt, className = '' }: { src: MediaSources; alt: string; className?: string }) {
  const [stage, setStage] = useState(0);
  const [retry, setRetry] = useState(0);

  useEffect(() => {
    setStage(0);
    setRetry(0);
  }, [src.thumb]);

  useEffect(() => {
    if (stage < 2 || retry >= MAX_RETRIES) return;
    const t = setTimeout(() => {
      setRetry((r) => r + 1);
      setStage(1);
    }, RETRY_MS);
    return () => clearTimeout(t);
  }, [stage, retry]);

  if (stage >= 2) {
    return (
      <div className={`flex flex-col items-center justify-center gap-1 bg-container text-muted ${className}`}>
        <Film size={28} strokeWidth={1.5} aria-hidden />
        <span className="px-2 text-center text-[11px]">กำลังเตรียมภาพตัวอย่าง</span>
      </div>
    );
  }

  const url = stage === 0 ? src.thumb : `${src.thumbFallback}${retry ? `&r=${retry}` : ''}`;
  return (
    <img
      src={url}
      alt={alt}
      loading="lazy"
      decoding="async"
      referrerPolicy="no-referrer"
      draggable={false}
      onError={() => setStage((s) => s + 1)}
      className={className}
    />
  );
}
