import { useMemo, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { AlertTriangle, ArrowRight, Download, FileText, Search } from 'lucide-react';
import { useAuth } from '../auth/AuthProvider';
import DemoBadge from '../components/DemoBadge';
import SourceBadge from '../components/SourceBadge';
import SourceToggle from '../components/SourceToggle';
import Badge from '../components/ui/Badge';
import Button from '../components/ui/Button';
import Card from '../components/ui/Card';
import Chip from '../components/ui/Chip';
import Input from '../components/ui/Input';
import PageHeader from '../components/ui/PageHeader';
import Select from '../components/ui/Select';
import { Empty, ErrorBox, Loading } from '../components/ui/States';
import { useCatalog } from '../context/CatalogProvider';
import { listOrders } from '../data/orders';
import { useAsync } from '../hooks/useAsync';
import {
  BILL_STAGE,
  BILL_STAGES,
  billSummaryCsv,
  netMargin,
  stageAction,
  summarizeBill,
  totalBills,
  type BillStage,
  type BillStep,
  type BillSummary,
} from '../lib/billSummary';
import { DATE_RANGES, DATE_RANGE_LABEL, parseDateRange, rangeFrom } from '../lib/dateRange';
import { formatDateShort, formatMoney, toIsoDate } from '../lib/format';
import { matchesSearch } from '../lib/orderStatus';
import { ORDER_SOURCES, type Order, type OrderSource } from '../types';

type StageFilter = 'all' | 'open' | BillStage;
type Sort = 'latest' | 'oldest' | 'netDesc' | 'netAsc' | 'receivable';

const SORT_LABEL: Record<Sort, string> = {
  latest: 'ล่าสุดก่อน',
  oldest: 'เก่าสุดก่อน',
  netDesc: 'เหลือมากสุด',
  netAsc: 'เหลือน้อยสุด',
  receivable: 'ค้างรับมากสุด',
};

interface Row {
  order: Order;
  summary: BillSummary;
  driverName: string;
}

const isOpen = (s: BillStage) => s !== 'done' && s !== 'cancelled';

function sortRows(rows: Row[], sort: Sort): Row[] {
  const byDate = (a: Row, b: Row) =>
    a.order.orderDate.localeCompare(b.order.orderDate) || a.order.createdAt.localeCompare(b.order.createdAt);
  const sorted = [...rows];
  if (sort === 'latest') sorted.sort((a, b) => byDate(b, a));
  if (sort === 'oldest') sorted.sort(byDate);
  if (sort === 'netDesc') sorted.sort((a, b) => b.summary.net - a.summary.net);
  if (sort === 'netAsc') sorted.sort((a, b) => a.summary.net - b.summary.net);
  if (sort === 'receivable') sorted.sort((a, b) => b.summary.receivable - a.summary.receivable);
  return sorted;
}

function downloadCsv(rows: Row[]) {
  const blob = new Blob([billSummaryCsv(rows)], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = `สรุปบิล-${toIsoDate()}.csv`;
  link.click();
  URL.revokeObjectURL(url);
}

export default function BillSummaryPage() {
  const [params, setParams] = useSearchParams();
  const { lockedSource } = useAuth();
  const { zoneById, driverById, settings } = useCatalog();
  const range = parseDateRange(params.get('r'));
  const sourceParam = params.get('source');
  const source = lockedSource ? null : (ORDER_SOURCES.find((s) => s === sourceParam) ?? null);
  const stageParam = params.get('stage');
  const stage: StageFilter =
    stageParam === 'open' || BILL_STAGES.some((s) => s.id === stageParam) ? (stageParam as StageFilter) : 'all';
  const sort = (Object.keys(SORT_LABEL) as Sort[]).find((s) => s === params.get('sort')) ?? 'latest';
  const [query, setQuery] = useState('');

  const setParam = (key: string, value: string | null) => {
    const next = new URLSearchParams(params);
    if (value) next.set(key, value);
    else next.delete(key);
    setParams(next, { replace: true });
  };

  const { data, error, loading } = useAsync(
    () => listOrders({ from: rangeFrom(range), limit: 2000 }),
    [range],
    'bill-summary-range',
  );

  const rows = useMemo<Row[]>(
    () =>
      (data ?? []).map((o) => ({
        order: o,
        summary: summarizeBill(o, zoneById, settings.delivery),
        driverName: driverById(o.driverId)?.name ?? '',
      })),
    [data, zoneById, driverById, settings.delivery],
  );

  const sourceCounts = useMemo(() => {
    const c = { all: rows.length } as Record<OrderSource | 'all', number>;
    for (const s of ORDER_SOURCES) c[s] = rows.filter((r) => r.order.source === s).length;
    return c;
  }, [rows]);
  const searched = useMemo(
    () => rows.filter((r) => (!source || r.order.source === source) && matchesSearch(r.order, query)),
    [rows, source, query],
  );
  const stageCounts = useMemo(() => {
    const c = { all: searched.length, open: 0 } as Record<StageFilter, number>;
    for (const s of BILL_STAGES) c[s.id] = 0;
    for (const r of searched) {
      c[r.summary.stage] += 1;
      if (isOpen(r.summary.stage)) c.open += 1;
    }
    return c;
  }, [searched]);
  const visible = useMemo(() => {
    const filtered = searched.filter((r) =>
      stage === 'all' ? true : stage === 'open' ? isOpen(r.summary.stage) : r.summary.stage === stage,
    );
    return sortRows(filtered, sort);
  }, [searched, stage, sort]);

  const totals = useMemo(() => totalBills(searched.map((r) => r.summary)), [searched]);
  const visibleTotals = useMemo(() => totalBills(visible.map((r) => r.summary)), [visible]);
  const margin = netMargin(totals.net, totals.revenue);
  const losses = searched.filter((r) => r.summary.deliveryMargin < 0 && r.summary.stage !== 'cancelled').length;

  return (
    <div>
      <PageHeader
        title="สรุปบิล"
        subtitle="แต่ละบิลได้ค่าของเท่าไร หักค่ารถเท่าไร เหลือเข้าร้านเท่าไร และติดขั้นตอนไหน"
        actions={
          <Button variant="secondary" onClick={() => downloadCsv(visible)} disabled={!visible.length}>
            <Download size={18} aria-hidden /> ส่งออก Excel
          </Button>
        }
      />

      <div className="mb-3 flex flex-col gap-2 sm:flex-row">
        <div className="relative flex-1">
          <Search size={18} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted" aria-hidden />
          <Input
            aria-label="ค้นหาบิล"
            placeholder="ค้นหาชื่อ ชื่อเรียก เบอร์โทร หรือเลขที่บิล"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            className="pl-10"
          />
        </div>
        <Select aria-label="ช่วงวันที่" value={range} onChange={(e) => setParam('r', e.target.value)} className="sm:w-40">
          {DATE_RANGES.map((r) => (
            <option key={r} value={r}>
              {DATE_RANGE_LABEL[r]}
            </option>
          ))}
        </Select>
        <Select
          aria-label="เรียงตาม"
          value={sort}
          onChange={(e) => setParam('sort', e.target.value === 'latest' ? null : e.target.value)}
          className="sm:w-44"
        >
          {(Object.keys(SORT_LABEL) as Sort[]).map((s) => (
            <option key={s} value={s}>
              {SORT_LABEL[s]}
            </option>
          ))}
        </Select>
      </div>

      {lockedSource ? null : (
        <SourceToggle className="mb-4" value={source} onChange={(s) => setParam('source', s)} counts={sourceCounts} />
      )}

      {error ? <ErrorBox message={error} /> : null}
      {loading && !data ? (
        <Loading />
      ) : (
        <>
          <section aria-label="ภาพรวม" className="mb-4 grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
            <Kpi label="ยอดบิลรวม" value={formatMoney(totals.revenue)} hint={`${totals.count} บิล`} />
            <Kpi label="ค่าสินค้า" value={formatMoney(totals.goods)} hint="หลังหักส่วนลด" />
            <Kpi label="ค่าส่งเก็บลูกค้า" value={formatMoney(totals.deliveryFee)} hint="หลังหักส่วนลดค่าส่ง" />
            <Kpi
              label="หักค่ารถคนขับ"
              value={formatMoney(totals.driverCost)}
              hint={totals.driverCostPending ? `ยังไม่จ่าย ${formatMoney(totals.driverCostPending)}` : 'จ่ายครบแล้ว'}
            />
            <Kpi
              label="คงเหลือเข้าร้าน"
              value={formatMoney(totals.net)}
              hint={margin != null ? `${margin}% ของยอดบิล` : undefined}
              tone="success"
            />
            <Kpi
              label="ค้างรับ"
              value={formatMoney(totals.receivable)}
              hint={`รับแล้ว ${formatMoney(totals.received)}`}
              tone={totals.receivable > 0 ? 'warning' : undefined}
            />
          </section>

          {losses ? (
            <p className="mb-4 flex items-start gap-2 rounded border border-warning/30 bg-warning-soft px-3 py-2 text-sm text-warning">
              <AlertTriangle size={18} className="mt-0.5 shrink-0" aria-hidden />
              มี {losses} บิลที่ค่ารถคนขับสูงกว่าค่าส่งที่เก็บลูกค้า (ขาดทุนค่าส่ง) เรียง "เหลือน้อยสุด" เพื่อดู
            </p>
          ) : null}

          <div className="-mx-4 mb-4 flex gap-2 overflow-x-auto px-4 pb-1 sm:mx-0 sm:flex-wrap sm:px-0">
            <Chip active={stage === 'all'} onClick={() => setParam('stage', null)} count={stageCounts.all}>
              ทั้งหมด
            </Chip>
            <Chip active={stage === 'open'} onClick={() => setParam('stage', 'open')} count={stageCounts.open}>
              ต้องตามงาน
            </Chip>
            {BILL_STAGES.filter((s) => stageCounts[s.id] > 0 || stage === s.id).map((s) => (
              <Chip key={s.id} active={stage === s.id} onClick={() => setParam('stage', s.id)} count={stageCounts[s.id]}>
                {s.label}
              </Chip>
            ))}
          </div>

          <Card className="overflow-hidden">
            {visible.length ? (
              <>
                <BillTable rows={visible} totals={visibleTotals} />
                <ul className="divide-y divide-border lg:hidden">
                  {visible.map((r) => (
                    <li key={r.order.id}>
                      <BillCard row={r} />
                    </li>
                  ))}
                </ul>
                <div className="flex flex-wrap justify-between gap-2 border-t border-border bg-subtle/60 px-4 py-3 text-sm lg:hidden">
                  <span className="text-muted">{visible.length} รายการ</span>
                  <span className="tabular-nums">
                    ยอดบิล {formatMoney(visibleTotals.revenue)} · เหลือ{' '}
                    <b className="text-success">{formatMoney(visibleTotals.net)}</b>
                  </span>
                </div>
              </>
            ) : (
              <Empty title={query ? 'ไม่พบบิลที่ค้นหา' : 'ยังไม่มีบิลในช่วงนี้'} />
            )}
          </Card>
          <p className="mt-3 text-xs text-muted">
            ค่ารถที่มีเครื่องหมาย ≈ คือค่ารถตามเรทตำบลที่ยังไม่ได้จ่ายคนขับ ยอดจริงจะใช้ตามที่บันทึกตอนเคลียร์ค่ารถ · บิลที่ยกเลิกไม่นับรวมยอด
          </p>
        </>
      )}
    </div>
  );
}

function Kpi({ label, value, hint, tone }: { label: string; value: string; hint?: string; tone?: 'success' | 'warning' }) {
  const color = tone === 'success' ? 'text-success' : tone === 'warning' ? 'text-warning' : 'text-ink';
  return (
    <div className="min-w-0 rounded border border-border bg-surface p-4">
      <p className="text-sm text-muted">{label}</p>
      <p className={['mt-1 truncate text-xl font-semibold tabular-nums', color].join(' ')}>{value}</p>
      {hint ? <p className="truncate text-xs text-muted">{hint}</p> : null}
    </div>
  );
}

function DriverCost({ s }: { s: BillSummary }) {
  if (!s.driverCost && !s.driverCostEstimated) return <span className="text-muted">—</span>;
  return (
    <span className={s.driverCostEstimated ? 'text-muted' : ''} title={s.driverCostEstimated ? 'ประมาณตามเรท ยังไม่จ่าย' : 'จ่ายแล้ว'}>
      {s.driverCostEstimated ? '≈ ' : ''}−{formatMoney(s.driverCost)}
    </span>
  );
}

function Net({ s }: { s: BillSummary }) {
  return (
    <span className="inline-flex items-center gap-1">
      {s.deliveryMargin < 0 && s.stage !== 'cancelled' ? (
        <AlertTriangle size={14} className="text-warning" aria-label="ขาดทุนค่าส่ง" />
      ) : null}
      <b className={s.stage === 'cancelled' ? 'text-muted' : 'text-success'}>{formatMoney(s.net)}</b>
    </span>
  );
}

function StageCell({ order, s }: { order: Order; s: BillSummary }) {
  const meta = BILL_STAGE[s.stage];
  const action = stageAction(order, s.stage);
  return (
    <div className="flex flex-col items-start gap-1.5">
      <Badge tone={meta.tone}>{meta.label}</Badge>
      <Steps steps={s.steps} cancelled={s.stage === 'cancelled'} />
      {action ? (
        <Link to={action.to} className="inline-flex items-center gap-1 text-xs font-medium text-primary hover:underline">
          {action.label} <ArrowRight size={12} aria-hidden />
        </Link>
      ) : null}
    </div>
  );
}

function Steps({ steps, cancelled, labels }: { steps: BillStep[]; cancelled: boolean; labels?: boolean }) {
  const shown = steps.filter((s) => s.state !== 'skip');
  return (
    <ol className="flex w-full max-w-56 gap-1" aria-label="ขั้นตอน">
      {shown.map((step) => {
        const color = cancelled
          ? 'bg-border'
          : step.state === 'done'
            ? 'bg-success'
            : step.state === 'current'
              ? 'bg-warning'
              : 'bg-border';
        const status = step.state === 'done' ? 'เสร็จ' : step.state === 'current' ? 'ขั้นตอนปัจจุบัน' : 'ยังไม่ถึง';
        return (
          <li key={step.key} className="flex min-w-0 flex-1 flex-col gap-1" title={`${step.label}: ${status}`}>
            <span className={['h-1.5 rounded-full', color].join(' ')} aria-hidden />
            {labels ? (
              <span
                className={[
                  'truncate text-[11px]',
                  step.state === 'current' && !cancelled ? 'font-medium text-ink' : 'text-muted',
                ].join(' ')}
              >
                {step.label}
              </span>
            ) : (
              <span className="sr-only">
                {step.label}: {status}
              </span>
            )}
          </li>
        );
      })}
    </ol>
  );
}

function BillTable({ rows, totals }: { rows: Row[]; totals: ReturnType<typeof totalBills> }) {
  const th = 'px-3 py-2 font-medium';
  const num = 'px-3 py-3 text-right tabular-nums';
  return (
    <div className="hidden overflow-x-auto lg:block">
      <table className="w-full text-sm">
        <thead className="border-b border-border bg-subtle/60 text-left text-xs text-muted">
          <tr>
            <th className={th}>บิล</th>
            <th className={th}>ลูกค้า</th>
            <th className={`${th} text-right`}>ยอดบิล</th>
            <th className={`${th} text-right`}>ค่าสินค้า</th>
            <th className={`${th} text-right`}>ค่าส่ง</th>
            <th className={`${th} text-right`}>ค่ารถคนขับ</th>
            <th className={`${th} text-right`}>คงเหลือ</th>
            <th className={th}>ขั้นตอน</th>
          </tr>
        </thead>
        <tbody className="divide-y divide-border">
          {rows.map(({ order: o, summary: s, driverName }) => (
            <tr key={o.id} className={['align-top hover:bg-subtle/50', s.stage === 'cancelled' ? 'opacity-60' : ''].join(' ')}>
              <td className="px-3 py-3">
                <Link to={`/orders/${o.id}`} className="font-medium text-primary hover:underline">
                  {o.orderNo}
                </Link>
                <div className="mt-0.5 flex flex-wrap items-center gap-1 text-xs text-muted">
                  {formatDateShort(o.orderDate)} <SourceBadge source={o.source} />
                  {o.demo ? <DemoBadge /> : null}
                </div>
                <Link
                  to={`/bill/order/${o.id}`}
                  className="mt-1 inline-flex items-center gap-1 text-xs text-muted hover:text-primary"
                >
                  <FileText size={12} aria-hidden /> ใบส่งของ
                </Link>
              </td>
              <td className="max-w-48 px-3 py-3">
                <p className={['truncate font-medium', s.stage === 'cancelled' ? 'line-through' : ''].join(' ')}>
                  {o.customer.name}
                </p>
                <p className="truncate text-xs text-muted">
                  {o.fulfillment === 'delivery' ? `ส่ง ${o.trips} เที่ยว${driverName ? ` · ${driverName}` : ''}` : 'มารับเอง'}
                </p>
              </td>
              <td className={`${num} font-medium`}>{formatMoney(s.revenue)}</td>
              <td className={num}>{formatMoney(s.goods)}</td>
              <td className={num}>{s.deliveryFee ? formatMoney(s.deliveryFee) : <span className="text-muted">—</span>}</td>
              <td className={num}>
                <DriverCost s={s} />
              </td>
              <td className={num}>
                <Net s={s} />
                {s.receivable ? <p className="text-xs text-warning">ค้างรับ {formatMoney(s.receivable)}</p> : null}
              </td>
              <td className="px-3 py-3">
                <StageCell order={o} s={s} />
              </td>
            </tr>
          ))}
        </tbody>
        <tfoot className="border-t-2 border-border bg-subtle/60 font-semibold">
          <tr>
            <td className="px-3 py-3" colSpan={2}>
              รวม {totals.count} บิล
            </td>
            <td className={num}>{formatMoney(totals.revenue)}</td>
            <td className={num}>{formatMoney(totals.goods)}</td>
            <td className={num}>{formatMoney(totals.deliveryFee)}</td>
            <td className={num}>−{formatMoney(totals.driverCost)}</td>
            <td className={`${num} text-success`}>{formatMoney(totals.net)}</td>
            <td className="px-3 py-3 text-xs font-normal text-muted">
              {totals.receivable ? `ค้างรับ ${formatMoney(totals.receivable)}` : 'รับเงินครบ'}
            </td>
          </tr>
        </tfoot>
      </table>
    </div>
  );
}

function BillCard({ row: { order: o, summary: s, driverName } }: { row: Row }) {
  const meta = BILL_STAGE[s.stage];
  const action = stageAction(o, s.stage);
  const cancelled = s.stage === 'cancelled';
  return (
    <div className={['flex flex-col gap-3 px-4 py-4', cancelled ? 'opacity-60' : ''].join(' ')}>
      <div className="flex items-start justify-between gap-3">
        <Link to={`/orders/${o.id}`} className="min-w-0">
          <p className={['truncate font-medium', cancelled ? 'line-through' : ''].join(' ')}>{o.customer.name}</p>
          <p className="mt-0.5 flex flex-wrap items-center gap-1 text-xs text-muted tabular-nums">
            {o.orderNo} · {formatDateShort(o.orderDate)} <SourceBadge source={o.source} />
            {o.demo ? <DemoBadge /> : null}
          </p>
        </Link>
        <Badge tone={meta.tone}>{meta.label}</Badge>
      </div>

      <dl className="grid grid-cols-2 gap-x-4 gap-y-1.5 rounded bg-subtle/70 px-3 py-2.5 text-sm">
        <dt className="text-muted">ยอดบิล</dt>
        <dd className="text-right font-medium tabular-nums">{formatMoney(s.revenue)}</dd>
        <dt className="text-muted">ค่าสินค้า</dt>
        <dd className="text-right tabular-nums">{formatMoney(s.goods)}</dd>
        {o.fulfillment === 'delivery' ? (
          <>
            <dt className="text-muted">ค่าส่งเก็บลูกค้า</dt>
            <dd className="text-right tabular-nums">{formatMoney(s.deliveryFee)}</dd>
            <dt className="truncate text-muted">ค่ารถ{driverName ? ` (${driverName})` : ''}</dt>
            <dd className="text-right tabular-nums">
              <DriverCost s={s} />
            </dd>
          </>
        ) : null}
        <dt className="border-t border-border pt-1.5 font-medium">คงเหลือเข้าร้าน</dt>
        <dd className="border-t border-border pt-1.5 text-right tabular-nums">
          <Net s={s} />
        </dd>
        {s.receivable ? (
          <>
            <dt className="text-warning">ค้างรับ</dt>
            <dd className="text-right tabular-nums text-warning">{formatMoney(s.receivable)}</dd>
          </>
        ) : null}
      </dl>

      <Steps steps={s.steps} cancelled={cancelled} labels />

      <div className="flex flex-wrap gap-x-4 gap-y-1 text-sm">
        {action ? (
          <Link to={action.to} className="inline-flex min-h-11 items-center gap-1 font-medium text-primary">
            {action.label} <ArrowRight size={14} aria-hidden />
          </Link>
        ) : null}
        <Link to={`/bill/order/${o.id}`} className="inline-flex min-h-11 items-center gap-1 text-muted">
          <FileText size={14} aria-hidden /> ใบส่งของ
        </Link>
      </div>
    </div>
  );
}
