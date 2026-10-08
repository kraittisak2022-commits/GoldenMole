import { useState } from 'react';
import { ChevronDown, Minus, Plus } from 'lucide-react';
import { lineAmount } from '../../calc/pricing';
import { totalTrips, truckForLoads, type Load } from '../../calc/trips';
import { formatMoney, formatNumber } from '../../lib/format';
import { PRODUCT_CATEGORY_LABEL, type Product, type ProductCategory } from '../../types';
import StepTitle from './StepTitle';
import { quantitiesOf, totalQuantity } from './wizardState';

interface Props {
  products: Product[];
  loads: Record<string, Load>;
  onChange: (loads: Record<string, Load>) => void;
}

const PER_TRIP = [1, 2, 3, 4, 5];
const CATEGORIES = Object.keys(PRODUCT_CATEGORY_LABEL) as ProductCategory[];

export default function StepProducts({ products, loads, onChange }: Props) {
  const active = products.filter((p) => p.active);
  const quantities = quantitiesOf(loads);
  const [open, setOpen] = useState<Set<ProductCategory>>(
    () => new Set(active.filter((p) => quantities[p.id] > 0).map((p) => p.category)),
  );

  const setLoad = (id: string, load: Load | null) => {
    const next = { ...loads };
    if (load && load.perTrip > 0) next[id] = load;
    else delete next[id];
    onChange(next);
  };

  const pickPerTrip = (id: string, perTrip: number) => {
    const cur = loads[id];
    if (cur?.perTrip === perTrip) return setLoad(id, null);
    setLoad(id, { perTrip, trips: Math.max(1, cur?.trips ?? 0) });
  };

  const setTrips = (id: string, trips: number) => {
    const cur = loads[id];
    if (!cur) return;
    setLoad(id, { ...cur, trips: Math.max(0, Math.floor(trips || 0)) });
  };

  const toggle = (c: ProductCategory) => {
    const next = new Set(open);
    if (next.has(c)) next.delete(c);
    else next.add(c);
    setOpen(next);
  };

  const sum = active.reduce((s, p) => s + lineAmount(p.pricePerUnit, quantities[p.id] || 0), 0);
  const count = totalQuantity(quantities);
  const tripCount = totalTrips(Object.values(loads));
  const truck = truckForLoads(Object.values(loads));

  return (
    <div className="step-enter flex flex-col gap-6">
      <StepTitle title="เลือกสินค้า" subtitle="เลือกหมวด หิน หรือ ทราย แล้วเลือกคิวต่อเที่ยวและจำนวนเที่ยว" />
      <div className="flex flex-col gap-3">
        {CATEGORIES.map((c) => {
          const list = active.filter((p) => p.category === c);
          if (!list.length) return null;
          const isOpen = open.has(c);
          const picked = list.filter((p) => quantities[p.id] > 0);
          const pickedQty = picked.reduce((s, p) => s + quantities[p.id], 0);
          const pickedSum = picked.reduce((s, p) => s + lineAmount(p.pricePerUnit, quantities[p.id]), 0);
          return (
            <section
              key={c}
              className={['overflow-hidden rounded border transition-colors', picked.length ? 'border-ink' : 'border-border'].join(' ')}
            >
              <button
                type="button"
                aria-expanded={isOpen}
                aria-controls={`cat-${c}`}
                onClick={() => toggle(c)}
                className="flex min-h-16 w-full items-center gap-3 px-4 py-3 text-left transition-colors hover:bg-subtle cursor-pointer sm:px-5"
              >
                <span className="min-w-0 flex-1">
                  <span className="block text-lg font-semibold">{PRODUCT_CATEGORY_LABEL[c]}</span>
                  <span className="block text-sm text-muted">
                    {picked.length
                      ? `เลือก ${picked.length} รายการ · ${formatNumber(pickedQty)} คิว`
                      : list.map((p) => p.name).join(' · ')}
                  </span>
                </span>
                {picked.length ? <span className="shrink-0 font-semibold tabular-nums">{formatMoney(pickedSum)}</span> : null}
                <ChevronDown
                  size={22}
                  aria-hidden
                  className={['shrink-0 text-muted transition-transform duration-200', isOpen ? 'rotate-180' : ''].join(' ')}
                />
              </button>
              {isOpen ? (
                <div id={`cat-${c}`} className="divide-y divide-border border-t border-border">
                  {list.map((p) => (
                    <ProductCard
                      key={p.id}
                      product={p}
                      load={loads[p.id]}
                      qty={quantities[p.id] || 0}
                      onPerTrip={(n) => pickPerTrip(p.id, n)}
                      onTrips={(n) => setTrips(p.id, n)}
                    />
                  ))}
                </div>
              ) : null}
            </section>
          );
        })}
      </div>
      {count > 0 ? (
        <div className="flex items-baseline justify-between px-1">
          <span className="text-muted">
            รวม {formatNumber(count)} คิว · {tripCount} เที่ยว · รถ {truck} คิว
          </span>
          <span className="text-lg font-semibold tabular-nums">{formatMoney(sum)} บาท</span>
        </div>
      ) : null}
    </div>
  );
}

