import type { ReactNode } from 'react';
import { Mountain, Store } from 'lucide-react';
import { ORDER_SOURCE_LABEL, type OrderSource } from '../../types';
import StepTitle from './StepTitle';

interface Props {
  source: OrderSource | null;
  onSelect: (source: OrderSource) => void;
}

const OPTIONS: { value: OrderSource; icon: ReactNode; hint: string; docNo: string }[] = [
  { value: 'shop', icon: <Store size={32} aria-hidden />, hint: 'ลูกค้าสั่งผ่านร้านวัสดุก่อสร้าง', docNo: 'เลขที่ DO…' },
  { value: 'pit', icon: <Mountain size={32} aria-hidden />, hint: 'ลูกค้าสั่งกับท่าทรายโดยตรง', docNo: 'เลขที่ TS…' },
];

export default function StepSource({ source, onSelect }: Props) {
  return (
    <div className="step-enter flex flex-col gap-5">
      <StepTitle title="ประเภทออเดอร์" subtitle="ออเดอร์นี้มาจากร้านวัสดุก่อสร้าง หรือสั่งที่ท่าทรายโดยตรง" />
      <div className="grid gap-3 sm:grid-cols-2" role="radiogroup" aria-label="ประเภทออเดอร์">
        {OPTIONS.map((o) => {
          const active = source === o.value;
          return (
            <button
              key={o.value}
              type="button"
              role="radio"
              aria-checked={active}
              onClick={() => onSelect(o.value)}
              className={[
                'flex min-h-32 items-center gap-4 rounded border-2 p-5 text-left transition-colors cursor-pointer sm:flex-col sm:justify-center sm:text-center',
                active ? 'border-primary bg-primary-soft/50' : 'border-border bg-surface hover:bg-subtle',
              ].join(' ')}
            >
              <span
                className={[
                  'flex h-14 w-14 shrink-0 items-center justify-center rounded-full',
                  active ? 'bg-primary text-primary-foreground' : 'bg-subtle text-primary',
                ].join(' ')}
              >
                {o.icon}
              </span>
              <span className="flex min-w-0 flex-col gap-1">
                <span className="text-lg font-semibold text-ink">ออเดอร์{ORDER_SOURCE_LABEL[o.value]}</span>
                <span className="text-sm text-muted">{o.hint}</span>
                <span className="text-xs tabular-nums text-muted">{o.docNo}</span>
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
}
