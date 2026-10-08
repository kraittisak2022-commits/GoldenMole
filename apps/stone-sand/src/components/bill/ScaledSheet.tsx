import { useLayoutEffect, useRef, useState, type ReactNode } from 'react';

/** Shrinks a sheet of `widthPx` (96dpi) to the available width on screen; print CSS removes the transform. */
export default function ScaledSheet({ widthPx, children }: { widthPx: number; children: ReactNode }) {
  const outer = useRef<HTMLDivElement>(null);
  const inner = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(1);
  const [height, setHeight] = useState<number | undefined>(undefined);

  useLayoutEffect(() => {
    const el = outer.current;
    const content = inner.current;
    if (!el || !content) return;
    const update = () => {
      const s = Math.min(1, el.clientWidth / widthPx);
      setScale(s);
      setHeight(content.scrollHeight * s);
    };
    update();
    const ro = new ResizeObserver(update);
    ro.observe(el);
    ro.observe(content);
    return () => ro.disconnect();
  }, [widthPx]);

  return (
    <div ref={outer} className="bill-scale-outer w-full" style={{ height }}>
      <div
        ref={inner}
        className="bill-scale"
        style={{ width: widthPx, transform: `scale(${scale})`, transformOrigin: 'top left', marginInline: scale < 1 ? 0 : 'auto' }}
      >
        {children}
      </div>
    </div>
  );
}
