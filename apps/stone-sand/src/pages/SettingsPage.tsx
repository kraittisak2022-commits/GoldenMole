import { useEffect, useState, type ReactNode } from 'react';
import { Check } from 'lucide-react';
import { suggestDeliveryFee } from '../calc/deliveryFee';
import Button from '../components/ui/Button';
import Card from '../components/ui/Card';
import Field from '../components/ui/Field';
import Input from '../components/ui/Input';
import PageHeader from '../components/ui/PageHeader';
import { ErrorBox, Loading } from '../components/ui/States';
import Textarea from '../components/ui/Textarea';
import { useCatalog } from '../context/CatalogProvider';
import { saveProduct, saveSetting, saveZone } from '../data/catalog';
import { formatNumber } from '../lib/format';
import { promptPayTarget } from '../lib/promptpay';
import type { AppSettings, Product, Zone } from '../types';

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

function ProductsSection({ products, onSaved }: { products: Product[]; onSaved: () => Promise<void> }) {
  const [rows, setRows] = useState(products);
  useEffect(() => setRows(products), [products]);
  const saver = useSaver(onSaved);
  const update = (id: string, patch: Partial<Product>) => setRows(rows.map((r) => (r.id === id ? { ...r, ...patch } : r)));

  return (
    <Section
      title="ราคาสินค้า (ต่อคิว)"
      subtitle="ราคา 3 คิว / 5 คิว คิดจากราคาต่อคิว × จำนวน"
      saver={saver}
      onSave={() =>
        saver.run(async () => {
          for (const r of rows) {
            const before = products.find((p) => p.id === r.id);
            if (before && (before.pricePerUnit !== r.pricePerUnit || before.name !== r.name || before.active !== r.active)) {
              await saveProduct(r);
            }
          }
        })
      }
    >
      <ul className="flex flex-col gap-3">
        {rows.map((p) => (
          <li key={p.id} className="grid grid-cols-[1fr_7rem] items-end gap-3 sm:grid-cols-[1fr_7rem_auto]">
            <Field id={`p-name-${p.id}`} label="ชื่อสินค้า">
              <Input id={`p-name-${p.id}`} value={p.name} onChange={(e) => update(p.id, { name: e.target.value })} />
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
            <label className="col-span-2 flex min-h-11 cursor-pointer items-center gap-2 text-sm sm:col-span-1">
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
    </Section>
  );
}

function ZonesSection({
  zones,
  delivery,
  onSaved,
}: {
  zones: Zone[];
  delivery: AppSettings['delivery'];
  onSaved: () => Promise<void>;
}) {
  const [rows, setRows] = useState(zones);
  useEffect(() => setRows(zones), [zones]);
  const saver = useSaver(onSaved);
  const update = (id: string, patch: Partial<Zone>) => setRows(rows.map((r) => (r.id === id ? { ...r, ...patch } : r)));
  const invalid = rows.find((r) => r.feeMax < r.feeMin);

  return (
    <Section
      title="ค่าส่งตามตำบล (บาท/เที่ยว)"
      subtitle={`ใกล้ถนนใหญ่ไม่เกิน ${formatNumber(delivery.nearKm)} กม. คิดราคาต่ำสุด ไกลขึ้นคิดเพิ่มตามระยะจนถึงราคาสูงสุด`}
      saver={saver}
      onSave={() =>
        saver.run(async () => {
          if (invalid) throw new Error(`ต.${invalid.name}: ราคาสูงสุดต้องไม่น้อยกว่าราคาต่ำสุด`);
          for (const r of rows) {
            const before = zones.find((z) => z.id === r.id);
            if (before && (before.feeMin !== r.feeMin || before.feeMax !== r.feeMax)) await saveZone(r);
          }
        })
      }
    >
      <div className="overflow-hidden rounded border border-border">
        <div className="grid grid-cols-[1fr_6rem_6rem] gap-2 bg-subtle px-3 py-2 text-xs font-medium text-muted">
          <span>ตำบล</span>
          <span>ต่ำสุด</span>
          <span>สูงสุด</span>
        </div>
        <ul className="divide-y divide-border">
          {rows.map((z) => (
            <li key={z.id} className="grid grid-cols-[1fr_6rem_6rem] items-center gap-2 px-3 py-2">
              <span className="text-sm font-medium">{z.name}</span>
              <Input
                aria-label={`ค่าส่งต่ำสุด ${z.name}`}
                type="number"
                inputMode="numeric"
                min={0}
                step={50}
                value={z.feeMin}
                onChange={(e) => update(z.id, { feeMin: num(e.target.value) })}
              />
              <Input
                aria-label={`ค่าส่งสูงสุด ${z.name}`}
                type="number"
                inputMode="numeric"
                min={0}
                step={50}
                value={z.feeMax}
                invalid={z.feeMax < z.feeMin}
                onChange={(e) => update(z.id, { feeMax: num(e.target.value) })}
              />
            </li>
          ))}
        </ul>
      </div>
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
      subtitle="ระยะวัดจากหมุดหน้างานถึงถนนสายหลักที่ใกล้ที่สุด (เส้นตรง)"
      saver={saver}
      onSave={() =>
        saver.run(async () => {
          if (form.maxKm <= form.nearKm) throw new Error('ระยะไกลสุดต้องมากกว่าระยะใกล้');
          await saveSetting('delivery', form);
        })
      }
    >
      <div className="grid grid-cols-3 gap-3">
        <Field id="ds-near" label="ระยะใกล้ (กม.)" hint="ไม่เกินนี้ = ราคาต่ำสุด">
          <Input id="ds-near" type="number" min={0} step={0.5} value={form.nearKm} onChange={(e) => setForm({ ...form, nearKm: num(e.target.value) })} />
        </Field>
        <Field id="ds-max" label="ระยะไกลสุด (กม.)" hint="ตั้งแต่นี้ = ราคาสูงสุด">
          <Input id="ds-max" type="number" min={0} step={0.5} value={form.maxKm} onChange={(e) => setForm({ ...form, maxKm: num(e.target.value) })} />
        </Field>
        <Field id="ds-round" label="ปัดขึ้นทีละ (บาท)">
          <Input id="ds-round" type="number" min={0} step={10} value={form.roundTo} onChange={(e) => setForm({ ...form, roundTo: num(e.target.value) })} />
        </Field>
      </div>
      {sample ? (
        <p className="mt-3 rounded bg-subtle px-3 py-2 text-sm text-muted">
          ตัวอย่าง ต.{sample.name}:{' '}
          {[1, 5, 8, 12].map((km) => `${km} กม. = ${formatNumber(suggestDeliveryFee(sample, km, form))}`).join(' · ')}
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

  return (
    <Section
      title="ช่องทางรับเงิน"
      subtitle="ถ้าใส่พร้อมเพย์ บิลที่ยังไม่จ่ายจะมี QR ให้ลูกค้าสแกนจ่ายพร้อมยอดเงิน"
      saver={saver}
      onSave={() =>
        saver.run(async () => {
          if (!ppValid) throw new Error('หมายเลขพร้อมเพย์ต้องเป็นเบอร์มือถือ 10 หลัก หรือเลขผู้เสียภาษี 13 หลัก');
          await saveSetting('payment', { promptPayId: form.promptPayId.trim(), bankText: form.bankText.trim() });
        })
      }
    >
      <div className="flex flex-col gap-3">
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
        <Field id="pm-bank" label="ข้อความบัญชีธนาคาร" hint="เช่น กสิกรไทย 123-4-56789-0 หจก. พีรสิทธิ์ วัสดุก่อสร้าง">
          <Input id="pm-bank" value={form.bankText} onChange={(e) => setForm({ ...form, bankText: e.target.value })} />
        </Field>
      </div>
    </Section>
  );
}
