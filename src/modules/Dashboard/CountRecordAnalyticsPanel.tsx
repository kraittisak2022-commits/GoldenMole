import { useMemo, useState, type ReactNode } from 'react';
import { BarChart3, ChevronDown } from 'lucide-react';
import { useShareLocale } from '../Share/shareI18n';
import type { Employee, Transaction } from '../../types';
import {
    buildCountRecordSandUnit,
    buildCountRecordTripUnits,
} from './countRecordUtils';
import {
    buildDayComparison,
    buildIntervalSparkline,
    computeCumulativeSeries,
    computeHourlyActiveWork,
    computeHourlyBuckets,
    computeHourlyEfficiency,
    computeHourlyHeatmap,
    computeHourlySandSpeed,
    computeIntervalStats,
    computeLapIntervals,
    computeMinuteSandSpeed,
    computePeakHour,
    computeSandPeriodSplit,
    computeSandWorkDurationSummary,
    computeTripFleetWorkDurationSummary,
    computeTripPeriodSplit,
    computeVehicleComparison,
    formatActiveHours,
    mergeTripLapTimeline,
    timelineToLapStamps,
    type PeriodSplit,
    type VehicleComparisonRow,
} from './countRecordAnalytics';
import CountRecordStatTiles from './CountRecordStatTiles';

interface CountRecordAnalyticsPanelProps {
    mode: 'sand' | 'trip';
    dayKey: string;
    transactions: Transaction[];
    employees?: Employee[];
    accentColor?: string;
}

function PeriodSplitBar({ split, roundLabel }: { split: PeriodSplit; roundLabel: string }) {
    const { t } = useShareLocale();
    const total = split.morning + split.afternoon;
    if (total <= 0) {
        return (
            <p className="flex h-20 items-center justify-center text-xs font-medium text-slate-400 dark:text-slate-500">
                {t('noMorningAfternoon')}
            </p>
        );
    }
    return (
        <div className="space-y-3">
            <div className="flex h-10 overflow-hidden rounded-xl shadow-inner">
                <div
                    className="flex items-center justify-center bg-gradient-to-r from-amber-400 to-amber-500 text-[10px] font-bold text-amber-950 transition-all"
                    style={{ width: `${split.morningPct}%`, minWidth: split.morning > 0 ? '2.5rem' : 0 }}
                >
                    {split.morning > 0 ? `${t('morning')} ${split.morning}` : ''}
                </div>
                <div
                    className="flex items-center justify-center bg-gradient-to-r from-indigo-500 to-violet-600 text-[10px] font-bold text-white transition-all"
                    style={{ width: `${split.afternoonPct}%`, minWidth: split.afternoon > 0 ? '2.5rem' : 0 }}
                >
                    {split.afternoon > 0 ? `${t('afternoon')} ${split.afternoon}` : ''}
                </div>
            </div>
            <div className="grid grid-cols-2 gap-2">
                <div className="rounded-xl bg-amber-50 px-3 py-2 dark:bg-amber-500/10">
                    <p className="text-[9px] font-bold uppercase tracking-wide text-amber-700 dark:text-amber-300">{t('morning')}</p>
                    <p className="text-lg font-black tabular-nums text-amber-900 dark:text-amber-100">
                        {split.morning} <span className="text-xs font-semibold">{roundLabel}</span>
                    </p>
                    <p className="text-[10px] font-medium text-amber-700/80 dark:text-amber-300/80">{Math.round(split.morningPct)}%</p>
                </div>
                <div className="rounded-xl bg-indigo-50 px-3 py-2 dark:bg-indigo-500/10">
                    <p className="text-[9px] font-bold uppercase tracking-wide text-indigo-700 dark:text-indigo-300">{t('afternoon')}</p>
                    <p className="text-lg font-black tabular-nums text-indigo-900 dark:text-indigo-100">
                        {split.afternoon} <span className="text-xs font-semibold">{roundLabel}</span>
                    </p>
                    <p className="text-[10px] font-medium text-indigo-700/80 dark:text-indigo-300/80">{Math.round(split.afternoonPct)}%</p>
                </div>
            </div>
        </div>
    );
}

