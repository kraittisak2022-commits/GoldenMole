import { FormEvent, useEffect, useState } from 'react';
import { Check, MapPin, Phone, Search, UserPlus, X } from 'lucide-react';
import Badge from '../../components/ui/Badge';
import Button from '../../components/ui/Button';
import Field from '../../components/ui/Field';
import Input from '../../components/ui/Input';
import Textarea from '../../components/ui/Textarea';
import { ErrorBox } from '../../components/ui/States';
import { saveCustomer, searchCustomers } from '../../data/customers';
import { matchedAlias, parseAliases } from '../../lib/customerSearch';
import { digitsOnly, formatPhone } from '../../lib/format';
import type { Customer } from '../../types';
import StepTitle from './StepTitle';

interface Props {
  customer: Customer | null;
  onSelect: (c: Customer | null) => void;
}

const emptyForm = { name: '', aliasText: '', phone: '', address: '', taxId: '', isCredit: false };

export default function StepCustomer({ customer, onSelect }: Props) {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<Customer[]>([]);
  const [searching, setSearching] = useState(false);
  const [creating, setCreating] = useState(false);
  const [form, setForm] = useState(emptyForm);
  const [formError, setFormError] = useState('');
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    const q = query.trim();
    if (!q) {
      setResults([]);
      return;
    }
    setSearching(true);
    const t = window.setTimeout(async () => {
      try {
        setResults(await searchCustomers(q));
        setError('');
      } catch (err) {
        setError(err instanceof Error ? err.message : 'ค้นหาไม่สำเร็จ');
      } finally {
        setSearching(false);
      }
    }, 250);
    return () => window.clearTimeout(t);
  }, [query]);

  const startCreate = () => {
    const digits = digitsOnly(query);
    setForm({ ...emptyForm, name: digits.length >= 6 ? '' : query.trim(), phone: digits.length >= 6 ? digits : '' });
    setFormError('');
    setCreating(true);
  };

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (!form.name.trim()) return setFormError('กรุณาใส่ชื่อลูกค้า');
    const phone = digitsOnly(form.phone);
    if (phone && (phone.length < 9 || phone.length > 10)) return setFormError('เบอร์โทรควรมี 9-10 หลัก');
    setSaving(true);
    setFormError('');
    try {
      const { aliasText, ...rest } = form;
      const c = await saveCustomer({ ...rest, aliases: parseAliases(aliasText), phone, zoneId: null, lat: null, lng: null, note: '' });
      onSelect(c);
      setCreating(false);
      setQuery('');
    } catch (err) {
      setFormError(err instanceof Error ? err.message : 'บันทึกไม่สำเร็จ');
    } finally {
      setSaving(false);
    }
  };

  if (customer) {
    return (
      <div className="step-enter flex flex-col gap-4">
        <StepTitle title="ลูกค้า" subtitle="ข้อมูลนี้จะแสดงบนบิล" />
        <div className="rounded border-2 border-primary bg-primary-soft/40 p-4">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-2">
                <p className="text-lg font-semibold">{customer.name}</p>
                {customer.isCredit ? <Badge tone="info">เครดิตรายเดือน</Badge> : null}
              </div>
              {customer.phone ? (
                <p className="mt-1 flex items-center gap-1.5 text-sm text-muted">
                  <Phone size={14} aria-hidden /> {formatPhone(customer.phone)}
                </p>
              ) : null}
              {customer.address ? (
                <p className="mt-1 flex items-start gap-1.5 text-sm text-muted">
                  <MapPin size={14} className="mt-0.5 shrink-0" aria-hidden /> {customer.address}
                </p>
              ) : null}
            </div>
            <Check className="shrink-0 text-primary" size={22} aria-hidden />
          </div>
        </div>
        <Button variant="secondary" onClick={() => onSelect(null)}>
          เปลี่ยนลูกค้า
        </Button>
      </div>
    );
  }

  return (
    <div className="step-enter flex flex-col gap-4">
      <StepTitle title="ลูกค้า" subtitle="ค้นหาจากชื่อ ชื่อเรียก หรือเบอร์โทร หรือเพิ่มลูกค้าใหม่" />

      {!creating ? (
        <>
          <div className="relative">
            <Search size={18} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted" aria-hidden />
            <Input
              autoFocus
              aria-label="ค้นหาลูกค้า"
              placeholder="ชื่อ ชื่อเรียก หรือ เบอร์โทร"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              className="min-h-12 pl-10 text-base"
            />
          </div>
          {error ? <ErrorBox message={error} /> : null}
          {query.trim() ? (
            <div className="flex flex-col divide-y divide-border overflow-hidden rounded border border-border bg-surface">
              {searching && !results.length ? <p className="px-4 py-3 text-sm text-muted">กำลังค้นหา…</p> : null}
              {!searching && !results.length ? (
                <p className="px-4 py-3 text-sm text-muted">ไม่พบลูกค้า "{query.trim()}"</p>
              ) : null}
              {results.map((c) => (
                <button
                  key={c.id}
                  type="button"
                  onClick={() => onSelect(c)}
                  className="flex min-h-14 items-center justify-between gap-3 px-4 py-3 text-left transition-colors hover:bg-subtle cursor-pointer"
                >
                  <div className="min-w-0">
                    <p className="font-medium">{c.name}</p>
                    {matchedAlias(c, query) ? (
                      <p className="truncate text-xs text-primary">ชื่อเรียก: {matchedAlias(c, query)}</p>
                    ) : null}
                    <p className="truncate text-sm text-muted">
                      {[c.phone && formatPhone(c.phone), c.address].filter(Boolean).join(' · ') || '—'}
                    </p>
                  </div>
                  {c.isCredit ? <Badge tone="info">เครดิต</Badge> : null}
                </button>
              ))}
            </div>
          ) : null}
          <Button variant="secondary" size="lg" onClick={startCreate}>
            <UserPlus size={18} aria-hidden /> เพิ่มลูกค้าใหม่
          </Button>
        </>
      ) : (
        <form onSubmit={submit} className="flex flex-col gap-4 rounded border border-border bg-surface p-4" noValidate>
          <div className="flex items-center justify-between">
            <p className="font-medium">ลูกค้าใหม่</p>
            <button
              type="button"
              aria-label="ยกเลิก"
              onClick={() => setCreating(false)}
              className="inline-flex min-h-11 min-w-11 items-center justify-center rounded text-muted hover:bg-subtle cursor-pointer"
            >
              <X size={18} aria-hidden />
            </button>
          </div>
          <Field id="c-name" label="ชื่อลูกค้า / ชื่อร้าน *">
            <Input id="c-name" autoFocus value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
          </Field>
          <Field id="c-aliases" label="ชื่อเรียกอื่น / ชื่อเล่น (ถ้ามี)" hint="คั่นหลายชื่อด้วย , เช่น เสี่ยบาส, บาส">
            <Input id="c-aliases" value={form.aliasText} onChange={(e) => setForm({ ...form, aliasText: e.target.value })} />
          </Field>
          <Field id="c-phone" label="เบอร์โทร">
            <Input
              id="c-phone"
              inputMode="tel"
              value={form.phone}
              onChange={(e) => setForm({ ...form, phone: e.target.value })}
              placeholder="0xx-xxx-xxxx"
            />
          </Field>
          <Field id="c-address" label="ที่อยู่ (สำหรับออกบิล)">
            <Textarea
              id="c-address"
              rows={2}
              value={form.address}
              onChange={(e) => setForm({ ...form, address: e.target.value })}
              placeholder="บ้านเลขที่ หมู่ ตำบล"
            />
          </Field>
          <Field id="c-tax" label="เลขผู้เสียภาษี (ถ้ามี)">
            <Input id="c-tax" inputMode="numeric" value={form.taxId} onChange={(e) => setForm({ ...form, taxId: e.target.value })} />
          </Field>
          <label className="flex min-h-11 cursor-pointer items-center gap-3 text-sm">
            <input
              type="checkbox"
              className="h-5 w-5 accent-[var(--color-primary)]"
              checked={form.isCredit}
              onChange={(e) => setForm({ ...form, isCredit: e.target.checked })}
            />
            ลูกค้าเครดิต (มารับประจำ เคลียร์บิลรายเดือน)
          </label>
          {formError ? <ErrorBox message={formError} /> : null}
          <Button type="submit" size="lg" disabled={saving}>
            {saving ? 'กำลังบันทึก…' : 'บันทึกและเลือกลูกค้านี้'}
          </Button>
        </form>
      )}
    </div>
  );
}