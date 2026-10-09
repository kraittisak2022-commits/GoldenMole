import { useEffect, useState, type ReactNode } from 'react';
import { Check, Plus, Trash2, Upload } from 'lucide-react';
import { useAuth } from '../auth/AuthProvider';
import { suggestDeliveryFee } from '../calc/deliveryFee';
import Button from '../components/ui/Button';
import Card from '../components/ui/Card';
import Field from '../components/ui/Field';
import Input from '../components/ui/Input';
import PageHeader from '../components/ui/PageHeader';
import Select from '../components/ui/Select';
import { ErrorBox, Loading } from '../components/ui/States';
import Textarea from '../components/ui/Textarea';
import { useCatalog } from '../context/CatalogProvider';
import { createProduct, createZone, deleteProduct, deleteZone, saveProduct, saveSetting, saveZone } from '../data/catalog';
import { formatNumber } from '../lib/format';
import { decodeQrImage } from '../lib/decodeQrImage';
import { isThaiQrPayload, promptPayTarget } from '../lib/promptpay';
import QrImage from '../components/bill/QrImage';
import { PRODUCT_CATEGORY_LABEL, type AppSettings, type Product, type ProductCategory, type Zone } from '../types';

export default function SettingsPage() {
  const { products, zones, settings, loading, error, reload } = useCatalog();
  if (loading && !products.length) return <Loading />;

  return (
    <div className="mx-auto max-w-3xl">
      <PageHeader title="ตั้งค่า" subtitle="ราคาสินค้า ค่าส่ง หัวบิล และช่องทางรับเงิน" />
      {error ? (
        <div className="mb-4">
          <ErrorBox message={error} />
        </div>
      ) : null}
      <div className="flex flex-col gap-5">
        <ProductsSection products={products} onSaved={reload} />
        <ZonesSection zones={zones} delivery={settings.delivery} onSaved={reload} />
        <DeliverySection settings={settings} zones={zones} onSaved={reload} />
        <CompanySection settings={settings} onSaved={reload} />
        <PaymentSection settings={settings} onSaved={reload} />
      </div>
    </div>
  );
}

function useSaver(onSaved: () => Promise<void>) {
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [done, setDone] = useState(false);
  const run = async (fn: () => Promise<unknown>) => {
    setSaving(true);
    setError('');
    setDone(false);
    try {
      await fn();
      await onSaved();
      setDone(true);
      window.setTimeout(() => setDone(false), 2000);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'บันทึกไม่สำเร็จ');
    } finally {
      setSaving(false);
    }
  };
  return { saving, error, done, run };
}

function Section({
  title,
  subtitle,
  children,
  saver,
  onSave,
}: {
  title: string;
  subtitle?: string;
  children: ReactNode;
  saver: ReturnType<typeof useSaver>;
  onSave: () => void;
}) {
  return (
    <Card className="p-4 sm:p-5">
      <h2 className="font-semibold">{title}</h2>
      {subtitle ? <p className="mb-4 mt-0.5 text-sm text-muted">{subtitle}</p> : <div className="mb-4" />}
      {children}
      {saver.error ? (
        <div className="mt-3">
          <ErrorBox message={saver.error} />
        </div>
      ) : null}
      <div className="mt-4 flex items-center justify-end gap-3">
        {saver.done ? (
          <span className="flex items-center gap-1 text-sm text-success">
            <Check size={16} aria-hidden /> บันทึกแล้ว
          </span>
        ) : null}
        <Button onClick={onSave} disabled={saver.saving}>
          {saver.saving ? 'กำลังบันทึก…' : 'บันทึก'}
        </Button>
      </div>
    </Card>
  );
}

const num = (v: string) => Math.max(0, Number(v) || 0);

const NEW_PREFIX = 'new-';
const isNew = (id: string) => id.startsWith(NEW_PREFIX);
const nextSort = (rows: { sortOrder: number }[]) => Math.max(0, ...rows.map((r) => r.sortOrder)) + 10;

function RemoveButton({ label, onClick }: { label: string; onClick: () => void }) {
  return (
    <button
      type="button"
      aria-label={label}
      onClick={onClick}
      className="inline-flex min-h-11 min-w-11 items-center justify-center rounded text-muted hover:bg-destructive-soft hover:text-destructive cursor-pointer"
    >
      <Trash2 size={18} aria-hidden />
    </button>
  );
}

