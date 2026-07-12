import { useCallback, useEffect, useMemo, useState } from 'react';
import { X, Truck, Droplets, Trash2, Save, AlertTriangle } from 'lucide-react';
import type { Employee, Transaction } from '../../types';
import {
    buildCountRecordSandUnit,
    buildCountRecordTripUnits,
    countRecordLapPeriods,
    driverDisplayName,
    getLapTimes,
} from './countRecordUtils';

interface CountRecordRoundManagerProps {
    open: boolean;
    onClose: () => void;
    dayKey: string;
    transactions: Transaction[];
    employees?: Employee[];
    onSaveTransaction: (t: Transaction) => void | Promise<boolean>;
    onDeleteTransaction: (id: string) => void | Promise<void>;
}

type RowKind = 'trip' | 'sand';

interface ManagedRow {
    id: string;
    kind: RowKind;
    title: string;
    subtitle?: string;
    tx: Transaction;
}

interface RowDraft {
    laps: string[];
    countOnly: number;
}

function lapTimePart(stamp: string): string {
    const sp = stamp.indexOf(' ');
    if (sp < 0) return stamp.trim();
    return stamp.slice(sp + 1).trim();
}

function lapDatePart(stamp: string): string {
    const sp = stamp.indexOf(' ');
    if (sp < 0) return '';
    return stamp.slice(0, sp).trim();
}

function lapSortKey(stamp: string): number {
    const time = lapTimePart(stamp);
    const [h = '0', m = '0', s = '0'] = time.split(':');
    return Number(h) * 3600 + Number(m) * 60 + Number(s);
}

function sortLaps(laps: string[]): string[] {
    return [...laps].sort((a, b) => lapSortKey(a) - lapSortKey(b));
}

function stampWithTime(stamp: string, hhmmss: string): string {
    const date = lapDatePart(stamp);
    const time = hhmmss.trim();
    if (!date) return time;
    return `${date} ${time}`;
}

function toTimeInputValue(stamp: string): string {
    const time = lapTimePart(stamp);
    const parts = time.split(':');
    if (parts.length >= 3) {
        const [h, m, s] = parts;
        return `${h!.padStart(2, '0')}:${m!.padStart(2, '0')}:${s!.padStart(2, '0')}`;
    }
    if (parts.length === 2) {
        return `${parts[0]!.padStart(2, '0')}:${parts[1]!.padStart(2, '0')}:00`;
    }
    return '00:00:00';
}

function tripCountFromTx(t: Transaction): number {
    const laps = getLapTimes(t);
    const fromField = Math.round(
        Number((t as { perCarTrips?: number; tripCount?: number }).perCarTrips ?? (t as { tripCount?: number }).tripCount ?? 0),
    );
    return laps.length > 0 ? laps.length : fromField;
}

function sandCountFromTx(t: Transaction): number {
    const laps = getLapTimes(t);
    const fromDrums = Math.round(Number((t as { drumsObtained?: number }).drumsObtained ?? 0));
    return laps.length > 0 ? laps.length : fromDrums;
}

function buildDraftFromTx(tx: Transaction, kind: RowKind): RowDraft {
    const laps = getLapTimes(tx);
    if (laps.length > 0) return { laps: [...laps], countOnly: laps.length };
    const countOnly = kind === 'trip' ? tripCountFromTx(tx) : sandCountFromTx(tx);
    return { laps: [], countOnly };
}

function buildTripTransaction(tx: Transaction, laps: string[], count: number): Transaction {
    const periods = countRecordLapPeriods({ ...tx, workAssignments: { lapTimes: laps } });
    const r = count;
    return {
        ...tx,
        description: `${String(tx.vehicleId ?? '').trim()}: ${r} เที่ยว`,
        tripCount: r,
        perCarTrips: r,
        tripMorning: periods.morning + periods.unknown,
        tripAfternoon: periods.afternoon,
        workAssignments: laps.length > 0 ? { lapTimes: laps } : undefined,
    };
}

function buildSandTransaction(tx: Transaction, laps: string[], count: number): Transaction {
    return {
        ...tx,
        description: `ร่อนทราย: ${count} รอบ`,
        drumsObtained: count,
        workAssignments: laps.length > 0 ? { lapTimes: laps } : undefined,
    };
}

