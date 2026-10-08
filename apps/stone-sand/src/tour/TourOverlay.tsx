import { useEffect, useLayoutEffect, useRef, useState, type CSSProperties } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { ArrowLeft, ArrowRight, ChevronUp, GraduationCap, Minus, MousePointerClick, X } from 'lucide-react';
import Button from '../components/ui/Button';
import { buildEnv, canGoBack, chapterProgress, findVisible, onPage } from './tourEngine';
import { CHAPTERS, TOUR_STEPS, type TourAction, type TourVars } from './tourSteps';

interface Props {
  index: number;
  vars: TourVars;
  busy: boolean;
  error: string;
  onAdvance: (vars?: Partial<TourVars>) => void;
  onBack: () => void;
  onAction: (action: TourAction) => void;
  onPause: () => void;
  onEnd: () => void;
}

interface Box {
  top: number;
  left: number;
  width: number;
  height: number;
}

const PAD = 8;
const GAP = 14;
const EDGE = 12;
const CARD_W = 380;
/** Keeps a desktop card off fixed footers such as the wizard's "ถัดไป" bar. */
const FOOTER_RESERVE = 96;
const ADVANCE_DELAY = 650;

const sameBox = (a: Box | null, b: Box | null) =>
  a === b ||
  (!!a && !!b && Math.abs(a.top - b.top) < 1 && Math.abs(a.left - b.left) < 1 && Math.abs(a.width - b.width) < 1 && Math.abs(a.height - b.height) < 1);

function isPinned(el: HTMLElement): boolean {
  for (let n: HTMLElement | null = el; n; n = n.parentElement) {
    const pos = getComputedStyle(n).position;
    if (pos === 'fixed' || pos === 'sticky') return true;
  }
  return false;
}

