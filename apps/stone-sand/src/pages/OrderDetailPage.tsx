import { useEffect, useState, type ReactNode } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import {
  ArrowLeft,
  Ban,
  Check,
  Copy,
  ExternalLink,
  FileText,
  MapPin,
  Pencil,
  Phone,
  RotateCcw,
  Share2,
  Store,
  Trash2,
  Truck,
} from 'lucide-react';
import { useAuth } from '../auth/AuthProvider';
import { lineDiscount, totalCubic } from '../calc/pricing';
import DeliveryMap from '../components/map/DeliveryMap';
import OrderEditModal from '../components/OrderEditModal';
import DemoBadge from '../components/DemoBadge';
import SourceBadge from '../components/SourceBadge';
import Badge from '../components/ui/Badge';
import Button from '../components/ui/Button';
import Card from '../components/ui/Card';
import Field from '../components/ui/Field';
import Input from '../components/ui/Input';
import Select from '../components/ui/Select';
import { ErrorBox, Loading } from '../components/ui/States';
import Textarea from '../components/ui/Textarea';
import { useCatalog } from '../context/CatalogProvider';
import { deleteOrder, getOrder, markOrderPaid, markOrderUnpaid, setDeliveryStatus, updateOrderFields } from '../data/orders';
import { getStatement } from '../data/statements';
import { useAsync } from '../hooks/useAsync';
import { driverTripRate } from '../lib/driverPay';
import {
  deliveryFeeFormula,
  formatDateShort,
  formatDateTime,
  formatMoney,
  formatNumber,
  formatPhone,
  googleMapsUrl,
} from '../lib/format';
import { deliveryBadge, driverMessage, paymentBadge } from '../lib/orderStatus';
import {
  DELIVERY_STATUS_LABEL,
  PAYMENT_METHOD_LABEL,
  ROUTE_GROUP_LABEL,
  type DeliveryStatus,
  type Order,
  type StatusLogEntry,
} from '../types';

const DELIVERY_STEPS: DeliveryStatus[] = ['waiting', 'dispatched', 'delivered'];