const CountRecordRoundManager = ({
    open,
    onClose,
    dayKey,
    transactions,
    employees = [],
    onSaveTransaction,
    onDeleteTransaction,
}: CountRecordRoundManagerProps) => {
    const [drafts, setDrafts] = useState<Record<string, RowDraft>>({});
    const [busyId, setBusyId] = useState<string | null>(null);
    const [message, setMessage] = useState<string | null>(null);

    const rows = useMemo((): ManagedRow[] => {
        const tripUnits = buildCountRecordTripUnits(dayKey, transactions, employees);
        const tripRows: ManagedRow[] = tripUnits.map((u) => {
            const tx = transactions.find((t) => t.id === u.id);
            if (!tx) return null;
            return {
                id: u.id,
                kind: 'trip' as const,
                title: u.vehicleId,
                subtitle: u.driverLabel,
                tx,
            };
        }).filter((r): r is ManagedRow => r != null);

        const sandUnit = buildCountRecordSandUnit(dayKey, transactions);
        const sandRows: ManagedRow[] = [];
        if (sandUnit) {
            const tx = transactions.find((t) => t.id === sandUnit.id);
            if (tx) {
                sandRows.push({
                    id: sandUnit.id,
                    kind: 'sand',
                    title: 'การร่อนทราย',
                    subtitle: `${sandUnit.rounds} รอบ`,
                    tx,
                });
            }
        }

        return [...tripRows, ...sandRows];
    }, [dayKey, transactions, employees]);

    useEffect(() => {
        if (!open) return;
        const next: Record<string, RowDraft> = {};
        for (const row of rows) {
            next[row.id] = buildDraftFromTx(row.tx, row.kind);
        }
        setDrafts(next);
        setMessage(null);
        setBusyId(null);
    }, [open, rows]);

    useEffect(() => {
        if (!open) return;
        const onKey = (e: KeyboardEvent) => {
            if (e.key === 'Escape') onClose();
        };
        window.addEventListener('keydown', onKey);
        return () => window.removeEventListener('keydown', onKey);
    }, [open, onClose]);

    const updateDraft = useCallback((id: string, updater: (d: RowDraft) => RowDraft) => {
        setDrafts((prev) => {
            const cur = prev[id];
            if (!cur) return prev;
            return { ...prev, [id]: updater(cur) };
        });
    }, []);

    const handleDeleteLap = (rowId: string, lapIndex: number) => {
        updateDraft(rowId, (d) => {
            const laps = d.laps.filter((_, i) => i !== lapIndex);
            return { laps, countOnly: laps.length > 0 ? laps.length : Math.max(0, d.countOnly - 1) };
        });
    };

    const handleLapTimeChange = (rowId: string, lapIndex: number, hhmmss: string) => {
        updateDraft(rowId, (d) => {
            const laps = [...d.laps];
            const stamp = laps[lapIndex];
            if (!stamp) return d;
            laps[lapIndex] = stampWithTime(stamp, hhmmss.length === 5 ? `${hhmmss}:00` : hhmmss);
            const sorted = sortLaps(laps);
            return { laps: sorted, countOnly: sorted.length };
        });
    };

    const handleCountOnlyChange = (rowId: string, value: number) => {
        updateDraft(rowId, (d) => ({ ...d, countOnly: Math.max(0, Math.round(value)) }));
    };

    const handleSaveRow = async (row: ManagedRow) => {
        const draft = drafts[row.id];
        if (!draft) return;

        const laps = draft.laps;
        const count = laps.length > 0 ? laps.length : draft.countOnly;

        if (count <= 0 && laps.length === 0) {
            const ok = window.confirm(
                `ไม่มีรอบเหลือสำหรับ "${row.title}" — ลบรายการนี้จากฐานข้อมูลเลยหรือไม่?`,
            );
            if (!ok) return;
            setBusyId(row.id);
            try {
                await onDeleteTransaction(row.id);
                setMessage(`ลบรายการ ${row.title} แล้ว`);
            } finally {
                setBusyId(null);
            }
            return;
        }

        const updated =
            row.kind === 'trip'
                ? buildTripTransaction(row.tx, laps, count)
                : buildSandTransaction(row.tx, laps, count);

        setBusyId(row.id);
        try {
            await onSaveTransaction(updated);
            setMessage(`บันทึก ${row.title} แล้ว (${count} ${row.kind === 'trip' ? 'เที่ยว' : 'รอบ'})`);
        } finally {
            setBusyId(null);
        }
    };

    const handleDeleteRow = async (row: ManagedRow) => {
        const ok = window.confirm(
            `ลบรายการ "${row.title}" ทั้งหมดจากฐานข้อมูล?\n\nการกระทำนี้ไม่สามารถย้อนกลับได้`,
        );
        if (!ok) return;
        setBusyId(row.id);
        try {
            await onDeleteTransaction(row.id);
            setMessage(`ลบรายการ ${row.title} จากฐานข้อมูลแล้ว`);
        } finally {
            setBusyId(null);
        }
    };

    if (!open) return null;

    return (
        <div className="fixed inset-0 z-[100] flex items-end justify-center p-0 sm:items-center sm:p-4">
            <button
                type="button"
                className="absolute inset-0 bg-slate-950/60 backdrop-blur-sm"
                aria-label="ปิด"
                onClick={onClose}
            />
            <div
                role="dialog"
                aria-modal="true"
                aria-labelledby="count-round-manager-title"
                className="relative flex max-h-[92vh] w-full max-w-2xl flex-col overflow-hidden rounded-t-[24px] border border-slate-200/80 bg-white shadow-2xl dark:border-slate-700/60 dark:bg-slate-900 sm:rounded-[24px]"
            >
                <header className="flex items-start justify-between gap-3 border-b border-slate-200/80 bg-gradient-to-r from-slate-900 via-indigo-950 to-slate-900 px-5 py-4 dark:border-slate-700/60">
                    <div className="min-w-0">
                        <p className="text-[10px] font-bold uppercase tracking-[0.16em] text-indigo-300">SuperAdmin</p>
                        <h2 id="count-round-manager-title" className="text-lg font-bold text-white">
                            จัดการรอบ
                        </h2>
                        <p className="mt-0.5 text-xs text-slate-300">วันที่ {dayKey} · แก้ไข/ลบในฐานข้อมูลจริง</p>
                    </div>
                    <button
                        type="button"
                        onClick={onClose}
                        className="rounded-xl bg-white/10 p-2 text-white ring-1 ring-white/20 transition hover:bg-white/15"
                        aria-label="ปิด"
                    >
                        <X size={18} />
                    </button>
                </header>

                {message && (
                    <div className="border-b border-emerald-200/80 bg-emerald-50 px-4 py-2 text-xs font-medium text-emerald-800 dark:border-emerald-500/20 dark:bg-emerald-500/10 dark:text-emerald-200">
                        {message}
                    </div>
                )}

                <div className="flex-1 overflow-y-auto p-4 sm:p-5">
                    {rows.length === 0 ? (
                        <div className="flex flex-col items-center justify-center rounded-2xl border border-dashed border-slate-200 bg-slate-50/50 px-6 py-12 text-center dark:border-slate-700 dark:bg-slate-800/40">
                            <AlertTriangle size={28} className="text-slate-400 dark:text-slate-500" />
                            <p className="mt-3 text-sm font-semibold text-slate-600 dark:text-slate-300">
                                ยังไม่มีรอบที่บันทึกในวันนี้
                            </p>
                        </div>
                    ) : (
                        <div className="space-y-4">
                            {rows.map((row) => {
                                const draft = drafts[row.id] ?? buildDraftFromTx(row.tx, row.kind);
                                const hasLaps = draft.laps.length > 0;
                                const Icon = row.kind === 'trip' ? Truck : Droplets;
                                const accent =
                                    row.kind === 'trip'
                                        ? 'border-blue-200/80 dark:border-blue-500/25'
                                        : 'border-pink-200/80 dark:border-pink-500/25';
                                const iconBg =
                                    row.kind === 'trip'
                                        ? 'bg-blue-50 text-blue-600 dark:bg-blue-500/15 dark:text-blue-300'
                                        : 'bg-pink-50 text-pink-600 dark:bg-pink-500/15 dark:text-pink-300';
                                const isBusy = busyId === row.id;

                                return (
                                    <section
                                        key={row.id}
                                        className={`rounded-2xl border bg-white p-4 shadow-sm dark:bg-slate-900 ${accent}`}
                                    >
                                        <div className="flex flex-wrap items-start justify-between gap-3">
                                            <div className="flex min-w-0 items-start gap-3">
                                                <span className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-xl ${iconBg}`}>
                                                    <Icon size={18} />
                                                </span>
                                                <div className="min-w-0">
                                                    <h3 className="truncate text-sm font-bold text-slate-900 dark:text-slate-100">
                                                        {row.title}
                                                    </h3>
                                                    {row.subtitle && (
                                                        <p className="text-xs text-slate-500 dark:text-slate-400">{row.subtitle}</p>
                                                    )}
                                                    {row.kind === 'trip' && row.tx.driverId && (
                                                        <p className="text-[11px] text-slate-400 dark:text-slate-500">
                                                            คนขับ: {driverDisplayName(String(row.tx.driverId), employees)}
                                                        </p>
                                                    )}
                                                </div>
                                            </div>
                                            <div className="flex flex-wrap gap-2">
                                                <button
                                                    type="button"
                                                    disabled={isBusy}
                                                    onClick={() => void handleSaveRow(row)}
                                                    className="inline-flex items-center gap-1.5 rounded-xl bg-indigo-600 px-3 py-2 text-xs font-bold text-white transition hover:bg-indigo-700 disabled:opacity-50 dark:bg-indigo-500 dark:hover:bg-indigo-400"
                                                >
                                                    <Save size={14} />
                                                    บันทึก
                                                </button>
                                                <button
                                                    type="button"
                                                    disabled={isBusy}
                                                    onClick={() => void handleDeleteRow(row)}
                                                    className="inline-flex items-center gap-1.5 rounded-xl border border-rose-200 bg-rose-50 px-3 py-2 text-xs font-bold text-rose-700 transition hover:bg-rose-100 disabled:opacity-50 dark:border-rose-500/30 dark:bg-rose-500/10 dark:text-rose-200 dark:hover:bg-rose-500/20"
                                                >
                                                    <Trash2 size={14} />
                                                    ลบทั้งรายการ
                                                </button>
                                            </div>
                                        </div>

                                        {hasLaps ? (
                                            <ul className="mt-4 space-y-2">
                                                {draft.laps.map((stamp, lapIndex) => (
                                                    <li
                                                        key={`${row.id}-${lapIndex}-${stamp}`}
                                                        className="flex flex-wrap items-center gap-2 rounded-xl bg-slate-50 px-3 py-2 dark:bg-slate-800/60"
                                                    >
                                                        <span className="w-14 shrink-0 text-[11px] font-bold text-slate-500 dark:text-slate-400">
                                                            รอบ {lapIndex + 1}
                                                        </span>
                                                        <input
                                                            type="time"
                                                            step={1}
                                                            value={toTimeInputValue(stamp)}
                                                            onChange={(e) =>
                                                                handleLapTimeChange(row.id, lapIndex, e.target.value)
                                                            }
                                                            className="min-w-0 flex-1 rounded-lg border border-slate-200 bg-white px-2 py-1.5 font-mono text-xs text-slate-800 dark:border-slate-600 dark:bg-slate-900 dark:text-slate-200"
                                                        />
                                                        <span className="hidden font-mono text-[10px] text-slate-400 sm:inline dark:text-slate-500">
                                                            {lapDatePart(stamp)}
                                                        </span>
                                                        <button
                                                            type="button"
                                                            onClick={() => handleDeleteLap(row.id, lapIndex)}
                                                            className="inline-flex items-center gap-1 rounded-lg border border-rose-200 px-2 py-1.5 text-[11px] font-semibold text-rose-600 transition hover:bg-rose-50 dark:border-rose-500/30 dark:text-rose-300 dark:hover:bg-rose-500/10"
                                                        >
                                                            <Trash2 size={12} />
                                                            ลบรอบ
                                                        </button>
                                                    </li>
                                                ))}
                                            </ul>
                                        ) : (
                                            <div className="mt-4 flex flex-wrap items-center gap-3 rounded-xl bg-slate-50 px-3 py-3 dark:bg-slate-800/60">
                                                <label className="text-xs font-semibold text-slate-600 dark:text-slate-300">
                                                    จำนวน{row.kind === 'trip' ? 'เที่ยว' : 'รอบ'} (ไม่มี timestamp)
                                                </label>
                                                <input
                                                    type="number"
                                                    min={0}
                                                    value={draft.countOnly}
                                                    onChange={(e) =>
                                                        handleCountOnlyChange(row.id, Number(e.target.value) || 0)
                                                    }
                                                    className="w-24 rounded-lg border border-slate-200 bg-white px-2 py-1.5 text-sm font-bold tabular-nums text-slate-800 dark:border-slate-600 dark:bg-slate-900 dark:text-slate-200"
                                                />
                                            </div>
                                        )}

                                        {hasLaps && (
                                            <p className="mt-2 text-[11px] text-slate-400 dark:text-slate-500">
                                                รวม {draft.laps.length} {row.kind === 'trip' ? 'เที่ยว' : 'รอบ'} · เรียงตามเวลาอัตโนมัติเมื่อแก้เวลา
                                            </p>
                                        )}
                                    </section>
                                );
                            })}
                        </div>
                    )}
                </div>

                <footer className="border-t border-slate-200/80 px-4 py-3 text-center text-[11px] text-slate-400 dark:border-slate-700/60 dark:text-slate-500">
                    การลบ/แก้ไขมีผลในตาราง transactions ทันที · มือถือจะเห็นค่าที่อัปเดตผ่าน Realtime
                </footer>
            </div>
        </div>
    );
};

export default CountRecordRoundManager;
