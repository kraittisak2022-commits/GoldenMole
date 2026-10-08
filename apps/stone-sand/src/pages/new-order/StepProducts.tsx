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

  return (
    <div className="step-enter flex flex-col gap-4">
      <StepTitle title="สินค้า" subtitle="ใส่จำนวนเป็นคิว กดปุ่มลัด 1 / 3 / 5 คิว หรือพิมพ์เอง" />
      <div className="flex flex-col gap-3">
        {active.map((p) => {
          const qty = quantities[p.id] || 0;
          const selected = qty > 0;
          return (
            <div
              key={p.id}
              className={[
                'rounded border bg-surface p-4 transition-colors',
                selected ? 'border-primary ring-1 ring-primary' : 'border-border',
              ].join(' ')}
            >
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="font-medium">{p.name}</p>
                  <p className="text-sm text-muted">
                    {formatNumber(p.pricePerUnit)} บาท / {p.unit}
                  </p>
                </div>
                {selected ? (
                  <p className="text-right font-semibold tabular-nums text-primary">
                    {formatMoney(lineAmount(p.pricePerUnit, qty))}
                  </p>
                ) : null}
              </div>
              <div className="mt-3 flex flex-wrap items-center gap-2">
                {QUICK.map((n) => (
                  <button
                    key={n}
                    type="button"
                    onClick={() => setQty(p.id, qty === n ? 0 : n)}
                    aria-pressed={qty === n}
                    className={[
                      'min-h-11 min-w-14 rounded border px-3 text-sm font-medium transition-colors cursor-pointer',
                      qty === n ? 'border-primary bg-primary text-primary-foreground' : 'border-border hover:bg-subtle',
                    ].join(' ')}
                  >
                    {n} คิว
                  </button>
                ))}
                <div className="ml-auto flex items-center rounded border border-border">
                  <button
                    type="button"
                    aria-label={`ลด ${p.name}`}
                    onClick={() => setQty(p.id, qty - 1)}
                    className="inline-flex min-h-11 min-w-11 items-center justify-center text-muted hover:text-ink cursor-pointer disabled:opacity-40"
                    disabled={qty <= 0}
                  >
                    <Minus size={16} aria-hidden />
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
                    className="h-11 w-16 border-x border-border bg-transparent text-center text-base tabular-nums"
                  />
                  <button
                    type="button"
                    aria-label={`เพิ่ม ${p.name}`}
                    onClick={() => setQty(p.id, qty + 1)}
                    className="inline-flex min-h-11 min-w-11 items-center justify-center text-muted hover:text-ink cursor-pointer"
                  >
                    <Plus size={16} aria-hidden />
                  </button>
                </div>
              </div>
            </div>
          );
        })}
      </div>
      <div className="flex items-center justify-between rounded bg-subtle px-4 py-3 text-sm">
        <span className="text-muted">รวม {formatNumber(totalQuantity(quantities))} คิว</span>
        <span className="font-semibold tabular-nums">{formatMoney(sum)} บาท</span>
      </div>
    </div>
  );
}