function VehicleComparisonChart({ rows, color }: { rows: VehicleComparisonRow[]; color: string }) {
    const { t } = useShareLocale();
    if (rows.length === 0) {
        return (
            <p className="flex h-24 items-center justify-center text-xs font-medium text-slate-400 dark:text-slate-500">
                {t('noVehicleData')}
            </p>
        );
    }
    const max = Math.max(...rows.map((r) => r.rounds), 1);
    return (
        <div className="space-y-2">
            {rows.map((row) => (
                <div key={row.vehicleId} className="space-y-1">
                    <div className="flex items-center justify-between gap-2 text-[10px]">
                        <span className="truncate font-bold text-slate-700 dark:text-slate-200">{row.vehicleId}</span>
                        <span className="shrink-0 font-black tabular-nums text-slate-900 dark:text-slate-100">{row.rounds} {t('tripUnit')}</span>
                    </div>
                    <div className="flex h-3 overflow-hidden rounded-full bg-slate-100 dark:bg-slate-800">
                        <div
                            className="h-full bg-amber-400"
                            style={{ width: `${(row.morning / max) * 100}%` }}
                            title={`${t('morning')} ${row.morning}`}
                        />
                        <div
                            className="h-full"
                            style={{ width: `${(row.afternoon / max) * 100}%`, backgroundColor: color }}
                            title={`${t('afternoon')} ${row.afternoon}`}
                        />
                    </div>
                    <p className="text-[9px] text-slate-400 dark:text-slate-500">
                        {t('morning')} {row.morning} · {t('afternoon')} {row.afternoon}
                    </p>
                </div>
            ))}
        </div>
    );
}

function PeakHourCard({
    peak,
    roundLabel,
    color,
}: {
    peak: ReturnType<typeof computePeakHour>;
    roundLabel: string;
    color: string;
}) {
    const { t } = useShareLocale();
    if (!peak) {
        return (
            <p className="flex h-24 items-center justify-center text-xs font-medium text-slate-400 dark:text-slate-500">
                {t('noPeakHour')}
            </p>
        );
    }
    return (
        <div className="flex flex-col items-center justify-center py-2 text-center">
            <p className="text-[10px] font-bold uppercase tracking-[0.12em] text-slate-400 dark:text-slate-500">{t('peakHourLabel')}</p>
            <p className="mt-2 text-3xl font-black tabular-nums" style={{ color }}>
                {peak.label}
            </p>
            <p className="mt-1 text-sm font-bold text-slate-700 dark:text-slate-200">
                {peak.count} {roundLabel}
            </p>
            <p className="mt-2 text-[10px] text-slate-400 dark:text-slate-500">{t('peakHourHint')}</p>
        </div>
    );
}

function EfficiencyBarChart({
    buckets,
    color,
    unitLabel,
}: {
    buckets: ReturnType<typeof computeHourlyEfficiency>;
    color: string;
    unitLabel: string;
}) {
    const { t } = useShareLocale();
    if (buckets.length === 0) {
        return (
            <p className="flex h-24 items-center justify-center text-xs font-medium text-slate-400 dark:text-slate-500">
                {t('noSpeedData')}
            </p>
        );
    }
    const max = Math.max(...buckets.map((b) => b.roundsPerHour), 1);
    return (
        <div className="flex h-24 items-end justify-between gap-0.5 px-0.5">
            {buckets.map((b) => (
                <div key={b.hour} className="flex min-w-0 flex-1 flex-col items-center justify-end gap-0.5">
                    <span className="text-[8px] font-bold tabular-nums text-slate-500 dark:text-slate-400">{b.roundsPerHour}</span>
                    <div
                        className="chart-bar-grow w-full rounded-t-sm"
                        style={{ height: `${(b.roundsPerHour / max) * 72}px`, backgroundColor: color, minHeight: 4 }}
                    />
                    <span className="w-full truncate text-center text-[7px] text-slate-400 dark:text-slate-500">{b.label}</span>
                    <span className="text-[7px] text-slate-300 dark:text-slate-600">{unitLabel}</span>
                </div>
            ))}
        </div>
    );
}

