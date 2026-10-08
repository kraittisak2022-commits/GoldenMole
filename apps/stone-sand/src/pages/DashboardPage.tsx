import { useMemo, useRef, type ReactNode } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { CalendarDays, ChevronLeft, ChevronRight, Plus } from 'lucide-react';
import { useAuth } from '../auth/AuthProvider';
import OrderRow from '../components/OrderRow';
import SourceBadge from '../components/SourceBadge';
import Card from '../components/ui/Card';
import Skeleton from '../components/ui/Skeleton';
import { Empty, ErrorBox, Loading } from '../components/ui/States';
import { listOrders, listUnclearedOrders } from '../data/orders';
import { useAsync } from '../hooks/useAsync';
import { TH_MONTHS, formatDateLongTh, formatMoney, formatNumber, monthRange, shiftIsoDate, toIsoDate } from '../lib/format';
import { periodStats, type PeriodStats } from '../lib/stats';
import { ORDER_SOURCES } from '../types';

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

export default function DashboardPage() {
  const { user } = useAuth();
  const [params, setParams] = useSearchParams();
  const today = toIsoDate();
  const param = params.get('d') ?? '';
  const date = ISO_DATE.test(param) ? param : today;
  const isToday = date === today;
  const { from, to } = monthRange(date);

  const setDate = (next: string) => {
    const p = new URLSearchParams(params);
    if (!next || next === today) p.delete('d');
    else p.set('d', next);
    setParams(p, { replace: true });
  };

  const month = useAsync(() => listOrders({ from, to, limit: 3000 }), [from, to], 'orders-month');
  const open = useAsync(() => listUnclearedOrders(), [], 'orders-uncleared');
  const waiting = useAsync(() => listOrders({ deliveryStatuses: ['waiting', 'dispatched'], limit: 200 }), [], 'orders-waiting');

  const monthOrders = useMemo(() => month.data ?? [], [month.data]);
  const dayOrders = useMemo(() => monthOrders.filter((o) => o.orderDate === date), [monthOrders, date]);
  const day = useMemo(() => periodStats(dayOrders), [dayOrders]);
  const monthStats = useMemo(() => periodStats(monthOrders), [monthOrders]);

  const openOrders = open.data ?? [];
  const waitingAll = waiting.data ?? [];
  const unpaidTotal = openOrders.filter((o) => o.paymentStatus === 'unpaid').reduce((s, o) => s + o.total, 0);
  const creditTotal = openOrders.filter((o) => o.paymentStatus === 'credit').reduce((s, o) => s + o.total, 0);

  const error = month.error || open.error || waiting.error;
  const monthPending = month.loading && !month.data;
  const openPending = open.loading && !open.data;
  const waitingPending = waiting.loading && !waiting.data;
  const [y, m] = date.split('-').map(Number);

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="text-2xl font-semibold tracking-tight">สวัสดี {user?.displayName}</h1>
        <Link
          to="/new"
          className="hidden min-h-12 items-center gap-2 rounded bg-primary px-5 text-base font-medium text-primary-foreground hover:bg-primary-hover md:inline-flex"
        >
          <Plus size={20} aria-hidden /> สร้างออเดอร์
        </Link>
      </div>

      <DateBar date={date} isToday={isToday} onChange={setDate} />

      {error ? <ErrorBox message={error} /> : null}

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Kpi label="ออเดอร์" value={formatNumber(day.orderCount)} hint={`${formatMoney(day.net)} บาท`} pending={monthPending} />
        <Kpi label="สินค้า" value={`${formatNumber(day.quantity)} คิว`} hint={`${formatNumber(day.trips)} เที่ยว`} pending={monthPending} />
        <Kpi label="รับเงินแล้ว" value={formatMoney(day.paid)} hint="บาท" pending={monthPending} />
        <Kpi
          label="ค้างรับ"
          value={formatMoney(day.outstanding)}
          hint="ยังไม่จ่าย + เครดิต"
          warn={day.outstanding > 0}
          pending={monthPending}
        />
      </div>

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-[minmax(0,1fr)_22rem]">
        <section>
          <SectionTitle>
            ออเดอร์{isToday ? 'วันนี้' : 'วันที่เลือก'} {dayOrders.length ? `(${dayOrders.length})` : ''}
          </SectionTitle>
          {month.loading && !month.data ? (
            <Loading />
          ) : (
            <Card className="overflow-hidden">
              {dayOrders.length ? (
                <ul className="divide-y divide-border">
                  {dayOrders.map((o) => (
                    <li key={o.id}>
                      <OrderRow order={o} />
                    </li>
                  ))}
                </ul>
              ) : (
                <Empty title={isToday ? 'ยังไม่มีออเดอร์วันนี้' : 'ไม่มีออเดอร์ในวันที่เลือก'} />
              )}
            </Card>
          )}
        </section>

        <section>
          <SectionTitle>สรุปวัน</SectionTitle>
          {monthPending ? <Loading rows={2} /> : <SummaryCard stats={day} />}
        </section>
      </div>

      <section>
        <SectionTitle action={<Link to="/orders?f=waiting&r=all" className="text-sm text-primary">ดูทั้งหมด</Link>}>
          งานค้าง (ทุกวัน)
        </SectionTitle>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <Kpi
            to="/orders?f=waiting&r=all"
            label="รอจัดส่ง"
            value={`${formatNumber(waitingAll.length)} ออเดอร์`}
            warn={waitingAll.length > 0}
            pending={waitingPending}
          />
          <Kpi to="/orders?f=unpaid&r=all" label="ยังไม่จ่าย" value={formatMoney(unpaidTotal)} warn={unpaidTotal > 0} pending={openPending} />
          <Kpi to="/statements" label="ค้างเครดิต" value={formatMoney(creditTotal)} pending={openPending} />
        </div>
        {waitingAll.length ? (
          <Card className="mt-3 overflow-hidden">
            <ul className="divide-y divide-border">
              {waitingAll.slice(0, 6).map((o) => (
                <li key={o.id}>
                  <OrderRow order={o} />
                </li>
              ))}
            </ul>
          </Card>
        ) : null}
      </section>

      <section>
        <SectionTitle>
          สรุปเดือน{TH_MONTHS[m - 1]} {y + 543}
        </SectionTitle>
        {monthPending ? <Loading rows={2} /> : <SummaryCard stats={monthStats} />}
      </section>
    </div>
  );
}

