import { useState } from 'react';
import { Trash2 } from 'lucide-react';
import { lineAmount, lineDiscount } from '../calc/pricing';
import { useCatalog } from '../context/CatalogProvider';
import { draftTotals, updateOrder, type OrderEdit } from '../data/orders';
import { deliveryFeeFormula, formatMoney } from '../lib/format';
import { PAYMENT_METHOD_LABEL, type Order, type PaymentMethod, type TruckSize } from '../types';
import Button from './ui/Button';
import Field from './ui/Field';
import Input from './ui/Input';
import Modal from './ui/Modal';
import Select from './ui/Select';
import { ErrorBox } from './ui/States';
import Textarea from './ui/Textarea';

const num = (v: string) => Math.max(0, Number(v) || 0);
const ITEM_COLS = 'grid grid-cols-[minmax(0,1fr)_5rem_6rem_2.75rem] gap-2';

export default function OrderEditModal({
  order: o,
  by,
  onClose,
  onSaved,
}: {
  order: Order;
  by: string;
  onClose: () => void;
  onSaved: (o: Order) => void;
}) {
  const { products } = useCatalog();
  const delivery = o.fulfillment === 'delivery';
  const [form, setForm] = useState<OrderEdit>({
    orderDate: o.orderDate,
    items: o.items.map((it) => ({ ...it })),
    truckSize: o.truckSize,
    trips: o.trips,
    feePerCubic: o.feePerCubic,
    feePerTrip: o.feePerTrip,
    remoteSurcharge: o.remoteSurcharge,
    deliveryDiscount: o.deliveryDiscount,
    discountType: o.discountType,
    discountValue: o.discountValue,
    paymentMethod: o.paymentMethod,
    deliveryAddress: o.deliveryAddress,
    note: o.note,
  });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const set = (patch: Partial<OrderEdit>) => setForm((f) => ({ ...f, ...patch }));
  const setItem = (i: number, patch: Partial<OrderEdit['items'][number]>) =>
    set({ items: form.items.map((it, j) => (j === i ? { ...it, ...patch } : it)) });
  const addProduct = (id: string) => {
    const p = products.find((x) => x.id === id);
    if (p) set({ items: [...form.items, { productId: p.id, name: p.name, unit: p.unit, unitPrice: p.pricePerUnit, quantity: 1, amount: 0 }] });
  };

  const totals = draftTotals({ ...form, fulfillment: o.fulfillment });

  const submit = async () => {
    if (!form.items.some((it) => it.quantity > 0)) return setError('ต้องมีสินค้าอย่างน้อย 1 รายการ');
    if (form.items.some((it) => !it.name.trim())) return setError('กรุณาใส่ชื่อสินค้าให้ครบ');
    setSaving(true);
    setError('');
    try {
      onSaved(await updateOrder(o, form, by));
    } catch (err) {
      setError(err instanceof Error ? err.message : 'บันทึกไม่สำเร็จ');
      setSaving(false);
    }
  };

  return (
    <Modal
      open
      wide
      title={`แก้ไขออเดอร์ ${o.orderNo}`}
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
      <div className="flex flex-col gap-5">
        <div className="grid grid-cols-2 gap-3">
          <Field id="oe-date" label="วันที่ออเดอร์">
            <Input id="oe-date" type="date" value={form.orderDate} onChange={(e) => set({ orderDate: e.target.value })} />
          </Field>
          <Field id="oe-pay" label="วิธีชำระเงิน">
            <Select id="oe-pay" value={form.paymentMethod} onChange={(e) => set({ paymentMethod: e.target.value as PaymentMethod })}>
              {(Object.keys(PAYMENT_METHOD_LABEL) as PaymentMethod[]).map((m) => (
                <option key={m} value={m}>
                  {PAYMENT_METHOD_LABEL[m]}
                </option>
              ))}
            </Select>
          </Field>
        </div>

        <section>
          <p className="mb-2 text-sm font-medium">รายการสินค้า</p>
          <div className={`${ITEM_COLS} mb-1 text-xs text-muted`} aria-hidden>
            <span>สินค้า</span>
            <span>จำนวน</span>
            <span>ราคา/หน่วย</span>
          </div>
          <ul className="flex flex-col gap-2">
            {form.items.map((it, i) => (
              <li key={it.id ?? `new-${i}`} className={`${ITEM_COLS} items-center`}>
                <Input aria-label={`ชื่อสินค้า ${i + 1}`} value={it.name} onChange={(e) => setItem(i, { name: e.target.value })} />
                <Input
                  aria-label={`จำนวน ${it.name}`}
                  type="number"
                  inputMode="decimal"
                  min={0}
                  step={0.5}
                  value={it.quantity}
                  onChange={(e) => setItem(i, { quantity: num(e.target.value) })}
                />
                <Input
                  aria-label={`ราคาต่อหน่วย ${it.name}`}
                  type="number"
                  inputMode="decimal"
                  min={0}
                  value={it.unitPrice}
                  onChange={(e) => setItem(i, { unitPrice: num(e.target.value) })}
                />
                <button
                  type="button"
                  aria-label={`ลบ ${it.name}`}
                  onClick={() => set({ items: form.items.filter((_, j) => j !== i) })}
                  className="inline-flex min-h-11 min-w-11 items-center justify-center rounded text-muted hover:bg-destructive-soft hover:text-destructive cursor-pointer"
                >
                  <Trash2 size={16} aria-hidden />
                </button>
                <div className="col-span-full -mt-1 flex flex-wrap items-center gap-2 text-xs text-muted">
                  <span>ลด{it.unit}ละ</span>
                  <span className="w-24">
                    <Input
                      aria-label={`ส่วนลดต่อ${it.unit} ${it.name}`}
                      type="number"
                      inputMode="decimal"
                      min={0}
                      value={it.discountPerUnit || ''}
                      placeholder="0"
                      className="min-h-9 px-2 text-right text-sm"
                      onChange={(e) => setItem(i, { discountPerUnit: Math.min(it.unitPrice, num(e.target.value)) })}
                    />
                  </span>
                  <span>
                    บาท · รวม {formatMoney(lineAmount(it.unitPrice, it.quantity) - lineDiscount(it.unitPrice, it.quantity, it.discountPerUnit))}{' '}
                    บาท
                  </span>
                </div>
              </li>
            ))}
          </ul>
          <Select aria-label="เพิ่มสินค้า" className="mt-2" value="" onChange={(e) => addProduct(e.target.value)}>
            <option value="">+ เพิ่มสินค้า</option>
            {products
              .filter((p) => p.active)
              .map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name} ({formatMoney(p.pricePerUnit)}/{p.unit})
                </option>
              ))}
          </Select>
        </section>

        {delivery ? (
          <section className="flex flex-col gap-3">
            <p className="text-sm font-medium">การจัดส่ง</p>
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
              <Field id="oe-truck" label="ขนาดรถ">
                <Select
                  id="oe-truck"
                  value={form.truckSize ?? ''}
                  onChange={(e) => set({ truckSize: e.target.value ? (Number(e.target.value) as TruckSize) : null })}
                >
                  <option value="">—</option>
                  <option value={3}>3 คิว</option>
                  <option value={5}>5 คิว</option>
                </Select>
              </Field>
              <Field id="oe-trips" label="จำนวนเที่ยว">
                <Input
                  id="oe-trips"
                  type="number"
                  inputMode="numeric"
                  min={0}
                  value={form.trips}
                  onChange={(e) => set({ trips: Math.floor(num(e.target.value)) })}
                />
              </Field>
              <Field id="oe-fee-cubic" label="ค่าส่ง/คิว">
                <Input
                  id="oe-fee-cubic"
                  type="number"
                  inputMode="numeric"
                  min={0}
                  value={form.feePerCubic}
                  onChange={(e) => set({ feePerCubic: num(e.target.value) })}
                />
              </Field>
              <Field id="oe-fee" label="ค่าส่ง/เที่ยว">
                <Input id="oe-fee" type="number" inputMode="numeric" min={0} value={form.feePerTrip} onChange={(e) => set({ feePerTrip: num(e.target.value) })} />
              </Field>
              <Field id="oe-extra" label="ค่าส่งเพิ่ม">
                <Input
                  id="oe-extra"
                  type="number"
                  inputMode="numeric"
                  min={0}
                  value={form.remoteSurcharge}
                  onChange={(e) => set({ remoteSurcharge: num(e.target.value) })}
                />
              </Field>
              <Field id="oe-ddisc" label="ลดค่าส่ง (บาท)">
                <Input
                  id="oe-ddisc"
                  type="number"
                  inputMode="decimal"
                  min={0}
                  value={form.deliveryDiscount || ''}
                  placeholder="0"
                  onChange={(e) => set({ deliveryDiscount: num(e.target.value) })}
                />
              </Field>
            </div>
            <Field id="oe-addr" label="ที่อยู่จัดส่ง">
              <Textarea id="oe-addr" rows={2} value={form.deliveryAddress} onChange={(e) => set({ deliveryAddress: e.target.value })} />
            </Field>
          </section>
        ) : null}

        <section>
          <p className="mb-2 text-sm font-medium">ส่วนลด</p>
          <div className="flex gap-2">
            <div className="flex shrink-0 rounded border border-border p-0.5" role="radiogroup" aria-label="ประเภทส่วนลด">
              {(['baht', 'percent'] as const).map((t) => (
                <button
                  key={t}
                  type="button"
                  role="radio"
                  aria-checked={form.discountType === t}
                  onClick={() => form.discountType !== t && set({ discountType: t, discountValue: 0 })}
                  className={[
                    'min-h-10 rounded px-3 text-sm font-medium cursor-pointer',
                    form.discountType === t ? 'bg-primary text-primary-foreground' : 'text-muted hover:text-ink',
                  ].join(' ')}
                >
                  {t === 'baht' ? 'บาท' : '%'}
                </button>
              ))}
            </div>
            <Input
              aria-label="ส่วนลด"
              type="number"
              inputMode="decimal"
              min={0}
              max={form.discountType === 'percent' ? 100 : undefined}
              value={form.discountValue}
              onChange={(e) => set({ discountValue: num(e.target.value) })}
            />
          </div>
        </section>

        <Field id="oe-note" label="หมายเหตุ">
          <Textarea id="oe-note" rows={2} value={form.note} onChange={(e) => set({ note: e.target.value })} />
        </Field>

        <dl className="flex flex-col gap-1 rounded bg-subtle px-4 py-3 text-sm">
          <Row label="ค่าสินค้า" value={formatMoney(totals.subtotal)} />
          {delivery ? (
            <Row
              label={`ค่าจัดส่ง (${deliveryFeeFormula({ ...form, cubic: totals.totalQuantity })})`}
              value={formatMoney(totals.deliveryTotal)}
            />
          ) : null}
          {totals.deliveryDiscount ? <Row label="ส่วนลดค่าส่ง" value={`-${formatMoney(totals.deliveryDiscount)}`} /> : null}
          {totals.discountAmount - totals.deliveryDiscount > 0 ? (
            <Row label="ส่วนลด" value={`-${formatMoney(totals.discountAmount - totals.deliveryDiscount)}`} />
          ) : null}
          <div className="mt-1 flex items-baseline justify-between border-t border-border pt-2">
            <dt className="font-semibold">ยอดสุทธิใหม่</dt>
            <dd className="text-xl font-bold tabular-nums text-primary">{formatMoney(totals.total)}</dd>
          </div>
          {totals.total !== o.total ? (
            <p className="text-xs text-muted">
              เดิม {formatMoney(o.total)} บาท{o.statementId ? ' · ยอดในใบวางบิลจะปรับตามให้อัตโนมัติ' : ''}
            </p>
          ) : null}
        </dl>

        {error ? <ErrorBox message={error} /> : null}
      </div>
    </Modal>
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
