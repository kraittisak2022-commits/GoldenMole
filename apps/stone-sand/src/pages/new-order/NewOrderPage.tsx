import { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { ArrowLeft, ArrowRight, Check, X } from 'lucide-react';
import { useAuth } from '../../auth/AuthProvider';
import Button from '../../components/ui/Button';
import { ErrorBox, Loading } from '../../components/ui/States';
import { useCatalog } from '../../context/CatalogProvider';
import { getCustomer } from '../../data/customers';
import { createOrder, draftTotals } from '../../data/orders';
import { formatMoney } from '../../lib/format';
import type { Customer } from '../../types';
import StepConfirm from './StepConfirm';
import StepCustomer from './StepCustomer';
import StepFulfillment from './StepFulfillment';
import StepProducts from './StepProducts';
import StepSummary from './StepSummary';
import { STEPS, buildItems, initialWizardState, toDraft, totalQuantity, validateStep, type WizardState } from './wizardState';

const DRAFT_KEY = 'stone_sand_new_order_v1';

interface StoredDraft {
  step: number;
  state: WizardState;
}

function readDraft(): StoredDraft | null {
  try {
    const raw = sessionStorage.getItem(DRAFT_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as StoredDraft;
    return { step: Math.min(Math.max(0, parsed.step || 0), STEPS.length - 1), state: { ...initialWizardState, ...parsed.state } };
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
  const { user } = useAuth();
  const { products, zones, drivers, settings, loading, error, zoneById, driverById } = useCatalog();
  const navigate = useNavigate();
  const [params] = useSearchParams();

  const [initial] = useState(() => (params.get('customer') ? null : readDraft()));
  const [step, setStep] = useState(initial?.step ?? 0);
  const [state, setState] = useState<WizardState>(initial?.state ?? initialWizardState);
  const [stepError, setStepError] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState('');

  const patch = useCallback((p: Partial<WizardState>) => setState((prev) => ({ ...prev, ...p })), []);

  const selectCustomer = useCallback((c: Customer | null) => {
    setState((prev) => ({
      ...prev,
      customer: c,
      ...(c?.isCredit && !prev.paymentMethod ? { paymentMethod: 'credit' as const, paidNow: false } : {}),
    }));
    if (c) setStep((s) => (s === 0 ? 1 : s));
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

  const items = useMemo(() => buildItems(products, state.quantities), [products, state.quantities]);
  const totals = draftTotals({ ...state, fulfillment: state.fulfillment ?? 'pickup', items });
  const zone = zoneById(state.zoneId);
  const driver = driverById(state.driverId);

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
    const dirty = state.customer || totalQuantity(state.quantities) > 0;
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
      const order = await createOrder(toDraft(state, products, driver?.wagePerTrip ?? 0), user?.displayName || user?.username || '');
      clearDraft();
      navigate(`/bill/order/${order.id}?created=1`, { replace: true });
    } catch (err) {
      setSubmitError(err instanceof Error ? err.message : 'บันทึกออเดอร์ไม่สำเร็จ');
      setSubmitting(false);
    }
  };

  if (loading) return <Loading />;

  return (
    <div className="min-h-[100dvh] bg-page">
      <header className="sticky top-0 z-[500] border-b border-border bg-surface/95 pt-safe-top backdrop-blur">
        <div className="mx-auto flex max-w-2xl items-center gap-2 px-2 py-2">
          <button
            type="button"
            onClick={close}
            aria-label="ปิด"
            className="inline-flex min-h-11 min-w-11 items-center justify-center rounded text-muted hover:bg-subtle hover:text-ink cursor-pointer"
          >
            <X size={20} aria-hidden />
          </button>
          <h1 className="flex-1 text-base font-semibold">สร้างออเดอร์</h1>
          <span className="pr-2 text-sm text-muted">
            ขั้นที่ {step + 1}/{STEPS.length}
          </span>
        </div>
        <ol className="mx-auto flex max-w-2xl gap-1 px-4 pb-3" aria-label="ขั้นตอน">
          {STEPS.map((s, i) => {
            const done = i < step;
            const current = i === step;
            return (
              <li key={s.key} className="flex-1">
                <button
                  type="button"
                  onClick={() => (i < step ? setStep(i) : goTo(i))}
                  aria-current={current ? 'step' : undefined}
                  className="flex w-full flex-col items-stretch gap-1.5 text-left cursor-pointer"
                >
                  <span
                    className={[
                      'h-1.5 rounded-full transition-colors',
                      done || current ? 'bg-primary' : 'bg-border',
                    ].join(' ')}
                  />
                  <span
                    className={[
                      'flex items-center gap-1 truncate text-[11px] sm:text-xs',
                      current ? 'font-semibold text-primary' : done ? 'text-ink' : 'text-muted',
                    ].join(' ')}
                  >
                    {done ? <Check size={12} aria-hidden /> : null}
                    {s.label}
                  </span>
                </button>
              </li>
            );
          })}
        </ol>
      </header>

      <main className="mx-auto max-w-2xl px-4 pb-40 pt-5">
        {error ? (
          <div className="mb-4">
            <ErrorBox message={error} />
          </div>
        ) : null}

        {step === 0 ? <StepCustomer customer={state.customer} onSelect={selectCustomer} /> : null}
        {step === 1 ? (
          <StepProducts products={products} quantities={state.quantities} onChange={(q) => patch({ quantities: q })} />
        ) : null}
        {step === 2 ? (
          <StepFulfillment
            state={state}
            patch={patch}
            customer={state.customer}
            zones={zones}
            drivers={drivers}
            settings={settings}
            totalQty={totalQuantity(state.quantities)}
          />
        ) : null}
        {step === 3 ? <StepSummary state={state} patch={patch} items={items} /> : null}
        {step === 4 ? <StepConfirm state={state} items={items} zone={zone} driver={driver} onEdit={setStep} /> : null}

        {submitError ? (
          <div className="mt-4">
            <ErrorBox message={submitError} />
          </div>
        ) : null}
      </main>

      <footer className="fixed inset-x-0 bottom-0 z-[500] border-t border-border bg-surface/95 pb-safe-bottom backdrop-blur">
        <div className="mx-auto max-w-2xl px-4 py-3">
          {stepError ? (
            <p role="alert" className="mb-2 text-sm text-destructive">
              {stepError}
            </p>
          ) : null}
          <div className="flex items-center gap-3">
            <Button variant="secondary" size="lg" onClick={back} aria-label={step === 0 ? 'ยกเลิก' : 'ย้อนกลับ'}>
              <ArrowLeft size={18} aria-hidden />
              <span className="hidden xs:inline">{step === 0 ? 'ยกเลิก' : 'ย้อนกลับ'}</span>
            </Button>
            <div className="min-w-0 flex-1 text-right">
              <p className="text-xs text-muted">ยอดสุทธิ</p>
              <p className="truncate text-lg font-bold tabular-nums text-primary">{formatMoney(totals.total)}</p>
            </div>
            {step < STEPS.length - 1 ? (
              <Button size="lg" onClick={next}>
                ถัดไป <ArrowRight size={18} aria-hidden />
              </Button>
            ) : (
              <Button size="lg" variant="success" onClick={submit} disabled={submitting}>
                <Check size={18} aria-hidden /> {submitting ? 'กำลังบันทึก…' : 'ยืนยันและออกบิล'}
              </Button>
            )}
          </div>
        </div>
      </footer>
    </div>
  );
}
