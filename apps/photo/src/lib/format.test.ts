import { describe, expect, it } from 'vitest';
import { fromBangkokInput, toBangkokInput } from './format';

describe('Thai-time datetime inputs', () => {
  it('shows an instant as Thai wall-clock time', () => {
    expect(toBangkokInput('2026-10-12T17:30:00.000Z')).toBe('2026-10-13T00:30');
    expect(toBangkokInput(null)).toBe('');
  });

  it('reads the input back as Thai time', () => {
    expect(fromBangkokInput('2026-10-13T00:30')).toBe('2026-10-12T17:30:00.000Z');
    expect(fromBangkokInput('2026-10-13T00:30:15')).toBe('2026-10-12T17:30:15.000Z');
    expect(fromBangkokInput('')).toBeNull();
    expect(fromBangkokInput('nonsense')).toBeNull();
  });

  it('round-trips to the minute', () => {
    const iso = '2026-01-31T23:59:00.000Z';
    expect(fromBangkokInput(toBangkokInput(iso))).toBe(iso);
  });
});
