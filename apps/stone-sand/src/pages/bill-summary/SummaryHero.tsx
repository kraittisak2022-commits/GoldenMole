import Card from '../../components/ui/Card';
import { netMargin, type BillTotals } from '../../lib/billSummary';
import { formatMoney } from '../../lib/format';

function Stat({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <div className="min-w-0 bg-surface px-4 py-3 sm:px-5">
      <dt className="text-xs text-muted">{label}</dt>
      <dd className="mt-0.5 whitespace-nowrap text-[15px] font-semibold tabular-nums sm:text-lg">{value}</dd>
      {hint ? <dd className="text-xs text-muted">{hint}</dd> : null}
    </div>
  );
}

/** Period totals: what the shop keeps, how the bill splits, and what is still owed. */
export default function SummaryHero({ totals, periodLabel }: { totals: BillTotals; periodLabel: string }) {
  const margin = netMargin(totals.net, totals.revenue);
  const keepPct = totals.revenue > 0 ? Math.min(100, Math.max(0, (totals.net / totals.revenue) * 100)) : 0;

  return (
    <Card className="mb-4 overflow-hidden">
      <div className="grid gap-4 p-4 sm:p-5 lg:grid-cols-[minmax(0,1fr)_auto] lg:items-end">
        <div className="min-w-0">
          <p className="text-sm text-muted">คงเหลือเข้าร้าน · {periodLabel}</p>
          <p className="mt-1 whitespace-nowrap text-3xl font-semibold tracking-tight text-success tabular-nums xl:text-4xl">
            {formatMoney(totals.net)}
          </p>
          <p className="mt-1 text-sm text-muted">
            จาก {totals.count} บิล{margin != null ? ` · ${margin}% ของยอดบิล` : ''}
          </p>
        </div>
        <div className="min-w-0 rounded border border-border px-4 py-3 lg:min-w-56">
          <p className="text-sm text-muted">ค้างรับ</p>
          <p
            className={[
              'whitespace-nowrap text-xl font-semibold tabular-nums',
              totals.receivable > 0 ? 'text-warning' : 'text-ink',
            ].join(' ')}
          >
            {formatMoney(totals.receivable)}
          </p>
          <p className="text-xs text-muted">รับแล้ว {formatMoney(totals.received)}</p>
        </div>
      </div>

      {totals.revenue > 0 ? (
        <div className="px-4 pb-4 sm:px-5">
          <div
            className="flex h-2.5 overflow-hidden rounded-full bg-border"
            role="img"
            aria-label={`คงเหลือ ${Math.round(keepPct)}% ค่ารถคนขับ ${Math.round(100 - keepPct)}% ของยอดบิล`}
          >
            <span className="bg-success" style={{ width: `${keepPct}%` }} />
            <span className="bg-warning" style={{ width: `${100 - keepPct}%` }} />
          </div>
          <div className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted">
            <span className="inline-flex items-center gap-1.5">
              <span className="h-2 w-2 rounded-full bg-success" aria-hidden /> คงเหลือเข้าร้าน
            </span>
            <span className="inline-flex items-center gap-1.5">
              <span className="h-2 w-2 rounded-full bg-warning" aria-hidden /> ค่ารถคนขับ
            </span>
          </div>
        </div>
      ) : null}

      <dl className="grid grid-cols-2 gap-px border-t border-border bg-border xl:grid-cols-4">
        <Stat label="ยอดบิล" value={formatMoney(totals.revenue)} />
        <Stat label="ค่าสินค้า" value={formatMoney(totals.goods)} hint="หลังหักส่วนลด" />
        <Stat label="ค่าส่งเก็บลูกค้า" value={formatMoney(totals.deliveryFee)} hint="หลังหักส่วนลดค่าส่ง" />
        <Stat
          label="หักค่ารถคนขับ"
          value={`−${formatMoney(totals.driverCost)}`}
          hint={totals.driverCostPending ? `ยังไม่จ่าย ${formatMoney(totals.driverCostPending)}` : 'จ่ายครบแล้ว'}
        />
      </dl>
    </Card>
  );
}
