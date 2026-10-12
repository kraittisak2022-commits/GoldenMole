import { TouchEvent, useEffect, useRef, useState } from 'react';
import { ArrowLeft, ChevronLeft, ChevronRight, Download, Info, Trash2 } from 'lucide-react';
import type { MediaItem } from '../../shared/types';
import { formatDateTime } from '../lib/format';
import IconButton from './ui/IconButton';

interface Props {
  media: MediaItem[];
  index: number;
  onIndex: (index: number) => void;
  onClose: () => void;
  onDelete?: (item: MediaItem) => void;
}

const largeFallback = (item: MediaItem) => item.src.thumbFallback.replace(/sz=w\d+/, 'sz=w2048');

function Viewer({ item }: { item: MediaItem }) {
  const [failed, setFailed] = useState(false);
  useEffect(() => setFailed(false), [item.id]);

  if (item.kind === 'video' && item.src.preview) {
    return (
      <iframe
        key={item.id}
        src={item.src.preview}
        title={item.name}
        allow="autoplay; fullscreen; picture-in-picture"
        allowFullScreen
        className="h-full max-h-full w-full max-w-6xl border-0"
      />
    );
  }
  return (
    <img
      key={item.id}
      src={failed ? largeFallback(item) : item.src.large}
      alt={item.name}
      referrerPolicy="no-referrer"
      onError={() => setFailed(true)}
      draggable={false}
      className="max-h-full max-w-full select-none object-contain"
    />
  );
}

/** Full-screen viewer: arrows / swipe / keyboard to move, Esc to close. Videos play in Drive's player. */
export default function Lightbox({ media, index, onIndex, onClose, onDelete }: Props) {
  const item = media[index];
  const [showInfo, setShowInfo] = useState(false);
  const touchX = useRef<number | null>(null);
  const closeRef = useRef<HTMLButtonElement>(null);
  const hasPrev = index > 0;
  const hasNext = index < media.length - 1;

  useEffect(() => {
    closeRef.current?.focus();
    const { overflow } = document.body.style;
    document.body.style.overflow = 'hidden';
    return () => {
      document.body.style.overflow = overflow;
    };
  }, []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
      else if (e.key === 'ArrowLeft' && hasPrev) onIndex(index - 1);
      else if (e.key === 'ArrowRight' && hasNext) onIndex(index + 1);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [index, hasPrev, hasNext, onClose, onIndex]);

  useEffect(() => {
    [media[index - 1], media[index + 1]].forEach((m) => {
      if (m?.kind === 'image') {
        const img = new Image();
        img.referrerPolicy = 'no-referrer';
        img.src = m.src.large;
      }
    });
  }, [index, media]);

  if (!item) return null;

  const onTouchStart = (e: TouchEvent) => {
    touchX.current = e.touches[0].clientX;
  };
  const onTouchEnd = (e: TouchEvent) => {
    if (touchX.current === null) return;
    const dx = e.changedTouches[0].clientX - touchX.current;
    touchX.current = null;
    if (dx > 60 && hasPrev) onIndex(index - 1);
    else if (dx < -60 && hasNext) onIndex(index + 1);
  };

  const navButton = 'absolute top-1/2 z-10 hidden h-12 w-12 -translate-y-1/2 cursor-pointer items-center justify-center rounded-full bg-black/40 text-white transition hover:bg-black/60 sm:flex';

  return (
    <div className="fade-in fixed inset-0 z-[60] flex flex-col bg-black text-white" role="dialog" aria-modal="true" aria-label={`ดู ${item.name}`}>
      <div className="flex items-center gap-1 bg-gradient-to-b from-black/70 to-transparent px-2 pb-2 pt-[max(0.5rem,env(safe-area-inset-top))]">
        <IconButton ref={closeRef} label="ปิด" tone="onDark" onClick={onClose}>
          <ArrowLeft size={22} aria-hidden />
        </IconButton>
        <p className="min-w-0 flex-1 truncate text-sm text-white/80" aria-live="polite">
          {index + 1} / {media.length}
        </p>
        <IconButton label="ข้อมูล" tone="onDark" aria-pressed={showInfo} onClick={() => setShowInfo((v) => !v)}>
          <Info size={22} aria-hidden />
        </IconButton>
        <a
          href={item.src.download}
          target="_blank"
          rel="noreferrer"
          aria-label="ดาวน์โหลด"
          title="ดาวน์โหลด"
          className="inline-flex h-11 w-11 items-center justify-center rounded-full text-white hover:bg-white/15"
        >
          <Download size={22} aria-hidden />
        </a>
        {onDelete ? (
          <IconButton label="ลบ" tone="onDark" onClick={() => onDelete(item)}>
            <Trash2 size={22} aria-hidden />
          </IconButton>
        ) : null}
      </div>

      <div className="relative flex min-h-0 flex-1 items-center justify-center px-2 pb-4" onTouchStart={onTouchStart} onTouchEnd={onTouchEnd}>
        <Viewer item={item} />
        {hasPrev ? (
          <button type="button" aria-label="ก่อนหน้า" onClick={() => onIndex(index - 1)} className={`${navButton} left-4`}>
            <ChevronLeft size={28} aria-hidden />
          </button>
        ) : null}
        {hasNext ? (
          <button type="button" aria-label="ถัดไป" onClick={() => onIndex(index + 1)} className={`${navButton} right-4`}>
            <ChevronRight size={28} aria-hidden />
          </button>
        ) : null}
      </div>

      {showInfo ? (
        <div className="absolute inset-x-0 bottom-0 z-20 rounded-t-2xl bg-[#1E1F20] px-5 pb-[max(1.25rem,env(safe-area-inset-bottom))] pt-4 text-sm sm:inset-x-auto sm:bottom-4 sm:right-4 sm:w-80 sm:rounded-2xl">
          <p className="break-all font-medium">{item.name}</p>
          <dl className="mt-3 space-y-1.5 text-white/75">
            {item.takenAt ? (
              <div className="flex gap-2">
                <dt className="shrink-0">ถ่ายเมื่อ</dt>
                <dd>{formatDateTime(item.takenAt)}</dd>
              </div>
            ) : null}
            <div className="flex gap-2">
              <dt className="shrink-0">อัปโหลด</dt>
              <dd>
                {formatDateTime(item.createdAt)}
                {item.uploadedByName ? ` โดย ${item.uploadedByName}` : ''}
              </dd>
            </div>
            {item.width && item.height ? (
              <div className="flex gap-2">
                <dt className="shrink-0">ขนาด</dt>
                <dd>
                  {item.width} × {item.height}
                </dd>
              </div>
            ) : null}
          </dl>
        </div>
      ) : null}
    </div>
  );
}
