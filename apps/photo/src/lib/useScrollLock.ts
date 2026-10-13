import { useEffect } from 'react';

let locks = 0;
let savedY = 0;

/**
 * Freezes the page behind a dialog. iOS Safari ignores `overflow: hidden` on body, so the body is
 * pinned with `position: fixed` and the scroll position restored afterwards. Nested locks are counted.
 */
export function useScrollLock(active = true) {
  useEffect(() => {
    if (!active) return;
    const body = document.body;
    if (locks++ === 0) {
      savedY = window.scrollY;
      Object.assign(body.style, { position: 'fixed', top: `-${savedY}px`, left: '0', right: '0', overflow: 'hidden' });
    }
    return () => {
      if (--locks === 0) {
        Object.assign(body.style, { position: '', top: '', left: '', right: '', overflow: '' });
        window.scrollTo(0, savedY);
      }
    };
  }, [active]);
}
