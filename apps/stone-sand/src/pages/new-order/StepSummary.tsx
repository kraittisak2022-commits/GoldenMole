import { Banknote, CalendarClock, Wallet, Landmark } from 'lucide-react';
import type { ReactNode } from 'react';
import Field from '../../components/ui/Field';
import Input from '../../components/ui/Input';
import Textarea from '../../components/ui/Textarea';
import { lineDiscount } from '../../calc/pricing';
import { draftTotals } from '../../data/orders';
import { formatMoney, formatNumber } from '../../lib/format';
import { ORDER_SOURCE_LABEL, PAYMENT_METHOD_LABEL, type OrderItem, type PaymentMethod } from '../../types';
import StepTitle from './StepTitle';
import { defaultPaidNow, type WizardState } from './wizardState';

interface Props {
  state: WizardState;
  patch: (p: Partial<WizardState>) => void;
  items: OrderItem[];
}

const METHODS: { id: PaymentMethod; icon: ReactNode; hint: string }[] = [
  { id: 'cash', icon: <Banknote size={22} aria-hidden />, hint: 'รับเงินสดแล้ว' },
  { id: 'transfer', icon: <Landmark size={22} aria-hidden />, hint: 'โอน / พร้อมเพย์' },
  { id: 'cod', icon: <Wallet size={22} aria-hidden />, hint: 'เก็บเงินตอนส่งของ' },
  { id: 'credit', icon: <CalendarClock size={22} aria-hidden />, hint: 'รวมบิลเคลียร์สิ้นเดือน' },
];

