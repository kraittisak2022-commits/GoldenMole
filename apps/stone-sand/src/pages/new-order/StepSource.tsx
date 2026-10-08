import type { ReactNode } from 'react';
import { CalendarDays, Mountain, Store } from 'lucide-react';
import Chip from '../../components/ui/Chip';
import Input from '../../components/ui/Input';
import { formatDateLongTh, shiftIsoDate, toIsoDate } from '../../lib/format';
import { ORDER_SOURCE_LABEL, type OrderSource } from '../../types';
import StepTitle from './StepTitle';

interface Props {
  /** Sources this account may create; one means it is fixed. */
  sources: OrderSource[];
  source: OrderSource | null;
  onSelect: (source: OrderSource) => void;
  /** '' means today. */
  orderDate: string;
  onDateChange: (date: string) => void;
}

const OPTIONS: { value: OrderSource; icon: ReactNode; hint: string; docNo: string }[] = [
  { value: 'shop', icon: <Store size={32} aria-hidden />, hint: 'ลูกค้าสั่งผ่านร้านวัสดุก่อสร้าง', docNo: 'เลขที่ DO…' },
  { value: 'pit', icon: <Mountain size={32} aria-hidden />, hint: 'ลูกค้าสั่งกับท่าทรายโดยตรง', docNo: 'เลขที่ TS…' },
];

export default function StepSource({ sources, source, onSelect, orderDate, onDateChange }: Props) {
  const today = toIsoDate();
  const yesterday = shiftIsoDate(today, -1);
  const date = orderDate || today;

  return (
    <div className="step-enter flex flex-col gap-5">
      <StepTitle title="ประเภทออเดอร์" subtitle="เลือกวันที่ แล้วเลือกว่ามาจากร้านวัสดุก่อสร้าง หรือสั่งที่ท่าทรายโดยตรง" />

      <section className="flex flex-col gap-3 rounded border border-border bg-surface p-4" aria-labelledby="order-date-label">
        <div className="flex items-center gap-2">
          <CalendarDays size={18} className="text-primary" aria-hidden />
          <h3 id="order-date-label" className="font-semibold">
            วันที่ออเดอร์
          </h3>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <Chip active={date === today} onClick={() => onDateChange('')}>
            วันนี้
          </Chip>
          <Chip active={date === yesterday} onClick={() => onDateChange(yesterday)}>
            เมื่อวาน
          </Chip>
          <Input
            type="date"
            aria-label="เลือกวันที่ออเดอร์"
            value={date}
            onChange={(e) => onDateChange(e.target.value === today ? '' : e.target.value)}
            className="w-auto min-w-44 flex-1 sm:flex-none"
          />
        </div>
        <p className={['text-sm', date === today ? 'text-muted' : 'font-medium text-warning'].join(' ')}>
          {date === today ? 'ลงวันที่วันนี้' : date < today ? 'ลงวันที่ย้อนหลัง' : 'ลงวันที่ล่วงหน้า'} ·{' '}
          {formatDateLongTh(date)}
        </p>
      </section>

      {sources.length === 1 ? (
        <p className="-mb-2 text-sm text-muted">บัญชีนี้สร้างได้เฉพาะออเดอร์{ORDER_SOURCE_LABEL[sources[0]]}</p>
      ) : null}
      <div className="grid gap-3 sm:grid-cols-2" role="radiogroup" aria-label="ประเภทออเดอร์">
        {OPTIONS.filter((o) => sources.includes(o.value)).map((o) => {
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