export default function OrderDetailPage() {
  const { id = '' } = useParams();
  const { user, isSuperAdmin } = useAuth();
  const by = user?.displayName || user?.username || '';
  const navigate = useNavigate();
  const { zoneById, driverById, drivers, settings } = useCatalog();
  const { data: order, error, loading, setData } = useAsync(() => getOrder(id), [id], 'order');
  const { data: statement } = useAsync(
    () => (order?.statementId ? getStatement(order.statementId) : Promise.resolve(null)),
    [order?.statementId, order?.total],
  );
  const [editing, setEditing] = useState(false);

  const [busy, setBusy] = useState('');
  const [actionError, setActionError] = useState('');
  const [copied, setCopied] = useState(false);
  const [driverId, setDriverId] = useState('');
  const [wage, setWage] = useState(0);
  const [note, setNote] = useState('');

  useEffect(() => {
    if (!order) return;
    setDriverId(order.driverId ?? '');
    setWage(order.driverWage);
    setNote(order.note);
  }, [order?.id, order?.driverId, order?.driverWage, order?.note]);

  if (loading && !order) return <Loading />;
  if (error) return <ErrorBox message={error} />;
  if (!order) return <ErrorBox message="ไม่พบออเดอร์" />;

  const o = order;
  const zone = zoneById(o.zoneId);
  const driver = driverById(o.driverId);
  const delivery = o.fulfillment === 'delivery';
  const pay = paymentBadge(o);
  const del = deliveryBadge(o);
  const inOpenStatement = !!statement && statement.status === 'open';
  const inClearedStatement = !!statement && statement.status === 'cleared';
  const wagePaid = !!o.driverPayoutId;

  const run = async (key: string, fn: () => Promise<Order>) => {
    setBusy(key);
    setActionError('');
    try {
      setData(await fn());
    } catch (err) {
      setActionError(err instanceof Error ? err.message : 'ทำรายการไม่สำเร็จ');
    } finally {
      setBusy('');
    }
  };

  const payWith = (method: 'cash' | 'transfer' | 'cod') => run(`pay-${method}`, () => markOrderPaid(o.id, method, by));
  const undoPay = () => {
    if (!window.confirm('ยกเลิกสถานะ "จ่ายแล้ว" ของออเดอร์นี้?')) return;
    void run('unpay', () => markOrderUnpaid(o.id, by));
  };
  const removeOrder = async () => {
    const inStatement = statement ? ` และเอาออกจากใบวางบิล ${statement.statementNo}` : '';
    if (!window.confirm(`ลบออเดอร์ ${o.orderNo} ถาวร${inStatement}? กู้คืนไม่ได้`)) return;
    setBusy('delete');
    setActionError('');
    try {
      await deleteOrder(o.id);
      navigate('/orders', { replace: true });
    } catch (err) {
      setActionError(err instanceof Error ? err.message : 'ลบไม่สำเร็จ');
      setBusy('');
    }
  };
  const toggleCancel = () => {
    const msg = o.cancelled ? 'กู้คืนออเดอร์นี้?' : 'ยกเลิกออเดอร์นี้? บิลจะแสดงว่ายกเลิก';
    if (!window.confirm(msg)) return;
    void run('cancel', () => updateOrderFields(o.id, { cancelled: !o.cancelled }, by, o));
  };

  const pickDriver = (value: string) => {
    setDriverId(value);
    const { perTrip } = driverTripRate(zone, o.truckSize, o.roadDistanceKm, settings.delivery);
    if (value && perTrip) setWage(perTrip * o.trips);
  };
  const driverDirty = (driverId || null) !== o.driverId || wage !== o.driverWage;
  const saveDriver = () =>
    run('driver', () =>
      updateOrderFields(
        o.id,
        {
          ...((driverId || null) !== o.driverId ? { driverId: driverId || null } : {}),
          ...(wage !== o.driverWage ? { driverWage: wage } : {}),
        },
        by,
        o,
      ),
    );
  const saveNote = () => run('note', () => updateOrderFields(o.id, { note }, by, o));

  const message = driverMessage(o, zone, driverById(driverId) ?? driver);
  const copyMessage = async () => {
    try {
      await navigator.clipboard.writeText(message);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      window.prompt('คัดลอกข้อความนี้', message);
    }
  };

  return (
    <div
      className="mx-auto max-w-3xl"
      data-order-id={o.id}
      data-payment={o.paymentStatus}
      data-delivery={o.deliveryStatus}
      data-cancelled={o.cancelled ? '1' : '0'}
      data-cleared={o.cleared ? '1' : '0'}
      data-statement={statement ? statement.status : ''}
    >
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <Link
            to="/orders"
            aria-label="กลับไปหน้าออเดอร์"
            className="inline-flex min-h-11 min-w-11 items-center justify-center rounded text-muted hover:bg-subtle hover:text-ink"
          >
            <ArrowLeft size={20} aria-hidden />
          </Link>
          <div>
            <div className="flex flex-wrap items-center gap-2">
              <h1 className="text-xl font-semibold tabular-nums" data-tour="order-no">
                {o.orderNo}
              </h1>
              <SourceBadge source={o.source} long />
              {o.demo ? <DemoBadge /> : null}
            </div>
            <p className="text-sm text-muted">
              {formatDateShort(o.orderDate)}
              {o.receiptNo ? ` · ใบเสร็จ ${o.receiptNo}` : ''}
              {o.createdBy ? ` · โดย ${o.createdBy}` : ''}
            </p>
          </div>
        </div>
        <div className="flex flex-wrap gap-2">
          {isSuperAdmin || o.demo ? (
            <Button variant="secondary" onClick={() => setEditing(true)} disabled={!!busy} data-tour="edit-order">
              <Pencil size={16} aria-hidden /> แก้ไขออเดอร์
            </Button>
          ) : null}
          <Link
            to={`/bill/order/${o.id}`}
            data-tour="bill-link"
            className="inline-flex min-h-11 items-center gap-2 rounded bg-primary px-4 text-sm font-medium text-primary-foreground hover:bg-primary-hover"
          >
            <FileText size={18} aria-hidden /> ดู / พิมพ์บิล
          </Link>
        </div>
      </div>

      {o.cancelled ? (
        <div className="mb-4 flex items-center gap-2 rounded border border-red-200 bg-destructive-soft px-4 py-3 text-sm text-red-700">
          <Ban size={18} aria-hidden /> ออเดอร์นี้ถูกยกเลิกแล้ว
        </div>
      ) : null}
      {actionError ? (
        <div className="mb-4">
          <ErrorBox message={actionError} />
        </div>
      ) : null}

      <div className="flex flex-col gap-4">
        <Card className="p-4" data-tour="status-card">
          <SectionTitle>สถานะ</SectionTitle>
          <div className="flex flex-col divide-y divide-border">
            <StatusRow label="การชำระเงิน" badge={<Badge tone={pay.tone}>{pay.label}</Badge>}>
              <p className="text-sm text-muted">
                {PAYMENT_METHOD_LABEL[o.paymentMethod]}
                {o.paidAt ? ` · รับเงิน ${formatDateTime(o.paidAt)}` : ''}
              </p>
              {o.driverCashReported != null && o.paymentStatus !== 'paid' && !o.cancelled ? (
                <p
                  className={`text-sm font-medium ${o.driverCashReported < o.total ? 'text-amber-700' : 'text-emerald-700'}`}
                >
                  คนขับแจ้งเก็บเงินสด {formatMoney(o.driverCashReported)} บาท
                  {o.driverCashReported < o.total ? ` (ขาด ${formatMoney(o.total - o.driverCashReported)} บาท)` : ''}
                  {o.driverReportedAt ? ` · ${formatDateTime(o.driverReportedAt)}` : ''} — รับเงินจากคนขับตอนเคลียร์ค่ารถ
                </p>
              ) : null}
              {!o.cancelled && o.paymentStatus !== 'paid' ? (
                inOpenStatement ? (
                  <p className="text-sm text-muted">
                    อยู่ในใบวางบิล{' '}
                    <Link to={`/statements?open=${statement!.id}`} className="font-medium text-primary underline">
                      {statement!.statementNo}
                    </Link>{' '}
                    — เคลียร์ผ่านใบวางบิล
                  </p>
                ) : (
                  <div className="flex flex-wrap gap-2" data-tour="pay-buttons">
                    <Button variant="success" onClick={() => payWith('cash')} disabled={!!busy}>
                      <Check size={16} aria-hidden /> รับเงินสด
                    </Button>
                    <Button variant="secondary" onClick={() => payWith('transfer')} disabled={!!busy}>
                      รับโอนแล้ว
                    </Button>
                    {o.paymentMethod === 'cod' ? (
                      <Button variant="secondary" onClick={() => payWith('cod')} disabled={!!busy}>
                        เก็บปลายทางแล้ว
                      </Button>
                    ) : null}
                  </div>
                )
              ) : null}
              {o.paymentStatus === 'paid' && !inClearedStatement && !o.cancelled ? (
                <button
                  type="button"
                  onClick={undoPay}
                  disabled={!!busy}
                  className="inline-flex min-h-11 items-center gap-1.5 self-start text-sm text-muted underline hover:text-ink cursor-pointer"
                >
                  <RotateCcw size={14} aria-hidden /> ยกเลิกการรับเงิน
                </button>
              ) : null}
            </StatusRow>

            {delivery ? (
              <StatusRow label="การจัดส่ง" badge={<Badge tone={del.tone}>{del.label}</Badge>}>
                {o.deliveredAt ? <p className="text-sm text-muted">ส่งถึง {formatDateTime(o.deliveredAt)}</p> : null}
                {!o.cancelled ? (
                  <div
                    className="grid grid-cols-3 gap-1 rounded border border-border p-1"
                    role="radiogroup"
                    aria-label="สถานะจัดส่ง"
                    data-tour="delivery-steps"
                  >
                    {DELIVERY_STEPS.map((st) => (
                      <button
                        key={st}
                        type="button"
                        role="radio"
                        aria-checked={o.deliveryStatus === st}
                        disabled={!!busy}
                        onClick={() => o.deliveryStatus !== st && run(`del-${st}`, () => setDeliveryStatus(o.id, st, by))}
                        className={[
                          'min-h-11 rounded px-2 text-sm font-medium transition-colors cursor-pointer',
                          o.deliveryStatus === st ? 'bg-primary text-primary-foreground' : 'text-muted hover:bg-subtle',
                        ].join(' ')}
                      >
                        {DELIVERY_STATUS_LABEL[st]}
                      </button>
                    ))}
                  </div>
                ) : null}
              </StatusRow>
            ) : (
              <StatusRow label="การรับสินค้า" badge={<Badge tone="neutral">มารับเอง</Badge>} />
            )}

            <StatusRow
              label="เคลียร์บิล"
              badge={o.cleared ? <Badge tone="success">เคลียร์แล้ว</Badge> : <Badge tone="warning">ยังไม่เคลียร์</Badge>}
            >
              {o.clearedAt ? <p className="text-sm text-muted">เคลียร์เมื่อ {formatDateTime(o.clearedAt)}</p> : null}
              {statement ? (
                <p className="text-sm text-muted">
                  ใบวางบิล{' '}
                  <Link to={`/bill/statement/${statement.id}`} className="font-medium text-primary underline">
                    {statement.statementNo}
                  </Link>
                </p>
              ) : !o.cleared && o.paymentStatus === 'credit' && !o.cancelled ? (
                <Link
                  to={`/statements?customer=${o.customerId}&source=${o.source}`}
                  className="text-sm font-medium text-primary underline"
                  data-tour="to-statement"
                >
                  รวมเข้าใบวางบิลรายเดือน
                </Link>
              ) : null}
            </StatusRow>
          </div>
        </Card>

        <Card className="p-4">
          <SectionTitle>ลูกค้า</SectionTitle>
          <p className="font-medium">{o.customer.name}</p>
          {o.customer.phone ? (
            <a href={`tel:${o.customer.phone}`} className="mt-1 inline-flex min-h-11 items-center gap-1.5 text-sm text-primary">
              <Phone size={14} aria-hidden /> {formatPhone(o.customer.phone)}
            </a>
          ) : null}
          {o.customer.address ? <p className="text-sm text-muted">{o.customer.address}</p> : null}
          <Link to={`/customers?open=${o.customerId}`} className="mt-2 inline-block text-sm text-primary underline">
            ดูประวัติลูกค้า
          </Link>
        </Card>

        <Card className="overflow-hidden">
          <div className="px-4 pt-4">
            <SectionTitle>รายการสินค้า</SectionTitle>
          </div>
          <ul className="divide-y divide-border border-t border-border">
            {o.items.map((it) => (
              <li key={it.id ?? it.name} className="flex items-start justify-between gap-3 px-4 py-3 text-sm">
                <div>
                  <p className="font-medium">{it.name}</p>
                  <p className="text-muted">
                    {formatNumber(it.quantity)} {it.unit} × {formatNumber(it.unitPrice)}
                  </p>
                  {it.discountPerUnit ? (
                    <p className="text-success">
                      ลด{it.unit}ละ {formatNumber(it.discountPerUnit)} บาท (-
                      {formatMoney(lineDiscount(it.unitPrice, it.quantity, it.discountPerUnit))})
                    </p>
                  ) : null}
                </div>
                <p className="tabular-nums">{formatMoney(it.amount)}</p>
              </li>
            ))}
          </ul>
          <dl className="flex flex-col gap-1 border-t border-border px-4 py-3 text-sm">
            <TotalRow label="ค่าสินค้า" value={formatMoney(o.subtotal)} />
            {delivery ? (
              <TotalRow
                label={`ค่าจัดส่ง (${deliveryFeeFormula({ ...o, cubic: totalCubic(o.items) })})`}
                value={formatMoney(o.deliveryTotal)}
              />
            ) : null}
            {o.deliveryDiscount ? <TotalRow label="ส่วนลดค่าส่ง" value={`-${formatMoney(o.deliveryDiscount)}`} /> : null}
            {o.discountAmount - o.deliveryDiscount > 0 ? (
              <TotalRow
                label={
                  o.items.some((it) => it.discountPerUnit)
                    ? 'ส่วนลด (ต่อคิว + ท้ายบิล)'
                    : `ส่วนลด${o.discountType === 'percent' ? ` ${formatNumber(o.discountValue)}%` : ''}`
                }
                value={`-${formatMoney(o.discountAmount - o.deliveryDiscount)}`}
              />
            ) : null}
            <div className="mt-1 flex items-baseline justify-between border-t border-border pt-2">
              <dt className="font-semibold">ยอดสุทธิ</dt>
              <dd className="text-xl font-bold tabular-nums text-primary">{formatMoney(o.total)}</dd>
            </div>
          </dl>
        </Card>

        {delivery ? (
          <Card className="p-4">
            <SectionTitle>
              <Truck size={16} aria-hidden /> การจัดส่ง
            </SectionTitle>
            <div className="mb-3 grid grid-cols-2 gap-2 text-sm sm:grid-cols-4">
              <Info label="ตำบล" value={zone?.name ?? '—'} />
              <Info label="รถ" value={o.truckSize ? `${o.truckSize} คิว × ${o.trips}` : '—'} />
              <Info label="ระยะจากถนนใหญ่" value={o.roadDistanceKm != null ? `${formatNumber(o.roadDistanceKm)} กม.` : '—'} />
              {o.feePerCubic > 0 ? (
                <Info
                  label="ค่าส่ง"
                  value={`${formatNumber(o.feePerCubic)}/คิว${o.feePerTrip ? ` + ${formatNumber(o.feePerTrip)}/เที่ยว` : ''}`}
                />
              ) : (
                <Info label="ค่าส่ง/เที่ยว" value={formatNumber(o.feePerTrip)} />
              )}
            </div>
            {o.deliveryAddress ? (
              <p className="mb-3 flex items-start gap-1.5 text-sm">
                <MapPin size={16} className="mt-0.5 shrink-0 text-muted" aria-hidden /> {o.deliveryAddress}
              </p>
            ) : null}
            {o.pinLat != null && o.pinLng != null ? (
              <div className="mb-3 flex flex-col gap-2">
                <DeliveryMap value={{ lat: o.pinLat, lng: o.pinLng }} height={220} readOnly />
                <a
                  href={googleMapsUrl(o.pinLat, o.pinLng)}
                  target="_blank"
                  rel="noreferrer"
                  className="inline-flex min-h-11 items-center gap-1.5 self-start text-sm font-medium text-primary"
                >
                  <ExternalLink size={14} aria-hidden /> เปิดใน Google Maps
                </a>
              </div>
            ) : null}

            <div className="flex flex-col gap-3 border-t border-border pt-3">
              <div className="grid grid-cols-1 gap-3 sm:grid-cols-[minmax(0,1fr)_10rem]">
                <Field id="d-driver" label="คนขับ">
                  <Select id="d-driver" value={driverId} onChange={(e) => pickDriver(e.target.value)} disabled={o.cancelled || wagePaid}>
                    <option value="">— ยังไม่ระบุ —</option>
                    {drivers
                      .filter((d) => d.active || d.id === o.driverId)
                      .map((d) => (
                        <option key={d.id} value={d.id}>
                          {d.name} · {d.truckSize} คิว · {ROUTE_GROUP_LABEL[d.routeGroup]}
                        </option>
                      ))}
                  </Select>
                </Field>
                <Field id="d-wage" label="ค่าจ้างคนขับ (บาท)">
                  <Input
                    id="d-wage"
                    type="number"
                    inputMode="numeric"
                    min={0}
                    value={wage || ''}
                    placeholder="0"
                    onChange={(e) => setWage(Math.max(0, Number(e.target.value) || 0))}
                    disabled={o.cancelled || wagePaid}
                  />
                </Field>
              </div>
              {o.driverId ? (
                <div className="flex flex-wrap items-center gap-2 text-sm">
                  {wagePaid ? (
                    <>
                      <Badge tone="success">จ่ายค่ารถแล้ว</Badge>
                      <span className="text-muted">ลบรายการจ่ายในหน้าเคลียร์ค่ารถก่อน ถ้าต้องการแก้คนขับหรือค่าจ้าง</span>
                    </>
                  ) : (
                    <Badge tone="warning">ค่ารถยังไม่จ่าย</Badge>
                  )}
                  <Link to={`/driver-pay?driver=${o.driverId}`} className="font-medium text-primary underline">
                    เคลียร์ค่ารถ
                  </Link>
                </div>
              ) : null}
              {driver?.contacts.length ? (
                <div className="flex flex-wrap gap-2">
                  {driver.contacts.map((c) => (
                    <a
                      key={c.phone}
                      href={`tel:${c.phone}`}
                      className="inline-flex min-h-11 items-center gap-1.5 rounded border border-border px-3 text-sm hover:bg-subtle"
                    >
                      <Phone size={14} aria-hidden /> {c.label ? `${c.label} ` : ''}
                      {formatPhone(c.phone)}
                    </a>
                  ))}
                </div>
              ) : null}
              <div className="flex flex-wrap gap-2">
                {driverDirty ? (
                  <Button onClick={saveDriver} disabled={!!busy}>
                    บันทึกคนขับ
                  </Button>
                ) : null}
                <Button variant="secondary" onClick={copyMessage} data-tour="copy-driver">
                  {copied ? <Check size={16} aria-hidden /> : <Copy size={16} aria-hidden />}
                  {copied ? 'คัดลอกแล้ว' : 'คัดลอกข้อความส่งคนขับ'}
                </Button>
                <a
                  href={`https://line.me/R/share?text=${encodeURIComponent(message)}`}
                  target="_blank"
                  rel="noreferrer"
                  className="inline-flex min-h-11 items-center gap-2 rounded border border-border bg-surface px-4 text-sm font-medium hover:bg-subtle"
                >
                  <Share2 size={16} aria-hidden /> ส่งทาง LINE
                </a>
              </div>
            </div>
          </Card>
        ) : (
          <Card className="flex items-center gap-3 p-4 text-sm text-muted">
            <Store size={18} className="text-primary" aria-hidden /> ลูกค้ามารับเองที่ท่าทราย
          </Card>
        )}

        <Card className="p-4">
          <Field id="o-note" label="หมายเหตุ">
            <Textarea id="o-note" rows={2} value={note} onChange={(e) => setNote(e.target.value)} />
          </Field>
          {note !== o.note ? (
            <Button className="mt-2" onClick={saveNote} disabled={!!busy}>
              บันทึกหมายเหตุ
            </Button>
          ) : null}
        </Card>

        <Card className="p-4">
          <SectionTitle>ประวัติ</SectionTitle>
          <ol className="flex flex-col gap-2">
            {[...o.statusLog].reverse().map((entry, i) => (
              <li key={`${entry.at}-${i}`} className="flex gap-3 text-sm">
                <span className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-primary/60" aria-hidden />
                <span className="flex-1">
                  {logLabel(entry, driverById)}
                  <span className="block text-xs text-muted">
                    {formatDateTime(entry.at)}
                    {entry.by ? ` · ${entry.by}` : ''}
                  </span>
                </span>
              </li>
            ))}
          </ol>
        </Card>

        <div className="flex flex-wrap justify-end gap-2">
          <Button variant="ghost" className="text-destructive hover:text-destructive" onClick={removeOrder} disabled={!!busy}>
            <Trash2 size={16} aria-hidden /> ลบออเดอร์
          </Button>
          {!inClearedStatement && !inOpenStatement ? (
            <Button variant={o.cancelled ? 'secondary' : 'ghost'} onClick={toggleCancel} disabled={!!busy} data-tour="cancel-order">
              {o.cancelled ? <RotateCcw size={16} aria-hidden /> : <Ban size={16} aria-hidden />}
              {o.cancelled ? 'กู้คืนออเดอร์' : 'ยกเลิกออเดอร์'}
            </Button>
          ) : null}
        </div>
      </div>

      {editing ? (
        <OrderEditModal
          order={o}
          by={by}
          onClose={() => setEditing(false)}
          onSaved={(next) => {
            setEditing(false);
            setData(next);
          }}
        />
      ) : null}
    </div>
  );
}

