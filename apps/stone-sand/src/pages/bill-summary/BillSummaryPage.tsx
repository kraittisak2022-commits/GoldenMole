import { useMemo, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { AlertTriangle, Download, Search } from 'lucide-react';
import { useAuth } from '../../auth/AuthProvider';
import SourceToggle from '../../components/SourceToggle';
import Button from '../../components/ui/Button';
import Card from '../../components/ui/Card';
import Chip from '../../components/ui/Chip';
import Input from '../../components/ui/Input';
import PageHeader from '../../components/ui/PageHeader';
import Select from '../../components/ui/Select';
import { Empty, ErrorBox, Loading } from '../../components/ui/States';
import { useCatalog } from '../../context/CatalogProvider';
import { listOrders } from '../../data/orders';
import { useAsync } from '../../hooks/useAsync';
import { BILL_STAGES, billSummaryCsv, summarizeBill, totalBills, type BillStage } from '../../lib/billSummary';
import { DATE_RANGES, DATE_RANGE_LABEL, parseDateRange, rangeFrom } from '../../lib/dateRange';
import { toIsoDate } from '../../lib/format';
import { matchesSearch } from '../../lib/orderStatus';
import { ORDER_SOURCES, type OrderSource } from '../../types';
import BillList, { type BillRowData } from './BillList';
import SummaryHero from './SummaryHero';

type StageFilter = 'all' | 'open' | BillStage;
type Sort = 'latest' | 'oldest' | 'netDesc' | 'netAsc' | 'receivable';

const SORT_LABEL: Record<Sort, string> = {
  latest: 'ล่าสุดก่อน',
  oldest: 'เก่าสุดก่อน',
  netDesc: 'เหลือมากสุด',
  netAsc: 'เหลือน้อยสุด',
  receivable: 'ค้างรับมากสุด',
};
const SORTS = Object.keys(SORT_LABEL) as Sort[];

const isOpen = (s: BillStage) => s !== 'done' && s !== 'cancelled';

function sortRows(rows: BillRowData[], sort: Sort): BillRowData[] {
  const byDate = (a: BillRowData, b: BillRowData) =>
    a.order.orderDate.localeCompare(b.order.orderDate) || a.order.createdAt.localeCompare(b.order.createdAt);
  const sorted = [...rows];
  if (sort === 'latest') sorted.sort((a, b) => byDate(b, a));
  if (sort === 'oldest') sorted.sort(byDate);
  if (sort === 'netDesc') sorted.sort((a, b) => b.summary.net - a.summary.net);
  if (sort === 'netAsc') sorted.sort((a, b) => a.summary.net - b.summary.net);
  if (sort === 'receivable') sorted.sort((a, b) => b.summary.receivable - a.summary.receivable);
  return sorted;
}

function downloadCsv(rows: BillRowData[]) {
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
  const sort = SORTS.find((s) => s === params.get('sort')) ?? 'latest';
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

  const rows = useMemo<BillRowData[]>(
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
  const losses = searched.filter((r) => r.summary.deliveryMargin < 0 && r.summary.stage !== 'cancelled').length;

  return (
    <div className="min-w-0">
      <PageHeader
        title="สรุปบิล"
        subtitle="ได้ค่าของเท่าไร หักค่ารถเท่าไร เหลือเข้าร้านเท่าไร และแต่ละบิลติดขั้นตอนไหน"
        actions={
          <Button variant="secondary" onClick={() => downloadCsv(visible)} disabled={!visible.length}>
            <Download size={18} aria-hidden /> ส่งออก Excel
          </Button>
        }
      />

      <div className="mb-3 grid grid-cols-2 gap-2 sm:grid-cols-[minmax(0,1fr)_10rem_11rem]">
        <div className="relative col-span-2 sm:col-span-1">
          <Search size={18} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted" aria-hidden />
          <Input
            aria-label="ค้นหาบิล"
            placeholder="ค้นหาชื่อ เบอร์โทร หรือเลขที่บิล"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            className="pl-10"
          />
        </div>
        <Select aria-label="ช่วงวันที่" value={range} onChange={(e) => setParam('r', e.target.value)}>
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
        >
          {SORTS.map((s) => (
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
          <SummaryHero totals={totals} periodLabel={DATE_RANGE_LABEL[range]} />

          {losses ? (
            <p className="mb-4 flex items-start gap-2 rounded border border-warning/30 bg-warning-soft px-3 py-2 text-sm text-warning">
              <AlertTriangle size={18} className="mt-0.5 shrink-0" aria-hidden />
              <span>
                มี {losses} บิลที่ค่ารถคนขับสูงกว่าค่าส่งที่เก็บลูกค้า{' '}
                <button
                  type="button"
                  onClick={() => setParam('sort', 'netAsc')}
                  className="font-medium underline cursor-pointer"
                >
                  ดูบิลที่เหลือน้อยสุดก่อน
                </button>
              </span>
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
              <BillList rows={visible} totals={visibleTotals} />
            ) : (
              <Empty title={query ? 'ไม่พบบิลที่ค้นหา' : 'ยังไม่มีบิลในช่วงนี้'} />
            )}
          </Card>
          <p className="mt-3 text-xs text-muted">
            ≈ คือค่ารถตามเรทตำบลที่ยังไม่ได้จ่ายคนขับ ยอดจริงใช้ตามที่บันทึกตอนเคลียร์ค่ารถ · บิลที่ยกเลิกไม่นับรวมยอด
          </p>
        </>
      )}
    </div>
  );
}
