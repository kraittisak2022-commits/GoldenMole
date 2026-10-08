import { useState } from 'react';
import { Pencil, Phone, Plus, Trash2 } from 'lucide-react';
import Badge from '../components/ui/Badge';
import Button from '../components/ui/Button';
import Card from '../components/ui/Card';
import Field from '../components/ui/Field';
import Input from '../components/ui/Input';
import Modal from '../components/ui/Modal';
import PageHeader from '../components/ui/PageHeader';
import Select from '../components/ui/Select';
import { ErrorBox, Loading } from '../components/ui/States';
import { useCatalog } from '../context/CatalogProvider';
import { saveDriver } from '../data/drivers';
import { formatNumber, formatPhone } from '../lib/format';
import { ROUTE_GROUP_LABEL, type Driver, type RouteGroup, type TruckSize } from '../types';

type DriverForm = Omit<Driver, 'id' | 'sortOrder'> & { id?: string };

const emptyDriver: DriverForm = {
  name: '',
  village: '',
  routeGroup: 'north',
  truckSize: 5,
  truckCount: 1,
  contacts: [{ label: '', phone: '' }],
  contactNote: '',
  wagePerTrip: 0,
  active: true,
};

export default function DriversPage() {
  const { drivers, loading, error, reload } = useCatalog();
  const [editing, setEditing] = useState<DriverForm | null>(null);
  const [actionError, setActionError] = useState('');

  const toggleActive = async (d: Driver) => {
    setActionError('');
    try {
      await saveDriver({ ...d, active: !d.active });
      await reload();
    } catch (err) {
      setActionError(err instanceof Error ? err.message : 'บันทึกไม่สำเร็จ');
    }
  };

  const groups = Object.keys(ROUTE_GROUP_LABEL) as RouteGroup[];

  return (
    <div>
      <PageHeader
        title="รถ / คนขับ"
        subtitle={`${drivers.filter((d) => d.active).length} คันพร้อมรับงาน · แบ่ง ${groups.length} สาย`}
        actions={
          <Button onClick={() => setEditing({ ...emptyDriver, contacts: [{ label: '', phone: '' }] })}>
            <Plus size={18} aria-hidden /> เพิ่มคนขับ
          </Button>
        }
      />
      {error || actionError ? (
        <div className="mb-4">
          <ErrorBox message={error || actionError} />
        </div>
      ) : null}
      {loading && !drivers.length ? (
        <Loading />
      ) : (
        <div className="grid grid-cols-1 gap-5 lg:grid-cols-3">
          {groups.map((g) => {
            const list = drivers.filter((d) => d.routeGroup === g);
            return (
              <section key={g}>
                <h2 className="mb-2 text-sm font-semibold text-muted">
                  {ROUTE_GROUP_LABEL[g]} · {list.length}
                </h2>
                <Card className="overflow-hidden">
                  <ul className="divide-y divide-border">
                    {list.map((d) => (
                      <li key={d.id} className={['px-4 py-3', d.active ? '' : 'bg-subtle/60'].join(' ')}>
                        <div className="flex items-start justify-between gap-2">
                          <div className="min-w-0">
                            <p className={['font-medium', d.active ? '' : 'text-muted line-through'].join(' ')}>{d.name}</p>
                            <p className="text-xs text-muted">
                              {[d.village, d.wagePerTrip ? `ค่าจ้าง ${formatNumber(d.wagePerTrip)}/เที่ยว` : ''].filter(Boolean).join(' · ') ||
                                '—'}
                            </p>
                          </div>
                          <div className="flex shrink-0 items-center gap-1">
                            <Badge tone="info">
                              {d.truckSize} คิว{d.truckCount > 1 ? ` ×${d.truckCount}` : ''}
                            </Badge>
                            <button
                              type="button"
                              aria-label={`แก้ไข ${d.name}`}
                              onClick={() => setEditing({ ...d, contacts: d.contacts.length ? d.contacts : [{ label: '', phone: '' }] })}
                              className="inline-flex min-h-11 min-w-11 items-center justify-center rounded text-muted hover:bg-subtle hover:text-ink cursor-pointer"
                            >
                              <Pencil size={16} aria-hidden />
                            </button>
                          </div>
                        </div>
                        <div className="mt-1 flex flex-wrap items-center gap-2">
                          {d.contacts.map((c) => (
                            <a
                              key={c.phone}
                              href={`tel:${c.phone}`}
                              className="inline-flex min-h-10 items-center gap-1.5 rounded border border-border px-2.5 text-sm text-primary hover:bg-subtle"
                            >
                              <Phone size={14} aria-hidden />
                              {c.label ? `${c.label} ` : ''}
                              {formatPhone(c.phone)}
                            </a>
                          ))}
                          {d.contactNote ? <span className="text-xs text-muted">{d.contactNote}</span> : null}
                          <label className="ml-auto flex min-h-10 cursor-pointer items-center gap-2 text-xs text-muted">
                            <input
                              type="checkbox"
                              className="h-4 w-4 accent-[var(--color-primary)]"
                              checked={d.active}
                              onChange={() => toggleActive(d)}
                            />
                            รับงาน
                          </label>
                        </div>
                      </li>
                    ))}
                    {!list.length ? <li className="px-4 py-3 text-sm text-muted">ยังไม่มีคนขับในสายนี้</li> : null}
                  </ul>
                </Card>
              </section>
            );
          })}
        </div>
      )}

      {editing ? (
        <DriverFormModal
          initial={editing}
          onClose={() => setEditing(null)}
          onSaved={async () => {
            setEditing(null);
            await reload();
          }}
        />
      ) : null}
    </div>
  );
}

