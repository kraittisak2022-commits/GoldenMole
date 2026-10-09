import { useEffect, useMemo, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { Check, Trash2, X } from 'lucide-react';
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
import { createDriverPayout, deleteDriverPayout, listDriverPayouts } from '../data/driverPayouts';
import { listDriverUnpaidOrders } from '../data/orders';
import { useAsync } from '../hooks/useAsync';
import { codToCollect, deliveredCubes, suggestedDriverPay, summarizeDriverDues, zoneDriverFee } from '../lib/driverPay';
import { formatDateShort, formatDateTime, formatMoney, formatNumber, toIsoDate } from '../lib/format';
import { PAYMENT_METHOD_LABEL, type DriverPayout, type Order } from '../types';

const PAY_HINTS: Record<PayMethod, string> = { cash: 'จ่ายเงินสดให้คนขับ', transfer: 'โอนเข้าบัญชีคนขับ' };
const DRIVER_PAYS_HINTS: Record<PayMethod, string> = { cash: 'คนขับส่งเงินสด', transfer: 'คนขับโอนเข้าบัญชีร้าน' };

export default function DriverPayPage() {
  const { user, isSuperAdmin } = useAuth();
  const by = user?.displayName || user?.username || '';
  const { driverById, zoneById } = useCatalog();
  const [params, setParams] = useSearchParams();
  const selectedDriver = params.get('driver');

  const unpaid = useAsync(() => listDriverUnpaidOrders(), [], 'driver-unpaid');
  const payouts = useAsync(() => listDriverPayouts(), [], 'driver-payouts');
  const [actionError, setActionError] = useState('');
  const [paidNo, setPaidNo] = useState('');

  const dues = useMemo(() => summarizeDriverDues(unpaid.data ?? [], zoneById), [unpaid.data, zoneById]);
  const dueTotal = dues.reduce((s, d) => s + d.total, 0);
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
    setPaidNo('');
    try {
      await deleteDriverPayout(p.id, by);
      await reloadAll();
    } catch (err) {
      setActionError(err instanceof Error ? err.message : 'ลบไม่สำเร็จ');
    }
  };

  return (
    <div>
      <PageHeader title="เคลียร์ค่ารถ" subtitle="จ่ายค่ารถให้คนขับตามออเดอร์ที่วิ่งส่ง แล้วบันทึกว่าจ่ายแล้ว" />
      {actionError ? (
        <div className="mb-4">
          <ErrorBox message={actionError} />
        </div>
      ) : null}
      {paidNo ? (
        <div className="mb-4 flex items-center gap-2 rounded border border-emerald-200 bg-success-soft px-4 py-3 text-sm text-emerald-800">
          <Check size={18} aria-hidden /> บันทึกจ่ายค่ารถ {paidNo} แล้ว
        </div>
      ) : null}

      <div className="grid grid-cols-1 gap-5 lg:grid-cols-2">
        <section>
          <h2 className="mb-2 text-sm font-semibold text-muted">
            คนขับที่ยังไม่ได้รับค่ารถ{dueTotal ? ` · รวม ${formatMoney(dueTotal)} บาท` : ''}
          </h2>
          {unpaid.error ? <ErrorBox message={unpaid.error} /> : null}
          {unpaid.loading && !unpaid.data ? (
            <Loading />
          ) : (
            <Card className="overflow-hidden">
              {dues.length ? (
                <ul className="divide-y divide-border">
                  {dues.map((row) => (
                    <li key={row.driverId}>
                      <button
                        type="button"
                        onClick={() => selectDriver(row.driverId)}
                        className={[
                          'flex min-h-16 w-full items-center gap-3 px-4 py-3 text-left transition-colors hover:bg-subtle cursor-pointer',
                          selectedDriver === row.driverId ? 'bg-primary-soft/60' : '',
                        ].join(' ')}
                      >
                        <div className="min-w-0 flex-1">
                          <p className="truncate font-medium">{driverName(row.driverId)}</p>
                          <p className="text-xs text-muted">
                            {row.count} ออเดอร์ · {formatNumber(row.trips)} เที่ยว · ตั้งแต่ {formatDateShort(row.oldestDate)}
                          </p>
                        </div>
                        <div className="text-right">
                          <p className="font-semibold tabular-nums">{formatMoney(row.total)}</p>
                          {row.cash ? (
                            <p className="text-xs text-warning">เก็บปลายทาง {formatMoney(row.cash)}</p>
                          ) : (
                            <p className="text-xs text-muted">ค่ารถ</p>
                          )}
                        </div>
                      </button>
                    </li>
                  ))}
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
              onPaid={async (no) => {
                setActionError('');
                setPaidNo(no);
                await reloadAll();
              }}
            />
          ) : (
            <Card className="p-5 text-sm text-muted">เลือกคนขับทางซ้ายเพื่อจ่ายค่ารถ</Card>
          )}
        </section>
      </div>

      <section className="mt-8">
        <h2 className="mb-2 text-sm font-semibold text-muted">
          ประวัติจ่ายค่ารถ{selectedDriver ? ` · ${driverName(selectedDriver)}` : ''}
        </h2>
        {payouts.error ? <ErrorBox message={payouts.error} /> : null}
        {payouts.loading && !payouts.data ? (
          <Loading />
        ) : (
          <Card className="overflow-hidden">
            {visiblePayouts.length ? (
              <ul className="divide-y divide-border">
                {visiblePayouts.map((p) => (
                  <li key={p.id} className="flex flex-wrap items-center gap-3 px-4 py-3">
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <p className="font-medium tabular-nums">{p.payoutNo}</p>
                        <Badge tone="success">จ่ายแล้ว · {PAYMENT_METHOD_LABEL[p.method]}</Badge>
                      </div>
                      <p className="truncate text-sm">{p.driverName}</p>
                      <p className="text-xs text-muted">
                        {formatDateTime(p.createdAt)}
                        {p.createdBy ? ` · โดย ${p.createdBy}` : ''} · {p.orders.length} ออเดอร์ ·{' '}
                        {formatNumber(p.orders.reduce((s, o) => s + o.trips, 0))} เที่ยว
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
                      <p className="font-semibold tabular-nums">ค่ารถ {formatMoney(p.total)}</p>
                      {p.cashCollected ? (
                        <>
                          <p className="text-xs text-muted tabular-nums">รับเงินสดจากคนขับ {formatMoney(p.cashCollected)}</p>
                          <p className="text-xs font-medium tabular-nums">
                            {p.total >= p.cashCollected
                              ? `ร้านจ่ายคนขับ ${formatMoney(p.total - p.cashCollected)}`
                              : `คนขับส่งร้าน ${formatMoney(p.cashCollected - p.total)}`}
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
                ))}
              </ul>
            ) : (
              <Empty title="ยังไม่มีประวัติจ่ายค่ารถ" />
            )}
          </Card>
        )}
      </section>
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
  onPaid: (payoutNo: string) => void;
}) {
  const { zoneById } = useCatalog();
  const today = toIsoDate();
  const oldest = orders[0]?.orderDate ?? today;
  const [from, setFrom] = useState(oldest);
  const [to, setTo] = useState(today < oldest ? oldest : today);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [amounts, setAmounts] = useState<Record<string, number>>(() =>
    Object.fromEntries(orders.map((o) => [o.id, suggestedDriverPay(o, zoneById(o.zoneId))])),
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
  const total = chosen.reduce((s, o) => s + (amounts[o.id] ?? 0), 0);
  const trips = chosen.reduce((s, o) => s + o.trips, 0);
  const cash = chosen.reduce((s, o) => s + codToCollect(o), 0);
  const codCount = chosen.filter((o) => codToCollect(o) > 0).length;
  const net = total - cash;
  const needsMethod = net !== 0;
  const [cashConfirmed, setCashConfirmed] = useState(false);

  useEffect(() => {
    setCashConfirmed(false);
  }, [cash]);

  const toggle = (id: string) => {
    const next = new Set(selected);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    setSelected(next);
  };

  const submit = async () => {
    if (!chosen.length) return setError('เลือกออเดอร์อย่างน้อย 1 รายการ');
    if (needsMethod && !method) return setError('เลือกช่องทางการจ่ายเงิน');
    if (cash > 0 && !cashConfirmed) return setError('ยืนยันการรับเงินสดจากคนขับก่อน');
    setSaving(true);
    setError('');
    try {
      const no = await createDriverPayout({
        driverId,
        lines: chosen.map((o) => ({ orderId: o.id, amount: amounts[o.id] ?? 0 })),
        method: method ?? 'cash',
        note,
        by,
        cashExpected: cash,
      });
      onPaid(no);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'บันทึกไม่สำเร็จ');
      setSaving(false);
    }
  };

  return (
    <Card className="p-4">
      <div className="mb-3 flex items-start justify-between gap-3">
        <div>
          <h2 className="font-semibold">จ่ายค่ารถ</h2>
          <p className="text-sm text-muted">{driverName}</p>
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
            <p className="mb-1 flex justify-between px-1 text-xs text-muted">
              <span>ออเดอร์</span>
              <span>ค่ารถ (บาท)</span>
            </p>
            <ul className="flex max-h-96 flex-col divide-y divide-border overflow-y-auto overflow-x-hidden rounded border border-border">
              {inRange.map((o) => {
                const zone = zoneById(o.zoneId);
                const perCubic = zoneDriverFee(zone, o.truckSize);
                const truckLabel = o.truckSize === 3 ? 'รถ 3 คิว' : 'รถ 5 คิว';
                return (
                  <li key={o.id} className="flex min-h-14 items-center gap-3 px-3 py-2 text-sm">
                    <input
                      type="checkbox"
                      aria-label={`เลือก ${o.orderNo}`}
                      className="h-5 w-5 shrink-0 cursor-pointer accent-[var(--color-primary)]"
                      checked={selected.has(o.id)}
                      onChange={() => toggle(o.id)}
                    />
                    <button type="button" className="min-w-0 flex-1 text-left cursor-pointer" onClick={() => toggle(o.id)}>
                      <span className="flex flex-wrap items-center gap-x-2 gap-y-0.5">
                        <span className="whitespace-nowrap font-medium tabular-nums">{o.orderNo}</span>
                        <SourceBadge source={o.source} />
                        {o.deliveryStatus !== 'delivered' ? <Badge tone="warning">ยังไม่ส่ง</Badge> : null}
                      </span>
                      {codToCollect(o) ? (
                        <span className="block text-xs font-medium text-primary">เก็บเงินปลายทาง {formatNumber(codToCollect(o))}</span>
                      ) : null}
                      <span className="block truncate text-xs text-muted">
                        {formatDateShort(o.orderDate)} · {o.customer.name}
                      </span>
                      <span className="block text-xs text-muted">
                        {o.truckSize ? `${o.truckSize} คิว × ` : ''}
                        {o.trips} เที่ยว · เก็บลูกค้า {formatNumber(o.deliveryTotal - o.deliveryDiscount)}
                      </span>
                      {zone && perCubic ? (
                        <span className="block text-xs text-muted">
                          ต.{zone.name} · {truckLabel} {formatNumber(perCubic)} บาท/คิว × {formatNumber(deliveredCubes(o.items))} คิว
                        </span>
                      ) : (
                        <span className="block text-xs font-medium text-warning">
                          {zone ? `ต.${zone.name} ยังไม่ได้ตั้งค่ารถ (${truckLabel})` : 'ออเดอร์นี้ไม่มีตำบล'} · ใส่ค่ารถเอง
                        </span>
                      )}
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
              ตั้งต้นจากค่ารถของตำบลตามขนาดรถ (บาท/คิว) × จำนวนคิวที่ส่ง (ตั้งได้ที่ ตั้งค่า › ค่าส่งตามตำบล) แก้ตัวเลขได้ก่อนยืนยัน
            </p>
          </div>

          {cash ? (
            <dl className="flex flex-col gap-1.5 rounded bg-subtle px-4 py-3 text-sm">
              <div className="flex justify-between gap-3">
                <dt className="text-muted">
                  ค่ารถ · {chosen.length} ออเดอร์ · {formatNumber(trips)} เที่ยว
                </dt>
                <dd className="tabular-nums">{formatMoney(total)}</dd>
              </div>
              <div className="flex justify-between gap-3">
                <dt className="text-muted">หัก เงินเก็บปลายทาง ({codCount} ออเดอร์)</dt>
                <dd className="tabular-nums text-destructive">-{formatMoney(cash)}</dd>
              </div>
              <div className="mt-1 flex items-baseline justify-between gap-3 border-t border-border pt-2">
                <dt className="font-semibold">{net >= 0 ? 'ร้านจ่ายคนขับ' : 'คนขับต้องส่งเงินให้ร้าน'}</dt>
                <dd className={['text-xl font-bold tabular-nums', net >= 0 ? 'text-primary' : 'text-warning'].join(' ')}>
                  {formatMoney(Math.abs(net))}
                </dd>
              </div>
            </dl>
          ) : (
            <div className="flex items-center justify-between gap-3 rounded bg-subtle px-4 py-3">
              <span className="text-sm text-muted">
                {chosen.length} ออเดอร์ · {formatNumber(trips)} เที่ยว
              </span>
              <span className="text-xl font-bold tabular-nums text-primary">{formatMoney(total)}</span>
            </div>
          )}

          {cash ? (
            <label className="flex cursor-pointer items-start gap-3 rounded border-2 border-amber-300 bg-warning-soft px-4 py-3 text-sm">
              <input
                type="checkbox"
                className="mt-0.5 h-5 w-5 shrink-0 accent-[var(--color-primary)]"
                checked={cashConfirmed}
                onChange={(e) => setCashConfirmed(e.target.checked)}
              />
              <span>
                <span className="block font-semibold">ได้รับเงินสด {formatMoney(cash)} บาท จากคนขับแล้ว</span>
                <span className="block text-muted">
                  เงินค่าสินค้าที่คนขับเก็บจากลูกค้า ออเดอร์เก็บปลายทางจะเปลี่ยนเป็น "จ่ายแล้ว" และออกใบเสร็จให้อัตโนมัติ
                </span>
              </span>
            </label>
          ) : null}

          {needsMethod ? (
            <PayMethodPicker
              value={method}
              onChange={setMethod}
              hints={net > 0 ? PAY_HINTS : DRIVER_PAYS_HINTS}
              label={net < 0 ? 'คนขับส่งเงินส่วนต่างด้วย' : cash ? 'จ่ายส่วนต่างให้คนขับด้วย' : 'จ่ายค่ารถด้วย'}
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
            disabled={saving || !chosen.length || (needsMethod && !method) || (cash > 0 && !cashConfirmed)}
          >
            <Check size={18} aria-hidden /> {saving ? 'กำลังบันทึก…' : cash ? 'ยืนยันเคลียร์ค่ารถ' : 'ยืนยันจ่ายค่ารถ'}
          </Button>
        </div>
      )}
    </Card>
  );
}
