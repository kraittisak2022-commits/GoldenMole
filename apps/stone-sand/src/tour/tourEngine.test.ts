import { afterEach, describe, expect, it } from 'vitest';
import { buildEnv, canGoBack, chapterProgress, findVisible, loadTourState, onPage, saveTourState } from './tourEngine';
import { CHAPTERS, TOUR_STEPS, type TourEnv, type TourStep } from './tourSteps';

const env = (over: Partial<TourEnv>): TourEnv => ({
  path: '/',
  has: () => false,
  wizardStep: null,
  order: null,
  vars: {},
  ...over,
});

const stepWithTarget = (target: string) => TOUR_STEPS.findIndex((s) => s.target === `[data-tour="${target}"]`);

afterEach(() => {
  localStorage.clear();
  document.body.innerHTML = '';
});

describe('tour state persistence', () => {
  it('round-trips and clears', () => {
    saveTourState({ step: 7, vars: { orderId: 'ord-1' }, paused: true });
    expect(loadTourState()).toEqual({ step: 7, vars: { orderId: 'ord-1' }, paused: true });
    saveTourState(null);
    expect(loadTourState()).toBeNull();
  });

  it('ignores corrupt data', () => {
    localStorage.setItem('stone_sand_tour_v1', '{oops');
    expect(loadTourState()).toBeNull();
    localStorage.setItem('stone_sand_tour_v1', JSON.stringify({ step: -1 }));
    expect(loadTourState()).toBeNull();
  });
});

describe('navigation rules', () => {
  const steps: TourStep[] = [
    { chapter: 0, title: 'a', body: '', on: /^\/$/ },
    { chapter: 0, title: 'b', body: '', on: /^\/$/ },
    { chapter: 0, title: 'c', body: '', on: /^\/$/, done: () => true },
    { chapter: 1, title: 'd', body: '', on: /^\/$/ },
    { chapter: 1, title: 'e', body: '', on: /^\/new$/ },
  ];

  it('allows back only to an explanation on the same page', () => {
    expect(canGoBack(steps, 0)).toBe(false);
    expect(canGoBack(steps, 1)).toBe(true);
    expect(canGoBack(steps, 3)).toBe(false);
    expect(canGoBack(steps, 4)).toBe(false);
  });

  it('counts steps within a chapter', () => {
    expect(chapterProgress(steps, 1)).toEqual({ chapter: 0, chapterStep: 2, chapterSize: 3 });
    expect(chapterProgress(steps, 4)).toEqual({ chapter: 1, chapterStep: 2, chapterSize: 2 });
  });

  it('matches pages by pathname', () => {
    expect(onPage(steps[4], '/new')).toBe(true);
    expect(onPage(steps[4], '/orders')).toBe(false);
    expect(onPage({ chapter: 0, title: '', body: '' }, '/anything')).toBe(true);
  });
});

describe('DOM probes', () => {
  it('reads the order page state and wizard step', () => {
    document.body.innerHTML = `
      <main data-wizard-step="summary"></main>
      <div data-order-id="ord-9" data-payment="paid" data-delivery="delivered" data-cancelled="0" data-cleared="1"></div>`;
    const e = buildEnv(document, '/orders/ord-9', {});
    expect(e.wizardStep).toBe('summary');
    expect(e.order).toEqual({ id: 'ord-9', payment: 'paid', delivery: 'delivered', cancelled: false, cleared: true });
  });

  it('picks the copy of a target that is actually on screen', () => {
    document.body.innerHTML = '<a data-tour="new-order" id="hidden"></a><a data-tour="new-order" id="shown"></a>';
    const shown = document.getElementById('shown')!;
    shown.getBoundingClientRect = () => ({ width: 56, height: 56, top: 0, left: 0, right: 56, bottom: 56, x: 0, y: 0, toJSON: () => ({}) });
    expect(findVisible(document, '[data-tour="new-order"]')?.id).toBe('shown');
  });
});

describe('tour script', () => {
  it('is well formed', () => {
    let chapter = 0;
    for (const s of TOUR_STEPS) {
      expect(s.chapter).toBeGreaterThanOrEqual(chapter);
      expect(s.chapter).toBeLessThan(CHAPTERS.length);
      chapter = s.chapter;
      if (s.on) expect(s.route, `${s.title} needs a route to resume on`).toBeDefined();
      expect(s.title.length).toBeGreaterThan(0);
    }
    expect(new Set(TOUR_STEPS.map((s) => s.chapter)).size).toBe(CHAPTERS.length);
    expect(TOUR_STEPS.at(-1)?.action).toBe('finish');
  });

  it('captures the new order id when the wizard lands on its bill', () => {
    const submit = TOUR_STEPS[stepWithTarget('wiz-submit')];
    const e = env({ path: '/bill/order/ord-abc' });
    expect(submit.done?.(e)).toBe(true);
    expect(submit.capture?.(e)).toEqual({ orderId: 'ord-abc' });
    expect(submit.done?.(env({ path: '/new' }))).toBe(false);
  });

  it('advances the wizard steps only once the wizard moves past them', () => {
    const products = TOUR_STEPS[stepWithTarget('wiz-products')];
    expect(products.done?.(env({ wizardStep: 'products' }))).toBe(false);
    expect(products.done?.(env({ wizardStep: 'customer' }))).toBe(true);
  });

  it('waits for the tour order, not any order page', () => {
    const pay = TOUR_STEPS[stepWithTarget('pay-buttons')];
    const order = { id: 'ord-x', payment: 'paid', delivery: 'pickup', cancelled: false, cleared: false };
    expect(pay.done?.(env({ order, vars: { orderId: 'ord-other' } }))).toBe(false);
    expect(pay.done?.(env({ order, vars: { orderId: 'ord-x' } }))).toBe(true);
  });

  it('skips delivery steps for a pickup order', () => {
    const delivery = TOUR_STEPS[stepWithTarget('delivery-steps')];
    const order = { id: 'ord-x', payment: 'unpaid', delivery: 'pickup', cancelled: false, cleared: false };
    expect(delivery.skip?.(env({ order, vars: { orderId: 'ord-x' } }))).toBe(true);
    expect(delivery.skip?.(env({ order: { ...order, delivery: 'waiting' }, vars: { orderId: 'ord-x' } }))).toBe(false);
  });

  it('finishes clearing only when the modal is gone and no clear button is left', () => {
    const confirm = TOUR_STEPS[stepWithTarget('st-clear-modal')];
    const has = (present: string[]) => (sel: string) => present.some((p) => sel === `[data-tour="${p}"]`);
    expect(confirm.done?.(env({ has: has(['st-clear-modal', 'st-clear']) }))).toBe(false);
    expect(confirm.done?.(env({ has: has(['st-clear']) }))).toBe(false);
    expect(confirm.done?.(env({ has: has([]) }))).toBe(true);
  });
});
