import { clampZoom, NO_ZOOM, pinchZoom, rubberBand, shouldDismiss, swipeDirection, toggleZoomAt } from './gestures';

describe('swipeDirection', () => {
  it('moves to the next item on a long left swipe', () => {
    expect(swipeDirection(-120, 0.1, 375, true, true)).toBe(1);
  });

  it('moves to the previous item on a quick right flick', () => {
    expect(swipeDirection(40, 0.8, 375, true, true)).toBe(-1);
  });

  it('snaps back on a short slow drag', () => {
    expect(swipeDirection(-40, 0.1, 375, true, true)).toBe(0);
  });

  it('snaps back at the ends of the album', () => {
    expect(swipeDirection(-200, 1, 375, true, false)).toBe(0);
    expect(swipeDirection(200, 1, 375, false, true)).toBe(0);
  });
});

describe('shouldDismiss', () => {
  it('closes after a long or fast downward drag', () => {
    expect(shouldDismiss(200, 0.1, 800)).toBe(true);
    expect(shouldDismiss(50, 0.9, 800)).toBe(true);
  });

  it('stays open for a small drag', () => {
    expect(shouldDismiss(50, 0.1, 800)).toBe(false);
    expect(shouldDismiss(10, 2, 800)).toBe(false);
  });
});

describe('rubberBand', () => {
  it('resists dragging past the ends', () => {
    expect(rubberBand(100, true)).toBe(100);
    expect(rubberBand(100, false)).toBe(30);
  });
});

describe('clampZoom', () => {
  it('limits panning to the zoomed overflow', () => {
    expect(clampZoom({ scale: 2, x: 500, y: -900 }, 400, 800)).toEqual({ scale: 2, x: 200, y: -400 });
  });

  it('keeps the scale between 1 and the maximum', () => {
    expect(clampZoom({ scale: 0.5, x: 30, y: 30 }, 400, 800)).toEqual(NO_ZOOM);
    expect(clampZoom({ scale: 9, x: 0, y: 0 }, 400, 800).scale).toBe(4);
  });
});

describe('pinchZoom', () => {
  it('keeps the point between the fingers fixed while zooming', () => {
    const z = pinchZoom(NO_ZOOM, { x: 100, y: 50 }, { x: 100, y: 50 }, 2);
    expect(z).toEqual({ scale: 2, x: -100, y: -50 });
    // The content point that was at (100, 50) maps back to the same screen point.
    expect(z.x + z.scale * 100).toBe(100);
  });

  it('follows the fingers when they move together', () => {
    const z = pinchZoom({ scale: 2, x: 0, y: 0 }, { x: 0, y: 0 }, { x: 30, y: -20 }, 1);
    expect(z).toEqual({ scale: 2, x: 30, y: -20 });
  });
});

describe('toggleZoomAt', () => {
  it('zooms in around the tapped point and back out', () => {
    const z = toggleZoomAt(NO_ZOOM, { x: 40, y: -20 });
    expect(z.scale).toBe(2.5);
    expect(z.x + z.scale * 40).toBeCloseTo(40);
    expect(toggleZoomAt(z, { x: 0, y: 0 })).toEqual(NO_ZOOM);
  });
});
