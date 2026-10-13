/** Pure math behind the lightbox touch gestures, kept separate so it can be unit tested. */

export interface Zoom {
  scale: number;
  x: number;
  y: number;
}

export const NO_ZOOM: Zoom = { scale: 1, x: 0, y: 0 };
export const MAX_SCALE = 4;
export const DOUBLE_TAP_SCALE = 2.5;

const SWIPE_DISTANCE = 0.25; // fraction of the screen width
const SWIPE_VELOCITY = 0.4; // px per ms, a quick flick
const DISMISS_DISTANCE = 0.18; // fraction of the screen height
const DISMISS_VELOCITY = 0.5;

/** Which way a horizontal swipe should move: -1 previous, 1 next, 0 snap back. */
export function swipeDirection(dx: number, velocity: number, width: number, hasPrev: boolean, hasNext: boolean): -1 | 0 | 1 {
  const far = Math.abs(dx) > width * SWIPE_DISTANCE;
  const flick = Math.abs(velocity) > SWIPE_VELOCITY && Math.abs(dx) > 20;
  if (!far && !flick) return 0;
  if (dx < 0 && hasNext) return 1;
  if (dx > 0 && hasPrev) return -1;
  return 0;
}

/** True when a downward drag is long or fast enough to close the viewer. */
export function shouldDismiss(dy: number, velocity: number, height: number): boolean {
  return dy > height * DISMISS_DISTANCE || (velocity > DISMISS_VELOCITY && dy > 30);
}

/** Drag resistance past the first or last item, so the edge is felt rather than hit. */
export function rubberBand(dx: number, canMove: boolean): number {
  return canMove ? dx : dx * 0.3;
}

/** Keeps a zoomed image covering the screen instead of drifting off it. */
export function clampZoom(zoom: Zoom, width: number, height: number): Zoom {
  const scale = Math.min(Math.max(zoom.scale, 1), MAX_SCALE);
  const maxX = ((scale - 1) * width) / 2;
  const maxY = ((scale - 1) * height) / 2;
  const clamp = (v: number, max: number) => Math.min(Math.max(v, -max), max) || 0;
  return { scale, x: clamp(zoom.x, maxX), y: clamp(zoom.y, maxY) };
}

/**
 * Zoom for a pinch: the content point under the starting midpoint stays under the fingers' current midpoint.
 * Points are offsets from the screen centre.
 */
export function pinchZoom(start: Zoom, startMid: { x: number; y: number }, mid: { x: number; y: number }, ratio: number): Zoom {
  const scale = Math.min(Math.max(start.scale * ratio, 1), MAX_SCALE);
  const contentX = (startMid.x - start.x) / start.scale;
  const contentY = (startMid.y - start.y) / start.scale;
  return { scale, x: mid.x - scale * contentX, y: mid.y - scale * contentY };
}

/** Double tap: zoom in keeping the tapped point in place, or zoom back out. */
export function toggleZoomAt(current: Zoom, point: { x: number; y: number }): Zoom {
  if (current.scale > 1) return NO_ZOOM;
  const s = DOUBLE_TAP_SCALE;
  return { scale: s, x: point.x * (1 - s), y: point.y * (1 - s) };
}