function ProductsSection({ products, onSaved }: { products: Product[]; onSaved: () => Promise<void> }) {
  const { isSuperAdmin } = useAuth();
  const [rows, setRows] = useState(products);
  useEffect(() => setRows(products), [products]);
  const saver = useSaver(onSaved);
  const update = (id: string, patch: Partial<Product>) => setRows(rows.map((r) => (r.id === id ? { ...r, ...patch } : r)));
  const add = () =>
    setRows([
      ...rows,
      { id: `${NEW_PREFIX}${Date.now()}`, name: '', category: 'stone', unit: 'คิว', pricePerUnit: 0, sortOrder: nextSort(rows), active: true },
    ]);
  const remove = (p: Product) => {
    if (isNew(p.id) || window.confirm(`ลบสินค้า "${p.name}"? (ออเดอร์เก่ายังแสดงชื่อเดิม) กดบันทึกเพื่อยืนยัน`)) {
      setRows(rows.filter((r) => r.id !== p.id));
    }
  };

  return (
    <Section
      title="ราคาสินค้า (ต่อคิว)"
      subtitle="ราคา 3 คิว / 5 คิว คิดจากราคาต่อคิว × จำนวน"
      saver={saver}
      onSave={() =>
        saver.run(async () => {
          const blank = rows.find((r) => !r.name.trim());
          if (blank) throw new Error('กรุณาใส่ชื่อสินค้าให้ครบ');
          for (const p of products) {
            if (!rows.some((r) => r.id === p.id)) await deleteProduct(p.id);
          }
          for (const r of rows) {
            if (isNew(r.id)) {
              await createProduct(r);
              continue;
            }
            const before = products.find((p) => p.id === r.id);
            if (
              before &&
              (before.pricePerUnit !== r.pricePerUnit ||
                before.name !== r.name ||
                before.category !== r.category ||
                before.active !== r.active)
            ) {
              await saveProduct(r);
            }
          }
        })
      }
    >
      <ul className="flex flex-col gap-3">
        {rows.map((p) => (
          <li
            key={p.id}
            className={[
              'grid items-end gap-3 border-b border-border pb-3 last:border-0 last:pb-0 sm:border-0 sm:pb-0',
              isSuperAdmin
                ? 'grid-cols-[1fr_7rem_auto] sm:grid-cols-[1fr_6rem_7rem_auto_auto]'
                : 'grid-cols-[1fr_7rem] sm:grid-cols-[1fr_6rem_7rem_auto]',
            ].join(' ')}
          >
            <div className="col-span-full sm:col-span-1">
              <Field id={`p-name-${p.id}`} label="ชื่อสินค้า">
                <Input id={`p-name-${p.id}`} value={p.name} onChange={(e) => update(p.id, { name: e.target.value })} />
              </Field>
            </div>
            <Field id={`p-cat-${p.id}`} label="หมวด">
              <Select
                id={`p-cat-${p.id}`}
                value={p.category}
                onChange={(e) => update(p.id, { category: e.target.value as ProductCategory })}
              >
                {(Object.keys(PRODUCT_CATEGORY_LABEL) as ProductCategory[]).map((c) => (
                  <option key={c} value={c}>
                    {PRODUCT_CATEGORY_LABEL[c]}
                  </option>
                ))}
              </Select>
            </Field>
            <Field id={`p-price-${p.id}`} label="บาท/คิว">
              <Input
                id={`p-price-${p.id}`}
                type="number"
                inputMode="numeric"
                min={0}
                value={p.pricePerUnit}
                onChange={(e) => update(p.id, { pricePerUnit: num(e.target.value) })}
              />
            </Field>
            {isSuperAdmin ? (
              <div className="sm:order-last">
                <RemoveButton label={`ลบสินค้า ${p.name}`} onClick={() => remove(p)} />
              </div>
            ) : null}
            <label className="col-span-full flex min-h-11 cursor-pointer items-center gap-2 text-sm sm:col-span-1">
              <input
                type="checkbox"
                className="h-5 w-5 accent-[var(--color-primary)]"
                checked={p.active}
                onChange={(e) => update(p.id, { active: e.target.checked })}
              />
              ขายอยู่
            </label>
          </li>
        ))}
      </ul>
      {isSuperAdmin ? (
        <Button variant="secondary" className="mt-3" onClick={add}>
          <Plus size={16} aria-hidden /> เพิ่มสินค้า
        </Button>
      ) : null}
    </Section>
  );
}

const ZONE_FEE_COLUMNS = [
  { key: 'feeMin', label: 'ค่าส่งลูกค้า' },
  { key: 'driverFee', label: 'ค่ารถ 5 คิว' },
  { key: 'driverFee3', label: 'ค่ารถ 3 คิว' },
] as const;

