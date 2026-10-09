import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { ArrowDownLeft, ArrowUpRight, Check, Trash2, X } from 'lucide-react';
import { useAuth } from '../auth/AuthProvider';
import PayMethodPicker, { type PayMethod } from '../components/PayMethodPicker';
import SourceBadge from '../components/SourceBadge';
import Badge from '../components/ui/Badge';
import Button from '../components/ui/Button';
import Card from '../components/ui/Card';
import Field from '../components/ui/Field';
import Input from '../components/ui/Input';
import PageHeader from '../components/ui/PageHeader';
import { Empty, ErrorBox, Loading } from '../components/ui/States';
import { useCatalog } from '../context/CatalogProvider';
import { createDriverPayout, deleteDriverPayout, listDriverPayouts, receiveDriverCod } from '../data/driverPayouts';
import { listDriverUnpaidOrders } from '../data/orders';
import { useAsync } from '../hooks/useAsync';
import {
  codToCollect,
  customerDeliveryFee,
  driverPayBreakdown,
  settleWithDriver,
  suggestedDriverPay,
  summarizeDriverDues,
} from '../lib/driverPay';
import { formatDateShort, formatDateTime, formatMoney, formatNumber, toIsoDate } from '../lib/format';
import { PAYMENT_METHOD_LABEL, type DriverPayout, type Order } from '../types';

const PAY_HINTS: Record<PayMethod, string> = { cash: 'จ่ายเงินสดให้คนขับ', transfer: 'โอนเข้าบัญชีคนขับ' };
const DRIVER_PAYS_HINTS: Record<PayMethod, string> = { cash: 'คนขับส่งเงินสด', transfer: 'คนขับโอนเข้าบัญชีร้าน' };

