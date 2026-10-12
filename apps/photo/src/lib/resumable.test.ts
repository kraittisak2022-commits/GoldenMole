import { describe, expect, it } from 'vitest';
import { CHUNK_SIZE, nextOffsetFromRange, retryDelayMs } from './resumable';

describe('resumable upload helpers', () => {
  it('chunks are a multiple of 256 KiB, as Drive requires', () => {
    expect(CHUNK_SIZE % (256 * 1024)).toBe(0);
  });

  it('continues after the last byte Drive confirmed', () => {
    expect(nextOffsetFromRange('bytes=0-8388607')).toBe(8_388_608);
    expect(nextOffsetFromRange(null)).toBe(0);
    expect(nextOffsetFromRange('nonsense')).toBe(0);
  });

  it('backs off exponentially up to 30 seconds', () => {
    expect([0, 1, 2, 3].map(retryDelayMs)).toEqual([1000, 2000, 4000, 8000]);
    expect(retryDelayMs(10)).toBe(30_000);
  });
});