function ZonesSection({
  zones,
  delivery,
  onSaved,
}: {
  zones: Zone[];
  delivery: AppSettings['delivery'];
  onSaved: () => Promise<void>;
}) {
  const { isSuperAdmin } = useAuth();
  const [rows, setRows] = useState(zones);
  useEffect(() => setRows(zones), [zones]);
  const saver = useSaver(onSaved);
  const update = (id: string, patch: Partial<Zone>) => setRows(rows.map((r) => (r.id === id ? { ...r, ...patch } : r)));
  const add = () =>
    setRows([...rows, { id: `${NEW_PREFIX}${Date.now()}`, name: '', feeMin: 0, driverFee: 0, driverFee3: 0, sortOrder: nextSort(rows) }]);
  const remove = (z: Zone) => {
    if (isNew(z.id) || window.confirm(`ลบ ต.${z.name}? กดบันทึกเพื่อยืนยัน`)) setRows(rows.filter((r) => r.id !== z.id));
  };
  const cols = isSuperAdmin
    ? 'grid-cols-[1fr_1fr_1fr_auto] sm:grid-cols-[1fr_6rem_6rem_6rem_auto]'
    : 'grid-cols-3 sm:grid-cols-[1fr_6rem_6rem_6rem]';

  return (
    <Section
      title="ค่าส่งตามตำบล (บาท/เที่ยว)"
      subtitle={`ค่าส่งลูกค้า: ราคาต่อเที่ยวเมื่อหน้างานห่างถนนใหญ่ไม่เกิน ${formatNumber(delivery.nearKm)} กม. ไกลกว่านั้นบวกเพิ่ม ${formatNumber(delivery.perKm)} บาท/กม. · ค่ารถคนขับ: บาทต่อเที่ยว แยกรถ 5 คิว (ปกติ) กับ 3 คิว บวกค่าส่งเพิ่มตามระยะแบบเดียวกับลูกค้า ใช้ตั้งต้นตอนเคลียร์ค่ารถ`}
      saver={saver}
      onSave={() =>
        saver.run(async () => {
          if (rows.some((r) => !r.name.trim())) throw new Error('กรุณาใส่ชื่อตำบลให้ครบ');
          for (const z of zones) {
            if (!rows.some((r) => r.id === z.id)) await deleteZone(z.id);
          }
          for (const r of rows) {
            if (isNew(r.id)) {
              await createZone(r);
              continue;
            }
            const before = zones.find((z) => z.id === r.id);
            const changed =
              before &&
              (before.name !== r.name || ZONE_FEE_COLUMNS.some((c) => before[c.key] !== r[c.key]));
            if (changed) await saveZone(r);
          }
        })
      }
    >
      <div className="overflow-hidden rounded border border-border">
        <div className={`hidden ${cols} gap-2 bg-subtle px-3 py-2 text-xs font-medium text-muted sm:grid`}>
          <span>ตำบล</span>
          {ZONE_FEE_COLUMNS.map((c) => (
            <span key={c.key}>{c.label}</span>
          ))}
          {isSuperAdmin ? <span className="w-11" /> : null}
        </div>
        <ul className="divide-y divide-border">
          {rows.map((z) => (
            <li key={z.id} className={`grid ${cols} items-end gap-2 px-3 py-2 sm:items-center`}>
              <div className="col-span-full sm:col-span-1">
                {isSuperAdmin ? (
                  <Input
                    aria-label="ชื่อตำบล"
                    placeholder="ชื่อตำบล"
                    value={z.name}
                    onChange={(e) => update(z.id, { name: e.target.value })}
                  />
                ) : (
                  <span className="text-sm font-medium">{z.name}</span>
                )}
              </div>
              {ZONE_FEE_COLUMNS.map((c) => (
                <label key={c.key} className="flex min-w-0 flex-col gap-1">
                  <span className="text-xs text-muted sm:hidden">{c.label}</span>
                  <Input
                    aria-label={`${c.label} ${z.name}`}
                    type="number"
                    inputMode="numeric"
                    min={0}
                    step={50}
                    value={z[c.key]}
                    onChange={(e) => update(z.id, { [c.key]: num(e.target.value) })}
                  />
                </label>
              ))}
              {isSuperAdmin ? <RemoveButton label={`ลบ ต.${z.name}`} onClick={() => remove(z)} /> : null}
            </li>
          ))}
        </ul>
      </div>
      {isSuperAdmin ? (
        <>
          <Button variant="secondary" className="mt-3" onClick={add}>
            <Plus size={16} aria-hidden /> เพิ่มตำบล
          </Button>
          <p className="mt-2 text-xs text-muted">ชื่อตำบลต้องตรงกับชื่อในแผนที่ ระบบจึงจะเลือกตำบลให้อัตโนมัติจากหมุดหน้างาน</p>
        </>
      ) : null}
    </Section>
  );
}