function logLabel(e: StatusLogEntry, driverById: (id: string) => { name: string } | undefined): string {
  const [kind, arg] = e.event.split(':');
  switch (kind) {
    case 'created':
      return 'สร้างออเดอร์';
    case 'paid':
      return `รับเงินแล้ว (${PAYMENT_METHOD_LABEL[arg as keyof typeof PAYMENT_METHOD_LABEL] ?? arg})`;
    case 'unpaid':
      return 'ยกเลิกการรับเงิน';
    case 'delivery':
      return `สถานะจัดส่ง: ${DELIVERY_STATUS_LABEL[arg as DeliveryStatus] ?? arg}`;
    case 'cleared':
      return `เคลียร์บิลกับใบวางบิล ${arg}`;
    case 'driver':
      return 'เปลี่ยนคนขับ';
    case 'wage':
      return `ค่าจ้างคนขับ ${formatNumber(Number(arg))} บาท`;
    case 'cancelled':
      return 'ยกเลิกออเดอร์';
    case 'edited':
      return 'แก้ไขออเดอร์';
    case 'uncleared':
      return `ลบใบวางบิล ${arg} (กลับเป็นยังไม่เคลียร์)`;
    case 'restored':
      return 'กู้คืนออเดอร์';
    case 'wage_paid':
      return `จ่ายค่ารถให้คนขับแล้ว (${arg})`;
    case 'wage_unpaid':
      return `ลบรายการจ่ายค่ารถ ${arg} (กลับเป็นค่ารถยังไม่จ่าย)`;
    case 'driver_cash':
      return `คนขับแจ้งเก็บเงินปลายทาง ${formatMoney(Number(arg))} บาท`;
    default:
      return driverById(arg)?.name ?? e.event;
  }
}

function SectionTitle({ children }: { children: ReactNode }) {
  return <h2 className="mb-3 flex items-center gap-2 text-sm font-semibold text-muted">{children}</h2>;
}

function StatusRow({ label, badge, children }: { label: string; badge: ReactNode; children?: ReactNode }) {
  return (
    <div className="flex flex-col gap-2 py-3 first:pt-0 last:pb-0">
      <div className="flex items-center justify-between gap-3">
        <p className="font-medium">{label}</p>
        {badge}
      </div>
      {children}
    </div>
  );
}

function TotalRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between gap-3">
      <dt className="text-muted">{label}</dt>
      <dd className="tabular-nums">{value}</dd>
    </div>
  );
}

function Info({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded bg-subtle px-3 py-2">
      <p className="text-xs text-muted">{label}</p>
      <p className="font-medium">{value}</p>
    </div>
  );
}