function CumulativeLineChart({
    points,
    color,
}: {
    points: { label: string; value: number }[];
    color: string;
}) {
    const { t } = useShareLocale();
    if (points.length < 2) {
        return (
            <p className="flex h-28 items-center justify-center text-xs font-medium text-slate-400 dark:text-slate-500">
                {t('needTwoRounds')}
            </p>
        );
    }
    const width = 100;
    const height = 80;
    const max = Math.max(...points.map((p) => p.value), 1);
    const coords = points.map((p, i) => ({
        x: (i / (points.length - 1)) * width,
        y: height - (p.value / max) * height,
    }));
    const linePoints = coords.map((c) => `${c.x},${c.y}`).join(' ');
    const gradId = `cum-${color.replace(/[^a-zA-Z0-9]/g, '')}`;
    return (
        <div className="relative h-28">
            <svg viewBox={`0 0 ${width} ${height}`} className="h-full w-full" preserveAspectRatio="none">
                <defs>
                    <linearGradient id={gradId} x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stopColor={color} stopOpacity="0.25" />
                        <stop offset="100%" stopColor={color} stopOpacity="0" />
                    </linearGradient>
                </defs>
                <path
                    d={`M0,${height} L${coords[0]!.x},${coords[0]!.y} ${coords.map((c) => `L${c.x},${c.y}`).join(' ')} L${width},${height} Z`}
                    fill={`url(#${gradId})`}
                />
                <polyline points={linePoints} fill="none" stroke={color} strokeWidth="1.5" strokeLinecap="round" />
            </svg>
            <div className="mt-1 flex justify-between text-[9px] text-slate-400 dark:text-slate-500">
                <span>{points[0]?.label}</span>
                <span>{points[points.length - 1]?.label}</span>
            </div>
        </div>
    );
}

function HourlyHeatmap({
    cells,
    color,
}: {
    cells: { hour: number; count: number; label: string; intensity: number; isLunch?: boolean }[];
    color: string;
}) {
    const { t } = useShareLocale();
    const active = cells.filter((c) => c.count > 0);
    if (active.length === 0) {
        return (
            <p className="flex h-12 items-center justify-center text-xs font-medium text-slate-400 dark:text-slate-500">
                {t('noHourlyData')}
            </p>
        );
    }
    return (
        <div className="space-y-2">
            <div className="grid grid-cols-12 gap-0.5 sm:grid-cols-24">
                {cells.map((c) => (
                    <div
                        key={c.hour}
                        title={
                            c.isLunch
                                ? `${c.label}: ${t('lunchBreak')}`
                                : `${c.label}: ${c.count} ${t('roundUnit')}`
                        }
                        className={`group relative aspect-square min-h-[10px] rounded-sm transition-transform hover:scale-110 ${
                            c.isLunch
                                ? 'bg-slate-200 dark:bg-slate-700'
                                : c.count === 0
                                  ? 'bg-slate-200 dark:bg-slate-700'
                                  : ''
                        }`}
                        style={
                            c.isLunch
                                ? {
                                      backgroundImage:
                                          'repeating-linear-gradient(-45deg, rgba(148,163,184,0.35) 0, rgba(148,163,184,0.35) 2px, transparent 2px, transparent 5px)',
                                  }
                                : {
                                      backgroundColor: c.count > 0 ? color : undefined,
                                      opacity: c.count > 0 ? 0.25 + c.intensity * 0.75 : 0.35,
                                  }
                        }
                    />
                ))}
            </div>
            <div className="flex justify-between text-[8px] text-slate-400 dark:text-slate-500">
                <span>00:00</span>
                <span>06:00</span>
                <span>12:00</span>
                <span>18:00</span>
                <span>23:00</span>
            </div>
        </div>
    );
}

function HourlyBarChart({
    buckets,
    color,
    valueKey = 'count',
    unitLabel,
}: {
    buckets: { label: string; count: number; speed?: number }[];
    color: string;
    valueKey?: 'count' | 'speed';
    unitLabel?: string;
}) {
    const { t } = useShareLocale();
    if (buckets.length === 0) {
        return (
            <p className="flex h-24 items-center justify-center text-xs font-medium text-slate-400 dark:text-slate-500">
                {t('noHourlyData')}
            </p>
        );
    }
    const values = buckets.map((b) => (valueKey === 'speed' ? (b.speed ?? b.count) : b.count));
    const max = Math.max(...values, 1);
    return (
        <div className="flex h-24 items-end justify-between gap-0.5 px-0.5">
            {buckets.map((b, i) => {
                const val = values[i]!;
                return (
                    <div key={i} className="flex min-w-0 flex-1 flex-col items-center justify-end gap-0.5">
                        <span className="text-[8px] font-bold tabular-nums text-slate-500 dark:text-slate-400">{val}</span>
                        <div
                            className="chart-bar-grow w-full rounded-t-sm"
                            style={{ height: `${(val / max) * 72}px`, backgroundColor: color, minHeight: 4 }}
                        />
                        <span className="w-full truncate text-center text-[7px] text-slate-400 dark:text-slate-500">{b.label}</span>
                        {unitLabel && <span className="text-[7px] text-slate-300 dark:text-slate-600">{unitLabel}</span>}
                    </div>
                );
            })}
        </div>
    );
}

