import { useLayoutEffect, useRef, useState, type ReactNode } from 'react';

/** One A5 half of a landscape A4 sheet, in CSS px (96dpi). */
const HALF_W = (148.5 / 25.4) * 96;
const HALF_H = (210 / 25.4) * 96;

/** Landscape A4 sheet with two A5 halves; each bill is scaled to fit its half, with a cut line between. */
export default function BillSpread({ left, right }: { left: ReactNode; right?: ReactNode }) {
  return (
    <div className="bill-spread relative flex bg-white shadow-lg" style={{ width: '297mm', height: '210mm' }}>
      <Half>{left}</Half>
      {right ? <Half>{right}</Half> : null}
      <div className="pointer-events-none absolute inset-y-[5mm] left-1/2 border-l border-dashed border-slate-300" aria-hidden />
    </div>
  );
}

function Half({ children }: { children: ReactNode }) {
  const inner = useRef<HTMLDivElement>(null);
  const [fit, setFit] = useState({ scale: 1, left: 0 });

  useLayoutEffect(() => {
    const el = inner.current;
    if (!el) return;
    const update = () => {
      const scale = Math.min(HALF_W / el.offsetWidth, HALF_H / el.offsetHeight);
      setFit({ scale, left: (HALF_W - el.offsetWidth * scale) / 2 });
    };
    update();
    const ro = new ResizeObserver(update);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  return (
    <div className="bill-half relative h-full shrink-0 overflow-hidden" style={{ width: '148.5mm' }}>
      <div
        ref={inner}
        className="bill-fit absolute top-0"
        style={{ left: fit.left, transform: `scale(${fit.scale})`, transformOrigin: 'top left' }}
      >
        {children}
      </div>
    </div>
  );
}
