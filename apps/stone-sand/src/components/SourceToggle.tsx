import { ORDER_SOURCES, ORDER_SOURCE_SHORT, type OrderSource } from '../types';

/** ทั้งหมด / ร้านวัสดุ / ท่าทราย segmented control with a count on each option. */
export default function SourceToggle({
  value,
  onChange,
  counts,
  className = '',
}: {
  value: OrderSource | null;
  onChange: (source: OrderSource | null) => void;
  counts: Record<OrderSource | 'all', number>;
  className?: string;
}) {
  return (
    <div
      className={['inline-flex w-full rounded border border-border bg-surface p-1 sm:w-auto', className].join(' ')}
      role="radiogroup"
      aria-label="ประเภทออเดอร์"
    >
      {([null, ...ORDER_SOURCES] as (OrderSource | null)[]).map((s) => {
        const active = value === s;
        return (
          <button
            key={s ?? 'all'}
            type="button"
            role="radio"
            aria-checked={active}
            onClick={() => onChange(s)}
            className={[
              'flex min-h-10 flex-1 items-center justify-center gap-1.5 rounded-[9px] px-3 text-sm font-medium transition-colors cursor-pointer sm:flex-none',
              active ? 'bg-primary text-primary-foreground' : 'text-muted hover:bg-subtle hover:text-ink',
            ].join(' ')}
          >
            {s ? ORDER_SOURCE_SHORT[s] : 'ทั้งหมด'}
            <span className={['tabular-nums text-xs', active ? 'opacity-80' : ''].join(' ')}>{counts[s ?? 'all']}</span>
          </button>
        );
      })}
    </div>
  );
}