export default function DriverPayPage() {
  const { user, isSuperAdmin } = useAuth();
  const by = user?.displayName || user?.username || '';
  const { driverById, zoneById, settings } = useCatalog();
  const [params, setParams] = useSearchParams();
  const selectedDriver = params.get('driver');

  const unpaid = useAsync(() => listDriverUnpaidOrders(), [], 'driver-unpaid');
  const payouts = useAsync(() => listDriverPayouts(), [], 'driver-payouts');
  const [actionError, setActionError] = useState('');
  const [doneMessage, setDoneMessage] = useState('');

  const dues = useMemo(
    () => summarizeDriverDues(unpaid.data ?? [], zoneById, settings.delivery),
    [unpaid.data, zoneById, settings.delivery],
  );
  const totals = useMemo(() => {
    let pay = 0;
    let cash = 0;
    let handover = 0;
    let topUp = 0;
    for (const d of dues) {
      const s = settleWithDriver(d.total, d.cash);
      pay += d.total;
      cash += d.cash;
      handover += s.handover;
      topUp += s.topUp;
    }
    return { pay, cash, handover, topUp };
  }, [dues]);
  const visiblePayouts = (payouts.data ?? []).filter((p) => !selectedDriver || p.driverId === selectedDriver);
  const driverName = (id: string) => driverById(id)?.name ?? 'คนขับ';

  const selectDriver = (id: string | null) => {
    const next = new URLSearchParams(params);
    if (id) next.set('driver', id);
    else next.delete('driver');
    setParams(next, { replace: true });
  };

  const reloadAll = async () => {
    await Promise.all([unpaid.reload(), payouts.reload()]);
  };

  const remove = async (p: DriverPayout) => {
    if (!window.confirm(`ลบรายการจ่ายค่ารถ ${p.payoutNo} (${p.driverName})? ออเดอร์ในรายการนี้จะกลับเป็น "ค่ารถยังไม่จ่าย"`)) return;
    setActionError('');
    setDoneMessage('');
    try {
      await deleteDriverPayout(p.id, by);
      await reloadAll();
    } catch (err) {
      setActionError(err instanceof Error ? err.message : 'ลบไม่สำเร็จ');
    }
  };

  const loadingDues = unpaid.loading && !unpaid.data;

  return (
    <div>
      <PageHeader title="เคลียร์ค่ารถ" subtitle="หักค่ารถจากเงินเก็บปลายทาง รับเงินส่วนที่เหลือจากคนขับ หรือจ่ายค่ารถส่วนที่ขาด" />
      {actionError ? (
        <div className="mb-4">
          <ErrorBox message={actionError} />
        </div>
      ) : null}
      {doneMessage ? (
        <div className="mb-4 flex items-center gap-2 rounded border border-emerald-200 bg-success-soft px-4 py-3 text-sm text-emerald-800">
          <Check size={18} aria-hidden /> {doneMessage}
        </div>
      ) : null}

      {!loadingDues && dues.length ? (
        <div className="mb-5 grid grid-cols-2 gap-3 lg:grid-cols-4">
          <Stat label="ค่ารถค้างจ่าย" value={formatMoney(totals.pay)} hint={`${dues.length} คนขับ`} />
          <Stat label="เงินปลายทางที่คนขับถืออยู่" value={formatMoney(totals.cash)} hint="เก็บจากลูกค้าแล้ว ยังไม่ส่งร้าน" />
          <Stat label="คนขับต้องส่งร้าน" value={formatMoney(totals.handover)} hint="หลังหักค่ารถ" tone={totals.handover ? 'warn' : undefined} />
          <Stat label="ร้านต้องจ่ายคนขับ" value={formatMoney(totals.topUp)} hint="ค่ารถที่เงินปลายทางไม่พอหัก" tone={totals.topUp ? 'primary' : undefined} />
        </div>
      ) : null}

      <div className="grid grid-cols-1 gap-5 lg:grid-cols-[minmax(0,5fr)_minmax(0,7fr)]">
        <section>
          <h2 className="mb-2 text-sm font-semibold text-muted">คนขับที่ยังไม่ได้เคลียร์</h2>
          {unpaid.error ? <ErrorBox message={unpaid.error} /> : null}
          {loadingDues ? (
            <Loading />
          ) : (
            <Card className="overflow-hidden">
              {dues.length ? (
                <ul className="divide-y divide-border">
                  {dues.map((row) => {
                    const s = settleWithDriver(row.total, row.cash);
                    const active = selectedDriver === row.driverId;
                    return (
                      <li key={row.driverId}>
                        <button
                          type="button"
                          aria-pressed={active}
                          onClick={() => selectDriver(row.driverId)}
                          className={[
                            'flex min-h-16 w-full items-center gap-3 border-l-4 px-4 py-3 text-left transition-colors cursor-pointer',
                            active ? 'border-primary bg-primary-soft/60' : 'border-transparent hover:bg-subtle',
                          ].join(' ')}
                        >
                          <div className="min-w-0 flex-1">
                            <p className="truncate font-medium">{driverName(row.driverId)}</p>
                            <p className="text-xs text-muted">
                              {row.count} ออเดอร์ · {formatNumber(row.trips)} เที่ยว · ตั้งแต่ {formatDateShort(row.oldestDate)}
                            </p>
                            {row.cash ? (
                              <p className="text-xs text-muted tabular-nums">
                                ค่ารถ {formatNumber(row.total)} · เก็บปลายทาง {formatNumber(row.cash)}
                              </p>
                            ) : null}
                          </div>
                          <div className="shrink-0 text-right">
                            {s.handover ? (
                              <>
                                <p className="text-xs text-warning">คนขับส่งร้าน</p>
                                <p className="font-semibold tabular-nums text-warning">{formatMoney(s.handover)}</p>
                              </>
                            ) : (
                              <>
                                <p className="text-xs text-muted">ร้านจ่ายคนขับ</p>
                                <p className="font-semibold tabular-nums">{formatMoney(s.topUp)}</p>
                              </>
                            )}
                          </div>
                        </button>
                      </li>
                    );
                  })}
                </ul>
              ) : (
                <Empty title="ไม่มีค่ารถค้างจ่าย" />
              )}
            </Card>
          )}
        </section>

        <section>
          {selectedDriver && !unpaid.data ? (
            <Loading />
          ) : selectedDriver ? (
            <PayoutPanel
              key={`${selectedDriver}-${unpaid.data?.length}`}
              driverId={selectedDriver}
              driverName={driverName(selectedDriver)}
              orders={(unpaid.data ?? []).filter((o) => o.driverId === selectedDriver)}
              by={by}
              onClose={() => selectDriver(null)}
              onPaid={async (message) => {
                setActionError('');
                setDoneMessage(message);
                await reloadAll();
              }}
            />
          ) : (
            <Card className="p-5 text-sm text-muted">เลือกคนขับทางซ้ายเพื่อเคลียร์ค่ารถ</Card>
          )}
        </section>
      </div>

      <section className="mt-8">
        <h2 className="mb-2 text-sm font-semibold text-muted">
          ประวัติเคลียร์ค่ารถ{selectedDriver ? ` · ${driverName(selectedDriver)}` : ''}
        </h2>
        {payouts.error ? <ErrorBox message={payouts.error} /> : null}
        {payouts.loading && !payouts.data ? (
          <Loading />
        ) : (
          <Card className="overflow-hidden">
            {visiblePayouts.length ? (
              <ul className="divide-y divide-border">
                {visiblePayouts.map((p) => {
                  const s = settleWithDriver(p.total, p.cashCollected);
                  return (
                    <li key={p.id} className="flex flex-wrap items-center gap-3 px-4 py-3">
                      <div className="min-w-0 flex-1">
                        <div className="flex flex-wrap items-center gap-2">
                          <p className="font-medium tabular-nums">{p.payoutNo}</p>
                          <Badge tone="success">เคลียร์แล้ว · {PAYMENT_METHOD_LABEL[p.method]}</Badge>
                        </div>
                        <p className="truncate text-sm">{p.driverName}</p>
                        <p className="text-xs text-muted">
                          {formatDateTime(p.createdAt)}
                          {p.createdBy ? ` · โดย ${p.createdBy}` : ''} · {p.orders.length} ออเดอร์ ·{' '}
                          {formatNumber(p.orders.reduce((sum, o) => sum + o.trips, 0))} เที่ยว
                        </p>
                        <p className="mt-1 flex flex-wrap gap-x-2 text-xs">
                          {p.orders.map((o) => (
                            <Link key={o.id} to={`/orders/${o.id}`} className="tabular-nums text-primary underline">
                              {o.orderNo}
                            </Link>
                          ))}
                        </p>
                        {p.note ? <p className="mt-1 text-xs text-muted">หมายเหตุ: {p.note}</p> : null}
                      </div>
                      <div className="text-right text-sm">
                        <p className="tabular-nums">ค่ารถ {formatMoney(p.total)}</p>
                        {p.cashCollected ? (
                          <>
                            <p className="text-xs text-muted tabular-nums">เงินปลายทาง {formatMoney(p.cashCollected)}</p>
                            <p className="text-xs font-semibold tabular-nums">
                              {s.handover ? `คนขับส่งร้าน ${formatMoney(s.handover)}` : `ร้านจ่ายคนขับ ${formatMoney(s.topUp)}`}
                            </p>
                          </>
                        ) : null}
                      </div>
                      {isSuperAdmin ? (
                        <Button variant="ghost" aria-label={`ลบ ${p.payoutNo}`} onClick={() => remove(p)}>
                          <Trash2 size={16} aria-hidden />
                        </Button>
                      ) : null}
                    </li>
                  );
                })}
              </ul>
            ) : (
              <Empty title="ยังไม่มีประวัติเคลียร์ค่ารถ" />
            )}
          </Card>
        )}
      </section>
    </div>
  );
}

