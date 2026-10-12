import { memo } from 'react';
import { Check, Play } from 'lucide-react';
import type { MediaItem } from '../../shared/types';
import Thumb from './Thumb';

interface Props {
  item: MediaItem;
  width: number;
  height: number;
  selectable: boolean;
  selectionMode: boolean;
  selected: boolean;
  onOpen: () => void;
  onToggle: () => void;
}

function MediaTile({ item, width, height, selectable, selectionMode, selected, onOpen, onToggle }: Props) {
  const label = `${item.kind === 'video' ? 'วิดีโอ' : 'รูป'} ${item.name}`;
  return (
    <div className="group relative shrink-0 overflow-hidden bg-container" style={{ width, height }}>
      <button
        type="button"
        onClick={selectionMode ? onToggle : onOpen}
        aria-label={selectionMode ? `${selected ? 'ยกเลิกเลือก' : 'เลือก'} ${label}` : `เปิด ${label}`}
        aria-pressed={selectionMode ? selected : undefined}
        className="block h-full w-full cursor-pointer"
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
            onClick={onToggle}
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
