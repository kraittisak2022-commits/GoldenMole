import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { useAuth } from '../auth/AuthProvider';
import { useCatalog } from '../context/CatalogProvider';
import { getCustomer, saveCustomer } from '../data/customers';
import { deleteDemoSession, deleteStaleDemoSessions } from '../data/demo';
import { createOrder } from '../data/orders';
import { clearAsyncCache } from '../hooks/useAsync';
import { DRAFT_KEY } from '../pages/new-order/wizardState';
import { DEMO_CUSTOMER_NAME, demoCreditDraft } from './demoData';
import TourOverlay from './TourOverlay';
import { TourContext, type TourApi } from './tourContext';
import { loadTourState, onPage, saveTourState, type TourState } from './tourEngine';
import { demoSession, endDemoSession, startDemoSession } from './tourSession';
import { TOUR_STEPS, type TourAction, type TourVars } from './tourSteps';

function clearWizardDraft() {
  try {
    sessionStorage.removeItem(DRAFT_KEY);
  } catch {
    // ignore
  }
}

export default function TourProvider({ children }: { children: ReactNode }) {
  const navigate = useNavigate();
  const { pathname } = useLocation();
  const { user, lockedSource } = useAuth();
  const { products } = useCatalog();
  const [state, setState] = useState<TourState | null>(() => (demoSession() ? loadTourState() : null));
  const [starting, setStarting] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const by = user?.displayName || user?.username || '';

  useEffect(() => saveTourState(state), [state]);

  const goTo = useCallback((step: number, vars?: Partial<TourVars>) => {
    setError('');
    setState((s) => (s ? { ...s, step: Math.max(0, Math.min(step, TOUR_STEPS.length - 1)), vars: { ...s.vars, ...vars } } : s));
  }, []);

  const active = !!state && !state.paused;
  const stepIndex = state?.step ?? -1;
  useEffect(() => {
    if (!state || state.paused) return;
    const step = TOUR_STEPS[state.step];
    if (!step || onPage(step, pathname)) return;
    const to = step.route?.(state.vars);
    if (to) navigate(to);
  }, [stepIndex, active]);

  const start = useCallback(async () => {
    setStarting(true);
    setError('');
    try {
      await deleteStaleDemoSessions().catch(() => undefined);
      const previous = demoSession();
      if (previous) await deleteDemoSession(previous).catch(() => undefined);
      startDemoSession();
      const customer = await saveCustomer({
        name: DEMO_CUSTOMER_NAME,
        aliases: ['ตัวอย่าง'],
        phone: '0800000000',
        address: '99 หมู่ 1 (ที่อยู่สาธิต)',
        zoneId: null,
        taxId: '',
        lat: null,
        lng: null,
        isCredit: false,
        note: 'สร้างโดยโหมดสอนใช้งาน',
      });
      clearWizardDraft();
      clearAsyncCache();
      setState({ step: 0, vars: { customerId: customer.id }, paused: false });
      navigate('/');
    } catch (err) {
      endDemoSession();
      setError(err instanceof Error ? err.message : 'เริ่มโหมดสอนใช้งานไม่สำเร็จ');
    } finally {
      setStarting(false);
    }
  }, [navigate]);

  const end = useCallback(async () => {
    setBusy(true);
    setError('');
    const session = demoSession();
    try {
      if (session) await deleteDemoSession(session);
    } catch {
      setError('ลบข้อมูลสาธิตไม่สำเร็จ ตรวจสอบอินเทอร์เน็ตแล้วลองอีกครั้ง');
      setBusy(false);
      return;
    }
    endDemoSession();
    clearWizardDraft();
    clearAsyncCache();
    setState(null);
    setBusy(false);
    navigate(pathname === '/menu' ? '/' : '/menu', { replace: true });
  }, [navigate, pathname]);

  const runAction = async (action: TourAction) => {
    if (action === 'finish') return end();
    if (!state) return;
    setBusy(true);
    setError('');
    try {
      const customer = state.vars.customerId ? await getCustomer(state.vars.customerId) : null;
      const product = products.find((p) => p.active) ?? products[0];
      if (!customer || !product) throw new Error('ไม่พบลูกค้าหรือสินค้าสำหรับออเดอร์ตัวอย่าง');
      const order = await createOrder(demoCreditDraft(customer, product, lockedSource ?? 'shop'), by);
      navigate(`/orders/${order.id}`);
      goTo(state.step + 1, { creditOrderId: order.id });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'สร้างออเดอร์ตัวอย่างไม่สำเร็จ');
    } finally {
      setBusy(false);
    }
  };

  const api = useMemo<TourApi>(
    () => ({
      state,
      starting,
      error,
      start,
      end,
      resume: () => setState((s) => (s ? { ...s, paused: false } : s)),
    }),
    [state, starting, error, start, end],
  );

  return (
    <TourContext.Provider value={api}>
      {children}
      {state && !state.paused ? (
        <TourOverlay
          index={state.step}
          vars={state.vars}
          busy={busy}
          error={error}
          onAdvance={(vars) => goTo(state.step + 1, vars)}
          onBack={() => goTo(state.step - 1)}
          onAction={runAction}
          onPause={() => setState((s) => (s ? { ...s, paused: true } : s))}
          onEnd={end}
        />
      ) : null}
    </TourContext.Provider>
  );
}
