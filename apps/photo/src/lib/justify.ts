export interface JustifiedRow {
  height: number;
  items: { index: number; width: number }[];
}

/** Very wide or tall shots would otherwise make a whole row tiny or a single tile huge. */
const clampAspect = (aspect: number) => (Number.isFinite(aspect) && aspect > 0 ? Math.min(Math.max(aspect, 0.4), 3) : 1);

/**
 * Google Photos-style rows: fill each row until it reaches the container width at `targetHeight`,
 * then scale the row to fit exactly. The last row keeps `targetHeight` instead of stretching.
 */
export function justifiedRows(aspects: number[], containerWidth: number, targetHeight: number, gap: number): JustifiedRow[] {
  if (containerWidth <= 0) return [];
  const rows: JustifiedRow[] = [];
  let current: number[] = [];
  let aspectSum = 0;

  const push = (height: number) => {
    rows.push({ height, items: current.map((index) => ({ index, width: clampAspect(aspects[index]) * height })) });
    current = [];
    aspectSum = 0;
  };

  aspects.forEach((aspect, index) => {
    current.push(index);
    aspectSum += clampAspect(aspect);
    const gaps = gap * (current.length - 1);
    if (aspectSum * targetHeight + gaps >= containerWidth) {
      push((containerWidth - gaps) / aspectSum);
    }
  });
  if (current.length) push(targetHeight);
  return rows;
}

export function targetRowHeight(containerWidth: number): number {
  if (containerWidth < 640) return 120;
  if (containerWidth < 1024) return 180;
  return 220;
}
