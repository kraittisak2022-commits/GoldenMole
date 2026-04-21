import React, { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { ChevronDown } from 'lucide-react';

export interface NumberPickerInputProps extends Omit<React.InputHTMLAttributes<HTMLInputElement>, 'value' | 'onChange' | 'type'> {
    value: string;
    onChange: (value: string) => void;
    /** ค่าต่ำสุดในรายการเลือก (รวม) */
    listMin: number;
    /** ค่าสูงสุดในรายการเลือก (รวม) */
    listMax: number;
    /** ระยะห่างในรายการ (เช่น 50 = 0,50,100… หรือ 0.5 = 0, 0.5, 1…) — ไม่ใส่ = ทุกจำนวนเต็ม 1 */
    listStep?: number;
    /** ถ้ายังไม่มีค่า ให้เลื่อนรายการมาโผล่แถวนี้ */
    scrollAnchor?: number;
    /** class ของห่อ input + ปุ่มลูกศร (ค่าเริ่มต้นเต็มความกว้างของคอลัมน์) */
    wrapperClassName?: string;
}

const parseNum = (raw: string) => {
    const x = parseFloat(String(raw).trim().replace(',', '.'));
    return Number.isFinite(x) ? x : NaN;
};

const buildListValues = (listMin: number, listMax: number, listStep?: number): number[] => {
    if (listStep == null || listStep <= 0) {
        const out: number[] = [];
        for (let i = listMin; i <= listMax; i += 1) out.push(i);
        return out;
    }
    const isFrac = listStep % 1 !== 0;
    const decPlaces = isFrac ? Math.max(1, (String(listStep).split('.')[1] || '').length) : 0;
    const out: number[] = [];
    const maxTicks = Math.floor((listMax - listMin) / listStep + 1e-9);
    for (let i = 0; i <= maxTicks; i += 1) {
        const raw = listMin + i * listStep;
        const v = isFrac ? Number(raw.toFixed(decPlaces)) : Math.round(raw);
        if (v - listMax > 1e-6) break;
        out.push(v);
    }
    return out;
};

const valueKey = (v: number, listStep?: number) => {
    if (listStep != null && listStep > 0 && listStep < 1) {
        const decPlaces = Math.max(1, (String(listStep).split('.')[1] || '').length);
        return String(Number(v.toFixed(decPlaces)));
    }
    return String(Math.round(v));
};

const NumberPickerInput: React.FC<NumberPickerInputProps> = ({
    value,
    onChange,
    className = '',
    listMin,
    listMax,
    listStep,
    scrollAnchor,
    wrapperClassName = 'flex min-w-0 w-full flex-1 items-stretch gap-1',
    disabled,
    ...rest
}) => {
    const [open, setOpen] = useState(false);
    const [panelPos, setPanelPos] = useState({ top: 0, left: 0, width: 0 });
    const wrapRef = useRef<HTMLDivElement>(null);
    const panelRef = useRef<HTMLDivElement>(null);
    const listRef = useRef<HTMLDivElement>(null);
    const inputRef = useRef<HTMLInputElement>(null);

    const values = React.useMemo(() => buildListValues(listMin, listMax, listStep), [listMin, listMax, listStep]);

    const updatePanelPos = useCallback(() => {
        const el = wrapRef.current;
        if (!el) return;
        const r = el.getBoundingClientRect();
        setPanelPos({ top: r.bottom + 4, left: r.left, width: Math.max(r.width, 120) });
    }, []);

    useLayoutEffect(() => {
        if (!open) return;
        updatePanelPos();
        const parsed = parseNum(value);
        let target: number;
        if (Number.isFinite(parsed)) {
            const hit = values.find(v => Math.abs(v - parsed) < 1e-4);
            target = hit !== undefined ? hit : scrollAnchor ?? values[Math.min(values.length - 1, Math.floor(values.length / 2))] ?? listMin;
        } else {
            const anchor = scrollAnchor ?? Math.floor((listMin + listMax) / 2);
            const hit = values.find(v => Math.abs(v - anchor) < 1e-4);
            target = hit !== undefined ? hit : values[Math.min(values.length - 1, Math.floor(values.length / 2))] ?? listMin;
        }
        const key = valueKey(target, listStep);
        requestAnimationFrame(() => {
            const row = listRef.current?.querySelector(`[data-value="${String(key).replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"]`);
            row?.scrollIntoView({ block: 'center' });
        });
    }, [open, value, scrollAnchor, listMin, listMax, listStep, values, updatePanelPos]);

    useEffect(() => {
        if (!open) return;
        updatePanelPos();
        const onScroll = () => updatePanelPos();
        const onResize = () => updatePanelPos();
        window.addEventListener('scroll', onScroll, true);
        window.addEventListener('resize', onResize);
        return () => {
            window.removeEventListener('scroll', onScroll, true);
            window.removeEventListener('resize', onResize);
        };
    }, [open, updatePanelPos]);

    useEffect(() => {
        if (!open) return;
        const onKey = (e: KeyboardEvent) => {
            if (e.key === 'Escape') setOpen(false);
        };
        document.addEventListener('keydown', onKey);
        return () => document.removeEventListener('keydown', onKey);
    }, [open]);

    useEffect(() => {
        if (!open) return;
        const onDown = (e: MouseEvent) => {
            const t = e.target as Node;
            if (wrapRef.current?.contains(t) || panelRef.current?.contains(t)) return;
            setOpen(false);
        };
        document.addEventListener('mousedown', onDown);
        return () => document.removeEventListener('mousedown', onDown);
    }, [open]);

    const toggle = () => {
        if (disabled) return;
        setOpen(o => !o);
    };

    const pick = (n: number) => {
        onChange(valueKey(n, listStep));
        setOpen(false);
        inputRef.current?.focus();
    };

    const parsedValue = parseNum(value);
    const isOptionSelected = (n: number) => Number.isFinite(parsedValue) && Math.abs(parsedValue - n) < 1e-4;

    return (
        <div ref={wrapRef} className={`relative ${wrapperClassName}`}>
            <input
                ref={inputRef}
                type="number"
                value={value}
                disabled={disabled}
                onChange={e => onChange(e.target.value)}
                className={`min-w-0 flex-1 touch-manipulation [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none ${className}`}
                {...rest}
            />
            <button
                type="button"
                disabled={disabled}
                onClick={e => {
                    e.preventDefault();
                    toggle();
                }}
                className="flex shrink-0 items-center justify-center rounded-xl border border-slate-200 bg-white px-2 text-slate-500 shadow-sm transition hover:bg-slate-50 hover:text-slate-700 disabled:opacity-50 dark:border-white/15 dark:bg-white/10 dark:text-slate-400 dark:hover:bg-white/15 touch-manipulation"
                title="เลือกจากรายการ"
                aria-expanded={open}
                aria-haspopup="listbox"
            >
                <ChevronDown size={18} className={open ? 'rotate-180 transition-transform' : 'transition-transform'} />
            </button>
            {open &&
                typeof document !== 'undefined' &&
                createPortal(
                    <div
                        ref={panelRef}
                        data-number-picker-panel
                        role="listbox"
                        className="fixed z-[9998] max-h-52 overflow-y-auto rounded-xl border border-slate-200 bg-white py-1 shadow-xl dark:border-white/15 dark:bg-slate-900"
                        style={{
                            top: panelPos.top,
                            left: panelPos.left,
                            width: panelPos.width,
                            maxHeight: '13rem',
                        }}
                    >
                        <div ref={listRef} className="flex flex-col">
                            {values.map(n => {
                                const k = valueKey(n, listStep);
                                return (
                                    <button
                                        key={k}
                                        type="button"
                                        role="option"
                                        data-value={k}
                                        onClick={() => pick(n)}
                                        className={`touch-manipulation px-3 py-2.5 text-left text-base font-semibold transition hover:bg-emerald-50 dark:hover:bg-emerald-500/15 ${
                                            isOptionSelected(n)
                                                ? 'bg-emerald-100 text-emerald-900 dark:bg-emerald-500/25 dark:text-emerald-100'
                                                : 'text-slate-800 dark:text-slate-100'
                                        }`}
                                    >
                                        {k}
                                    </button>
                                );
                            })}
                        </div>
                    </div>,
                    document.body
                )}
        </div>
    );
};

export default NumberPickerInput;
