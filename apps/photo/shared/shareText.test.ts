import { describe, expect, it } from 'vitest';
import { sortMedia } from './mediaOrder';
import { buildShareText, shareUrl } from './shareText';

describe('share text', () => {
  it('is the report title on one line and the link on the next', () => {
    const url = shareUrl('https://photo.goldenmole.pro', 'abc123');
    expect(url).toBe('https://photo.goldenmole.pro/a/abc123');
    expect(buildShareText('  เทปูนชั้น 2  ', url)).toBe('เทปูนชั้น 2\nhttps://photo.goldenmole.pro/a/abc123');
  });
});

describe('sortMedia', () => {
  it('orders by capture time, falling back to upload time', () => {
    const media = [
      { id: 'c', takenAt: '2026-10-12T05:00:00Z', createdAt: '2026-10-12T09:00:00Z' },
      { id: 'b', takenAt: null, createdAt: '2026-10-12T04:00:00Z' },
      { id: 'a', takenAt: '2026-10-12T01:00:00Z', createdAt: '2026-10-12T09:01:00Z' },
    ];
    expect(sortMedia(media).map((m) => m.id)).toEqual(['a', 'b', 'c']);
  });

  it('accepts database rows too', () => {
    const rows = [
      { id: 2, taken_at: null, created_at: '2026-10-12T03:00:00Z' },
      { id: 1, taken_at: '2026-10-11T03:00:00Z', created_at: '2026-10-12T04:00:00Z' },
    ];
    expect(sortMedia(rows).map((m) => m.id)).toEqual([1, 2]);
  });
});
