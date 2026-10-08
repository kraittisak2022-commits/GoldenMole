import { Link } from 'react-router-dom';
import { ChevronRight, Store, Truck } from 'lucide-react';
import { formatDateShort, formatMoney } from '../lib/format';
import { deliveryBadge, paymentBadge } from '../lib/orderStatus';
import type { Order } from '../types';
import SourceBadge from './SourceBadge';
import Badge from './ui/Badge';

export default function OrderRow({ order: o }: { order: Order }) {
  const pay = paymentBadge(o);
  const del = deliveryBadge(o);
  const Icon = o.fulfillment === 'delivery' ? Truck : Store;
  return (
    <Link
      to={`/orders/${o.id}`}
      className="flex min-h-16 items-center gap-3 px-4 py-3 transition-colors hover:bg-subtle"
    >
      <span
        className={[
          'flex h-10 w-10 shrink-0 items-center justify-center rounded-full',
          o.cancelled ? 'bg-subtle text-muted' : 'bg-primary-soft text-primary',
        ].join(' ')}
        aria-hidden
      >
        <Icon size={18} />
      </span>
      <div className="min-w-0 flex-1">
        <div className="flex items-baseline justify-between gap-2">
          <p className={['truncate font-medium', o.cancelled ? 'text-muted line-through' : ''].join(' ')}>{o.customer.name}</p>
          <p className="shrink-0 font-semibold tabular-nums">{formatMoney(o.total)}</p>
        </div>
        <div className="mt-1 flex flex-wrap items-center gap-1.5">
          <span className="mr-1 text-xs text-muted tabular-nums">
            {o.orderNo} · {formatDateShort(o.orderDate)}
          </span>
          <SourceBadge source={o.source} />
          {o.cancelled ? (
            <Badge tone="danger">ยกเลิก</Badge>
          ) : (
            <>
              <Badge tone={pay.tone}>{pay.label}</Badge>
              <Badge tone={del.tone}>{del.label}</Badge>
            </>
          )}
        </div>
      </div>
      <ChevronRight size={18} className="shrink-0 text-muted" aria-hidden />
    </Link>
  );
}
