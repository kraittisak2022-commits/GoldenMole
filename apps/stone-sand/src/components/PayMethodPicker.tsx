import { Banknote, Landmark } from 'lucide-react';
import { PAYMENT_METHOD_LABEL } from '../types';

export type PayMethod = 'cash' | 'transfer';

export default function PayMethodPicker({
  value,
  onChange,
  hints,
  label = 'ช่องทางการชำระเงิน',
}: {
  value: PayMethod | null;
  onChange: (m: PayMethod) => void;
  hints: Record<PayMethod, string>;
  label?: string;
}) {
  const options: { value: PayMethod; icon: typeof Banknote }[] = [
    { value: 'cash', icon: Banknote },
    { value: 'transfer', icon: Landmark },
  ];
  return (
    <div>
      <p className="mb-2 text-sm font-medium">{label}</p>
      <div className="grid grid-cols-2 gap-3" role="radiogroup" aria-label={label}>
        {options.map(({ value: m, icon: Icon }) => {
          const active = value === m;
          return (
            <button
              key={m}
              type="button"
              role="radio"
              aria-checked={active}
              onClick={() => onChange(m)}
              className={[
                'flex min-h-20 flex-col items-center justify-center gap-1 rounded border-2 p-3 text-center transition-colors cursor-pointer',
                active ? 'border-primary bg-primary-soft text-primary' : 'border-border hover:border-ink/30',
              ].join(' ')}
            >
              <Icon size={22} aria-hidden />
              <span className="font-semibold">{PAYMENT_METHOD_LABEL[m]}</span>
              <span className="text-xs text-muted">{hints[m]}</span>
            </button>
          );
        })}
      </div>
    </div>
  );
}
