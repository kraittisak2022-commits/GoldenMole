import { useCallback, useRef, useState, type ReactNode } from 'react';
import { CalendarDays, ChevronDown, Mountain, Store } from 'lucide-react';
import CalendarPicker from '../../components/ui/CalendarPicker';
import Chip from '../../components/ui/Chip';
import { formatDateLongTh, formatDateShort, toIsoDate } from '../../lib/format';
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
  const date = orderDate || today;
  const fixed = sources.length === 1 ? sources[0] : null;
  const [open, setOpen] = useState(false);
  const trigger = useRef<HTMLButtonElement>(null);
  const close = useCallback(() => {
    setOpen(false);
    trigger.current?.focus();
  }, []);
  const pick = (iso: string) => {
    onDateChange(iso === today ? '' : iso);
    close();
  };

  return (
    <div className="step-enter flex flex-col gap-5">
      {fixed ? (
        <StepTitle title="วันที่ออเดอร์" subtitle={`ออเดอร์${ORDER_SOURCE_LABEL[fixed]} · เลือกวันที่ แล้วกด "ถัดไป"`} />
      ) : (
        <StepTitle title="ประเภทออเดอร์" subtitle="เลือกวันที่ แล้วเลือกว่ามาจากร้านวัสดุก่อสร้าง หรือสั่งที่ท่าทรายโดยตรง" />
      )}

      <section
        className="flex flex-col gap-3 rounded border border-border bg-surface p-4"
        aria-labelledby="order-date-label"
        data-tour={fixed ? 'wiz-source' : 'wiz-date'}
      >
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
          <div className="relative min-w-0 flex-1 sm:flex-none">
            <button
              ref={trigger}
              type="button"
              onClick={() => setOpen((o) => !o)}
              aria-label={`${formatDateLongTh(date)} · เลือกวันที่ออเดอร์`}
              aria-haspopup="dialog"
              aria-expanded={open}
              className={[
                'flex min-h-12 w-full items-center gap-2 rounded border px-4 text-base font-medium transition-colors cursor-pointer sm:min-w-56',
                open ? 'border-primary bg-primary-soft text-primary' : 'border-border bg-surface hover:bg-subtle',
              ].join(' ')}
            >
              <CalendarDays size={18} className={open ? '' : 'text-muted'} aria-hidden />
              <span className="truncate tabular-nums">{formatDateShort(date)}</span>
              <ChevronDown size={16} className="ml-auto shrink-0 text-muted" aria-hidden />
            </button>
            {open ? <CalendarPicker value={date} today={today} onSelect={pick} onClose={close} /> : null}
          </div>
        </div>
        <p className={['text-sm', date === today ? 'text-muted' : 'font-medium text-warning'].join(' ')}>
          {date === today ? 'ลงวันที่วันนี้' : date < today ? 'ลงวันที่ย้อนหลัง' : 'ลงวันที่ล่วงหน้า'} ·{' '}
          {formatDateLongTh(date)}
        </p>
      </section>

      {fixed ? null : (
        <div className="grid gap-3 sm:grid-cols-2" role="radiogroup" aria-label="ประเภทออเดอร์" data-tour="wiz-source">
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
      )}
    </div>
  );
}