function DeliverySection({ settings, zones, onSaved }: { settings: AppSettings; zones: Zone[]; onSaved: () => Promise<void> }) {
  const [form, setForm] = useState(settings.delivery);
  useEffect(() => setForm(settings.delivery), [settings.delivery]);
  const saver = useSaver(onSaved);
  const sample = zones[0];

  return (
    <Section
      title="การคำนวณค่าส่งจากระยะ"
      subtitle="ระยะวัดตามถนนที่รถวิ่งจริง จากถนนสายหลักที่ใกล้ที่สุดเข้าไปถึงหมุดหน้างาน (ถ้าวัดตามถนนไม่ได้จะใช้ระยะเส้นตรง)"
      saver={saver}
      onSave={() =>
        saver.run(async () => {
          await saveSetting('delivery', { nearKm: form.nearKm, perKm: form.perKm, roundTo: form.roundTo });
        })
      }
    >
      <div className="grid grid-cols-3 gap-3">
        <Field id="ds-per" label="บาท/กม." hint="คิดเพิ่มต่อเที่ยว">
          <Input id="ds-per" type="number" min={0} step={5} value={form.perKm} onChange={(e) => setForm({ ...form, perKm: num(e.target.value) })} />
        </Field>
        <Field id="ds-near" label="ไม่คิดเพิ่ม (กม. แรก)" hint="ห่างถนนใหญ่ไม่เกินนี้ ไม่บวก">
          <Input id="ds-near" type="number" min={0} step={0.5} value={form.nearKm} onChange={(e) => setForm({ ...form, nearKm: num(e.target.value) })} />
        </Field>
        <Field id="ds-round" label="ปัดขึ้นทีละ (บาท)">
          <Input id="ds-round" type="number" min={0} step={10} value={form.roundTo} onChange={(e) => setForm({ ...form, roundTo: num(e.target.value) })} />
        </Field>
      </div>
      {sample ? (
        <p className="mt-3 rounded bg-subtle px-3 py-2 text-sm text-muted">
          ตัวอย่าง ต.{sample.name}:{' '}
          {[0.5, 1, 3, 5].map((km) => `${km} กม. = ${formatNumber(suggestDeliveryFee(sample, km, form))}`).join(' · ')}
        </p>
      ) : null}
    </Section>
  );
}

function CompanySection({ settings, onSaved }: { settings: AppSettings; onSaved: () => Promise<void> }) {
  const [form, setForm] = useState(settings.company);
  useEffect(() => setForm(settings.company), [settings.company]);
  const saver = useSaver(onSaved);

  return (
    <Section title="หัวบิล" subtitle="แสดงบนใบส่งของ ใบเสร็จ และใบวางบิล" saver={saver} onSave={() => saver.run(() => saveSetting('company', form))}>
      <div className="flex flex-col gap-3">
        <Field id="co-th" label="ชื่อ (ไทย)">
          <Input id="co-th" value={form.nameTh} onChange={(e) => setForm({ ...form, nameTh: e.target.value })} />
        </Field>
        <Field id="co-en" label="ชื่อ (อังกฤษ)">
          <Input id="co-en" value={form.nameEn} onChange={(e) => setForm({ ...form, nameEn: e.target.value })} />
        </Field>
        <Field id="co-addr" label="ที่อยู่">
          <Textarea id="co-addr" rows={2} value={form.address} onChange={(e) => setForm({ ...form, address: e.target.value })} />
        </Field>
        <div className="grid grid-cols-2 gap-3">
          <Field id="co-tax" label="เลขประจำตัวผู้เสียภาษี">
            <Input id="co-tax" inputMode="numeric" value={form.taxId} onChange={(e) => setForm({ ...form, taxId: e.target.value })} />
          </Field>
          <Field id="co-phone" label="โทร">
            <Input id="co-phone" inputMode="tel" value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} />
          </Field>
        </div>
      </div>
    </Section>
  );
}

