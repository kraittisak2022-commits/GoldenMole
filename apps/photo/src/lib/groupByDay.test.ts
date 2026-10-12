import { describe, expect, it } from 'vitest';
import type { MediaItem } from '../../shared/types';
import { groupByDay } from './groupByDay';

const item = (id: string, takenAt: string | null, createdAt = '2026-10-12T10:00:00Z') => ({ id, takenAt, createdAt }) as MediaItem;

describe('groupByDay', () => {
  it('splits on the Thai calendar day and keeps original indexes', () => {
    const sections = groupByDay([
      item('a', '2026-10-11T16:30:00Z'),
      item('b', '2026-10-11T17:30:00Z'),
      item('c', null, '2026-10-12T05:00:00Z'),
    ]);
    expect(sections.map((s) => [s.key, s.items.map((i) => `${i.item.id}${i.index}`)])).toEqual([
      ['2026-10-11', ['a0']],
      ['2026-10-12', ['b1', 'c2']],
    ]);
  });
});
