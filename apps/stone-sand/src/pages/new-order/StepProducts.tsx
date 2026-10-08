import { Minus, Plus } from 'lucide-react';
import { lineAmount } from '../../calc/pricing';
import { totalTrips, truckForLoads, type Load } from '../../calc/trips';
import { formatMoney, formatNumber } from '../../lib/format';
import type { Product } from '../../types';
import StepTitle from './StepTitle';
import { quantitiesOf, totalQuantity } from './wizardState';

interface Props {
  products: Product[];
  loads: Record<string, Load>;
  onChange: (loads: Record<string, Load>) => void;
}

const PER_TRIP = [1, 2, 3, 4, 5];

export default function StepProducts({ products, loads, onChange }: Props) {
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

  const active = products.filter((p) => p.active);
  const quantities = quantitiesOf(loads);
  const sum = active.reduce((s, p) => s + lineAmount(p.pricePerUnit, quantities[p.id] || 0), 0);
  const count = totalQuantity(quantities);
  const tripCount = totalTrips(Object.values(loads));
  const truck = truckForLoads(Object.values(loads));

  return (
    <div className="step-enter flex flex-col gap-6">
      <StepTitle title="เลือกสินค้า" subtitle="เลือกคิวต่อเที่ยว แล้วใส่จำนวนเที่ยว" />
      <div className="flex flex-col gap-3">
        {active.map((p) => {
          const load = loads[p.id];
          const qty = quantities[p.id] || 0;
          return (
            <div
              key={p.id}
              className={['rounded border p-4 transition-colors sm:p-5', qty > 0 ? 'border-ink' : 'border-border'].join(' ')}
            >
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="text-lg font-medium leading-snug">{p.name}</p>
                  <p className="text-sm text-muted">
                    {formatNumber(p.pricePerUnit)} บาท / {p.unit}
                  </p>
                </div>
                {qty > 0 ? (
                  <p className="shrink-0 text-lg font-semibold tabular-nums">{formatMoney(lineAmount(p.pricePerUnit, qty))}</p>
                ) : null}
              </div>

              <p className="mt-4 text-sm text-muted">คิวต่อเที่ยว</p>
              <div className="mt-2 grid grid-cols-5 gap-2" role="radiogroup" aria-label={`คิวต่อเที่ยว ${p.name}`}>
                {PER_TRIP.map((n) => (
                  <button
                    key={n}
                    type="button"
                    role="radio"
                    aria-checked={load?.perTrip === n}
                    onClick={() => pickPerTrip(p.id, n)}
                    className={[
                      'min-h-11 rounded-full text-sm transition-colors cursor-pointer',
                      load?.perTrip === n ? 'bg-ink font-semibold text-white' : 'bg-subtle text-ink hover:bg-border',
                    ].join(' ')}
                  >
                    {n} คิว
                  </button>
                ))}
              </div>

              <div className="mt-4 flex items-center justify-between gap-3">
                <div className="min-w-0">
                  <p className="text-sm text-muted">จำนวนเที่ยว</p>
                  <p className="text-sm font-medium tabular-nums" aria-live="polite">
                    {load ? `รวม ${formatNumber(qty)} คิว` : 'เลือกคิวต่อเที่ยวก่อน'}
                  </p>
                </div>
                <div className="flex shrink-0 items-center gap-1">
                  <button
                    type="button"
                    aria-label={`ลดเที่ยว ${p.name}`}
                    onClick={() => setTrips(p.id, (load?.trips ?? 0) - 1)}
                    disabled={!load || load.trips <= 0}
                    className="inline-flex h-12 w-12 items-center justify-center rounded-full bg-subtle text-ink transition-colors hover:bg-border disabled:opacity-30 cursor-pointer disabled:cursor-default"
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
                    onChange={(e) => setTrips(p.id, Number(e.target.value))}
                    className="h-12 w-12 bg-transparent text-center text-xl font-semibold tabular-nums placeholder:text-muted/50 disabled:opacity-30"
                  />
                  <button
                    type="button"
                    aria-label={`เพิ่มเที่ยว ${p.name}`}
                    onClick={() => setTrips(p.id, (load?.trips ?? 0) + 1)}
                    disabled={!load}
                    className="inline-flex h-12 w-12 items-center justify-center rounded-full bg-ink text-white transition-colors hover:bg-black disabled:opacity-30 cursor-pointer disabled:cursor-default"
                  >
                    <Plus size={20} aria-hidden />
                  </button>
                </div>
              </div>
            </div>
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
