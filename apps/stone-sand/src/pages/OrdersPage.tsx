import { useMemo, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { Plus, Search } from 'lucide-react';
import { useAuth } from '../auth/AuthProvider';
import OrderRow from '../components/OrderRow';
import Card from '../components/ui/Card';
import Chip from '../components/ui/Chip';
import Input from '../components/ui/Input';
import PageHeader from '../components/ui/PageHeader';
import Select from '../components/ui/Select';
import { Empty, ErrorBox, Loading } from '../components/ui/States';
import { listOrders } from '../data/orders';
import { useAsync } from '../hooks/useAsync';
import { formatMoney, toIsoDate } from '../lib/format';
import { ORDER_FILTERS, matchesFilter, matchesSearch, outstanding, type OrderFilter } from '../lib/orderStatus';
import { ORDER_SOURCES, ORDER_SOURCE_SHORT, type OrderSource } from '../types';

type Range = 'today' | '7d' | 'month' | '3m' | 'all';

const RANGE_LABEL: Record<Range, string> = {
  today: 'วันนี้',
  '7d': '7 วันล่าสุด',
  month: 'เดือนนี้',
  '3m': '3 เดือน',
  all: 'ทั้งหมด',
};

function rangeFrom(r: Range): string | undefined {
  const d = new Date();
  if (r === 'today') return toIsoDate(d);
  if (r === '7d') return toIsoDate(new Date(d.getFullYear(), d.getMonth(), d.getDate() - 6));
  if (r === 'month') return toIsoDate(new Date(d.getFullYear(), d.getMonth(), 1));
  if (r === '3m') return toIsoDate(new Date(d.getFullYear(), d.getMonth() - 2, 1));
  return undefined;
}

export default function OrdersPage() {
  const [params, setParams] = useSearchParams();
  const { lockedSource } = useAuth();
  const filter = (params.get('f') as OrderFilter) || 'all';
  const range = (params.get('r') as Range) || 'month';
  const sourceParam = params.get('source');
  const source = lockedSource ? null : (ORDER_SOURCES.find((s) => s === sourceParam) ?? null);
  const [query, setQuery] = useState('');

  const setParam = (key: string, value: string | null) => {
    const next = new URLSearchParams(params);
    if (value) next.set(key, value);
    else next.delete(key);
    setParams(next, { replace: true });
  };

  const { data, error, loading } = useAsync(() => listOrders({ from: rangeFrom(range), limit: 1000 }), [range]);
  const orders = data ?? [];

  const sourceCounts = useMemo(() => {
    const c = { all: orders.length } as Record<OrderSource | 'all', number>;
    for (const s of ORDER_SOURCES) c[s] = orders.filter((o) => o.source === s).length;
    return c;
  }, [orders]);
  const searched = useMemo(
    () => orders.filter((o) => (!source || o.source === source) && matchesSearch(o, query)),
    [orders, source, query],
  );
  const counts = useMemo(() => {
    const c = {} as Record<OrderFilter, number>;
    for (const f of ORDER_FILTERS) c[f.id] = searched.filter((o) => matchesFilter(o, f.id)).length;
    return c;
  }, [searched]);
  const visible = useMemo(() => searched.filter((o) => matchesFilter(o, filter)), [searched, filter]);
  const visibleTotal = visible.reduce((s, o) => s + (o.cancelled ? 0 : o.total), 0);
  const visibleOutstanding = visible.reduce((s, o) => s + outstanding(o), 0);

  return (
    <div>
      <PageHeader
        title="ออเดอร์"
        subtitle="ติดตามสถานะจ่ายเงิน จัดส่ง และเคลียร์บิล"
        actions={
          <Link
            to="/new"
            className="hidden min-h-11 items-center gap-2 rounded bg-primary px-4 text-sm font-medium text-primary-foreground hover:bg-primary-hover md:inline-flex"
          >
            <Plus size={18} aria-hidden /> สร้างออเดอร์
          </Link>
        }
      />

      <div className="mb-3 flex flex-col gap-2 sm:flex-row">
        <div className="relative flex-1">
          <Search size={18} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted" aria-hidden />
          <Input
            aria-label="ค้นหาออเดอร์"
            placeholder="ค้นหาชื่อลูกค้า เบอร์โทร หรือเลขที่บิล"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            className="pl-10"
          />
        </div>
        <Select aria-label="ช่วงวันที่" value={range} onChange={(e) => setParam('r', e.target.value)} className="sm:w-44">
          {(Object.keys(RANGE_LABEL) as Range[]).map((r) => (
            <option key={r} value={r}>
              {RANGE_LABEL[r]}
            </option>
          ))}
        </Select>
      </div>

      {lockedSource ? null : (
        <div
          className="mb-3 inline-flex w-full rounded border border-border bg-surface p-1 sm:w-auto"
          role="radiogroup"
          aria-label="ประเภทออเดอร์"
        >
          {([null, ...ORDER_SOURCES] as (OrderSource | null)[]).map((s) => {
            const active = source === s;
            return (
              <button
                key={s ?? 'all'}
                type="button"
                role="radio"
                aria-checked={active}
                onClick={() => setParam('source', s)}
                className={[
                  'flex min-h-10 flex-1 items-center justify-center gap-1.5 rounded-[9px] px-3 text-sm font-medium transition-colors cursor-pointer sm:flex-none',
                  active ? 'bg-primary text-primary-foreground' : 'text-muted hover:bg-subtle hover:text-ink',
                ].join(' ')}
              >
                {s ? ORDER_SOURCE_SHORT[s] : 'ทั้งหมด'}
                <span className={['tabular-nums text-xs', active ? 'opacity-80' : ''].join(' ')}>
                  {sourceCounts[s ?? 'all']}
                </span>
              </button>
            );
          })}
        </div>
      )}

      <div className="-mx-4 mb-4 flex gap-2 overflow-x-auto px-4 pb-1 sm:mx-0 sm:flex-wrap sm:px-0">
        {ORDER_FILTERS.map((f) => (
          <Chip key={f.id} active={filter === f.id} onClick={() => setParam('f', f.id)} count={counts[f.id]}>
            {f.label}
          </Chip>
        ))}
      </div>

      {error ? <ErrorBox message={error} /> : null}
      {loading && !data ? (
        <Loading />
      ) : (
        <Card className="overflow-hidden">
          {visible.length ? (
            <>
              <div className="flex items-center justify-between border-b border-border bg-subtle/60 px-4 py-2 text-xs text-muted">
                <span>{visible.length} รายการ</span>
                <span className="tabular-nums">
                  รวม {formatMoney(visibleTotal)}
                  {visibleOutstanding ? ` · ค้าง ${formatMoney(visibleOutstanding)}` : ''}
                </span>
              </div>
              <ul className="divide-y divide-border">
                {visible.map((o) => (
                  <li key={o.id}>
                    <OrderRow order={o} />
                  </li>
                ))}
              </ul>
            </>
          ) : (
            <Empty
              title={query ? 'ไม่พบออเดอร์ที่ค้นหา' : 'ยังไม่มีออเดอร์ในช่วงนี้'}
              action={
                <Link to="/new" className="text-sm font-medium text-primary underline">
                  สร้างออเดอร์ใหม่
                </Link>
              }
            />
          )}
        </Card>
      )}
    </div>
  );
}
