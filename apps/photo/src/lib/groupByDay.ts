import type { MediaItem } from '../../shared/types';
import { bangkokDayKey } from './format';

export interface DaySection {
  key: string;
  /** ISO time of the first item, for the heading. */
  at: string;
  items: { item: MediaItem; index: number }[];
}

/** Consecutive items on the same Thai calendar day share a section; `index` is the position in `media`. */
export function groupByDay(media: MediaItem[]): DaySection[] {
  const sections: DaySection[] = [];
  media.forEach((item, index) => {
    const at = item.takenAt ?? item.createdAt;
    const key = bangkokDayKey(at);
    const last = sections[sections.length - 1];
    if (last?.key === key) last.items.push({ item, index });
    else sections.push({ key, at, items: [{ item, index }] });
  });
  return sections;
}