export default function TourOverlay({ index, vars, busy, error, onAdvance, onBack, onAction, onPause, onEnd }: Props) {
  const step = TOUR_STEPS[index];
  const navigate = useNavigate();
  const { pathname } = useLocation();
  const [tick, setTick] = useState(0);
  const [rect, setRect] = useState<Box | null>(null);
  const [view, setView] = useState({ w: window.innerWidth, h: window.innerHeight });
  const [cardH, setCardH] = useState(0);
  const [minimized, setMinimized] = useState(false);
  const [confirmExit, setConfirmExit] = useState(false);
  const cardRef = useRef<HTMLDivElement>(null);
  const advancedFor = useRef(-1);
  const scrolledFor = useRef(-1);
  const timer = useRef<number | undefined>(undefined);

  useEffect(() => {
    let frame = 0;
    const bump = () => {
      if (frame) return;
      frame = requestAnimationFrame(() => {
        frame = 0;
        setTick((t) => t + 1);
      });
    };
    const id = window.setInterval(bump, 300);
    window.addEventListener('scroll', bump, true);
    window.addEventListener('resize', bump);
    return () => {
      window.clearInterval(id);
      cancelAnimationFrame(frame);
      window.removeEventListener('scroll', bump, true);
      window.removeEventListener('resize', bump);
    };
  }, []);

  useEffect(() => {
    advancedFor.current = -1;
    scrolledFor.current = -1;
    window.clearTimeout(timer.current);
    timer.current = undefined;
    setConfirmExit(false);
    setMinimized(false);
  }, [index]);

  useEffect(() => () => window.clearTimeout(timer.current), []);

  const advance = (captured?: Partial<TourVars>) => {
    if (advancedFor.current === index) return;
    advancedFor.current = index;
    onAdvance(captured);
  };

  useEffect(() => {
    if (!step) return;
    const env = buildEnv(document, pathname, vars);
    if (step.skip?.(env)) return advance();

    const el = step.target && onPage(step, pathname) ? findVisible(document, step.target) : null;
    const r = el?.getBoundingClientRect();
    const next = r ? { top: r.top, left: r.left, width: r.width, height: r.height } : null;
    setRect((prev) => (sameBox(prev, next) ? prev : next));
    setView((v) => (v.w === window.innerWidth && v.h === window.innerHeight ? v : { w: window.innerWidth, h: window.innerHeight }));

    if (el && r && scrolledFor.current !== index) {
      scrolledFor.current = index;
      if ((r.top < 72 || r.bottom > window.innerHeight - 180) && !isPinned(el)) {
        el.scrollIntoView({ block: 'center', behavior: 'smooth' });
      }
    }

    if (step.done && timer.current === undefined && advancedFor.current !== index && step.done(env)) {
      const captured = step.capture?.(env);
      timer.current = window.setTimeout(() => {
        timer.current = undefined;
        advance(captured);
      }, ADVANCE_DELAY);
    }
  }, [tick, index, pathname]);

  useLayoutEffect(() => {
    const h = cardRef.current?.offsetHeight ?? 0;
    if (Math.abs(h - cardH) > 1) setCardH(h);
  });

  if (!step) return null;

  const total = TOUR_STEPS.length;
  const { chapter, chapterStep, chapterSize } = chapterProgress(TOUR_STEPS, index);
  const offPage = !onPage(step, pathname);
  const offRoute = offPage ? step.route?.(vars) ?? null : null;
  const wide = view.w >= 768;
  const spot = rect && !minimized ? rect : null;

  const placeTop = step.place ? step.place === 'top' : !!spot && spot.top + spot.height / 2 > view.h / 2;
  let cardStyle: CSSProperties;
  if (!wide) {
    cardStyle = placeTop
      ? { left: EDGE, right: EDGE, top: `calc(env(safe-area-inset-top) + ${EDGE}px)` }
      : { left: EDGE, right: EDGE, bottom: `calc(env(safe-area-inset-bottom) + ${EDGE}px)` };
  } else {
    const maxTop = Math.max(EDGE, view.h - cardH - FOOTER_RESERVE);
    const clampTop = (t: number) => Math.min(Math.max(EDGE, t), maxTop);
    const clampLeft = (l: number) => Math.min(Math.max(EDGE, l), view.w - CARD_W - EDGE);
    if (spot && view.w - (spot.left + spot.width) >= CARD_W + GAP * 2) {
      cardStyle = { width: CARD_W, left: spot.left + spot.width + GAP + PAD, top: clampTop(spot.top) };
    } else if (spot && spot.left >= CARD_W + GAP * 2) {
      cardStyle = { width: CARD_W, left: spot.left - CARD_W - GAP - PAD, top: clampTop(spot.top) };
    } else if (spot && spot.top + spot.height + PAD + GAP + cardH <= view.h - FOOTER_RESERVE) {
      cardStyle = { width: CARD_W, left: clampLeft(spot.left), top: spot.top + spot.height + PAD + GAP };
    } else if (spot && spot.top - PAD - GAP - cardH >= EDGE) {
      cardStyle = { width: CARD_W, left: clampLeft(spot.left), top: spot.top - PAD - GAP - cardH };
    } else {
      cardStyle = placeTop ? { width: CARD_W, right: 24, top: 24 } : { width: CARD_W, right: 24, bottom: 24 };
    }
  }

  const interactive = !!step.done;
  const backOk = canGoBack(TOUR_STEPS, index);
  const progress = ((index + 1) / total) * 100;

  if (minimized) {
    return (
      <button
        type="button"
        onClick={() => setMinimized(false)}
        className="tour-pill fixed left-1/2 z-[1110] flex min-h-11 -translate-x-1/2 items-center gap-2 rounded-full bg-violet-600 px-4 text-sm font-semibold text-white shadow-lg cursor-pointer"
        style={{ top: 'calc(env(safe-area-inset-top) + 8px)' }}
      >
        <GraduationCap size={18} aria-hidden />
        สอนใช้งาน · ขั้น {index + 1}/{total}
        <ChevronUp size={16} aria-hidden />
      </button>
    );
  }

  return (
    <>
      {spot ? (
        <div
          aria-hidden
          className="tour-spot"
          style={{ top: spot.top - PAD, left: spot.left - PAD, width: spot.width + PAD * 2, height: spot.height + PAD * 2 }}
        />
      ) : (
        <div aria-hidden className="tour-dim" />
      )}

      <div
        ref={cardRef}
        role="dialog"
        aria-label="สอนใช้งาน"
        aria-live="polite"
        className="tour-card fixed z-[1110] flex max-h-[min(70dvh,34rem)] flex-col overflow-hidden rounded-2xl border border-violet-200 bg-surface text-ink shadow-2xl"
        style={cardStyle}
      >
        <div className="h-1 w-full bg-violet-100">
          <div className="h-full bg-violet-600 transition-[width] duration-300" style={{ width: `${progress}%` }} />
        </div>
        <div className="flex items-center gap-2 px-4 pt-3">
          <span className="inline-flex min-w-0 items-center gap-1.5 rounded-full bg-violet-50 px-2.5 py-1 text-xs font-semibold text-violet-700">
            <GraduationCap size={14} aria-hidden className="shrink-0" />
            <span className="truncate">
              บทที่ {chapter + 1}/{CHAPTERS.length} · {CHAPTERS[chapter]}
            </span>
          </span>
          <span className="ml-auto shrink-0 text-xs tabular-nums text-muted">
            {chapterStep}/{chapterSize}
          </span>
          <button
            type="button"
            onClick={() => setMinimized(true)}
            aria-label="ย่อหน้าต่างสอนใช้งาน"
            className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-muted hover:bg-subtle hover:text-ink cursor-pointer"
          >
            <Minus size={18} aria-hidden />
          </button>
          <button
            type="button"
            onClick={() => setConfirmExit(true)}
            aria-label="ออกจากโหมดสอนใช้งาน"
            className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-muted hover:bg-subtle hover:text-ink cursor-pointer"
          >
            <X size={18} aria-hidden />
          </button>
        </div>

        {confirmExit ? (
          <div className="flex flex-col gap-3 overflow-y-auto px-4 pb-4 pt-2">
            <p className="text-lg font-semibold">ออกจากโหมดสอนใช้งาน?</p>
            <p className="text-[15px] leading-relaxed text-muted">
              ลบข้อมูลสาธิตทั้งหมดตอนนี้ หรือพักไว้แล้วกลับมาสอนต่อจากหน้าเมนูก็ได้
            </p>
            {error ? <p className="rounded bg-destructive-soft px-3 py-2 text-sm text-destructive">{error}</p> : null}
            <Button variant="danger" size="lg" disabled={busy} onClick={onEnd}>
              {busy ? 'กำลังลบ…' : 'ลบข้อมูลสาธิตและออก'}
            </Button>
            <div className="grid grid-cols-2 gap-2">
              <Button variant="secondary" disabled={busy} onClick={onPause}>
                พักไว้ก่อน
              </Button>
              <Button variant="ghost" disabled={busy} onClick={() => setConfirmExit(false)}>
                สอนต่อ
              </Button>
            </div>
          </div>
        ) : (
          <>
            <div className="flex flex-col gap-2 overflow-y-auto px-4 pb-3 pt-2">
              <h2 className="text-lg font-semibold leading-snug">{step.title}</h2>
              <p className="whitespace-pre-line text-[15px] leading-relaxed text-ink/80">{step.body}</p>
              {offPage ? (
                <div className="flex flex-col gap-2 rounded-xl bg-warning-soft px-3 py-2.5 text-sm text-amber-800">
                  <span>ขั้นนี้อยู่อีกหน้าหนึ่ง</span>
                  {offRoute ? (
                    <Button variant="secondary" onClick={() => navigate(offRoute)}>
                      ไปที่หน้านั้น
                    </Button>
                  ) : null}
                </div>
              ) : interactive ? (
                <p className="flex items-start gap-2 rounded-xl bg-violet-50 px-3 py-2.5 text-sm font-medium text-violet-800">
                  <MousePointerClick size={18} aria-hidden className="mt-0.5 shrink-0" />
                  ทำตามจุดที่ไฮไลต์ไว้ ระบบจะพาไปขั้นต่อไปให้เอง
                </p>
              ) : null}
              {error ? <p className="rounded bg-destructive-soft px-3 py-2 text-sm text-destructive">{error}</p> : null}
            </div>
            <div className="flex items-center gap-2 border-t border-border px-4 py-3">
              <span className="text-xs tabular-nums text-muted">
                ขั้น {index + 1}/{total}
              </span>
              <div className="ml-auto flex gap-2">
                {backOk ? (
                  <Button variant="ghost" onClick={onBack} disabled={busy} aria-label="ย้อนกลับ" className="px-3">
                    <ArrowLeft size={18} aria-hidden />
                  </Button>
                ) : null}
                {step.action ? (
                  <Button
                    variant={step.action === 'finish' ? 'success' : 'primary'}
                    onClick={() => onAction(step.action!)}
                    disabled={busy}
                  >
                    {busy ? 'กำลังทำรายการ…' : step.actionLabel}
                  </Button>
                ) : interactive ? (
                  step.required ? null : (
                    <Button variant="ghost" onClick={() => advance()} disabled={busy}>
                      ข้ามขั้นนี้
                    </Button>
                  )
                ) : (
                  <Button onClick={() => advance()} disabled={busy}>
                    ถัดไป <ArrowRight size={18} aria-hidden />
                  </Button>
                )}
              </div>
            </div>
          </>
        )}
      </div>
    </>
  );
}