function DateBar({ date, isToday, onChange }: { date: string; isToday: boolean; onChange: (d: string) => void }) {
  const input = useRef<HTMLInputElement>(null);
  const openPicker = () => {
    const el = input.current;
    if (!el) return;
    try {
      el.showPicker();
    } catch {
      el.focus();
    }
  };
  const [weekday, ...rest] = formatDateLongTh(date).split(' ');
  const dayMonthYear = rest.join(' ');
  const step = 'inline-flex h-12 w-12 shrink-0 items-center justify-center rounded-full bg-subtle text-ink hover:bg-border cursor-pointer';

  return (
    <div className="flex items-center gap-2">
      <button type="button" aria-label="วันก่อนหน้า" onClick={() => onChange(shiftIsoDate(date, -1))} className={step}>
        <ChevronLeft size={22} aria-hidden />
      </button>
      <div className="relative min-w-0 flex-1">
        <button
          type="button"
          onClick={openPicker}
          aria-label={formatDateLongTh(date)}
          className="flex min-h-12 w-full items-center justify-center gap-2 rounded-full border border-border px-3 text-base font-medium cursor-pointer hover:bg-subtle sm:px-4"
        >
          <CalendarDays size={18} className="hidden shrink-0 text-muted min-[400px]:block" aria-hidden />
          <span className="truncate">
            <span className="hidden sm:inline">{weekday} </span>
            {dayMonthYear}
          </span>
        </button>
        <input
          ref={input}
          type="date"
          aria-label="เลือกวันที่"
          value={date}
          onChange={(e) => onChange(e.target.value)}
          className="pointer-events-none absolute inset-0 h-full w-full opacity-0"
          tabIndex={-1}
        />
      </div>
      <button type="button" aria-label="วันถัดไป" onClick={() => onChange(shiftIsoDate(date, 1))} className={step}>
        <ChevronRight size={22} aria-hidden />
      </button>
      {isToday ? null : (
        <button
          type="button"
          onClick={() => onChange('')}
          className="min-h-12 shrink-0 rounded-full bg-ink px-4 text-sm font-medium text-white cursor-pointer"
        >
          วันนี้
        </button>
      )}
    </div>
  );
}