function PaymentSection({ settings, onSaved }: { settings: AppSettings; onSaved: () => Promise<void> }) {
  const [form, setForm] = useState(settings.payment);
  useEffect(() => setForm(settings.payment), [settings.payment]);
  const saver = useSaver(onSaved);
  const ppValid = !form.promptPayId || !!promptPayTarget(form.promptPayId);
  const [qrError, setQrError] = useState('');
  const [readingQr, setReadingQr] = useState(false);

  const uploadQr = async (file: File | undefined) => {
    if (!file) return;
    setQrError('');
    setReadingQr(true);
    try {
      const text = await decodeQrImage(file);
      if (!text) setQrError('อ่าน QR จากรูปไม่ได้ ลองใช้รูปที่ชัดขึ้น หรือครอปให้เห็น QR เต็มๆ');
      else if (!isThaiQrPayload(text)) setQrError('QR นี้ไม่ใช่ QR รับเงิน (Thai QR / พร้อมเพย์)');
      else setForm((f) => ({ ...f, qrPayload: text }));
    } catch {
      setQrError('เปิดรูปไม่ได้');
    } finally {
      setReadingQr(false);
    }
  };

  return (
    <Section
      title="ช่องทางรับเงิน"
      subtitle="บัญชีธนาคารและ QR รับเงินจะแสดงที่หัวบิลด้านขวาของบิลที่ยังไม่ชำระ · ถ้าใส่พร้อมเพย์ บิลจะมี QR พร้อมยอดเงินเพิ่มอีกอัน"
      saver={saver}
      onSave={() =>
        saver.run(async () => {
          if (!ppValid) throw new Error('หมายเลขพร้อมเพย์ต้องเป็นเบอร์มือถือ 10 หลัก หรือเลขผู้เสียภาษี 13 หลัก');
          await saveSetting('payment', {
            promptPayId: form.promptPayId.trim(),
            bankText: form.bankText.trim(),
            bankName: form.bankName.trim(),
            bankAccountNo: form.bankAccountNo.trim(),
            bankAccountName: form.bankAccountName.trim(),
            qrPayload: form.qrPayload.trim(),
          });
        })
      }
    >
      <div className="flex flex-col gap-3">
        <div className="grid gap-3 sm:grid-cols-3">
          <Field id="pm-bank-name" label="ธนาคาร">
            <Input id="pm-bank-name" value={form.bankName} onChange={(e) => setForm({ ...form, bankName: e.target.value })} />
          </Field>
          <Field id="pm-acc-no" label="เลขบัญชี">
            <Input
              id="pm-acc-no"
              inputMode="numeric"
              value={form.bankAccountNo}
              onChange={(e) => setForm({ ...form, bankAccountNo: e.target.value })}
            />
          </Field>
          <Field id="pm-acc-name" label="ชื่อบัญชี">
            <Input id="pm-acc-name" value={form.bankAccountName} onChange={(e) => setForm({ ...form, bankAccountName: e.target.value })} />
          </Field>
        </div>
        <Field id="pm-qr" label="QR รับเงิน" hint="อัปโหลดรูป QR ของร้าน ระบบจะอ่านแล้ววาด QR ใหม่ให้คมชัดบนบิล" error={qrError || undefined}>
          <div className="flex items-center gap-3">
            {form.qrPayload ? (
              <div className="rounded border border-border bg-white p-1.5">
                <QrImage value={form.qrPayload} size={72} label="QR รับเงิน" />
              </div>
            ) : null}
            <div className="flex flex-wrap gap-2">
              <label className="inline-flex cursor-pointer items-center gap-1.5 rounded border border-border bg-surface px-3 py-2 text-sm font-medium hover:bg-subtle">
                <Upload size={16} aria-hidden /> {readingQr ? 'กำลังอ่าน…' : form.qrPayload ? 'เปลี่ยนรูป QR' : 'อัปโหลดรูป QR'}
                <input
                  id="pm-qr"
                  type="file"
                  accept="image/*"
                  className="sr-only"
                  disabled={readingQr}
                  onChange={(e) => {
                    void uploadQr(e.target.files?.[0]);
                    e.target.value = '';
                  }}
                />
              </label>
              {form.qrPayload ? (
                <Button variant="secondary" onClick={() => setForm({ ...form, qrPayload: '' })}>
                  ลบ QR
                </Button>
              ) : null}
            </div>
          </div>
        </Field>
        <Field
          id="pm-pp"
          label="หมายเลขพร้อมเพย์"
          hint="เบอร์มือถือ หรือ เลขผู้เสียภาษีของ หจก."
          error={ppValid ? undefined : 'รูปแบบไม่ถูกต้อง'}
        >
          <Input
            id="pm-pp"
            inputMode="numeric"
            value={form.promptPayId}
            invalid={!ppValid}
            onChange={(e) => setForm({ ...form, promptPayId: e.target.value })}
          />
        </Field>
        <Field id="pm-bank" label="ข้อความเพิ่มเติมท้ายบิล (ไม่บังคับ)" hint="แสดงตรงส่วนการชำระเงินด้านล่างของบิล">
          <Input id="pm-bank" value={form.bankText} onChange={(e) => setForm({ ...form, bankText: e.target.value })} />
        </Field>
      </div>
    </Section>
  );
}
