import { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { ArrowLeft, ArrowRight, Check, X } from 'lucide-react';
import { useAuth } from '../../auth/AuthProvider';
import { useVisibleSources } from '../../auth/useVisibleSources';
import Button from '../../components/ui/Button';
import { ErrorBox, Loading } from '../../components/ui/States';
import { useCatalog } from '../../context/CatalogProvider';
import { getCustomer } from '../../data/customers';
import { createOrder, draftTotals } from '../../data/orders';
import { driverTripRate } from '../../lib/driverPay';
import { formatDateShort, formatMoney } from '../../lib/format';
import { ORDER_SOURCE_LABEL, type Customer, type OrderSource } from '../../types';
import StepConfirm from './StepConfirm';
import StepCustomer from './StepCustomer';
import StepFulfillment from './StepFulfillment';
import StepProducts from './StepProducts';
import StepSource from './StepSource';
import StepSummary from './StepSummary';
import {
  DRAFT_KEY,
  STEPS,
  buildItems,
  initialWizardState,
  quantitiesOf,
  stepIndex,
  toDraft,
  totalQuantity,
  validateStep,
  withDeliveryPlan,
  type WizardState,
} from './wizardState';

interface StoredDraft {
  step: number;
  state: WizardState;
}

function readDraft(): StoredDraft | null {
  try {
    const raw = sessionStorage.getItem(DRAFT_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as StoredDraft;
    return { step: Math.min(Math.max(0, parsed.step || 0), STEPS.length - 1), state: withDeliveryPlan({ ...initialWizardState, ...parsed.state }) };
  } catch {
    return null;
  }
}

function clearDraft() {
  try {
    sessionStorage.removeItem(DRAFT_KEY);
  } catch {
    // ignore
  }
}

export default function NewOrderPage() {
  const { user, lockedSource } = useAuth();
  const sources = useVisibleSources();
  const { products, zones, drivers, settings, loading, error, zoneById, driverById } = useCatalog();
  const navigate = useNavigate();
  const [params] = useSearchParams();

  const [initial] = useState(() => (params.get('customer') ? null : readDraft()));
  const [step, setStep] = useState(initial?.step ?? 0);
  const [state, setState] = useState<WizardState>(() => {
    const s = initial?.state ?? initialWizardState;
    return lockedSource ? { ...s, source: lockedSource } : s;
  });
  const [stepError, setStepError] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState('');

  const patch = useCallback((p: Partial<WizardState>) => setState((prev) => withDeliveryPlan({ ...prev, ...p })), []);

  const selectCustomer = useCallback((c: Customer | null) => {
    setState((prev) => ({
      ...prev,
      customer: c,
      ...(c?.isCredit && !prev.paymentMethod ? { paymentMethod: 'credit' as const, paidNow: false } : {}),
    }));
    if (c) setStep((s) => (s === stepIndex('customer') ? s + 1 : s));
  }, []);

  const selectSource = useCallback((source: OrderSource) => {
    setState((prev) => ({ ...prev, source }));
    setStep((s) => (s === stepIndex('source') ? s + 1 : s));
  }, []);

  useEffect(() => {
    try {
      sessionStorage.setItem(DRAFT_KEY, JSON.stringify({ step, state }));
    } catch {
      // ignore quota / private mode
    }
  }, [step, state]);

  useEffect(() => {
    const id = params.get('customer');
    if (!id) return;
    getCustomer(id)
      .then((c) => {
        if (c) selectCustomer(c);
      })
      .catch(() => undefined);
  }, []);

  useEffect(() => {
    setStepError('');
    window.scrollTo({ top: 0 });
  }, [step]);

  const quantities = useMemo(() => quantitiesOf(state.loads), [state.loads]);
  const loadLines = useMemo(
    () =>
      products
        .filter((p) => (state.loads[p.id]?.perTrip ?? 0) > 0 && (state.loads[p.id]?.trips ?? 0) > 0)
        .map((p) => ({ id: p.id, name: p.name, ...state.loads[p.id] })),
    [products, state.loads],
  );
  const items = useMemo(() => buildItems(products, quantities, state.unitDiscounts), [products, quantities, state.unitDiscounts]);
  const totals = draftTotals({ ...state, fulfillment: state.fulfillment ?? 'pickup', items });
  const zone = zoneById(state.zoneId);
  const driver = driverById(state.driverId);
  const stepKey = STEPS[step].key;

  const next = () => {
    const err = validateStep(step, state);
    if (err) return setStepError(err);
    setStep((s) => Math.min(STEPS.length - 1, s + 1));
  };

  const back = () => {
    if (step === 0) return close();
    setStep((s) => s - 1);
  };

  const close = () => {
    const dirty = state.customer || totalQuantity(quantities) > 0;
    if (dirty && !window.confirm('ยกเลิกออเดอร์นี้? ข้อมูลที่กรอกไว้จะหายไป')) return;
    clearDraft();
    navigate('/');
  };

  const goTo = (target: number) => {
    for (let i = 0; i < target; i += 1) {
      const err = validateStep(i, state);
      if (err) {
        setStep(i);
        setStepError(err);
        return;
      }
    }
    setStep(target);
  };

  const submit = async () => {
    for (let i = 0; i < STEPS.length - 1; i += 1) {
      const err = validateStep(i, state);
      if (err) {
        setStep(i);
        setStepError(err);
        return;
      }
    }
    setSubmitting(true);
    setSubmitError('');
    try {
      const order = await createOrder(toDraft(state, products, driverTripRate(zone, state.truckSize, state.roadDistanceKm, settings.delivery).perTrip), user?.displayName || user?.username || '');
      clearDraft();
      navigate(`/bill/order/${order.id}?created=1`, { replace: true });
    } catch (err) {
      setSubmitError(err instanceof Error ? err.message : 'บันทึกออเดอร์ไม่สำเร็จ');
      setSubmitting(false);
    }
  };

  if (loading) return <Loading page />;

  return (
    <div className="min-h-[100dvh] bg-page">
      <header className="sticky top-0 z-[500] bg-surface/95 pt-safe-top backdrop-blur">
        <div className="mx-auto flex max-w-2xl items-center gap-2 px-2 pt-2">
          <button
            type="button"
            onClick={close}
            aria-label="ปิด"
            className="inline-flex min-h-12 min-w-12 items-center justify-center rounded-full text-muted hover:bg-subtle hover:text-ink cursor-pointer"
          >
            <X size={22} aria-hidden />
          </button>
          <div className="flex min-w-0 flex-1 flex-col">
            <h1 className="text-lg font-semibold leading-tight">สร้างออเดอร์</h1>
            {state.source ? (
              <p className="truncate text-xs font-medium text-primary">
                ออเดอร์{ORDER_SOURCE_LABEL[state.source]}
                {state.orderDate ? ` · ${formatDateShort(state.orderDate)}` : ''}
              </p>
            ) : null}
          </div>
          <span className="pr-3 text-sm tabular-nums text-muted">
            {step + 1} / {STEPS.length}
          </span>
        </div>
        <ol className="mx-auto flex max-w-2xl gap-1.5 px-4 pb-3 pt-1 short:pb-1" aria-label="ขั้นตอน" data-tour="wiz-progress">
          {STEPS.map((s, i) => {
            const done = i < step;
            const current = i === step;
            return (
              <li key={s.key} className="flex-1">
                <button
                  type="button"
                  onClick={() => (i < step ? setStep(i) : goTo(i))}
                  aria-current={current ? 'step' : undefined}
                  className="flex w-full flex-col items-stretch gap-2 py-1 text-left cursor-pointer"
                >
                  <span
                    className={[
                      'h-1 rounded-full transition-colors',
                      done || current ? 'bg-primary' : 'bg-border',
                    ].join(' ')}
                  />
                  <span
                    className={[
                      'truncate text-xs sm:text-sm short:hidden',
                      current ? 'font-semibold text-ink' : 'text-muted',
                    ].join(' ')}
                  >
                    {s.label}
                  </span>
                </button>
              </li>
            );
          })}
        </ol>
      </header>

      <main className="mx-auto max-w-2xl px-4 pb-44 pt-4" data-wizard-step={stepKey}>
        {error ? (
          <div className="mb-4">
            <ErrorBox message={error} />
          </div>
        ) : null}

        {stepKey === 'source' ? (
          <StepSource
            sources={sources}
            source={state.source}
            onSelect={selectSource}
            orderDate={state.orderDate}
            onDateChange={(orderDate) => patch({ orderDate })}
          />
        ) : null}
        {stepKey === 'products' ? (
          <StepProducts products={products} loads={state.loads} onChange={(l) => patch({ loads: l })} />
        ) : null}
        {stepKey === 'customer' ? <StepCustomer customer={state.customer} onSelect={selectCustomer} /> : null}
        {stepKey === 'fulfillment' ? (
          <StepFulfillment
            state={state}
            patch={patch}
            customer={state.customer}
            zones={zones}
            drivers={drivers}
            settings={settings}
            loadLines={loadLines}
            onEditProducts={() => setStep(stepIndex('products'))}
          />
        ) : null}
        {stepKey === 'summary' ? <StepSummary state={state} patch={patch} items={items} /> : null}
        {stepKey === 'confirm' ? (
          <StepConfirm state={state} items={items} zone={zone} driver={driver} onEdit={setStep} />
        ) : null}

        {submitError ? (
          <div className="mt-4">
            <ErrorBox message={submitError} />
          </div>
        ) : null}
      </main>

      <footer className="pad-x-safe fixed inset-x-0 bottom-0 z-[500] border-t border-border bg-surface/95 pb-safe-bottom backdrop-blur">
        <div className="mx-auto max-w-2xl px-4 py-3 short:py-2">
          {stepError ? (
            <p role="alert" className="mb-2 text-sm text-destructive">
              {stepError}
            </p>
          ) : null}
          <div className="flex items-center gap-3">
            <Button variant="ghost" size="lg" onClick={back} aria-label={step === 0 ? 'ยกเลิก' : 'ย้อนกลับ'} className="px-3">
              <ArrowLeft size={22} aria-hidden />
            </Button>
            <div className="min-w-0 flex-1">
              <p className="text-xs text-muted">ยอดสุทธิ</p>
              <p className="truncate text-xl font-semibold tabular-nums text-ink">{formatMoney(totals.total)}</p>
            </div>
            {step < STEPS.length - 1 ? (
              <Button size="lg" onClick={next} data-tour="wiz-next">
                ถัดไป <ArrowRight size={18} aria-hidden />
              </Button>
            ) : (
              <Button size="lg" variant="success" onClick={submit} disabled={submitting} data-tour="wiz-submit">
                <Check size={18} aria-hidden /> {submitting ? 'กำลังบันทึก…' : 'ยืนยันและออกบิล'}
              </Button>
            )}
          </div>
        </div>
      </footer>
    </div>
  );
}
