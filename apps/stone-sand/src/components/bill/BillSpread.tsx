import { useLayoutEffect, useRef, useState, type ReactNode } from 'react';

const mmToPx = (mm: number) => (mm / 25.4) * 96;
const HALF_H = mmToPx(210);

/** Landscape A4 sheet with two A5 halves; each bill is scaled to fit its half, with a cut line between. */
export default function BillSpread({ left, right }: { left: ReactNode; right?: ReactNode }) {
  return (
    <div className="bill-spread relative flex bg-white shadow-lg" style={{ width: '297mm', height: '210mm' }}>
      <Half widthMm={148.5}>{left}</Half>
      {right ? <Half widthMm={148.5}>{right}</Half> : null}
      <div className="pointer-events-none absolute inset-y-[5mm] left-1/2 border-l border-dashed border-slate-300" aria-hidden />
    </div>
  );
}

/** One A5 portrait sheet holding a single bill, scaled to fit. */
export function BillA5Page({ children }: { children: ReactNode }) {
  return (
    <div className="bill-a5-page relative flex bg-white shadow-lg" style={{ width: '148mm', height: '210mm' }}>
      <Half widthMm={148}>{children}</Half>
    </div>
  );
}

function Half({ widthMm, children }: { widthMm: number; children: ReactNode }) {
  const inner = useRef<HTMLDivElement>(null);
  const [fit, setFit] = useState({ scale: 1, left: 0 });

  useLayoutEffect(() => {
    const el = inner.current;
    if (!el) return;
    const width = mmToPx(widthMm);
    const update = () => {
      const scale = Math.min(width / el.offsetWidth, HALF_H / el.offsetHeight);
      setFit({ scale, left: (width - el.offsetWidth * scale) / 2 });
    };
    update();
    const ro = new ResizeObserver(update);
    ro.observe(el);
    return () => ro.disconnect();
  }, [widthMm]);

  return (
    <div className="bill-half relative h-full shrink-0 overflow-hidden" style={{ width: `${widthMm}mm` }}>
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
