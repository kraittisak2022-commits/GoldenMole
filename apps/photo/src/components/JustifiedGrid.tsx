import { useLayoutEffect, useMemo, useRef, useState } from 'react';
import type { MediaItem } from '../../shared/types';
import { formatDayHeading } from '../lib/format';
import { groupByDay } from '../lib/groupByDay';
import { justifiedRows, targetRowHeight } from '../lib/justify';
import MediaTile from './MediaTile';

const GAP = 4;
/** Day heading height (py-3 + text-sm line), used to reserve space for off-screen sections. */
const HEADING = 44;

interface Props {
  media: MediaItem[];
  selectable: boolean;
  selected: Set<string>;
  onOpen: (index: number) => void;
  onToggle: (id: string) => void;
}

const aspectOf = (m: MediaItem) => (m.width > 0 && m.height > 0 ? m.width / m.height : m.kind === 'video' ? 16 / 9 : 4 / 3);

/** Photos grouped by day, each day laid out in justified rows that fill the container width. */
export default function JustifiedGrid({ media, selectable, selected, onOpen, onToggle }: Props) {
  const ref = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(0);

  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return;
    setWidth(el.clientWidth);
    const observer = new ResizeObserver(([entry]) => setWidth(Math.floor(entry.contentRect.width)));
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  const sections = useMemo(() => {
    const target = targetRowHeight(width);
    return groupByDay(media).map((section) => {
      const rows = justifiedRows(section.items.map(({ item }) => aspectOf(item)), width, target, GAP);
      const height = HEADING + rows.reduce((sum, row) => sum + Math.floor(row.height) + GAP, 0);
      return { ...section, rows, height };
    });
  }, [media, width]);

  const selectionMode = selected.size > 0;

  return (
    <div ref={ref}>
      {width > 0
        ? sections.map((section) => (
            <section
              key={section.key}
              className="mb-6"
              aria-label={formatDayHeading(section.at)}
              style={{ contentVisibility: 'auto', containIntrinsicSize: `auto ${section.height}px` }}
            >
              <h2 className="py-3 text-sm font-medium text-ink">{formatDayHeading(section.at)}</h2>
              <div className="flex flex-col" style={{ gap: GAP }}>
                {section.rows.map((row, r) => (
                  <div key={r} className="flex" style={{ gap: GAP }}>
                    {row.items.map(({ index, width: w }) => {
                      const { item, index: mediaIndex } = section.items[index];
                      return (
                        <MediaTile
                          key={item.id}
                          item={item}
                          index={mediaIndex}
                          width={Math.floor(w)}
                          height={Math.floor(row.height)}
                          selectable={selectable}
                          selectionMode={selectionMode}
                          selected={selected.has(item.id)}
                          onOpen={onOpen}
                          onToggle={onToggle}
                        />
                      );
                    })}
                  </div>
                ))}
              </div>
            </section>
          ))
        : null}
    </div>
  );
}
