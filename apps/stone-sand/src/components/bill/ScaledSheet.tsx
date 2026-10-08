import { useLayoutEffect, useRef, useState, type ReactNode } from 'react';

/** 210mm at 96dpi */
const SHEET_PX = 794;

/** Shrinks an A4 sheet to the available width on screen; print CSS removes the transform. */
export default function ScaledSheet({ children }: { children: ReactNode }) {
  const outer = useRef<HTMLDivElement>(null);
  const inner = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(1);
  const [height, setHeight] = useState<number | undefined>(undefined);

  useLayoutEffect(() => {
    const el = outer.current;
    const content = inner.current;
    if (!el || !content) return;
    const update = () => {
      const s = Math.min(1, el.clientWidth / SHEET_PX);
      setScale(s);
      setHeight(content.scrollHeight * s);
    };
    update();
    const ro = new ResizeObserver(update);
    ro.observe(el);
    ro.observe(content);
    return () => ro.disconnect();
  }, []);

  return (
    <div ref={outer} className="bill-scale-outer w-full" style={{ height }}>
      <div
        ref={inner}
        className="bill-scale"
        style={{ width: SHEET_PX, transform: `scale(${scale})`, transformOrigin: 'top left', marginInline: scale < 1 ? 0 : 'auto' }}
      >
        {children}
      </div>
    </div>
  );
}
