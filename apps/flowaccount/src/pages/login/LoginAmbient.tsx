import { useEffect, useState } from 'react';

function prefersReducedMotion() {
  if (typeof window === 'undefined' || !window.matchMedia) return false;
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}

/** Soft aurora blobs + ledger grid with light desktop parallax. */
export default function LoginAmbient() {
  const [offset, setOffset] = useState({ x: 0, y: 0 });

  useEffect(() => {
    if (prefersReducedMotion()) return;

    const mq = window.matchMedia('(min-width: 768px)');
    let active = mq.matches;

    const onMove = (e: MouseEvent) => {
      if (!active) return;
      const nx = (e.clientX / window.innerWidth - 0.5) * 16;
      const ny = (e.clientY / window.innerHeight - 0.5) * 12;
      setOffset({ x: nx, y: ny });
    };

    const onMq = () => {
      active = mq.matches;
      if (!active) setOffset({ x: 0, y: 0 });
    };

    window.addEventListener('mousemove', onMove, { passive: true });
    mq.addEventListener('change', onMq);
    return () => {
      window.removeEventListener('mousemove', onMove);
      mq.removeEventListener('change', onMq);
    };
  }, []);

  return (
    <div className="pointer-events-none absolute inset-0 overflow-hidden" aria-hidden>
      {/* Aurora blobs — parallax on outer wrapper so CSS animation keeps its transform */}
      <div
        className="absolute -left-32 -top-24 h-[28rem] w-[28rem] transition-transform duration-300 ease-out will-change-transform"
        style={{ transform: `translate(${offset.x * 0.6}px, ${offset.y * 0.6}px)` }}
      >
        <div className="h-full w-full rounded-full bg-accent/15 blur-3xl animate-login-aurora" />
      </div>
      <div
        className="absolute -bottom-40 -right-20 h-[32rem] w-[32rem] transition-transform duration-300 ease-out will-change-transform"
        style={{ transform: `translate(${offset.x * -0.4}px, ${offset.y * -0.5}px)` }}
      >
        <div className="h-full w-full rounded-full bg-gold/20 blur-3xl animate-login-aurora-delayed" />
      </div>
      <div
        className="absolute left-1/3 top-1/2 h-64 w-64 -translate-y-1/2 transition-transform duration-300 ease-out will-change-transform"
        style={{ transform: `translate(${offset.x * 0.3}px, calc(-50% + ${offset.y * 0.3}px))` }}
      >
        <div
          className="h-full w-full rounded-full bg-sky-200/30 blur-3xl animate-login-aurora"
          style={{ animationDelay: '4s' }}
        />
      </div>

      {/* Ledger paper grid */}
      <div
        className="absolute inset-0 opacity-[0.35] transition-transform duration-300 ease-out will-change-transform"
        style={{
          transform: `translate(${offset.x * 0.5}px, ${offset.y * 0.5}px)`,
          backgroundImage: `
            linear-gradient(to right, rgba(3, 105, 161, 0.06) 1px, transparent 1px),
            linear-gradient(to bottom, rgba(3, 105, 161, 0.06) 1px, transparent 1px)
          `,
          backgroundSize: '40px 40px',
        }}
      />

      {/* Soft vignette */}
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,transparent_40%,rgba(248,250,252,0.85)_100%)]" />
    </div>
  );
}
