import { useEffect, useMemo, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { Check, FileText, Trash2, X } from 'lucide-react';
import { useAuth } from '../auth/AuthProvider';
import { useVisibleSources } from '../auth/useVisibleSources';
import PayMethodPicker, { type PayMethod } from '../components/PayMethodPicker';
import SourceBadge from '../components/SourceBadge';
import Badge from '../components/ui/Badge';
import Button from '../components/ui/Button';
import Card from '../components/ui/Card';
import Chip from '../components/ui/Chip';
import Field from '../components/ui/Field';
import Input from '../components/ui/Input';
import Modal from '../components/ui/Modal';
import PageHeader from '../components/ui/PageHeader';
import { Empty, ErrorBox, Loading } from '../components/ui/States';
import Textarea from '../components/ui/Textarea';
import { listUnclearedOrders } from '../data/orders';
import { clearStatement, createStatement, deleteStatement, listStatements } from '../data/statements';
import { useAsync } from '../hooks/useAsync';
import { formatDateShort, formatMoney, formatNumber, formatPhone, toIsoDate } from '../lib/format';
import { summarizeOutstanding } from '../lib/orderStatus';
import {
  ORDER_SOURCES,
  ORDER_SOURCE_LABEL,
  ORDER_SOURCE_SHORT,
  PAYMENT_METHOD_LABEL,
  type Order,
  type OrderSource,
  type Statement,
} from '../types';

type StatusFilter = 'open' | 'cleared' | 'all';

const CLEAR_HINTS: Record<PayMethod, string> = { cash: 'รับเป็นเงินสด', transfer: 'โอนเข้าบัญชี / พร้อมเพย์' };

export default function StatementsPage() {
  const { user, isSuperAdmin, lockedSource } = useAuth();
  const sources = useVisibleSources();
  const by = user?.displayName || user?.username || '';
  const navigate = useNavigate();
  const [params, setParams] = useSearchParams();
  const selectedCustomer = params.get('customer');
  const sourceParam = params.get('source');
  const highlight = params.get('open');

  const uncleared = useAsync(() => listUnclearedOrders(), [], 'orders-uncleared');
  const statements = useAsync(() => listStatements(), [], 'statements');
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('open');
  const [clearing, setClearing] = useState<Statement | null>(null);
  const [clearMethod, setClearMethod] = useState<PayMethod | null>(null);
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState('');

  const summary = useMemo(() => summarizeOutstanding(uncleared.data ?? []), [uncleared.data]);
  const selectedSource: OrderSource =
    lockedSource ??
    ORDER_SOURCES.find((s) => s === sourceParam) ??
    summary.find((r) => r.customerId === selectedCustomer && r.unbilledCount)?.source ??
    'shop';
  const customerUnbilled = useMemo(
    () => (uncleared.data ?? []).filter((o) => o.customerId === selectedCustomer && !o.statementId),
    [uncleared.data, selectedCustomer],
  );
  const visibleStatements = (statements.data ?? []).filter((s) => statusFilter === 'all' || s.status === statusFilter);
  const openTotal = (statements.data ?? []).filter((s) => s.status === 'open').reduce((sum, s) => sum + s.total, 0);

  const selectCustomer = (id: string | null, source?: OrderSource) => {
    const next = new URLSearchParams(params);
    if (id) next.set('customer', id);
    else next.delete('customer');
    if (id && source) next.set('source', source);
    else next.delete('source');
    setParams(next, { replace: true });
  };

  const reloadAll = async () => {
    await Promise.all([uncleared.reload(), statements.reload()]);
  };

  const openClear = (s: Statement) => {
    setClearMethod(null);
    setClearing(s);
  };

  const confirmClear = async () => {
    if (!clearing || !clearMethod) return;
    setBusy(true);
    setActionError('');
    try {
      await clearStatement(clearing.id, clearMethod, by);
      setClearing(null);
      await reloadAll();
    } catch (err) {
      setActionError(err instanceof Error ? err.message : 'เคลียร์บิลไม่สำเร็จ');
    } finally {
      setBusy(false);
    }
  };

  const remove = async (s: Statement) => {
    const msg =
      s.status === 'cleared'
        ? `ลบใบวางบิล ${s.statementNo} ที่เคลียร์แล้ว? ออเดอร์ในใบนี้จะกลับไปเป็น "ยังไม่จ่าย / ยังไม่เคลียร์"`
        : `ลบใบวางบิล ${s.statementNo}? ออเดอร์จะกลับไปเป็นยังไม่วางบิล`;
    if (!window.confirm(msg)) return;
    setActionError('');
    try {
      await deleteStatement(s.id, by);
      await reloadAll();
    } catch (err) {
      setActionError(err instanceof Error ? err.message : 'ลบไม่สำเร็จ');
    }
  };

  return (
    <div>
      <PageHeader title="เคลียร์บิล" subtitle="รวมออเดอร์ค้างจ่ายของลูกค้าประจำเป็นใบวางบิลรายเดือน แล้วกดเคลียร์เมื่อได้รับเงิน" />
      {actionError ? (
        <div className="mb-4">
          <ErrorBox message={actionError} />
        </div>
      ) : null}

      <div className="grid grid-cols-1 gap-5 lg:grid-cols-2">
        <section>
          <h2 className="mb-2 text-sm font-semibold text-muted">ลูกค้าที่ยังไม่เคลียร์บิล</h2>
          {uncleared.error ? <ErrorBox message={uncleared.error} /> : null}
          {uncleared.loading && !uncleared.data ? (
            <Loading />
          ) : (
            <Card className="overflow-hidden">
              {summary.length ? (
                <ul className="divide-y divide-border">
                  {summary.map((row) => (
                    <li key={`${row.customerId}:${row.source}`}>
                      <button
                        type="button"
                        onClick={() => selectCustomer(row.customerId, row.source)}
                        className={[
                          'flex min-h-16 w-full items-center gap-3 px-4 py-3 text-left transition-colors hover:bg-subtle cursor-pointer',
                          selectedCustomer === row.customerId && selectedSource === row.source ? 'bg-primary-soft/60' : '',
                        ].join(' ')}
                      >
                        <div className="min-w-0 flex-1">
                          <div className="flex min-w-0 items-center gap-2">
                            <p className="truncate font-medium">{row.name}</p>
                            <SourceBadge source={row.source} />
                          </div>
                          <p className="text-xs text-muted">
                            {row.count} ออเดอร์ · ตั้งแต่ {formatDateShort(row.oldestDate)}
                            {row.unbilledCount < row.count ? ` · วางบิลแล้ว ${row.count - row.unbilledCount}` : ''}
                          </p>
                        </div>
                        <div className="text-right">
                          <p className="font-semibold tabular-nums">{formatMoney(row.total)}</p>
                          {row.unbilledCount ? (
                            <p className="text-xs text-warning">ยังไม่วางบิล {formatMoney(row.unbilledTotal)}</p>
                          ) : (
                            <p className="text-xs text-muted">รอเคลียร์</p>
                          )}
                        </div>
                      </button>
                    </li>
                  ))}
                </ul>
              ) : (
                <Empty title="ไม่มียอดค้าง ทุกบิลเคลียร์แล้ว" />
              )}
            </Card>
          )}
        </section>

        <section>
          {selectedCustomer && !uncleared.data ? (
            <Loading />
          ) : selectedCustomer ? (
            <CreateStatementPanel
              key={`${selectedCustomer}-${selectedSource}-${uncleared.data?.length}`}
              customerId={selectedCustomer}
              source={selectedSource}
              orders={customerUnbilled.filter((o) => o.source === selectedSource)}
              sources={sources}
              sourceCounts={Object.fromEntries(
                ORDER_SOURCES.map((s) => [s, customerUnbilled.filter((o) => o.source === s).length]),
              ) as Record<OrderSource, number>}
              by={by}
              onSource={(s) => selectCustomer(selectedCustomer, s)}
              onClose={() => selectCustomer(null)}
              onCreated={(s) => navigate(`/bill/statement/${s.id}`)}
            />
          ) : (
            <Card className="p-5 text-sm text-muted">เลือกลูกค้าทางซ้ายเพื่อสร้างใบวางบิล</Card>
          )}
        </section>
      </div>

      <section className="mt-8">
        <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
          <h2 className="text-sm font-semibold text-muted">
            ใบวางบิล{openTotal ? ` · รอเก็บเงิน ${formatMoney(openTotal)} บาท` : ''}
          </h2>
          <div className="flex gap-2">
            {(['open', 'cleared', 'all'] as StatusFilter[]).map((f) => (
              <Chip key={f} active={statusFilter === f} onClick={() => setStatusFilter(f)}>
                {f === 'open' ? 'รอเคลียร์' : f === 'cleared' ? 'เคลียร์แล้ว' : 'ทั้งหมด'}
              </Chip>
            ))}
          </div>
        </div>
        {statements.error ? <ErrorBox message={statements.error} /> : null}
        {statements.loading && !statements.data ? (
          <Loading />
        ) : (
          <Card className="overflow-hidden">
            {visibleStatements.length ? (
              <ul className="divide-y divide-border">
                {visibleStatements.map((s) => (
                  <li
                    key={s.id}
                    className={['flex flex-wrap items-center gap-3 px-4 py-3', highlight === s.id ? 'bg-warning-soft' : ''].join(' ')}
                  >
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <p className="font-medium tabular-nums">{s.statementNo}</p>
                        <SourceBadge source={s.source} />
                        {s.status === 'cleared' ? (
                          <Badge tone="success">
                            เคลียร์แล้ว{s.paymentMethod ? ` · ${PAYMENT_METHOD_LABEL[s.paymentMethod]}` : ''}
                          </Badge>
                        ) : (
                          <Badge tone="warning">รอเคลียร์</Badge>
                        )}
                      </div>
                      <p className="truncate text-sm">{s.customer.name}</p>
                      <p className="text-xs text-muted">
                        {formatDateShort(s.periodFrom)} – {formatDateShort(s.periodTo)} · {s.orderIds.length} ออเดอร์
                      </p>
                    </div>
                    <p className="font-semibold tabular-nums">{formatMoney(s.total)}</p>
                    <div className="flex w-full gap-2 sm:w-auto">
                      <Link
                        to={`/bill/statement/${s.id}`}
                        className="inline-flex min-h-11 flex-1 items-center justify-center gap-1.5 rounded border border-border px-3 text-sm font-medium hover:bg-subtle sm:flex-none"
                      >
                        <FileText size={16} aria-hidden /> บิล
                      </Link>
                      {s.status === 'open' ? (
                        <Button variant="success" className="flex-1 sm:flex-none" onClick={() => openClear(s)}>
                          <Check size={16} aria-hidden /> เคลียร์บิล
                        </Button>
                      ) : null}
                      {s.status === 'open' || isSuperAdmin ? (
                        <Button variant="ghost" aria-label={`ลบ ${s.statementNo}`} onClick={() => remove(s)}>
                          <Trash2 size={16} aria-hidden />
                        </Button>
                      ) : null}
                    </div>
                  </li>
                ))}
              </ul>
            ) : (
              <Empty title="ยังไม่มีใบวางบิล" />
            )}
          </Card>
        )}
      </section>

      <Modal open={!!clearing} title="ยืนยันเคลียร์บิล" onClose={() => setClearing(null)}>
        {clearing ? (
          <div className="flex flex-col gap-4">
            <p className="text-sm">
              {clearing.statementNo} · {clearing.customer.name}
              <span className="mt-1 block text-2xl font-bold tabular-nums text-primary">{formatMoney(clearing.total)} บาท</span>
            </p>
            <PayMethodPicker value={clearMethod} onChange={setClearMethod} hints={CLEAR_HINTS} />
            <p className="text-sm text-muted">ทุกออเดอร์ในใบวางบิลนี้จะเปลี่ยนเป็น "จ่ายแล้ว" และออกเลขใบเสร็จให้อัตโนมัติ</p>
            <div className="grid grid-cols-2 gap-3">
              <Button variant="secondary" size="lg" disabled={busy} onClick={() => setClearing(null)}>
                ยกเลิก
              </Button>
              <Button variant="success" size="lg" disabled={busy || !clearMethod} onClick={confirmClear}>
                <Check size={18} aria-hidden /> {busy ? 'กำลังบันทึก…' : 'ยืนยันเคลียร์บิล'}
              </Button>
            </div>
          </div>
        ) : null}
      </Modal>
    </div>
  );
}

function CreateStatementPanel({
  customerId,
  source,
  orders,
  sources,
  sourceCounts,
  by,
  onSource,
  onClose,
  onCreated,
}: {
  customerId: string;
  source: OrderSource;
  orders: Order[];
  sources: OrderSource[];
  sourceCounts: Record<OrderSource, number>;
  by: string;
  onSource: (s: OrderSource) => void;
  onClose: () => void;
  onCreated: (s: Statement) => void;
}) {
  const today = toIsoDate();
  const oldest = orders[0]?.orderDate ?? today;
  const [from, setFrom] = useState(oldest);
  const [to, setTo] = useState(today);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [note, setNote] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const inRange = orders.filter((o) => o.orderDate >= from && o.orderDate <= to);
  const rangeKey = inRange.map((o) => o.id).join(',');

  useEffect(() => {
    setSelected(new Set(rangeKey ? rangeKey.split(',') : []));
  }, [rangeKey]);

  const chosen = inRange.filter((o) => selected.has(o.id));
  const total = chosen.reduce((s, o) => s + o.total, 0);
  const name = orders[0]?.customer.name ?? '';
  const phone = orders[0]?.customer.phone ?? '';

  const toggle = (id: string) => {
    const next = new Set(selected);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    setSelected(next);
  };

  const submit = async () => {
    if (!chosen.length) return setError('เลือกออเดอร์อย่างน้อย 1 รายการ');
    setSaving(true);
    setError('');
    try {
      onCreated(await createStatement({ source, customerId, orderIds: chosen.map((o) => o.id), from, to, note, by }));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'สร้างใบวางบิลไม่สำเร็จ');
      setSaving(false);
    }
  };

  return (
    <Card className="p-4">
      <div className="mb-3 flex items-start justify-between gap-3">
        <div className="min-w-0">
          <h2 className="font-semibold">สร้างใบวางบิล · {ORDER_SOURCE_SHORT[source]}</h2>
          <p className="text-sm text-muted">
            {name || 'ลูกค้า'}
            {phone ? ` · ${formatPhone(phone)}` : ''}
          </p>
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

      {sources.length > 1 ? (
        <>
          <div className="mb-4 grid grid-cols-2 gap-1 rounded border border-border p-1" role="radiogroup" aria-label="ประเภทออเดอร์">
            {sources.map((s) => (
              <button
                key={s}
                type="button"
                role="radio"
                aria-checked={source === s}
                onClick={() => onSource(s)}
                className={[
                  'flex min-h-10 items-center justify-center gap-1.5 rounded-[9px] px-2 text-sm font-medium transition-colors cursor-pointer',
                  source === s ? 'bg-primary text-primary-foreground' : 'text-muted hover:bg-subtle hover:text-ink',
                ].join(' ')}
              >
                {ORDER_SOURCE_SHORT[s]}
                <span className="text-xs tabular-nums opacity-80">{sourceCounts[s]}</span>
              </button>
            ))}
          </div>
          <p className="-mt-2 mb-4 text-xs text-muted">ใบวางบิลแยกกันระหว่างออเดอร์ร้านวัสดุก่อสร้างกับออเดอร์ท่าทราย</p>
        </>
      ) : null}

      {!orders.length ? (
        <p className="text-sm text-muted">ไม่มีออเดอร์{ORDER_SOURCE_LABEL[source]}ที่ยังไม่วางบิล</p>
      ) : (
        <div className="flex flex-col gap-4">
          <div className="grid grid-cols-2 gap-3">
            <Field id="st-from" label="ตั้งแต่วันที่">
              <Input id="st-from" type="date" value={from} max={to} onChange={(e) => setFrom(e.target.value)} />
            </Field>
            <Field id="st-to" label="ถึงวันที่">
              <Input id="st-to" type="date" value={to} min={from} onChange={(e) => setTo(e.target.value)} />
            </Field>
          </div>

          <ul className="flex max-h-80 flex-col divide-y divide-border overflow-y-auto rounded border border-border">
            {inRange.map((o) => (
              <li key={o.id}>
                <label className="flex min-h-12 cursor-pointer items-center gap-3 px-3 py-2 text-sm hover:bg-subtle">
                  <input
                    type="checkbox"
                    className="h-5 w-5 accent-[var(--color-primary)]"
                    checked={selected.has(o.id)}
                    onChange={() => toggle(o.id)}
                  />
                  <span className="min-w-0 flex-1">
                    <span className="block tabular-nums">
                      {formatDateShort(o.orderDate)} · {o.orderNo}
                    </span>
                    <span className="block truncate text-xs text-muted">
                      {o.items.map((it) => `${it.name} ${formatNumber(it.quantity)}`).join(', ')}
                    </span>
                  </span>
                  <span className="tabular-nums">{formatMoney(o.total)}</span>
                </label>
              </li>
            ))}
            {!inRange.length ? <li className="px-3 py-3 text-sm text-muted">ไม่มีออเดอร์ในช่วงวันที่นี้</li> : null}
          </ul>

          <Field id="st-note" label="หมายเหตุบนใบวางบิล">
            <Textarea id="st-note" rows={2} value={note} onChange={(e) => setNote(e.target.value)} />
          </Field>

          {error ? <ErrorBox message={error} /> : null}

          <div className="flex items-center justify-between gap-3 rounded bg-subtle px-4 py-3">
            <span className="text-sm text-muted">{chosen.length} ออเดอร์</span>
            <span className="text-xl font-bold tabular-nums text-primary">{formatMoney(total)}</span>
          </div>
          <Button size="lg" onClick={submit} disabled={saving || !chosen.length}>
            <FileText size={18} aria-hidden /> {saving ? 'กำลังสร้าง…' : 'สร้างใบวางบิลและพิมพ์'}
          </Button>
        </div>
      )}
    </Card>
  );
}