export default function StepSummary({ state: s, patch, items }: Props) {
  const totals = draftTotals({ ...s, fulfillment: s.fulfillment ?? 'pickup', items });
  const delivery = s.fulfillment === 'delivery';

  const chooseMethod = (m: PaymentMethod) => patch({ paymentMethod: m, paidNow: defaultPaidNow(m) });

  return (
    <div className="step-enter flex flex-col gap-5">
      <StepTitle title="สรุปยอดและการชำระเงิน" subtitle={s.source ? `ออเดอร์${ORDER_SOURCE_LABEL[s.source]}` : undefined} />

      <section className="rounded border border-border bg-surface">
        <ul className="divide-y divide-border">
          {items.map((it) => {
            const load = it.productId ? s.loads[it.productId] : undefined;
            const off = lineDiscount(it.unitPrice, it.quantity, it.discountPerUnit);
            return (
              <li key={it.productId ?? it.name} className="flex flex-col gap-2 px-4 py-3 text-sm">
                <div className="flex items-start justify-between gap-3">
                  <div>
                    <p className="font-medium">{it.name}</p>
                    {load ? (
                      <p className="text-muted">
                        {formatNumber(load.perTrip)} {it.unit} × {load.trips} เที่ยว = {formatNumber(it.quantity)} {it.unit}
                      </p>
                    ) : null}
                    <p className="text-muted">
                      {formatNumber(it.quantity)} {it.unit} × {formatNumber(it.unitPrice)} บาท
                    </p>
                  </div>
                  <div className="text-right">
                    <p className={['tabular-nums', off ? 'text-muted line-through' : ''].join(' ')}>{formatMoney(it.amount)}</p>
                    {off ? <p className="font-medium tabular-nums">{formatMoney(it.amount - off)}</p> : null}
                  </div>
                </div>
                {it.productId ? (
                  <label className="flex items-center gap-2">
                    <span className="shrink-0 text-muted">ลดคิวละ</span>
                    <span className="w-28">
                      <Input
                        aria-label={`ส่วนลดต่อ${it.unit} ${it.name}`}
                        type="number"
                        inputMode="decimal"
                        min={0}
                        max={it.unitPrice}
                        value={s.unitDiscounts[it.productId] || ''}
                        placeholder="0"
                        className="min-h-10 px-3 text-right tabular-nums"
                        onChange={(e) => {
                          const v = Math.min(it.unitPrice, Math.max(0, Number(e.target.value) || 0));
                          patch({ unitDiscounts: { ...s.unitDiscounts, [it.productId as string]: v } });
                        }}
                      />
                    </span>
                    <span className="text-muted">บาท</span>
                    {off ? (
                      <span className="ml-auto text-right text-success tabular-nums">
                        เหลือคิวละ {formatNumber(it.unitPrice - (it.discountPerUnit || 0))} · ลด {formatMoney(off)}
                      </span>
                    ) : null}
                  </label>
                ) : null}
              </li>
            );
          })}
          {delivery ? (
            <li className="flex items-start justify-between gap-3 px-4 py-3 text-sm">
              <div>
                <p className="font-medium">ค่าจัดส่ง</p>
                <p className="text-muted">
                  {formatNumber(s.feePerTrip)} × {s.trips} เที่ยว
                  {s.remoteSurcharge ? ` + ที่กันดาร ${formatNumber(s.remoteSurcharge)}` : ''}
                </p>
              </div>
              <p className="tabular-nums">{formatMoney(totals.deliveryTotal)}</p>
            </li>
          ) : null}
        </ul>

        <div className="border-t border-border px-4 py-3">
          <p className="mb-2 text-sm font-medium">ส่วนลดท้ายบิล</p>
          <div className="flex gap-2">
            <div className="flex shrink-0 rounded border border-border p-0.5" role="radiogroup" aria-label="ประเภทส่วนลด">
              {(['baht', 'percent'] as const).map((t) => (
                <button
                  key={t}
                  type="button"
                  role="radio"
                  aria-checked={s.discountType === t}
                  onClick={() => t !== s.discountType && patch({ discountType: t, discountValue: 0 })}
                  className={[
                    'min-h-10 min-w-12 rounded px-3 text-sm font-medium cursor-pointer',
                    s.discountType === t ? 'bg-primary text-primary-foreground' : 'text-muted hover:text-ink',
                  ].join(' ')}
                >
                  {t === 'baht' ? 'บาท' : '%'}
                </button>
              ))}
            </div>
            <Input
              aria-label="ส่วนลด"
              type="number"
              inputMode="decimal"
              min={0}
              max={s.discountType === 'percent' ? 100 : undefined}
              value={s.discountValue || ''}
              placeholder="0"
              onChange={(e) => {
                const v = Math.max(0, Number(e.target.value) || 0);
                patch({ discountValue: s.discountType === 'percent' ? Math.min(100, v) : v });
              }}
            />
          </div>
          {s.discountType === 'percent' ? <p className="mt-1 text-xs text-muted">% คิดจากค่าสินค้าเท่านั้น ไม่รวมค่าส่ง</p> : null}
        </div>

        <dl className="flex flex-col gap-1.5 border-t border-border px-4 py-3 text-sm">
          <Row label="ค่าสินค้า" value={formatMoney(totals.subtotal)} />
          {delivery ? <Row label="ค่าจัดส่ง" value={formatMoney(totals.deliveryTotal)} /> : null}
          {totals.itemDiscount ? (
            <Row label="ส่วนลดต่อคิว" value={`-${formatMoney(totals.itemDiscount)}`} tone="text-success" />
          ) : null}
          {totals.discountAmount - totals.itemDiscount > 0 ? (
            <Row label="ส่วนลดท้ายบิล" value={`-${formatMoney(totals.discountAmount - totals.itemDiscount)}`} tone="text-success" />
          ) : null}
          <div className="mt-1 flex items-baseline justify-between border-t border-border pt-2">
            <dt className="font-semibold">ยอดสุทธิ</dt>
            <dd className="text-2xl font-bold tabular-nums text-primary">{formatMoney(totals.total)}</dd>
          </div>
        </dl>
      </section>

      <section className="flex flex-col gap-3">
        <h3 className="font-medium">วิธีชำระเงิน *</h3>
        <div className="grid grid-cols-2 gap-3" role="radiogroup" aria-label="วิธีชำระเงิน">
          {METHODS.map((m) => {
            const active = s.paymentMethod === m.id;
            return (
              <button
                key={m.id}
                type="button"
                role="radio"
                aria-checked={active}
                onClick={() => chooseMethod(m.id)}
                className={[
                  'flex min-h-20 flex-col items-start gap-1 rounded border-2 p-3 text-left transition-colors cursor-pointer',
                  active ? 'border-primary bg-primary-soft/50' : 'border-border bg-surface hover:bg-subtle',
                ].join(' ')}
              >
                <span className={active ? 'text-primary' : 'text-muted'}>{m.icon}</span>
                <span className="font-semibold">{PAYMENT_METHOD_LABEL[m.id]}</span>
                <span className="text-xs text-muted">{m.hint}</span>
              </button>
            );
          })}
        </div>

        {s.paymentMethod && s.paymentMethod !== 'credit' ? (
          <label className="flex min-h-11 cursor-pointer items-center gap-3 rounded border border-border bg-surface p-3 text-sm">
            <input
              type="checkbox"
              className="h-5 w-5 accent-[var(--color-primary)]"
              checked={s.paidNow}
              onChange={(e) => patch({ paidNow: e.target.checked })}
            />
            <span>
              <b>ได้รับเงินแล้ว</b> — ออกใบเสร็จรับเงินทันที
            </span>
          </label>
        ) : null}
        {s.paymentMethod === 'credit' ? (
          <p className="rounded bg-primary-soft px-3 py-2.5 text-sm text-primary">
            ออกใบส่งของก่อน แล้วรวมยอดไปเคลียร์ในใบวางบิลรายเดือน
          </p>
        ) : null}
      </section>

      <Field id="o-note" label="หมายเหตุ">
        <Textarea
          id="o-note"
          rows={2}
          value={s.note}
          onChange={(e) => patch({ note: e.target.value })}
          placeholder="เช่น ส่งช่วงเช้า เทกองหน้าบ้าน"
        />
      </Field>
    </div>
  );
}

function Row({ label, value, tone = '' }: { label: string; value: string; tone?: string }) {
  return (
    <div className="flex justify-between">
      <dt className="text-muted">{label}</dt>
      <dd className={`tabular-nums ${tone}`}>{value}</dd>
    </div>
  );
}
