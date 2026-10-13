import { TouchEvent, useEffect, useLayoutEffect, useRef, useState } from 'react';
import { ArrowLeft, ChevronLeft, ChevronRight, Download, Info, Pencil, Trash2 } from 'lucide-react';
import type { MediaItem } from '../../shared/types';
import { formatDateTime } from '../lib/format';
import { clampZoom, NO_ZOOM, pinchZoom, rubberBand, shouldDismiss, swipeDirection, toggleZoomAt, Zoom } from '../lib/gestures';
import { useScrollLock } from '../lib/useScrollLock';
import IconButton from './ui/IconButton';

interface Props {
  media: MediaItem[];
  index: number;
  onIndex: (index: number) => void;
  onClose: () => void;
  onDelete?: (item: MediaItem) => void;
  onEdit?: (item: MediaItem) => void;
  /** A dialog is open on top: leave the keyboard (Esc, arrows) to it. */
  paused?: boolean;
}

type Point = { x: number; y: number };
type Drag = { mode: 'pending' | 'swipe' | 'dismiss' | 'up' | 'pan' | 'idle'; start: Point; t0: number; dx: number; dy: number; zoom: Zoom };
type Gesture = { mode: 'pinch'; dist: number; mid: Point; zoom: Zoom } | Drag;

const GAP = 16;
const SLIDE_MS = 220;
const DOUBLE_TAP_MS = 280;
const EASE = 'cubic-bezier(0.2, 0.8, 0.2, 1)';

const largeFallback = (item: MediaItem) => item.src.thumbFallback.replace(/sz=w\d+/, 'sz=w2048');
const pointOf = (t: { clientX: number; clientY: number }): Point => ({ x: t.clientX, y: t.clientY });

function Viewer({ item, active }: { item: MediaItem; active: boolean }) {
  const [failed, setFailed] = useState(false);
  useEffect(() => setFailed(false), [item.id]);

  if (active && item.kind === 'video' && item.src.preview) {
    return (
      <iframe
        key={item.id}
        src={item.src.preview}
        title={item.name}
        allow="autoplay; fullscreen; picture-in-picture"
        allowFullScreen
        className="aspect-video max-h-full w-full max-w-6xl border-0"
      />
    );
  }
  return (
    <img
      key={item.id}
      src={failed ? largeFallback(item) : item.src.large}
      alt={active ? item.name : ''}
      referrerPolicy="no-referrer"
      onError={() => setFailed(true)}
      draggable={false}
      className="max-h-full max-w-full select-none object-contain"
    />
  );
}

/**
 * Full-screen viewer. Touch: swipe sideways to move, down to close, up for info, tap to hide the bars,
 * pinch or double tap to zoom. Desktop: arrows and keyboard. Videos play in Drive's player.
 */
