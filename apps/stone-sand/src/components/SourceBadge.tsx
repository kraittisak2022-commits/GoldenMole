import { Mountain, Store } from 'lucide-react';
import { ORDER_SOURCE_LABEL, ORDER_SOURCE_SHORT, type OrderSource } from '../types';

export default function SourceBadge({ source, long = false }: { source: OrderSource; long?: boolean }) {
  const Icon = source === 'pit' ? Mountain : Store;
  return (
    <span
      className={[
        'inline-flex items-center gap-1 whitespace-nowrap rounded-full border px-2.5 py-0.5 text-xs font-medium',
        source === 'pit' ? 'border-orange-200 bg-orange-50 text-orange-800' : 'border-border bg-subtle text-slate-700',
      ].join(' ')}
    >
      <Icon size={12} aria-hidden />
      {long ? ORDER_SOURCE_LABEL[source] : ORDER_SOURCE_SHORT[source]}
    </span>
  );
}