function Stat({ label, value, hint, tone }: { label: string; value: string; hint?: string; tone?: 'warn' | 'primary' }) {
  return (
    <div className="min-w-0 rounded border border-border bg-surface p-4">
      <p className="truncate text-sm text-muted">{label}</p>
      <p
        className={[
          'mt-1 truncate text-xl font-semibold tabular-nums',
          tone === 'warn' ? 'text-warning' : tone === 'primary' ? 'text-primary' : 'text-ink',
        ].join(' ')}
      >
        {value}
      </p>
      {hint ? <p className="truncate text-xs text-muted">{hint}</p> : null}
    </div>
  );
}

function CashModeOption({ active, onClick, title, detail }: { active: boolean; onClick: () => void; title: string; detail: string }) {
  return (
    <button
      type="button"
      role="radio"
      aria-checked={active}
      onClick={onClick}
      className={[
        'flex min-h-14 w-full items-start gap-3 rounded border-2 px-4 py-3 text-left text-sm transition-colors cursor-pointer',
        active ? 'border-amber-400 bg-warning-soft' : 'border-border bg-surface hover:bg-subtle',
      ].join(' ')}
    >
      <span
        className={[
          'mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full border-2',
          active ? 'border-warning' : 'border-border',
        ].join(' ')}
        aria-hidden
      >
        {active ? <span className="h-2.5 w-2.5 rounded-full bg-warning" /> : null}
      </span>
      <span className="min-w-0">
        <span className="block font-semibold tabular-nums">{title}</span>
        <span className="block tabular-nums text-muted">{detail}</span>
      </span>
    </button>
  );
}

