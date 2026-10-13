import { memo, PointerEvent, useRef } from 'react';
import { Check, Play } from 'lucide-react';
import type { MediaItem } from '../../shared/types';
import Thumb from './Thumb';

const LONG_PRESS_MS = 450;
const MOVE_TOLERANCE = 10;

interface Props {
  item: MediaItem;
  index: number;
  width: number;
  height: number;
  selectable: boolean;
  selectionMode: boolean;
  selected: boolean;
  onOpen: (index: number) => void;
  onToggle: (id: string) => void;
}

function MediaTile({ item, index, width, height, selectable, selectionMode, selected, onOpen, onToggle }: Props) {
  const label = `${item.kind === 'video' ? 'วิดีโอ' : 'รูป'} ${item.name}`;
  const press = useRef<{ timer: number; x: number; y: number } | null>(null);
  const longPressed = useRef(false);

  const cancelPress = () => {
    if (press.current) window.clearTimeout(press.current.timer);
    press.current = null;
  };

  // Touch screens have no hover checkbox, so holding a photo starts selection (as in Google Photos).
  const onPointerDown = (e: PointerEvent) => {
    longPressed.current = false;
    if (!selectable || selectionMode || e.pointerType === 'mouse') return;
    const { clientX: x, clientY: y } = e;
    press.current = {
      x,
      y,
      timer: window.setTimeout(() => {
        press.current = null;
        longPressed.current = true;
        navigator.vibrate?.(10);
        onToggle(item.id);
      }, LONG_PRESS_MS),
    };
  };
  const onPointerMove = (e: PointerEvent) => {
    const p = press.current;
    if (p && Math.hypot(e.clientX - p.x, e.clientY - p.y) > MOVE_TOLERANCE) cancelPress();
  };
  const onClick = () => {
    if (longPressed.current) {
      longPressed.current = false;
      return;
    }
    if (selectionMode) onToggle(item.id);
    else onOpen(index);
  };

  return (
    <div className="group no-callout relative shrink-0 overflow-hidden bg-container" style={{ width, height }}>
      <button
        type="button"
        onClick={onClick}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={cancelPress}
        onPointerCancel={cancelPress}
        onPointerLeave={cancelPress}
        onContextMenu={selectable ? (e) => e.preventDefault() : undefined}
        aria-label={selectionMode ? `${selected ? 'ยกเลิกเลือก' : 'เลือก'} ${label}` : `เปิด ${label}`}
        aria-pressed={selectionMode ? selected : undefined}
        className="block h-full w-full cursor-pointer transition-opacity active:opacity-80"
      >
        <Thumb
          src={item.src}
          alt=""
          className={`h-full w-full object-cover transition-transform duration-200 ${selected ? 'scale-[0.86] rounded-xl' : ''}`}
        />
        {item.kind === 'video' ? (
          <span className="pointer-events-none absolute right-1.5 top-1.5 flex h-6 w-6 items-center justify-center rounded-full bg-black/55 text-white">
            <Play size={12} fill="currentColor" aria-hidden />
          </span>
        ) : null}
      </button>
      {selectable ? (
        <>
          <span
            aria-hidden
            className={`pointer-events-none absolute inset-x-0 top-0 h-14 bg-gradient-to-b from-black/35 to-transparent transition-opacity duration-150 ${selectionMode || selected ? 'opacity-0' : 'opacity-0 group-hover:opacity-100'}`}
          />
          <button
            type="button"
            onClick={() => onToggle(item.id)}
            aria-label={`${selected ? 'ยกเลิกเลือก' : 'เลือก'} ${label}`}
            aria-pressed={selected}
            className={[
              'absolute left-0 top-0 flex h-11 w-11 cursor-pointer items-center justify-center transition-opacity duration-150',
              selected || selectionMode ? 'opacity-100' : 'opacity-0 focus-visible:opacity-100 group-hover:opacity-100 [@media(hover:none)]:hidden',
            ].join(' ')}
          >
            <span
              className={[
                'flex h-6 w-6 items-center justify-center rounded-full border-2',
                selected ? 'border-primary bg-primary text-primary-foreground' : 'border-white/90 bg-black/20 text-transparent',
              ].join(' ')}
            >
              <Check size={14} strokeWidth={3} aria-hidden />
            </span>
          </button>
        </>
      ) : null}
    </div>
  );
}

export default memo(MediaTile);
