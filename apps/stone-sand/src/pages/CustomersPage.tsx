import { FormEvent, useMemo, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { FileText, Pencil, Phone, Plus, Search, Trash2, UserPlus } from 'lucide-react';
import { useAuth } from '../auth/AuthProvider';
import OrderRow from '../components/OrderRow';
import Badge from '../components/ui/Badge';
import Button from '../components/ui/Button';
import Card from '../components/ui/Card';
import Field from '../components/ui/Field';
import Input from '../components/ui/Input';
import Modal from '../components/ui/Modal';
import PageHeader from '../components/ui/PageHeader';
import { Empty, ErrorBox, Loading } from '../components/ui/States';
import Textarea from '../components/ui/Textarea';
import { deleteCustomer, listCustomers, saveCustomer, type CustomerInput } from '../data/customers';
import { listOrders, listUnclearedOrders } from '../data/orders';
import { useAsync } from '../hooks/useAsync';
import { digitsOnly, formatMoney, formatPhone } from '../lib/format';
import { summarizeOutstanding } from '../lib/orderStatus';
import type { Customer } from '../types';

const emptyInput: CustomerInput = {
  name: '',
  phone: '',
  address: '',
  zoneId: null,
  taxId: '',
  lat: null,
  lng: null,
  isCredit: false,
  note: '',
};

export default function CustomersPage() {
  const [params, setParams] = useSearchParams();
  const openId = params.get('open');
  const customers = useAsync(() => listCustomers(), []);
  const uncleared = useAsync(() => listUnclearedOrders(), []);
  const [query, setQuery] = useState('');
  const [onlyOutstanding, setOnlyOutstanding] = useState(false);
  const [editing, setEditing] = useState<CustomerInput | null>(null);

  const balances = useMemo(() => {
    const map = new Map<string, number>();
    for (const row of summarizeOutstanding(uncleared.data ?? [])) map.set(row.customerId, row.total);
    return map;
  }, [uncleared.data]);

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    const digits = digitsOnly(q);
    return (customers.data ?? []).filter((c) => {
      if (onlyOutstanding && !balances.get(c.id)) return false;
      if (!q) return true;
      return c.name.toLowerCase().includes(q) || (digits.length >= 3 && c.phone.includes(digits));
    });
  }, [customers.data, query, onlyOutstanding, balances]);

  const totalOutstanding = [...balances.values()].reduce((s, v) => s + v, 0);
  const openCustomer = (customers.data ?? []).find((c) => c.id === openId) ?? null;

  const setOpen = (id: string | null) => {
    const next = new URLSearchParams(params);
    if (id) next.set('open', id);
    else next.delete('open');
    setParams(next, { replace: true });
  };

  const onSaved = async (c: Customer) => {
    setEditing(null);
    await customers.reload();
    setOpen(c.id);
  };

  return (
    <div>
      <PageHeader
        title="ลูกค้า"
        subtitle={totalOutstanding ? `ยอดค้างรวม ${formatMoney(totalOutstanding)} บาท` : 'ข้อมูลลูกค้าสำหรับออกบิล'}
        actions={
          <Button onClick={() => setEditing({ ...emptyInput })}>
            <UserPlus size={18} aria-hidden /> เพิ่มลูกค้า
          </Button>
        }
      />

      <div className="mb-4 flex flex-col gap-2 sm:flex-row sm:items-center">
        <div className="relative flex-1">
          <Search size={18} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted" aria-hidden />
          <Input
            aria-label="ค้นหาลูกค้า"
            placeholder="ค้นหาชื่อหรือเบอร์โทร"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            className="pl-10"
          />
        </div>
        <label className="flex min-h-11 cursor-pointer items-center gap-2 text-sm">
          <input
            type="checkbox"
            className="h-5 w-5 accent-[var(--color-primary)]"
            checked={onlyOutstanding}
            onChange={(e) => setOnlyOutstanding(e.target.checked)}
          />
          เฉพาะที่มียอดค้าง
        </label>
      </div>

      {customers.error ? <ErrorBox message={customers.error} /> : null}
      {customers.loading && !customers.data ? (
        <Loading />
      ) : (
        <Card className="overflow-hidden">
          {visible.length ? (
            <ul className="divide-y divide-border">
              {visible.map((c) => {
                const balance = balances.get(c.id) ?? 0;
                return (
                  <li key={c.id}>
                    <button
                      type="button"
                      onClick={() => setOpen(c.id)}
                      className="flex min-h-16 w-full items-center gap-3 px-4 py-3 text-left transition-colors hover:bg-subtle cursor-pointer"
                    >
                      <div className="min-w-0 flex-1">
                        <div className="flex flex-wrap items-center gap-2">
                          <p className="truncate font-medium">{c.name}</p>
                          {c.isCredit ? <Badge tone="info">เครดิต</Badge> : null}
                        </div>
                        <p className="truncate text-sm text-muted">
                          {[c.phone && formatPhone(c.phone), c.address].filter(Boolean).join(' · ') || '—'}
                        </p>
                      </div>
                      {balance ? (
                        <div className="text-right">
                          <p className="text-xs text-muted">ค้าง</p>
                          <p className="font-semibold tabular-nums text-warning">{formatMoney(balance)}</p>
                        </div>
                      ) : null}
                    </button>
                  </li>
                );
              })}
            </ul>
          ) : (
            <Empty title={query ? 'ไม่พบลูกค้า' : 'ยังไม่มีลูกค้า'} />
          )}
        </Card>
      )}

      {openCustomer && !editing ? (
        <CustomerDetail
          customer={openCustomer}
          balance={balances.get(openCustomer.id) ?? 0}
          onClose={() => setOpen(null)}
          onEdit={() => setEditing({ ...openCustomer })}
          onDeleted={async () => {
            setOpen(null);
            await customers.reload();
          }}
        />
      ) : null}

      {editing ? <CustomerForm initial={editing} onClose={() => setEditing(null)} onSaved={onSaved} /> : null}
    </div>
  );
}