function SectionTitle({ children, action }: { children: ReactNode; action?: ReactNode }) {
  return (
    <div className="mb-2 flex items-center justify-between gap-3">
      <h2 className="text-sm font-semibold text-muted">{children}</h2>
      {action}
    </div>
  );
}

function SummaryCard({ stats }: { stats: PeriodStats }) {
  const { lockedSource } = useAuth();
  return (
    <Card className="p-4">
      <dl className="flex flex-col gap-2 text-sm">
        <Row label="จำนวนออเดอร์" value={formatNumber(stats.orderCount)} />
        <Row label="ค่าสินค้า" value={formatMoney(stats.productSales)} />
        <Row label="ค่าจัดส่ง" value={formatMoney(stats.deliveryFees)} />
        {stats.discounts ? <Row label="ส่วนลด" value={`-${formatMoney(stats.discounts)}`} /> : null}
        <div className="flex items-baseline justify-between border-t border-border pt-2">
          <dt className="font-semibold">ยอดขายสุทธิ</dt>
          <dd className="text-lg font-semibold tabular-nums">{formatMoney(stats.net)}</dd>
        </div>
        <Row label="รับเงินแล้ว" value={formatMoney(stats.paid)} />
        <Row label="ค้างรับ" value={formatMoney(stats.outstanding)} />
        <Row label="ค่าจ้างคนขับ" value={formatMoney(stats.driverWages)} />
      </dl>
      {lockedSource ? null : (
        <div className="mt-4 border-t border-border pt-3">
          <p className="mb-2 text-xs font-semibold text-muted">แยกตามประเภทออเดอร์</p>
          <ul className="grid grid-cols-2 gap-2">
            {ORDER_SOURCES.map((s) => {
              const row = stats.bySource[s];
              return (
                <li key={s} className="min-w-0 rounded border border-border px-3 py-2">
                  <SourceBadge source={s} />
                  <p className="mt-1.5 truncate text-base font-semibold tabular-nums">{formatMoney(row.net)}</p>
                  <p className="truncate text-xs text-muted tabular-nums">
                    {formatNumber(row.orderCount)} ออเดอร์ · {formatNumber(row.quantity)} คิว
                  </p>
                </li>
              );
            })}
          </ul>
        </div>
      )}
      {stats.quantityByProduct.length ? (
        <div className="mt-4 border-t border-border pt-3">
          <p className="mb-2 text-xs font-semibold text-muted">ขายตามสินค้า</p>
          <ul className="flex flex-col gap-1.5 text-sm">
            {stats.quantityByProduct.map((p) => (
              <li key={p.name} className="flex justify-between gap-3">
                <span className="truncate">{p.name}</span>
                <span className="shrink-0 tabular-nums text-muted">
                  {formatNumber(p.quantity)} {p.unit} · {formatMoney(p.amount)}
                </span>
              </li>
            ))}
          </ul>
        </div>
      ) : null}
    </Card>
  );
}

function Kpi({
  label,
  value,
  hint,
  warn,
  to,
  pending,
}: {
  label: string;
  value: string;
  hint?: string;
  warn?: boolean;
  to?: string;
  /** Data not loaded yet: show a placeholder instead of a misleading 0. */
  pending?: boolean;
}) {
  const body = (
    <>
      <p className="text-sm text-muted">{label}</p>
      {pending ? (
        <>
          <Skeleton className="mt-2 h-6 w-24" />
          {hint !== undefined ? <Skeleton className="mt-2 h-3 w-16" /> : null}
        </>
      ) : (
        <>
          <p className={['mt-1 truncate text-xl font-semibold tabular-nums', warn ? 'text-warning' : 'text-ink'].join(' ')}>{value}</p>
          {hint ? <p className="truncate text-xs text-muted">{hint}</p> : null}
        </>
      )}
    </>
  );
  const cls = 'min-w-0 rounded border border-border bg-surface p-4';
  return to ? (
    <Link to={to} className={`${cls} transition duration-150 hover:border-ink/30 active:scale-[0.98]`}>
      {body}
    </Link>
  ) : (
    <div className={cls}>{body}</div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between gap-3">
      <dt className="text-muted">{label}</dt>
      <dd className="tabular-nums">{value}</dd>
    </div>
  );
}
