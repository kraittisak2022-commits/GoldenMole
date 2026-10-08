import { useMemo, type ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { CalendarClock, ClipboardList, Plus, Truck, Wallet } from 'lucide-react';
import { useAuth } from '../auth/AuthProvider';
import OrderRow from '../components/OrderRow';
import Card from '../components/ui/Card';
import { Empty, ErrorBox, Loading } from '../components/ui/States';
import { listOrders, listUnclearedOrders } from '../data/orders';
import { useAsync } from '../hooks/useAsync';
import { formatDateTh, formatMoney, formatNumber, toIsoDate } from '../lib/format';
import { periodStats } from '../lib/stats';

const TH_MONTHS = ['มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน', 'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม'];

export default function DashboardPage() {
  const { user } = useAuth();
  const now = new Date();
  const today = toIsoDate(now);
  const monthStart = toIsoDate(new Date(now.getFullYear(), now.getMonth(), 1));

  const month = useAsync(() => listOrders({ from: monthStart, limit: 2000 }), [monthStart]);
  const open = useAsync(() => listUnclearedOrders(), []);
  const waiting = useAsync(() => listOrders({ deliveryStatuses: ['waiting', 'dispatched'], limit: 200 }), []);

  const monthOrders = month.data ?? [];
  const stats = useMemo(() => periodStats(monthOrders), [monthOrders]);
  const todayOrders = monthOrders.filter((o) => o.orderDate === today && !o.cancelled);
  const todayTotal = todayOrders.reduce((s, o) => s + o.total, 0);

  const openOrders = open.data ?? [];
  const waitingAll = waiting.data ?? [];
  const unpaidTotal = openOrders.filter((o) => o.paymentStatus === 'unpaid').reduce((s, o) => s + o.total, 0);
  const creditTotal = openOrders.filter((o) => o.paymentStatus === 'credit').reduce((s, o) => s + o.total, 0);

  const error = month.error || open.error || waiting.error;

  return (
    <div>
      <div className="mb-5 flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="text-sm text-muted">{formatDateTh(now)}</p>
          <h1 className="text-xl font-semibold tracking-tight sm:text-2xl">สวัสดี {user?.displayName}</h1>
        </div>
        <Link
          to="/new"
          className="inline-flex min-h-12 items-center gap-2 rounded bg-primary px-5 text-base font-medium text-primary-foreground hover:bg-primary-hover"
        >
          <Plus size={20} aria-hidden /> สร้างออเดอร์
        </Link>
      </div>

      {error ? (
        <div className="mb-4">
          <ErrorBox message={error} />
        </div>
      ) : null}

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Kpi
          to="/orders?r=today"
          icon={<ClipboardList size={18} aria-hidden />}
          label="ออเดอร์วันนี้"
          value={formatNumber(todayOrders.length)}
          hint={`${formatMoney(todayTotal)} บาท`}
        />
        <Kpi
          to="/orders?f=waiting&r=all"
          icon={<Truck size={18} aria-hidden />}
          label="รอจัดส่ง"
          value={formatNumber(waitingAll.length)}
          hint="เที่ยวที่ยังไม่ส่ง"
          tone={waitingAll.length ? 'warning' : undefined}
        />
        <Kpi
          to="/orders?f=unpaid&r=all"
          icon={<Wallet size={18} aria-hidden />}
          label="ยังไม่จ่าย"
          value={formatMoney(unpaidTotal)}
          hint="เงินสด/โอน/ปลายทาง"
          tone={unpaidTotal ? 'warning' : undefined}
        />
        <Kpi
          to="/statements"
          icon={<CalendarClock size={18} aria-hidden />}
          label="ค้างเครดิต"
          value={formatMoney(creditTotal)}
          hint="รอเคลียร์บิลรายเดือน"
        />
      </div>

      <div className="mt-5 grid grid-cols-1 gap-5 lg:grid-cols-[minmax(0,1fr)_22rem]">
        <section>
          <div className="mb-2 flex items-center justify-between">
            <h2 className="text-sm font-semibold text-muted">รอจัดส่ง</h2>
            <Link to="/orders?f=waiting&r=all" className="text-sm text-primary">
              ดูทั้งหมด
            </Link>
          </div>
          {waiting.loading && !waiting.data ? (
            <Loading />
          ) : (
            <Card className="overflow-hidden">
              {waitingAll.length ? (
                <ul className="divide-y divide-border">
                  {waitingAll.slice(0, 6).map((o) => (
                    <li key={o.id}>
                      <OrderRow order={o} />
                    </li>
                  ))}
                </ul>
              ) : (
                <Empty title="ไม่มีงานรอจัดส่ง" />
              )}
            </Card>
          )}

          <div className="mb-2 mt-5 flex items-center justify-between">
            <h2 className="text-sm font-semibold text-muted">ออเดอร์ล่าสุด</h2>
            <Link to="/orders" className="text-sm text-primary">
              ดูทั้งหมด
            </Link>
          </div>
          <Card className="overflow-hidden">
            {monthOrders.length ? (
              <ul className="divide-y divide-border">
                {monthOrders.slice(0, 6).map((o) => (
                  <li key={o.id}>
                    <OrderRow order={o} />
                  </li>
                ))}
              </ul>
            ) : (
              <Empty title="ยังไม่มีออเดอร์เดือนนี้" />
            )}
          </Card>
        </section>

        <section>
          <h2 className="mb-2 text-sm font-semibold text-muted">
            สรุปเดือน{TH_MONTHS[now.getMonth()]} {now.getFullYear() + 543}
          </h2>
          <Card className="p-4">
            <dl className="flex flex-col gap-2 text-sm">
              <Row label="จำนวนออเดอร์" value={formatNumber(stats.orderCount)} />
              <Row label="ค่าสินค้า" value={formatMoney(stats.productSales)} />
              <Row label="ค่าจัดส่ง" value={formatMoney(stats.deliveryFees)} />
              {stats.discounts ? <Row label="ส่วนลด" value={`-${formatMoney(stats.discounts)}`} /> : null}
              <div className="flex items-baseline justify-between border-t border-border pt-2">
                <dt className="font-semibold">ยอดขายสุทธิ</dt>
                <dd className="text-lg font-bold tabular-nums text-primary">{formatMoney(stats.net)}</dd>
              </div>
              <Row label="รับเงินแล้ว" value={formatMoney(stats.paid)} />
              <Row label="ค่าจ้างคนขับ" value={formatMoney(stats.driverWages)} />
            </dl>
            {stats.quantityByProduct.length ? (
              <div className="mt-4 border-t border-border pt-3">
                <p className="mb-2 text-xs font-semibold text-muted">ขายตามสินค้า</p>
                <ul className="flex flex-col gap-1.5 text-sm">
                  {stats.quantityByProduct.map((p) => (
                    <li key={p.name} className="flex justify-between gap-3">
                      <span className="truncate">{p.name}</span>
                      <span className="shrink-0 tabular-nums text-muted">
                        {formatNumber(p.quantity)} {p.unit}
                      </span>
                    </li>
                  ))}
                </ul>
              </div>
            ) : null}
          </Card>
        </section>
      </div>
    </div>
  );
}

function Kpi({
  to,
  icon,
  label,
  value,
  hint,
  tone,
}: {
  to: string;
  icon: ReactNode;
  label: string;
  value: string;
  hint: string;
  tone?: 'warning';
}) {
  return (
    <Link to={to} className="rounded border border-border bg-surface p-4 transition-colors hover:border-primary/40">
      <p className="flex items-center gap-1.5 text-xs font-medium text-muted">
        {icon}
        {label}
      </p>
      <p className={['mt-1 text-xl font-bold tabular-nums', tone === 'warning' ? 'text-warning' : 'text-ink'].join(' ')}>{value}</p>
      <p className="text-xs text-muted">{hint}</p>
    </Link>
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
