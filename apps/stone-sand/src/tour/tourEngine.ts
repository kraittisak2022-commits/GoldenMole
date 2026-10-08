import type { OrderDom, TourEnv, TourStep, TourVars } from './tourSteps';

export interface TourState {
  step: number;
  vars: TourVars;
  /** Overlay hidden; demo data and progress are kept so the tour can be resumed from the menu. */
  paused: boolean;
}

const KEY = 'stone_sand_tour_v1';

export function loadTourState(): TourState | null {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return null;
    const s = JSON.parse(raw) as Partial<TourState>;
    if (typeof s.step !== 'number' || s.step < 0) return null;
    return { step: s.step, vars: s.vars ?? {}, paused: !!s.paused };
  } catch {
    return null;
  }
}

export function saveTourState(state: TourState | null): void {
  try {
    if (state) localStorage.setItem(KEY, JSON.stringify(state));
    else localStorage.removeItem(KEY);
  } catch {
    // private mode: the tour still works, it just cannot resume after a reload
  }
}

export const onPage = (step: TourStep, path: string): boolean => !step.on || step.on.test(path);

/** Back only re-shows explanations on the same page; interactive steps cannot be "undone". */
export function canGoBack(steps: TourStep[], index: number): boolean {
  if (index <= 0) return false;
  const prev = steps[index - 1];
  const cur = steps[index];
  return !prev.done && !prev.action && String(prev.on) === String(cur.on);
}

export function chapterProgress(steps: TourStep[], index: number) {
  const chapter = steps[index]?.chapter ?? 0;
  const inChapter = steps.map((s, i) => ({ s, i })).filter(({ s }) => s.chapter === chapter);
  return {
    chapter,
    chapterStep: inChapter.findIndex(({ i }) => i === index) + 1,
    chapterSize: inChapter.length,
  };
}

function visible(el: Element): boolean {
  const r = el.getBoundingClientRect();
  return r.width > 0 && r.height > 0;
}

/** The same target can exist twice (desktop sidebar + mobile tab bar); use the one on screen. */
export function findVisible(doc: Document, selector: string): HTMLElement | null {
  const all = Array.from(doc.querySelectorAll<HTMLElement>(selector));
  return all.find(visible) ?? null;
}

export function readOrderDom(doc: Document): OrderDom | null {
  const el = doc.querySelector<HTMLElement>('[data-order-id]');
  if (!el) return null;
  const d = el.dataset;
  return {
    id: d.orderId ?? '',
    payment: d.payment ?? '',
    delivery: d.delivery ?? '',
    cancelled: d.cancelled === '1',
    cleared: d.cleared === '1',
  };
}

export function buildEnv(doc: Document, path: string, vars: TourVars): TourEnv {
  return {
    path,
    has: (selector) => !!findVisible(doc, selector),
    wizardStep: doc.querySelector('[data-wizard-step]')?.getAttribute('data-wizard-step') ?? null,
    order: readOrderDom(doc),
    vars,
  };
}