function WorkHoursBarChart({
    buckets,
    color,
}: {
    buckets: { label: string; activeHours: number }[];
    color: string;
}) {
    const { t, locale } = useShareLocale();
    if (buckets.length === 0) {
        return (
            <p className="flex h-24 items-center justify-center text-xs font-medium text-slate-400 dark:text-slate-500">
                {t('noWorkTimeData')}
            </p>
        );
    }
    const max = Math.max(...buckets.map((b) => b.activeHours), 0.1);
    return (
        <div className="flex h-28 items-end justify-between gap-1 px-0.5">
            {buckets.map((b, i) => (
                <div key={i} className="flex min-w-0 flex-1 flex-col items-center justify-end gap-0.5">
                    <span className="text-[8px] font-bold tabular-nums text-slate-500 dark:text-slate-400">
                        {formatActiveHours(b.activeHours, locale)}
                    </span>
                    <div
                        className="chart-bar-grow w-full rounded-t-md"
                        style={{ height: `${(b.activeHours / max) * 80}px`, backgroundColor: color, minHeight: 4 }}
                    />
                    <span className="w-full truncate text-center text-[7px] text-slate-400 dark:text-slate-500">{b.label}</span>
                </div>
            ))}
        </div>
    );
}

function MinuteTimelineChart({
    buckets,
    color,
}: {
    buckets: { label: string; speed: number }[];
    color: string;
}) {
    const { t } = useShareLocale();
    if (buckets.length === 0) {
        return (
            <p className="flex h-24 items-center justify-center text-xs font-medium text-slate-400 dark:text-slate-500">
                {t('noSpeedData')}
            </p>
        );
    }
    const max = Math.max(...buckets.map((b) => b.speed), 1);
    const w = Math.max(buckets.length * 8, 200);
    const h = 56;
    const coords = buckets.map((b, i) => ({
        x: (i / Math.max(buckets.length - 1, 1)) * w,
        y: h - (b.speed / max) * h,
    }));
    const areaPath =
        coords.length >= 2
            ? `M0,${h} ${coords.map((c) => `L${c.x},${c.y}`).join(' ')} L${w},${h} Z`
            : '';
    const linePath = coords.map((c, i) => `${i === 0 ? 'M' : 'L'}${c.x},${c.y}`).join(' ');
    const gradId = `min-${color.replace(/[^a-zA-Z0-9]/g, '')}`;

    return (
        <div className="space-y-2">
            <div className="overflow-x-auto pb-1">
                <div style={{ minWidth: w }} className="relative h-16">
                    <svg viewBox={`0 0 ${w} ${h}`} className="h-full w-full" preserveAspectRatio="none">
                        <defs>
                            <linearGradient id={gradId} x1="0" y1="0" x2="0" y2="1">
                                <stop offset="0%" stopColor={color} stopOpacity="0.35" />
                                <stop offset="100%" stopColor={color} stopOpacity="0" />
                            </linearGradient>
                        </defs>
                        {areaPath && <path d={areaPath} fill={`url(#${gradId})`} />}
                        {linePath && (
                            <path d={linePath} fill="none" stroke={color} strokeWidth="1.5" strokeLinecap="round" />
                        )}
                    </svg>
                </div>
            </div>
            <div className="flex h-14 items-end gap-px overflow-x-auto px-0.5">
                {buckets.map((b, i) => (
                    <div key={i} className="flex w-5 shrink-0 flex-col items-center justify-end gap-0.5">
                        <div
                            className="chart-bar-grow w-full rounded-t-sm"
                            style={{ height: `${(b.speed / max) * 48}px`, backgroundColor: color, minHeight: 2 }}
                        />
                        {i % 5 === 0 && (
                            <span className="w-full truncate text-center text-[6px] text-slate-400 dark:text-slate-500">{b.label}</span>
                        )}
                    </div>
                ))}
            </div>
            <p className="text-center text-[9px] text-slate-400 dark:text-slate-500">{t('minuteTimelineHint')}</p>
        </div>
    );
}

