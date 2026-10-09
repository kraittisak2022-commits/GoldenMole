import type { ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { AlertTriangle, ArrowRight, FileText } from 'lucide-react';
import DemoBadge from '../../components/DemoBadge';
import SourceBadge from '../../components/SourceBadge';
import Badge from '../../components/ui/Badge';
import { BILL_STAGE, stageAction, type BillStep, type BillSummary, type BillTotals } from '../../lib/billSummary';
import { formatDateShort, formatMoney } from '../../lib/format';
import type { Order } from '../../types';

export interface BillRowData {
  order: Order;
  summary: BillSummary;
  driverName: string;
}

function Steps({ steps, cancelled }: { steps: BillStep[]; cancelled: boolean }) {
  return (
    <ol className="grid w-full max-w-md auto-cols-fr grid-flow-col gap-1" aria-label="ขั้นตอน">
      {steps
        .filter((s) => s.state !== 'skip')
        .map((step) => {
          const current = step.state === 'current' && !cancelled;
          const color = cancelled
            ? 'bg-border'
            : step.state === 'done'
              ? 'bg-success'
              : current
                ? 'bg-warning'
                : 'bg-border';
          const status = step.state === 'done' ? 'เสร็จ' : current ? 'ขั้นตอนปัจจุบัน' : 'ยังไม่ถึง';
          return (
            <li key={step.key} className="flex min-w-0 flex-col gap-1">
              <span className={['h-1.5 rounded-full', color].join(' ')} aria-hidden />
              <span className={['truncate text-[11px]', current ? 'font-medium text-ink' : 'text-muted'].join(' ')}>
                {step.label}
                <span className="sr-only">: {status}</span>
              </span>
            </li>
          );
        })}
    </ol>
  );
}

function MoneyLine({
  label,
  children,
  strong,
  tone,
}: {
  label: string;
  children: ReactNode;
  strong?: boolean;
  tone?: 'warning';
}) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <dt
        className={[
          'min-w-0 truncate',
          tone === 'warning' ? 'text-warning' : strong ? 'font-medium text-ink' : 'text-muted',
        ].join(' ')}
      >
        {label}
      </dt>
      <dd className={['shrink-0 tabular-nums', tone === 'warning' ? 'text-warning' : ''].join(' ')}>{children}</dd>
    </div>
  );
}

function Money({ order: o, summary: s, driverName }: BillRowData) {
  const cancelled = s.stage === 'cancelled';
  const loss = s.deliveryMargin < 0 && !cancelled;
  return (
    <dl className="flex flex-col gap-1 rounded bg-subtle/70 px-3 py-2.5 text-sm">
      <MoneyLine label="ยอดบิล" strong>
        <span className="font-medium">{formatMoney(s.revenue)}</span>
      </MoneyLine>
      <MoneyLine label="ค่าสินค้า">{formatMoney(s.goods)}</MoneyLine>
      {o.fulfillment === 'delivery' ? (
        <>
          <MoneyLine label="ค่าส่งเก็บลูกค้า">{formatMoney(s.deliveryFee)}</MoneyLine>
          <MoneyLine label={driverName ? `ค่ารถ · ${driverName}` : 'ค่ารถคนขับ'}>
            {s.driverCost || s.driverCostEstimated ? (
              <span
                className={s.driverCostEstimated ? 'text-muted' : ''}
                title={s.driverCostEstimated ? 'ประมาณตามเรท ยังไม่จ่าย' : 'จ่ายแล้ว'}
              >
                {s.driverCostEstimated ? '≈ ' : ''}−{formatMoney(s.driverCost)}
              </span>
            ) : (
              <span className="text-muted">—</span>
            )}
          </MoneyLine>
        </>
      ) : null}
      <div className="my-0.5 border-t border-border" />
      <MoneyLine label="คงเหลือเข้าร้าน" strong>
        <span className="inline-flex items-center gap-1">
          {loss ? <AlertTriangle size={14} className="text-warning" aria-label="ขาดทุนค่าส่ง" /> : null}
          <b className={cancelled ? 'text-muted' : 'text-success'}>{formatMoney(s.net)}</b>
        </span>
      </MoneyLine>
      {s.receivable ? (
        <MoneyLine label="ค้างรับ" tone="warning">
          {formatMoney(s.receivable)}
        </MoneyLine>
      ) : null}
    </dl>
  );
}

function BillRow(row: BillRowData) {
  const { order: o, summary: s, driverName } = row;
  const meta = BILL_STAGE[s.stage];
  const action = stageAction(o, s.stage);
  const cancelled = s.stage === 'cancelled';
  const fulfillment =
    o.fulfillment === 'delivery' ? `ส่ง ${o.trips} เที่ยว${driverName ? ` · ${driverName}` : ''}` : 'มารับเอง';

  return (
    <li className={['px-4 py-4 sm:px-5', cancelled ? 'opacity-60' : ''].join(' ')}>
      <div className="grid gap-3 lg:grid-cols-[minmax(0,1fr)_18rem] lg:gap-6">
        <div className="flex min-w-0 flex-col gap-2">
          <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
            <Link
              to={`/orders/${o.id}`}
              className={['max-w-full truncate font-semibold hover:text-primary', cancelled ? 'line-through' : ''].join(' ')}
            >
              {o.customer.name}
            </Link>
            <Badge tone={meta.tone}>{meta.label}</Badge>
          </div>
          <p className="flex flex-wrap items-center gap-x-1.5 gap-y-1 text-xs text-muted tabular-nums">
            <span>
              {o.orderNo} · {formatDateShort(o.orderDate)}
            </span>
            <SourceBadge source={o.source} />
            {o.demo ? <DemoBadge /> : null}
            <span className="min-w-0 truncate">· {fulfillment}</span>
          </p>
          <Steps steps={s.steps} cancelled={cancelled} />
          <div className="flex flex-wrap gap-x-4 text-sm">
            {action ? (
              <Link to={action.to} className="inline-flex min-h-10 items-center gap-1 font-medium text-primary hover:underline">
                {action.label} <ArrowRight size={14} aria-hidden />
              </Link>
            ) : null}
            <Link to={`/bill/order/${o.id}`} className="inline-flex min-h-10 items-center gap-1 text-muted hover:text-primary">
              <FileText size={14} aria-hidden /> ใบส่งของ
            </Link>
          </div>
        </div>
        <Money {...row} />
      </div>
    </li>
  );
}

export default function BillList({ rows, totals }: { rows: BillRowData[]; totals: BillTotals }) {
  return (
    <>
      <ul className="divide-y divide-border">
        {rows.map((r) => (
          <BillRow key={r.order.id} {...r} />
        ))}
      </ul>
      <div className="flex flex-wrap items-center justify-between gap-x-4 gap-y-1 border-t border-border bg-subtle/60 px-4 py-3 text-sm sm:px-5">
        <span className="text-muted">{totals.count} บิล</span>
        <span className="tabular-nums">
          ยอดบิล {formatMoney(totals.revenue)}
          <span className="text-muted"> · ค่ารถ −{formatMoney(totals.driverCost)}</span> · เหลือ{' '}
          <b className="text-success">{formatMoney(totals.net)}</b>
        </span>
      </div>
    </>
  );
}
