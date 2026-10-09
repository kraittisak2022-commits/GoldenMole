import { useEffect, useRef, useState, type KeyboardEvent } from 'react';
import { ChevronLeft, ChevronRight } from 'lucide-react';
import { TH_WEEKDAYS_SHORT, monthGrid, sameMonth, shiftMonth, yearMonthOf, type YearMonth } from '../../lib/calendar';
import { TH_MONTHS, formatDateLongTh, shiftIsoDate } from '../../lib/format';

interface Props {
  value: string;
  today: string;
  /** Orders per ISO day, known only for the month of `value`. */
  counts?: Record<string, number>;
  onSelect: (iso: string) => void;
  onClose: () => void;
}

const KEY_STEP: Record<string, number> = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7 };

/**
 * Month calendar in Thai with Buddhist-era years: a bottom sheet on phones and a popover
 * under its `relative` parent from `sm` up.
 */
export default function CalendarPicker({ value, today, counts, onSelect, onClose }: Props) {
  const [view, setView] = useState<YearMonth>(() => yearMonthOf(value));
  const [focused, setFocused] = useState(value);
  const days = useRef(new Map<string, HTMLButtonElement>());
  const moved = useRef(false);

  useEffect(() => {
    const onKey = (e: globalThis.KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  useEffect(() => {
    days.current.get(focused)?.focus({ preventScroll: !moved.current });
    moved.current = true;
  }, [focused]);

  const grid = monthGrid(view);
  const tabStop = grid.includes(focused) ? focused : grid.find((iso) => sameMonth(iso, view));
  const countsShown = !!counts && sameMonth(value, view);
  const step = (by: number) => setView((v) => shiftMonth(v, by));

  const focusDay = (iso: string) => {
    setFocused(iso);
    if (!sameMonth(iso, view)) setView(yearMonthOf(iso));
  };

  const onGridKey = (e: KeyboardEvent<HTMLDivElement>) => {
    const by = KEY_STEP[e.key];
    if (by == null) return;
    e.preventDefault();
    focusDay(shiftIsoDate(focused, by));
  };

  return (
    <>
      <button
        type="button"
        aria-label="ปิดปฏิทิน"
        onClick={onClose}
        className="modal-backdrop fixed inset-0 z-[1000] cursor-default bg-ink/40 sm:bg-transparent"
      />
      <div className="fixed inset-x-0 bottom-0 z-[1001] sm:absolute sm:inset-x-auto sm:bottom-auto sm:left-1/2 sm:top-full sm:mt-2 sm:-translate-x-1/2">
        <div
          role="dialog"
          aria-label="เลือกวันที่"
          className="modal-panel rounded-t-2xl border border-border bg-surface px-4 pt-3 shadow-2xl pb-[max(1rem,env(safe-area-inset-bottom))] sm:w-[22rem] sm:rounded-2xl sm:pb-4"
        >
          <div className="mx-auto mb-2 h-1 w-10 rounded-full bg-border sm:hidden" aria-hidden />
          <div className="flex items-center justify-between gap-2">
            <button
              type="button"
              aria-label="เดือนก่อนหน้า"
              onClick={() => step(-1)}
              className="inline-flex h-11 w-11 items-center justify-center rounded-full text-ink hover:bg-subtle cursor-pointer"
            >
              <ChevronLeft size={20} aria-hidden />
            </button>
            <p className="text-base font-semibold" aria-live="polite">
              {TH_MONTHS[view.month]} <span className="tabular-nums text-muted">{view.year + 543}</span>
            </p>
            <button
              type="button"
              aria-label="เดือนถัดไป"
              onClick={() => step(1)}
              className="inline-flex h-11 w-11 items-center justify-center rounded-full text-ink hover:bg-subtle cursor-pointer"
            >
              <ChevronRight size={20} aria-hidden />
            </button>
          </div>

          <div className="mt-2 grid grid-cols-7 text-center text-xs font-medium text-muted" aria-hidden>
            {TH_WEEKDAYS_SHORT.map((d, i) => (
              <span key={d} className={['py-1.5', i === 0 ? 'text-destructive/80' : ''].join(' ')}>
                {d}
              </span>
            ))}
          </div>

          <div className="grid grid-cols-7 gap-y-1" onKeyDown={onGridKey}>
            {grid.map((iso) => {
              const inMonth = sameMonth(iso, view);
              const selected = iso === value;
              const isToday = iso === today;
              const count = countsShown ? (counts?.[iso] ?? 0) : 0;
              const label = [formatDateLongTh(iso), isToday ? 'วันนี้' : '', count ? `มีออเดอร์ ${count} รายการ` : '']
                .filter(Boolean)
                .join(' · ');
              return (
                <button
                  key={iso}
                  ref={(el) => {
                    if (el) days.current.set(iso, el);
                    else days.current.delete(iso);
                  }}
                  type="button"
                  tabIndex={iso === tabStop ? 0 : -1}
                  aria-label={label}
                  aria-pressed={selected}
                  aria-current={isToday ? 'date' : undefined}
                  onClick={() => onSelect(iso)}
                  onFocus={() => setFocused(iso)}
                  className={[
                    'relative mx-auto flex h-11 w-11 flex-col items-center justify-center rounded-full text-sm tabular-nums transition-colors cursor-pointer',
                    'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-surface',
                    selected
                      ? 'bg-primary font-semibold text-primary-foreground shadow-md hover:bg-primary-hover'
                      : isToday
                        ? 'font-semibold text-primary ring-1 ring-inset ring-primary hover:bg-primary-soft'
                        : inMonth
                          ? 'text-ink hover:bg-subtle'
                          : 'text-muted/50 hover:bg-subtle',
                  ].join(' ')}
                >
                  {Number(iso.slice(8))}
                  {count ? (
                    <span
                      aria-hidden
                      className={[
                        'absolute bottom-1.5 h-1 w-1 rounded-full',
                        selected ? 'bg-primary-foreground' : 'bg-primary',
                      ].join(' ')}
                    />
                  ) : null}
                </button>
              );
            })}
          </div>

          <div className="mt-3 flex items-center justify-between gap-3 border-t border-border pt-3">
            <span className="flex items-center gap-1.5 text-xs text-muted">
              {countsShown ? (
                <>
                  <span className="h-1.5 w-1.5 rounded-full bg-primary" aria-hidden /> มีออเดอร์
                </>
              ) : null}
            </span>
            <div className="flex gap-2">
              <button
                type="button"
                onClick={onClose}
                className="min-h-11 rounded-full px-4 text-sm font-medium text-muted hover:bg-subtle cursor-pointer sm:hidden"
              >
                ปิด
              </button>
              <button
                type="button"
                onClick={() => onSelect(today)}
                className="min-h-11 rounded-full bg-primary-soft px-4 text-sm font-semibold text-primary hover:bg-primary/15 cursor-pointer"
              >
                วันนี้
              </button>
            </div>
          </div>
        </div>
      </div>
    </>
  );
}
