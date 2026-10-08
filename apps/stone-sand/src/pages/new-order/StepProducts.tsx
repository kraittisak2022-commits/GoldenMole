import { Minus, Plus } from 'lucide-react';
import { lineAmount } from '../../calc/pricing';
import { formatMoney, formatNumber } from '../../lib/format';
import type { Product } from '../../types';
import StepTitle from './StepTitle';
import { totalQuantity } from './wizardState';

interface Props {
  products: Product[];
  quantities: Record<string, number>;
  onChange: (q: Record<string, number>) => void;
}

const QUICK = [1, 3, 5];

export default function StepProducts({ products, quantities, onChange }: Props) {
  const setQty = (id: string, qty: number) => {
    const clean = Math.max(0, Math.round(qty * 10) / 10);
    onChange({ ...quantities, [id]: clean });
  };

  const active = products.filter((p) => p.active);
  const sum = active.reduce((s, p) => s + lineAmount(p.pricePerUnit, quantities[p.id] || 0), 0);
  const count = totalQuantity(quantities);

  return (
    <div className="step-enter flex flex-col gap-6">
      <StepTitle title="เลือกสินค้า" subtitle="ใส่จำนวนเป็นคิว" />
      <div className="flex flex-col gap-3">
        {active.map((p) => {
          const qty = quantities[p.id] || 0;
          const selected = qty > 0;
          return (
            <div
              key={p.id}
              className={[
                'rounded border p-4 transition-colors sm:p-5',
                selected ? 'border-ink' : 'border-border',
              ].join(' ')}
            >
              <div className="flex items-center justify-between gap-3">
                <div className="min-w-0">
                  <p className="text-lg font-medium leading-snug">{p.name}</p>
                  <p className="text-sm text-muted">
                    {formatNumber(p.pricePerUnit)} บาท / {p.unit}
                    {selected ? (
                      <span className="font-medium tabular-nums text-ink"> · {formatMoney(lineAmount(p.pricePerUnit, qty))}</span>
                    ) : null}
                  </p>
                </div>
                <div className="flex shrink-0 items-center gap-1">
                  <button
                    type="button"
                    aria-label={`ลด ${p.name}`}
                    onClick={() => setQty(p.id, qty - 1)}
                    disabled={qty <= 0}
                    className="inline-flex h-12 w-12 items-center justify-center rounded-full bg-subtle text-ink transition-colors hover:bg-border disabled:opacity-30 cursor-pointer disabled:cursor-default"
                  >
                    <Minus size={20} aria-hidden />
                  </button>
                  <input
                    type="number"
                    inputMode="decimal"
                    min={0}
                    step={0.5}
                    aria-label={`จำนวน ${p.name} (คิว)`}
                    value={qty || ''}
                    placeholder="0"
                    onChange={(e) => setQty(p.id, Number(e.target.value))}
                    className="h-12 w-14 bg-transparent text-center text-xl font-semibold tabular-nums placeholder:text-muted/50"
                  />
                  <button
                    type="button"
                    aria-label={`เพิ่ม ${p.name}`}
                    onClick={() => setQty(p.id, qty + 1)}
                    className="inline-flex h-12 w-12 items-center justify-center rounded-full bg-ink text-white transition-colors hover:bg-black cursor-pointer"
                  >
                    <Plus size={20} aria-hidden />
                  </button>
                </div>
              </div>
              <div className="mt-3 flex gap-2">
                {QUICK.map((n) => (
                  <button
                    key={n}
                    type="button"
                    onClick={() => setQty(p.id, qty === n ? 0 : n)}
                    aria-pressed={qty === n}
                    className={[
                      'min-h-11 rounded-full px-4 text-sm transition-colors cursor-pointer',
                      qty === n ? 'bg-ink text-white' : 'bg-subtle text-ink hover:bg-border',
                    ].join(' ')}
                  >
                    {n} คิว
                  </button>
                ))}
              </div>
            </div>
          );
        })}
      </div>
      {count > 0 ? (
        <div className="flex items-baseline justify-between px-1">
          <span className="text-muted">รวม {formatNumber(count)} คิว</span>
          <span className="text-lg font-semibold tabular-nums">{formatMoney(sum)} บาท</span>
        </div>
      ) : null}
    </div>
  );
}