function CustomerDetail({
  customer: c,
  balance,
  onClose,
  onEdit,
  onDeleted,
}: {
  customer: Customer;
  balance: number;
  onClose: () => void;
  onEdit: () => void;
  onDeleted: () => void;
}) {
  const { isSuperAdmin } = useAuth();
  const { data: orders, loading, error } = useAsync(() => listOrders({ customerId: c.id, limit: 100 }), [c.id]);
  const totalSpent = (orders ?? []).filter((o) => !o.cancelled).reduce((s, o) => s + o.total, 0);
  const [deleting, setDeleting] = useState(false);
  const [deleteError, setDeleteError] = useState('');

  const remove = async () => {
    if (!window.confirm(`ลบลูกค้า "${c.name}"?`)) return;
    setDeleting(true);
    setDeleteError('');
    try {
      await deleteCustomer(c.id);
      onDeleted();
    } catch (err) {
      setDeleteError(err instanceof Error ? err.message : 'ลบไม่สำเร็จ');
      setDeleting(false);
    }
  };

  return (
    <Modal open title={c.name} onClose={onClose} wide>
      <div className="flex flex-col gap-4">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="text-sm">
            {c.phone ? (
              <a href={`tel:${c.phone}`} className="inline-flex min-h-11 items-center gap-1.5 text-primary">
                <Phone size={14} aria-hidden /> {formatPhone(c.phone)}
              </a>
            ) : null}
            {c.address ? <p className="text-muted">{c.address}</p> : null}
            {c.taxId ? <p className="text-muted">เลขผู้เสียภาษี {c.taxId}</p> : null}
            {c.note ? <p className="mt-1 text-muted">หมายเหตุ: {c.note}</p> : null}
          </div>
          <div className="flex gap-2">
            <Button variant="secondary" onClick={onEdit}>
              <Pencil size={16} aria-hidden /> แก้ไข
            </Button>
            {isSuperAdmin ? (
              <Button variant="ghost" onClick={remove} disabled={deleting} aria-label={`ลบลูกค้า ${c.name}`}>
                <Trash2 size={16} aria-hidden /> ลบ
              </Button>
            ) : null}
          </div>
        </div>
        {deleteError ? <ErrorBox message={deleteError} /> : null}

        <div className="grid grid-cols-2 gap-3">
          <div className="rounded bg-subtle px-3 py-2">
            <p className="text-xs text-muted">ยอดค้างเคลียร์</p>
            <p className={['text-lg font-bold tabular-nums', balance ? 'text-warning' : ''].join(' ')}>{formatMoney(balance)}</p>
          </div>
          <div className="rounded bg-subtle px-3 py-2">
            <p className="text-xs text-muted">ยอดซื้อ ({orders?.length ?? 0} ออเดอร์ล่าสุด)</p>
            <p className="text-lg font-bold tabular-nums">{formatMoney(totalSpent)}</p>
          </div>
        </div>

        <div className="flex flex-wrap gap-2">
          <Link
            to={`/new?customer=${c.id}`}
            className="inline-flex min-h-11 flex-1 items-center justify-center gap-2 rounded bg-primary px-4 text-sm font-medium text-primary-foreground hover:bg-primary-hover"
          >
            <Plus size={16} aria-hidden /> สร้างออเดอร์
          </Link>
          {balance ? (
            <Link
              to={`/statements?customer=${c.id}`}
              className="inline-flex min-h-11 flex-1 items-center justify-center gap-2 rounded border border-border px-4 text-sm font-medium hover:bg-subtle"
            >
              <FileText size={16} aria-hidden /> ทำใบวางบิล
            </Link>
          ) : null}
        </div>

        <div>
          <h3 className="mb-2 text-sm font-semibold text-muted">ประวัติออเดอร์</h3>
          {error ? <ErrorBox message={error} /> : null}
          {loading && !orders ? (
            <Loading />
          ) : orders?.length ? (
            <ul className="-mx-5 divide-y divide-border border-y border-border">
              {orders.map((o) => (
                <li key={o.id}>
                  <OrderRow order={o} />
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-sm text-muted">ยังไม่มีออเดอร์</p>
          )}
        </div>
      </div>
    </Modal>
  );
}

function CustomerForm({
  initial,
  onClose,
  onSaved,
}: {
  initial: CustomerInput;
  onClose: () => void;
  onSaved: (c: Customer) => void;
}) {
  const [form, setForm] = useState(initial);
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);

  const submit = async (e?: FormEvent) => {
    e?.preventDefault();
    if (!form.name.trim()) return setError('กรุณาใส่ชื่อลูกค้า');
    const phone = digitsOnly(form.phone);
    if (phone && (phone.length < 9 || phone.length > 10)) return setError('เบอร์โทรควรมี 9-10 หลัก');
    setSaving(true);
    setError('');
    try {
      onSaved(await saveCustomer({ ...form, phone }));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'บันทึกไม่สำเร็จ');
      setSaving(false);
    }
  };

  return (
    <Modal
      open
      title={initial.id ? 'แก้ไขลูกค้า' : 'เพิ่มลูกค้า'}
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            ยกเลิก
          </Button>
          <Button onClick={() => submit()} disabled={saving}>
            {saving ? 'กำลังบันทึก…' : 'บันทึก'}
          </Button>
        </>
      }
    >
      <form onSubmit={submit} className="flex flex-col gap-4" noValidate>
        <Field id="cf-name" label="ชื่อลูกค้า / ชื่อร้าน *">
          <Input id="cf-name" autoFocus value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
        </Field>
        <Field id="cf-phone" label="เบอร์โทร">
          <Input id="cf-phone" inputMode="tel" value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} />
        </Field>
        <Field id="cf-address" label="ที่อยู่ (สำหรับออกบิล)">
          <Textarea id="cf-address" rows={2} value={form.address} onChange={(e) => setForm({ ...form, address: e.target.value })} />
        </Field>
        <Field id="cf-tax" label="เลขผู้เสียภาษี">
          <Input id="cf-tax" inputMode="numeric" value={form.taxId} onChange={(e) => setForm({ ...form, taxId: e.target.value })} />
        </Field>
        <Field id="cf-note" label="หมายเหตุ">
          <Input id="cf-note" value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} />
        </Field>
        <label className="flex min-h-11 cursor-pointer items-center gap-3 text-sm">
          <input
            type="checkbox"
            className="h-5 w-5 accent-[var(--color-primary)]"
            checked={form.isCredit}
            onChange={(e) => setForm({ ...form, isCredit: e.target.checked })}
          />
          ลูกค้าเครดิต (เคลียร์บิลรายเดือน)
        </label>
        {error ? <ErrorBox message={error} /> : null}
        <button type="submit" className="hidden" />
      </form>
    </Modal>
  );
}