function PaymentBadge({ o }: { o: Order }) {
  const cod = codToCollect(o);
  if (cod) return <Badge tone="warning">เก็บปลายทาง {formatNumber(cod)}</Badge>;
  if (o.paymentStatus === 'paid') return <Badge tone="success">ลูกค้าจ่ายแล้ว</Badge>;
  if (o.paymentStatus === 'credit') return <Badge>เครดิต</Badge>;
  return <Badge>ลูกค้ายังไม่จ่าย ({PAYMENT_METHOD_LABEL[o.paymentMethod]})</Badge>;
}

function StatementRow({ label, value, strong, negative }: { label: ReactNode; value: number; strong?: boolean; negative?: boolean }) {
  return (
    <div className="flex items-baseline justify-between gap-3">
      <dt className={strong ? 'font-medium' : 'text-muted'}>{label}</dt>
      <dd className={['tabular-nums', negative ? 'text-destructive' : '', strong ? 'font-medium' : ''].join(' ')}>
        {negative ? '−' : ''}
        {formatMoney(value)}
      </dd>
    </div>
  );
}

function PayoutPanel({
  driverId,
  driverName,
  orders,
  by,
  onClose,
  onPaid,
}: {
  driverId: string;
  driverName: string;
  orders: Order[];
  by: string;
  onClose: () => void;
  onPaid: (message: string) => void;
}) {
  const { zoneById, settings } = useCatalog();
  const today = toIsoDate();
  const oldest = orders[0]?.orderDate ?? today;
  const [from, setFrom] = useState(oldest);
  const [to, setTo] = useState(today < oldest ? oldest : today);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [amounts, setAmounts] = useState<Record<string, number>>(() =>
    Object.fromEntries(orders.map((o) => [o.id, suggestedDriverPay(o, zoneById(o.zoneId), settings.delivery)])),
  );
  const [method, setMethod] = useState<PayMethod | null>(null);
  const [note, setNote] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const inRange = orders.filter((o) => o.orderDate >= from && o.orderDate <= to);
  const rangeKey = inRange.map((o) => o.id).join(',');

  useEffect(() => {
    setSelected(new Set(rangeKey ? rangeKey.split(',') : []));
  }, [rangeKey]);

  const chosen = inRange.filter((o) => selected.has(o.id));
  const pay = chosen.reduce((s, o) => s + (amounts[o.id] ?? 0), 0);
  const trips = chosen.reduce((s, o) => s + o.trips, 0);
  const cash = chosen.reduce((s, o) => s + codToCollect(o), 0);
  const codCount = chosen.filter((o) => codToCollect(o) > 0).length;
  const net = settleWithDriver(pay, cash);
  /** net = fee deducted from the COD cash now; later = driver hands over all the cash, fee waits for the monthly clearing */
  const [cashMode, setCashMode] = useState<'net' | 'later' | null>(null);
  const later = cash > 0 && cashMode === 'later';
  const handover = later ? cash : net.handover;
  const topUp = later ? 0 : net.topUp;
  const needsMethod = !later && (handover > 0 || topUp > 0);
  const allChosen = inRange.length > 0 && chosen.length === inRange.length;

  useEffect(() => {
    setCashMode(null);
  }, [cash, pay]);

  const toggle = (id: string) => {
    const next = new Set(selected);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    setSelected(next);
  };

  const submit = async () => {
    if (!chosen.length) return setError('เลือกออเดอร์อย่างน้อย 1 รายการ');
    if (cash > 0 && !cashMode) return setError('เลือกว่าหักค่ารถให้คนขับแล้ว หรือรับเงินเต็มจำนวน');
    if (needsMethod && !method) return setError('เลือกช่องทางการจ่ายเงิน');
    setSaving(true);
    setError('');
    try {
      if (later) {
        const received = await receiveDriverCod({
          driverId,
          orderIds: chosen.map((o) => o.id),
          note,
          by,
          cashExpected: cash,
        });
        onPaid(`รับเงินปลายทาง ${formatMoney(received)} บาท จากคนขับแล้ว · ค่ารถรอเคลียร์รอบเดือน`);
        return;
      }
      const no = await createDriverPayout({
        driverId,
        lines: chosen.map((o) => ({ orderId: o.id, amount: amounts[o.id] ?? 0 })),
        method: method ?? 'cash',
        note,
        by,
        cashExpected: cash,
      });
      onPaid(`บันทึกเคลียร์ค่ารถ ${no} แล้ว`);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'บันทึกไม่สำเร็จ');
      setSaving(false);
    }
  };

  const submitLabel = later
    ? `ยืนยันรับเงิน ${formatMoney(cash)} (ค่ารถรอเคลียร์รอบเดือน)`
    : handover
    ? `ยืนยันรับเงิน ${formatMoney(handover)} และเคลียร์ค่ารถ`
    : topUp
      ? `ยืนยันจ่ายค่ารถ ${formatMoney(topUp)}`
      : 'ยืนยันเคลียร์ค่ารถ';

  return (
    <Card className="p-4">
      <div className="mb-3 flex items-start justify-between gap-3">
        <div>
          <h2 className="font-semibold">เคลียร์ค่ารถ · {driverName}</h2>
          <p className="text-sm text-muted">{orders.length} ออเดอร์ที่ยังไม่ได้เคลียร์</p>
        </div>
        <button
          type="button"
          aria-label="ปิด"
          onClick={onClose}
          className="inline-flex min-h-11 min-w-11 items-center justify-center rounded text-muted hover:bg-subtle cursor-pointer"
        >
          <X size={18} aria-hidden />
        </button>
      </div>

      {!orders.length ? (
        <p className="text-sm text-muted">คนขับคนนี้ไม่มีค่ารถค้างจ่าย</p>
      ) : (
        <div className="flex flex-col gap-4">
          <div className="grid grid-cols-2 gap-3">
            <Field id="dp-from" label="ตั้งแต่วันที่">
              <Input id="dp-from" type="date" value={from} max={to} onChange={(e) => setFrom(e.target.value)} />
            </Field>
            <Field id="dp-to" label="ถึงวันที่">
              <Input id="dp-to" type="date" value={to} min={from} onChange={(e) => setTo(e.target.value)} />
            </Field>
          </div>

          <div>
            <div className="mb-1 flex items-center justify-between gap-3 px-1 text-xs text-muted">
              <label className="inline-flex cursor-pointer items-center gap-2">
                <input
                  type="checkbox"
                  className="h-4 w-4 cursor-pointer accent-[var(--color-primary)]"
                  checked={allChosen}
                  disabled={!inRange.length}
                  onChange={() => setSelected(allChosen ? new Set() : new Set(inRange.map((o) => o.id)))}
                />
                เลือกทั้งหมด ({chosen.length}/{inRange.length})
              </label>
              <span>ค่ารถ (บาท)</span>
            </div>
            <ul className="flex max-h-[28rem] flex-col divide-y divide-border overflow-y-auto overflow-x-hidden rounded border border-border">
              {inRange.map((o) => {
                const zone = zoneById(o.zoneId);
                const b = driverPayBreakdown(o, zone, settings.delivery);
                const truckLabel = o.truckSize === 3 ? 'รถ 3 คิว' : 'รถ 5 คิว';
                const isChosen = selected.has(o.id);
                return (
                  <li key={o.id} className={['flex items-start gap-3 px-3 py-2.5 text-sm', isChosen ? '' : 'opacity-60'].join(' ')}>
                    <input
                      type="checkbox"
                      aria-label={`เลือก ${o.orderNo}`}
                      className="mt-0.5 h-5 w-5 shrink-0 cursor-pointer accent-[var(--color-primary)]"
                      checked={isChosen}
                      onChange={() => toggle(o.id)}
                    />
                    <button type="button" className="min-w-0 flex-1 text-left cursor-pointer" onClick={() => toggle(o.id)}>
                      <span className="flex flex-wrap items-center gap-x-2 gap-y-1">
                        <span className="whitespace-nowrap font-medium tabular-nums">{o.orderNo}</span>
                        <SourceBadge source={o.source} />
                        {o.deliveryStatus !== 'delivered' ? <Badge tone="warning">ยังไม่ส่ง</Badge> : null}
                      </span>
                      <span className="block truncate text-xs text-muted">
                        {formatDateShort(o.orderDate)} · {o.customer.name}
                      </span>
                      <span className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-muted">
                        <PaymentBadge o={o} />
                        <span>
                          {o.truckSize ? `${o.truckSize} คิว × ` : ''}
                          {o.trips} เที่ยว · ค่าส่งในบิล {formatNumber(customerDeliveryFee(o))}
                        </span>
                      </span>
                      <span
                        className={['mt-1 block text-xs', b.source === 'zone' ? 'text-muted' : 'font-medium text-warning'].join(' ')}
                      >
                        {b.source === 'zone' && zone
                          ? `ค่ารถ ต.${zone.name} ${truckLabel} ${formatNumber(b.rate.base)}${b.rate.extra ? ` + ตามระยะ ${formatNumber(b.rate.extra)}` : ''} × ${o.trips} เที่ยว`
                          : b.source === 'stored'
                            ? 'ค่ารถตามที่บันทึกไว้ในออเดอร์'
                            : `${zone ? `ต.${zone.name} ยังไม่ได้ตั้งค่ารถ (${truckLabel})` : 'ไม่มีตำบล'} · ใช้ค่าส่งในบิลแทน`}
                      </span>
                    </button>
                    <div className="w-28 shrink-0">
                      <Input
                        aria-label={`ค่ารถ ${o.orderNo}`}
                        type="number"
                        inputMode="numeric"
                        min={0}
                        className="px-3 text-right tabular-nums"
                        value={amounts[o.id] || ''}
                        placeholder="0"
                        onChange={(e) => setAmounts({ ...amounts, [o.id]: Math.max(0, Number(e.target.value) || 0) })}
                      />
                    </div>
                  </li>
                );
              })}
              {!inRange.length ? <li className="px-3 py-3 text-sm text-muted">ไม่มีออเดอร์ในช่วงวันที่นี้</li> : null}
            </ul>
            <p className="mt-1 px-1 text-xs text-muted">
              ค่ารถตั้งต้น = (ค่ารถของตำบลตามขนาดรถ + ตามระยะ) × เที่ยว · ตำบลที่ยังไม่ได้ตั้งค่ารถใช้ค่าส่งในบิลแทน · แก้ตัวเลขได้ก่อนยืนยัน
            </p>
          </div>

          <div className="rounded border border-border">
            <dl className="flex flex-col gap-1.5 px-4 py-3 text-sm">
              {later ? (
                <>
                  <StatementRow label={`เงินที่คนขับเก็บจากลูกค้า (เก็บปลายทาง ${codCount} ออเดอร์)`} value={cash} />
                  <StatementRow
                    label={`ค่ารถคนขับ (${chosen.length} ออเดอร์ · ${formatNumber(trips)} เที่ยว) — ยังไม่จ่าย รอเคลียร์รอบเดือน`}
                    value={pay}
                  />
                </>
              ) : cash ? (
                <>
                  <StatementRow label={`เงินที่คนขับเก็บจากลูกค้า (เก็บปลายทาง ${codCount} ออเดอร์)`} value={cash} />
                  <StatementRow label={`หัก ค่ารถคนขับ (${chosen.length} ออเดอร์ · ${formatNumber(trips)} เที่ยว)`} value={pay} negative />
                </>
              ) : (
                <StatementRow label={`ค่ารถคนขับ (${chosen.length} ออเดอร์ · ${formatNumber(trips)} เที่ยว)`} value={pay} />
              )}
            </dl>
            <div
              className={[
                'flex items-center justify-between gap-3 rounded-b border-t px-4 py-3',
                handover ? 'border-amber-200 bg-warning-soft' : 'border-border bg-subtle',
              ].join(' ')}
            >
              <span className="flex items-center gap-2 font-semibold">
                {handover ? (
                  <>
                    <ArrowDownLeft size={18} className="text-warning" aria-hidden /> คนขับส่งเงินให้ร้าน
                  </>
                ) : topUp ? (
                  <>
                    <ArrowUpRight size={18} className="text-primary" aria-hidden /> {cash ? 'ร้านจ่ายค่ารถเพิ่ม' : 'ร้านจ่ายค่ารถคนขับ'}
                  </>
                ) : (
                  'หักกันพอดี ไม่ต้องจ่ายเพิ่ม'
                )}
              </span>
              <span className={['text-2xl font-bold tabular-nums', handover ? 'text-warning' : 'text-primary'].join(' ')}>
                {formatMoney(handover || topUp)}
              </span>
            </div>
          </div>

          {cash ? (
            <div className="flex flex-col gap-2" role="radiogroup" aria-label="รับเงินปลายทางจากคนขับ">
              <CashModeOption
                active={cashMode === 'net'}
                onClick={() => setCashMode('net')}
                title={
                  net.handover
                    ? `หักค่ารถให้คนขับแล้ว · รับเงิน ${formatMoney(net.handover)} บาท`
                    : net.topUp
                      ? `หักค่ารถให้คนขับแล้ว · ร้านจ่ายเพิ่ม ${formatMoney(net.topUp)} บาท`
                      : 'หักค่ารถให้คนขับแล้ว · หักกันพอดี'
                }
                detail={`เก็บปลายทาง ${formatMoney(cash)} − ค่ารถ ${formatMoney(pay)} · เคลียร์ค่ารถรอบนี้เลย`}
              />
              <CashModeOption
                active={cashMode === 'later'}
                onClick={() => setCashMode('later')}
                title={`ได้รับเงินสด ${formatMoney(cash)} บาท จากคนขับแล้ว`}
                detail={`ค่ารถ ${formatMoney(pay)} ยังไม่จ่าย รอเคลียร์ค่ารถทีเดียวในรอบเดือน`}
              />
              <p className="px-1 text-xs text-muted">ออเดอร์เก็บปลายทางจะเปลี่ยนเป็น "จ่ายแล้ว" และออกใบเสร็จให้อัตโนมัติ</p>
            </div>
          ) : null}

          {needsMethod ? (
            <PayMethodPicker
              value={method}
              onChange={setMethod}
              hints={handover ? DRIVER_PAYS_HINTS : PAY_HINTS}
              label={handover ? 'คนขับส่งเงินให้ร้านทาง' : 'ร้านจ่ายค่ารถทาง'}
            />
          ) : null}

          <Field id="dp-note" label="หมายเหตุ">
            <Input id="dp-note" value={note} onChange={(e) => setNote(e.target.value)} placeholder="เช่น โอนเข้าบัญชีภรรยา" />
          </Field>

          {error ? <ErrorBox message={error} /> : null}

          <Button
            variant="success"
            size="lg"
            onClick={submit}
            disabled={saving || !chosen.length || (cash > 0 && !cashMode) || (needsMethod && !method)}
          >
            <Check size={18} aria-hidden /> {saving ? 'กำลังบันทึก…' : submitLabel}
          </Button>
        </div>
      )}
    </Card>
  );
}