function DriverFormModal({ initial, onClose, onSaved }: { initial: DriverForm; onClose: () => void; onSaved: () => void }) {
  const [form, setForm] = useState<DriverForm>(initial);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const setContact = (i: number, patch: Partial<{ label: string; phone: string }>) =>
    setForm({ ...form, contacts: form.contacts.map((c, j) => (j === i ? { ...c, ...patch } : c)) });

  const submit = async () => {
    if (!form.name.trim()) return setError('กรุณาใส่ชื่อคนขับ');
    setSaving(true);
    setError('');
    try {
      await saveDriver({
        ...form,
        contacts: form.contacts.map((c) => ({ label: c.label.trim(), phone: c.phone.replace(/\D/g, '') })),
      });
      onSaved();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'บันทึกไม่สำเร็จ');
      setSaving(false);
    }
  };

  return (
    <Modal
      open
      title={initial.id ? 'แก้ไขคนขับ' : 'เพิ่มคนขับ'}
      onClose={onClose}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            ยกเลิก
          </Button>
          <Button onClick={submit} disabled={saving}>
            {saving ? 'กำลังบันทึก…' : 'บันทึก'}
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <div className="grid grid-cols-2 gap-3">
          <Field id="dv-name" label="ชื่อ *">
            <Input id="dv-name" autoFocus value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
          </Field>
          <Field id="dv-village" label="บ้าน / หมู่บ้าน">
            <Input id="dv-village" value={form.village} onChange={(e) => setForm({ ...form, village: e.target.value })} />
          </Field>
        </div>
        <div className="grid grid-cols-3 gap-3">
          <Field id="dv-group" label="สาย">
            <Select
              id="dv-group"
              value={form.routeGroup}
              onChange={(e) => setForm({ ...form, routeGroup: e.target.value as RouteGroup })}
            >
              {(Object.keys(ROUTE_GROUP_LABEL) as RouteGroup[]).map((g) => (
                <option key={g} value={g}>
                  {ROUTE_GROUP_LABEL[g]}
                </option>
              ))}
            </Select>
          </Field>
          <Field id="dv-size" label="ขนาดรถ">
            <Select
              id="dv-size"
              value={form.truckSize}
              onChange={(e) => setForm({ ...form, truckSize: Number(e.target.value) as TruckSize })}
            >
              <option value={3}>3 คิว</option>
              <option value={5}>5 คิว</option>
            </Select>
          </Field>
          <Field id="dv-count" label="จำนวนคัน">
            <Input
              id="dv-count"
              type="number"
              min={1}
              value={form.truckCount}
              onChange={(e) => setForm({ ...form, truckCount: Math.max(1, Number(e.target.value) || 1) })}
            />
          </Field>
        </div>
        <Field id="dv-wage" label="ค่าจ้างต่อเที่ยว (บาท)" hint="ใช้คำนวณค่าจ้างอัตโนมัติเมื่อเลือกคนขับในออเดอร์">
          <Input
            id="dv-wage"
            type="number"
            inputMode="numeric"
            min={0}
            value={form.wagePerTrip || ''}
            placeholder="0"
            onChange={(e) => setForm({ ...form, wagePerTrip: Math.max(0, Number(e.target.value) || 0) })}
          />
        </Field>
        <div className="flex flex-col gap-2">
          <p className="text-sm font-medium">เบอร์โทร</p>
          {form.contacts.map((c, i) => (
            <div key={i} className="flex gap-2">
              <Input
                aria-label={`ชื่อผู้ติดต่อ ${i + 1}`}
                placeholder="เช่น ภรรยา"
                value={c.label}
                onChange={(e) => setContact(i, { label: e.target.value })}
                className="w-28"
              />
              <Input
                aria-label={`เบอร์โทร ${i + 1}`}
                inputMode="tel"
                placeholder="0xx-xxx-xxxx"
                value={c.phone}
                onChange={(e) => setContact(i, { phone: e.target.value })}
              />
              <Button
                variant="ghost"
                aria-label="ลบเบอร์"
                onClick={() => setForm({ ...form, contacts: form.contacts.filter((_, j) => j !== i) })}
              >
                <Trash2 size={16} aria-hidden />
              </Button>
            </div>
          ))}
          <Button
            variant="secondary"
            className="self-start"
            onClick={() => setForm({ ...form, contacts: [...form.contacts, { label: '', phone: '' }] })}
          >
            <Plus size={16} aria-hidden /> เพิ่มเบอร์
          </Button>
        </div>
        <Field id="dv-note" label="หมายเหตุการติดต่อ">
          <Input id="dv-note" value={form.contactNote} onChange={(e) => setForm({ ...form, contactNote: e.target.value })} />
        </Field>
        <label className="flex min-h-11 cursor-pointer items-center gap-3 text-sm">
          <input
            type="checkbox"
            className="h-5 w-5 accent-[var(--color-primary)]"
            checked={form.active}
            onChange={(e) => setForm({ ...form, active: e.target.checked })}
          />
          พร้อมรับงาน
        </label>
        {error ? <ErrorBox message={error} /> : null}
      </div>
    </Modal>
  );
}
