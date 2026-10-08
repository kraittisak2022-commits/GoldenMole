import type { ReactNode } from 'react';
import { draftTotals } from '../../data/orders';
import { formatMoney, formatNumber, formatPhone } from '../../lib/format';
import { PAYMENT_METHOD_LABEL, type Driver, type OrderItem, type Zone } from '../../types';
import StepTitle from './StepTitle';
import type { WizardState } from './wizardState';

interface Props {
  state: WizardState;
  items: OrderItem[];
  zone: Zone | undefined;
  driver: Driver | undefined;
  onEdit: (step: number) => void;
}

export default function StepConfirm({ state: s, items, zone, driver, onEdit }: Props) {
  const totals = draftTotals({ ...s, fulfillment: s.fulfillment ?? 'pickup', items });
  const c = s.customer;
  const delivery = s.fulfillment === 'delivery';
  const paidLabel =
    s.paymentMethod === 'credit' ? 'ค้างเครดิต (เคลียร์รายเดือน)' : s.paidNow ? 'จ่ายแล้ว — ออกใบเสร็จ' : 'ยังไม่จ่าย';

  return (
    <div className="step-enter flex flex-col gap-4">
      <StepTitle title="ตรวจสอบก่อนออกบิล" subtitle="แตะ 'แก้ไข' เพื่อกลับไปแก้ขั้นตอนนั้น" />

      <Block title="ลูกค้า" onEdit={() => onEdit(0)}>
        <p className="font-medium">{c?.name}</p>
        <p className="text-muted">{[c?.phone && formatPhone(c.phone), c?.address].filter(Boolean).join(' · ') || '—'}</p>
      </Block>

      <Block title="สินค้า" onEdit={() => onEdit(1)}>
        <ul className="flex flex-col gap-1">
          {items.map((it) => (
            <li key={it.productId ?? it.name} className="flex justify-between gap-3">
              <span>
                {it.name} <span className="text-muted">× {formatNumber(it.quantity)} {it.unit}</span>
              </span>
              <span className="tabular-nums">{formatMoney(it.amount)}</span>
            </li>
          ))}
        </ul>
      </Block>

      <Block title="การรับสินค้า" onEdit={() => onEdit(2)}>
        {delivery ? (
          <div className="flex flex-col gap-0.5">
            <p className="font-medium">
              จัดส่ง · ต.{zone?.name ?? '—'} · รถ {s.truckSize} คิว × {s.trips} เที่ยว
            </p>
            {s.deliveryAddress ? <p className="text-muted">{s.deliveryAddress}</p> : null}
            <p className="text-muted">
              ค่าส่ง {formatNumber(s.feePerTrip)}/เที่ยว
              {s.roadDistanceKm != null ? ` · ห่างถนนใหญ่ ${formatNumber(s.roadDistanceKm)} กม.` : ''}
            </p>
            <p className="text-muted">คนขับ: {driver ? driver.name : 'ยังไม่ระบุ'}</p>
          </div>
        ) : (
          <p className="font-medium">มารับเองที่ท่าทราย</p>
        )}
      </Block>

      <Block title="ชำระเงิน" onEdit={() => onEdit(3)}>
        <p className="font-medium">{s.paymentMethod ? PAYMENT_METHOD_LABEL[s.paymentMethod] : '—'}</p>
        <p className="text-muted">{paidLabel}</p>
        {s.note ? <p className="mt-1 text-muted">หมายเหตุ: {s.note}</p> : null}
      </Block>

      <div className="rounded border-2 border-primary bg-primary-soft/40 px-4 py-3">
        <dl className="flex flex-col gap-1 text-sm">
          <div className="flex justify-between">
            <dt className="text-muted">ค่าสินค้า</dt>
            <dd className="tabular-nums">{formatMoney(totals.subtotal)}</dd>
          </div>
          {delivery ? (
            <div className="flex justify-between">
              <dt className="text-muted">ค่าจัดส่ง</dt>
              <dd className="tabular-nums">{formatMoney(totals.deliveryTotal)}</dd>
            </div>
          ) : null}
          {totals.discountAmount ? (
            <div className="flex justify-between">
              <dt className="text-muted">ส่วนลด</dt>
              <dd className="tabular-nums text-success">-{formatMoney(totals.discountAmount)}</dd>
            </div>
          ) : null}
          <div className="mt-1 flex items-baseline justify-between border-t border-primary/20 pt-2">
            <dt className="font-semibold">ยอดสุทธิ</dt>
            <dd className="text-2xl font-bold tabular-nums text-primary">{formatMoney(totals.total)} บาท</dd>
          </div>
        </dl>
      </div>
    </div>
  );
}

function Block({ title, onEdit, children }: { title: string; onEdit: () => void; children: ReactNode }) {
  return (
    <section className="rounded border border-border bg-surface px-4 py-3 text-sm">
      <div className="mb-1 flex items-center justify-between">
        <h3 className="text-xs font-semibold uppercase tracking-wide text-muted">{title}</h3>
        <button type="button" onClick={onEdit} className="min-h-11 px-2 text-sm font-medium text-primary cursor-pointer">
          แก้ไข
        </button>
      </div>
      {children}
    </section>
  );
}