export default function Lightbox({ media, index, onIndex, onClose, onDelete, onEdit, paused = false }: Props) {
  const item = media[index];
  const [showInfo, setShowInfo] = useState(false);
  const [chrome, setChrome] = useState(true);
  const closeRef = useRef<HTMLButtonElement>(null);
  const stageRef = useRef<HTMLDivElement>(null);
  const trackRef = useRef<HTMLDivElement>(null);
  const zoomRef = useRef<HTMLDivElement>(null);
  const backdropRef = useRef<HTMLDivElement>(null);
  const zoom = useRef<Zoom>(NO_ZOOM);
  const gesture = useRef<Gesture | null>(null);
  const lastTap = useRef<{ t: number; at: Point; timer: number } | null>(null);
  const sliding = useRef<number | null>(null);
  const hasPrev = index > 0;
  const hasNext = index < media.length - 1;
  useScrollLock();

  useEffect(() => {
    closeRef.current?.focus();
    // iOS Safari zooms the whole page on pinch unless its proprietary gesture events are cancelled.
    const stop = (e: Event) => e.preventDefault();
    document.addEventListener('gesturestart', stop);
    return () => {
      document.removeEventListener('gesturestart', stop);
      if (sliding.current) window.clearTimeout(sliding.current);
      if (lastTap.current) window.clearTimeout(lastTap.current.timer);
    };
  }, []);

  useEffect(() => {
    if (paused) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
      else if (e.key === 'ArrowLeft' && hasPrev) onIndex(index - 1);
      else if (e.key === 'ArrowRight' && hasNext) onIndex(index + 1);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [index, hasPrev, hasNext, onClose, onIndex, paused]);

  // Neighbours are already rendered beside the current slide; warm the cache one step further.
  useEffect(() => {
    [media[index - 2], media[index + 2]].forEach((m) => {
      if (m) {
        const img = new Image();
        img.referrerPolicy = 'no-referrer';
        img.src = m.src.large;
      }
    });
  }, [index, media]);

  const size = () => ({ w: stageRef.current?.clientWidth ?? window.innerWidth, h: stageRef.current?.clientHeight ?? window.innerHeight });

  const setTrack = (transform: string, animate: boolean) => {
    const el = trackRef.current;
    if (!el) return;
    el.style.transition = animate ? `transform ${SLIDE_MS}ms ${EASE}` : 'none';
    el.style.transform = transform;
  };
  const setBackdrop = (opacity: number, animate: boolean) => {
    const el = backdropRef.current;
    if (!el) return;
    el.style.transition = animate ? `opacity ${SLIDE_MS}ms ${EASE}` : 'none';
    el.style.opacity = String(opacity);
  };
  const setZoom = (next: Zoom, animate: boolean) => {
    zoom.current = next;
    const el = zoomRef.current;
    if (!el) return;
    el.style.transition = animate ? `transform ${SLIDE_MS}ms ${EASE}` : 'none';
    el.style.transform = next.scale === 1 ? '' : `translate3d(${next.x}px, ${next.y}px, 0) scale(${next.scale})`;
  };

  useLayoutEffect(() => {
    setTrack('', false);
    setZoom(NO_ZOOM, false);
    sliding.current = null;
  }, [index]);

  if (!item) return null;

  const slideTo = (dir: -1 | 1) => {
    setTrack(`translate3d(${-dir * (size().w + GAP)}px, 0, 0)`, true);
    sliding.current = window.setTimeout(() => onIndex(index + dir), SLIDE_MS);
  };

  const fromCentre = (p: Point): Point => {
    const rect = stageRef.current?.getBoundingClientRect();
    if (!rect) return p;
    return { x: p.x - rect.left - rect.width / 2, y: p.y - rect.top - rect.height / 2 };
  };

  const onTap = (at: Point) => {
    const prev = lastTap.current;
    if (prev && performance.now() - prev.t < DOUBLE_TAP_MS && Math.hypot(at.x - prev.at.x, at.y - prev.at.y) < 40) {
      window.clearTimeout(prev.timer);
      lastTap.current = null;
      if (item.kind === 'image') {
        const { w, h } = size();
        setZoom(clampZoom(toggleZoomAt(zoom.current, fromCentre(at)), w, h), true);
      }
      return;
    }
    const timer = window.setTimeout(() => {
      lastTap.current = null;
      if (showInfo) setShowInfo(false);
      else setChrome((v) => !v);
    }, DOUBLE_TAP_MS);
    lastTap.current = { t: performance.now(), at, timer };
  };

  const startSingle = (t: { clientX: number; clientY: number }, timeStamp: number): Drag => ({
    mode: zoom.current.scale > 1 ? 'pan' : 'pending',
    start: pointOf(t),
    t0: timeStamp,
    dx: 0,
    dy: 0,
    zoom: zoom.current,
  });

  const onTouchStart = (e: TouchEvent) => {
    if (sliding.current) return;
    const touches = e.touches;
    if (touches.length >= 2) {
      const a = pointOf(touches[0]);
      const b = pointOf(touches[1]);
      gesture.current = {
        mode: 'pinch',
        dist: Math.hypot(a.x - b.x, a.y - b.y) || 1,
        mid: fromCentre({ x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 }),
        zoom: zoom.current,
      };
      setTrack('', true);
      setBackdrop(1, true);
      return;
    }
    gesture.current = startSingle(touches[0], e.timeStamp);
  };

  const onTouchMove = (e: TouchEvent) => {
    const g = gesture.current;
    if (!g) return;
    const { w, h } = size();
    if (g.mode === 'pinch') {
      if (e.touches.length < 2 || item.kind !== 'image') return;
      const a = pointOf(e.touches[0]);
      const b = pointOf(e.touches[1]);
      const mid = fromCentre({ x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 });
      setZoom(clampZoom(pinchZoom(g.zoom, g.mid, mid, Math.hypot(a.x - b.x, a.y - b.y) / g.dist), w, h), false);
      return;
    }
    const p = pointOf(e.touches[0]);
    g.dx = p.x - g.start.x;
    g.dy = p.y - g.start.y;
    if (g.mode === 'pending') {
      if (Math.hypot(g.dx, g.dy) < 8) return;
      g.mode = Math.abs(g.dx) > Math.abs(g.dy) ? 'swipe' : g.dy > 0 ? 'dismiss' : 'up';
    }
    if (g.mode === 'swipe') {
      setTrack(`translate3d(${rubberBand(g.dx, g.dx > 0 ? hasPrev : hasNext)}px, 0, 0)`, false);
    } else if (g.mode === 'dismiss') {
      const progress = Math.min(Math.max(g.dy, 0) / h, 1);
      setTrack(`translate3d(${g.dx * 0.5}px, ${Math.max(g.dy, 0)}px, 0) scale(${1 - progress * 0.25})`, false);
      setBackdrop(1 - progress, false);
    } else if (g.mode === 'pan') {
      setZoom(clampZoom({ ...g.zoom, x: g.zoom.x + g.dx, y: g.zoom.y + g.dy }, w, h), false);
    }
  };

  const onTouchEnd = (e: TouchEvent) => {
    const g = gesture.current;
    if (!g) return;
    if (g.mode === 'pinch') {
      if (e.touches.length === 1) {
        gesture.current = { ...startSingle(e.touches[0], e.timeStamp), mode: zoom.current.scale > 1 ? 'pan' : 'idle' };
        return;
      }
      gesture.current = null;
      if (zoom.current.scale < 1.05) setZoom(NO_ZOOM, true);
      return;
    }
    if (e.touches.length > 0) return;
    gesture.current = null;
    const { w, h } = size();
    const elapsed = Math.max(1, e.timeStamp - g.t0);
    const moved = Math.hypot(g.dx, g.dy) >= 8;
    if (!moved && (g.mode === 'pending' || g.mode === 'pan')) {
      onTap(pointOf(e.changedTouches[0]));
    } else if (g.mode === 'swipe') {
      const dir = swipeDirection(g.dx, g.dx / elapsed, w, hasPrev, hasNext);
      if (dir) slideTo(dir);
      else setTrack('', true);
    } else if (g.mode === 'dismiss') {
      if (shouldDismiss(g.dy, g.dy / elapsed, h)) onClose();
      else {
        setTrack('', true);
        setBackdrop(1, true);
      }
    } else if (g.mode === 'up' && g.dy < -60) {
      setShowInfo(true);
    }
  };

  const hidden = chrome ? 'opacity-100' : 'pointer-events-none opacity-0';
  const navButton = [
    'absolute top-1/2 z-10 h-12 w-12 -translate-y-1/2 cursor-pointer items-center justify-center rounded-full bg-black/40 text-white transition hover:bg-black/60',
    item.kind === 'video' ? 'flex' : 'hidden sm:flex',
    hidden,
  ].join(' ');

  return (
    <div className="fade-in fixed inset-0 z-[60] overflow-hidden overscroll-none text-white" role="dialog" aria-modal="true" aria-label={`ดู ${item.name}`}>
      <div ref={backdropRef} className="absolute inset-0 bg-black" aria-hidden />

      <div
        ref={stageRef}
        className="absolute inset-0 touch-none select-none"
        onTouchStart={onTouchStart}
        onTouchMove={onTouchMove}
        onTouchEnd={onTouchEnd}
        onTouchCancel={onTouchEnd}
      >
        <div ref={trackRef} className="absolute inset-0 will-change-transform">
          {[-1, 0, 1].map((offset) => {
            const m = media[index + offset];
            if (!m) return null;
            return (
              <div
                key={m.id}
                className="absolute inset-0 flex items-center justify-center pb-[env(safe-area-inset-bottom)] pt-[env(safe-area-inset-top)]"
                style={{ transform: `translateX(calc(${offset * 100}% + ${offset * GAP}px))` }}
                aria-hidden={offset !== 0}
              >
                <div ref={offset === 0 ? zoomRef : undefined} className="flex h-full w-full items-center justify-center">
                  <Viewer item={m} active={offset === 0} />
                </div>
              </div>
            );
          })}
        </div>
      </div>

      <div
        className={`absolute inset-x-0 top-0 z-10 flex items-center gap-1 bg-gradient-to-b from-black/70 to-transparent px-2 pb-6 pt-[max(0.5rem,env(safe-area-inset-top))] transition-opacity duration-200 ${hidden}`}
      >
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
        {onEdit ? (
          <IconButton label="แก้ไข" tone="onDark" onClick={() => onEdit(item)}>
            <Pencil size={20} aria-hidden />
          </IconButton>
        ) : null}
        {onDelete ? (
          <IconButton label="ลบ" tone="onDark" onClick={() => onDelete(item)}>
            <Trash2 size={22} aria-hidden />
          </IconButton>
        ) : null}
      </div>

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

      {showInfo ? (
        <div className="sheet-up absolute inset-x-0 bottom-0 z-20 rounded-t-2xl bg-[#1E1F20] px-5 pb-[max(1.25rem,env(safe-area-inset-bottom))] pt-4 text-sm sm:inset-x-auto sm:bottom-4 sm:right-4 sm:w-80 sm:rounded-2xl">
          <div className="flex items-start gap-2">
            <p className="min-w-0 flex-1 break-all pt-2.5 font-medium">{item.name}</p>
            {onEdit ? (
              <IconButton label="แก้ไขชื่อ ผู้ส่ง และวันที่ถ่าย" tone="onDark" onClick={() => onEdit(item)} className="-mr-2 shrink-0">
                <Pencil size={18} aria-hidden />
              </IconButton>
            ) : null}
          </div>
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
