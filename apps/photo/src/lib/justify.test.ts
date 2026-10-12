import { describe, expect, it } from 'vitest';
import { justifiedRows, targetRowHeight } from './justify';

const rowWidth = (row: { items: { width: number }[] }, gap: number) =>
  row.items.reduce((sum, i) => sum + i.width, 0) + gap * (row.items.length - 1);

describe('justifiedRows', () => {
  it('fills full rows to the container width and keeps every item once', () => {
    const aspects = [1.5, 0.75, 1, 1.78, 1.33, 0.56, 1.5, 1];
    const rows = justifiedRows(aspects, 800, 200, 4);
    for (const row of rows.slice(0, -1)) expect(rowWidth(row, 4)).toBeCloseTo(800, 6);
    expect(rows.flatMap((r) => r.items.map((i) => i.index))).toEqual(aspects.map((_, i) => i));
  });

  it('leaves the last row at the target height instead of stretching it', () => {
    const rows = justifiedRows([1], 800, 200, 4);
    expect(rows).toEqual([{ height: 200, items: [{ index: 0, width: 200 }] }]);
  });

  it('clamps extreme or missing aspect ratios', () => {
    const [row] = justifiedRows([20, 0.01, NaN], 10_000, 100, 0);
    expect(row.items.map((i) => i.width)).toEqual([300, 40, 100]);
  });

  it('returns nothing before the container has a width', () => {
    expect(justifiedRows([1, 1], 0, 200, 4)).toEqual([]);
  });

  it('uses shorter rows on small screens', () => {
    expect(targetRowHeight(375)).toBe(120);
    expect(targetRowHeight(800)).toBe(180);
    expect(targetRowHeight(1400)).toBe(220);
  });
});