function ChartBlock({
    title,
    children,
    className = '',
}: {
    title: string;
    children: ReactNode;
    className?: string;
}) {
    return (
        <div className={`rounded-xl border border-slate-200/80 bg-white p-3 shadow-sm dark:border-slate-700/60 dark:bg-slate-900 ${className}`}>
            <p className="mb-2 text-[10px] font-bold uppercase tracking-[0.1em] text-slate-400 dark:text-slate-500">{title}</p>
            {children}
        </div>
    );
}

function VehicleSummaryCard({
    vehicleId,
    lapTimes,
    rounds,
    morning,
    afternoon,
    dayKey,
    color,
    defaultOpen,
}: {
    vehicleId: string;
    lapTimes: string[];
    rounds: number;
    morning: number;
    afternoon: number;
    dayKey: string;
    color: string;
    defaultOpen?: boolean;
}) {
    const { t } = useShareLocale();
    const [open, setOpen] = useState(defaultOpen ?? false);
    const stats = useMemo(() => {
        const intervals = computeLapIntervals(lapTimes, dayKey);
        return computeIntervalStats(intervals.intervalsSec);
    }, [lapTimes, dayKey]);

    if (lapTimes.length === 0) return null;

    const lastLap = lapTimes[lapTimes.length - 1];

    return (
        <div className="overflow-hidden rounded-xl border border-slate-200/80 bg-white dark:border-slate-700/60 dark:bg-slate-900">
            <button
                type="button"
                onClick={() => setOpen((v) => !v)}
                className="flex w-full items-center justify-between gap-2 px-3 py-2.5 text-left transition hover:bg-slate-50 dark:hover:bg-slate-800"
            >
                <div className="min-w-0">
                    <p className="truncate text-xs font-bold text-slate-800 dark:text-slate-100">{vehicleId}</p>
                    <p className="text-[10px] font-medium text-slate-500 dark:text-slate-400">
                        {rounds} {t('tripUnit')} · {t('morning')} {morning} · {t('afternoon')} {afternoon}
                    </p>
                </div>
                <ChevronDown size={16} className={`shrink-0 text-slate-400 dark:text-slate-500 transition-transform ${open ? 'rotate-180' : ''}`} />
            </button>
            {open && (
                <div className="border-t border-slate-100 px-3 pb-3 pt-2 dark:border-slate-800">
                    <div className="grid grid-cols-2 gap-2">
                        <div className="rounded-lg bg-slate-50 px-2.5 py-2 dark:bg-slate-800/60">
                            <p className="text-[9px] font-bold uppercase text-slate-400">{t('avgPaceLabel')}</p>
                            <p className="text-sm font-black tabular-nums text-slate-800 dark:text-slate-100">
                                {stats.avg != null ? `${Math.round(stats.avg)} ${t('secUnit')}` : '—'}
                            </p>
                        </div>
                        <div className="rounded-lg bg-slate-50 px-2.5 py-2 dark:bg-slate-800/60">
                            <p className="text-[9px] font-bold uppercase text-slate-400">{t('latestLabel')}</p>
                            <p className="truncate font-mono text-[10px] font-semibold text-slate-600 dark:text-slate-300">{lastLap}</p>
                        </div>
                    </div>
                    <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-slate-100 dark:bg-slate-800">
                        <div className="flex h-full">
                            <div
                                className="bg-amber-400"
                                style={{ width: `${rounds > 0 ? (morning / rounds) * 100 : 0}%` }}
                            />
                            <div
                                className="h-full"
                                style={{
                                    width: `${rounds > 0 ? (afternoon / rounds) * 100 : 0}%`,
                                    backgroundColor: color,
                                }}
                            />
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}

const CountRecordAnalyticsPanel = ({
    mode,
    dayKey,
    transactions,
    employees = [],
    accentColor,
}: CountRecordAnalyticsPanelProps) => {
    const { t, roundLabelTrip, roundLabelSand } = useShareLocale();
    const color = accentColor ?? (mode === 'sand' ? '#db2777' : '#2563eb');

    const comparison = useMemo(
        () => buildDayComparison(dayKey, transactions, employees),
        [dayKey, transactions, employees],
    );

    const modeComparison = mode === 'sand' ? comparison.sand : comparison.trip;

    const { lapTimes, tripUnits } = useMemo(() => {
        if (mode === 'sand') {
            const sand = buildCountRecordSandUnit(dayKey, transactions);
            return { lapTimes: sand?.lapTimes ?? [], tripUnits: [] as ReturnType<typeof buildCountRecordTripUnits> };
        }
        const units = buildCountRecordTripUnits(dayKey, transactions, employees);
        const timeline = mergeTripLapTimeline(units, dayKey);
        return { lapTimes: timelineToLapStamps(timeline), tripUnits: units };
    }, [mode, dayKey, transactions, employees]);

    const intervals = useMemo(() => computeLapIntervals(lapTimes, dayKey), [lapTimes, dayKey]);
    const stats = useMemo(() => computeIntervalStats(intervals.intervalsSec), [intervals]);
    const sparkline = useMemo(() => buildIntervalSparkline(intervals.intervalsSec, 10), [intervals]);
    const hourly = useMemo(() => computeHourlyBuckets(lapTimes, dayKey), [lapTimes, dayKey]);
    const hourlyHeatmap = useMemo(() => computeHourlyHeatmap(lapTimes, dayKey), [lapTimes, dayKey]);
    const cumulative = useMemo(() => computeCumulativeSeries(lapTimes, dayKey), [lapTimes, dayKey]);
    const sandWorkSummary = useMemo(
        () => (mode === 'sand' ? computeSandWorkDurationSummary(lapTimes, dayKey) : null),
        [mode, lapTimes, dayKey],
    );
    const hourlyActiveWork = useMemo(
        () => (mode === 'sand' ? computeHourlyActiveWork(lapTimes, dayKey) : []),
        [mode, lapTimes, dayKey],
    );
    const hourlySandSpeed = useMemo(
        () => (mode === 'sand' ? computeHourlySandSpeed(lapTimes, dayKey) : []),
        [mode, lapTimes, dayKey],
    );
    const minuteSandSpeed = useMemo(
        () => (mode === 'sand' ? computeMinuteSandSpeed(lapTimes, dayKey) : []),
        [mode, lapTimes, dayKey],
    );
    const sandUnit = useMemo(
        () => (mode === 'sand' ? buildCountRecordSandUnit(dayKey, transactions) : null),
        [mode, dayKey, transactions],
    );
    const periodSplit = useMemo(() => {
        if (mode === 'trip') return computeTripPeriodSplit(tripUnits);
        return computeSandPeriodSplit(sandUnit?.morning ?? 0, sandUnit?.afternoon ?? 0);
    }, [mode, tripUnits, sandUnit]);
    const vehicleComparison = useMemo(
        () => (mode === 'trip' ? computeVehicleComparison(tripUnits) : []),
        [mode, tripUnits],
    );
    const peakHour = useMemo(() => computePeakHour(hourlyHeatmap), [hourlyHeatmap]);
    const hourlyEfficiency = useMemo(() => computeHourlyEfficiency(lapTimes, dayKey), [lapTimes, dayKey]);
    const tripWorkSummary = useMemo(
        () => (mode === 'trip' ? computeTripFleetWorkDurationSummary(tripUnits, dayKey) : null),
        [mode, tripUnits, dayKey],
    );
    const tripHourlyActiveWork = useMemo(
        () => (mode === 'trip' ? computeHourlyActiveWork(lapTimes, dayKey) : []),
        [mode, lapTimes, dayKey],
    );

    const roundLabel = mode === 'sand' ? roundLabelSand() : roundLabelTrip();
    const hasAnyLaps = lapTimes.length > 0;

    if (!hasAnyLaps && modeComparison.todayRounds <= 0) return null;

    return (
        <div className="mt-3 space-y-3 border-t border-slate-200/60 pt-3 dark:border-slate-700/50">
            <div className="flex flex-col gap-0.5">
                <div className="flex items-center gap-2">
                    <BarChart3 size={14} className="text-slate-400 dark:text-slate-500" style={{ color }} />
                    <p className="text-[11px] font-bold uppercase tracking-[0.12em] text-slate-500 dark:text-slate-400">
                        {t('paceAnalytics')}
                    </p>
                </div>
                <p className="text-[10px] font-medium text-slate-400 dark:text-slate-500">{t('lunchBreakNote')}</p>
            </div>

            <CountRecordStatTiles
                stats={stats}
                comparison={modeComparison}
                roundLabel={roundLabel}
                sparkline={sparkline}
                accentColor={color}
                mode={mode}
                sandWorkSummary={sandWorkSummary}
                tripWorkSummary={tripWorkSummary}
            />

            {/* Bento grid */}
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-12">
                <ChartBlock title={t('morningAfternoonSplit')} className="sm:col-span-2 lg:col-span-4">
                    <PeriodSplitBar split={periodSplit} roundLabel={roundLabel} />
                </ChartBlock>

                <ChartBlock title={t('peakHour')} className="sm:col-span-1 lg:col-span-3">
                    <PeakHourCard peak={peakHour} roundLabel={roundLabel} color={color} />
                </ChartBlock>

                <ChartBlock title={t('heatmapHourly')} className="sm:col-span-1 lg:col-span-5">
                    <HourlyHeatmap cells={hourlyHeatmap} color={color} />
                </ChartBlock>

                <ChartBlock title={t('cumulativeByTime', { unit: roundLabel })} className="lg:col-span-6">
                    <CumulativeLineChart points={cumulative} color={color} />
                </ChartBlock>

                <ChartBlock title={t('countPerHour', { unit: roundLabel })} className="lg:col-span-6">
                    <HourlyBarChart buckets={hourly} color={color} />
                </ChartBlock>

                <ChartBlock title={t('speedPerHour', { unit: roundLabel })} className="lg:col-span-6">
                    <EfficiencyBarChart buckets={hourlyEfficiency} color={color} unitLabel={t('perHourUnit', { unit: roundLabel })} />
                </ChartBlock>

                {mode === 'trip' && (
                    <ChartBlock title={t('vehicleComparison')} className="lg:col-span-6">
                        <VehicleComparisonChart rows={vehicleComparison} color={color} />
                    </ChartBlock>
                )}

                {mode === 'sand' && (
                    <>
                        <ChartBlock title={t('sandWorkHourly')} className="lg:col-span-6">
                            <WorkHoursBarChart buckets={hourlyActiveWork} color={color} />
                        </ChartBlock>
                        <ChartBlock title={t('sandSpeedHourly')} className="lg:col-span-6">
                            <HourlyBarChart
                                buckets={hourlySandSpeed}
                                color={color}
                                valueKey="speed"
                                unitLabel={t('perHourUnit', { unit: roundLabel })}
                            />
                        </ChartBlock>
                        <ChartBlock title={t('sandSpeedMinute')} className="lg:col-span-12">
                            <MinuteTimelineChart buckets={minuteSandSpeed} color={color} />
                        </ChartBlock>
                    </>
                )}

                {mode === 'trip' && tripHourlyActiveWork.length > 0 && (
                    <ChartBlock title={t('fleetWorkHourly')} className="lg:col-span-12">
                        <WorkHoursBarChart buckets={tripHourlyActiveWork} color={color} />
                    </ChartBlock>
                )}
            </div>

            {mode === 'trip' && tripUnits.filter((u) => u.lapTimes.length > 0).length > 0 && (
                <div className="space-y-2">
                    <p className="text-[10px] font-bold uppercase tracking-[0.1em] text-slate-400 dark:text-slate-500">{t('perVehicleSummary')}</p>
                    {tripUnits
                        .filter((u) => u.lapTimes.length > 0)
                        .map((u, i) => (
                            <VehicleSummaryCard
                                key={u.id}
                                vehicleId={u.vehicleId}
                                lapTimes={u.lapTimes}
                                rounds={u.rounds}
                                morning={u.morning}
                                afternoon={u.afternoon}
                                dayKey={dayKey}
                                color={color}
                                defaultOpen={i === 0}
                            />
                        ))}
                </div>
            )}
        </div>
    );
};

export default CountRecordAnalyticsPanel;