function ProductCard({
  product: p,
  load,
  qty,
  onPerTrip,
  onTrips,
}: {
  product: Product;
  load: Load | undefined;
  qty: number;
  onPerTrip: (perTrip: number) => void;
  onTrips: (trips: number) => void;
}) {
  return (
    <div className={['px-4 py-4 transition-colors sm:px-5', qty > 0 ? 'bg-primary-soft/40' : ''].join(' ')}>
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="text-base font-medium leading-snug sm:text-lg">{p.name}</p>
          <p className="text-sm text-muted">
            {formatNumber(p.pricePerUnit)} บาท / {p.unit}
          </p>
          <p className="mt-1 text-sm tabular-nums" aria-live="polite">
            {load ? (
              <>
                รวม {formatNumber(qty)} คิว
                {qty > 0 ? <span className="font-semibold"> · {formatMoney(lineAmount(p.pricePerUnit, qty))}</span> : null}
              </>
            ) : (
              <span className="text-muted">เลือกคิวต่อเที่ยวก่อน</span>
            )}
          </p>
        </div>
        <div className="flex shrink-0 flex-col items-center gap-1">
          <p className="text-xs text-muted">จำนวนเที่ยว</p>
          <div className="flex items-center gap-1">
            <button
              type="button"
              aria-label={`ลดเที่ยว ${p.name}`}
              onClick={() => onTrips((load?.trips ?? 0) - 1)}
              disabled={!load || load.trips <= 0}
              className="inline-flex h-11 w-11 items-center justify-center rounded-full bg-subtle text-ink transition-colors hover:bg-border disabled:opacity-30 cursor-pointer disabled:cursor-default"
            >
              <Minus size={20} aria-hidden />
            </button>
            <input
              type="number"
              inputMode="numeric"
              min={0}
              step={1}
              aria-label={`จำนวนเที่ยว ${p.name}`}
              value={load?.trips || ''}
              placeholder="0"
              disabled={!load}
              onChange={(e) => onTrips(Number(e.target.value))}
              className="h-11 w-10 bg-transparent text-center text-xl font-semibold tabular-nums placeholder:text-muted/50 disabled:opacity-30"
            />
            <button
              type="button"
              aria-label={`เพิ่มเที่ยว ${p.name}`}
              onClick={() => onTrips((load?.trips ?? 0) + 1)}
              disabled={!load}
              className="inline-flex h-11 w-11 items-center justify-center rounded-full bg-ink text-white transition-colors hover:bg-black disabled:opacity-30 cursor-pointer disabled:cursor-default"
            >
              <Plus size={20} aria-hidden />
            </button>
          </div>
        </div>
      </div>

      <p className="mt-4 text-sm text-muted">คิวต่อเที่ยว</p>
      <div className="mt-2 grid grid-cols-5 gap-2" role="radiogroup" aria-label={`คิวต่อเที่ยว ${p.name}`}>
        {PER_TRIP.map((n) => (
          <button
            key={n}
            type="button"
            role="radio"
            aria-checked={load?.perTrip === n}
            onClick={() => onPerTrip(n)}
            className={[
              'min-h-11 rounded-full text-sm transition-colors cursor-pointer',
              load?.perTrip === n ? 'bg-ink font-semibold text-white' : 'bg-subtle text-ink hover:bg-border',
            ].join(' ')}
          >
            {n} คิว
          </button>
        ))}
      </div>
    </div>
  );
}
