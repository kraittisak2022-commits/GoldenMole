import { useCallback, useMemo, useRef, useState, type PointerEvent, type ReactNode } from 'react';
import { BarChart3, ChevronDown } from 'lucide-react';
import { useShareLocale } from '../Share/shareI18n';
import type { Employee, Transaction } from '../../types';
import {
    buildCountRecordSandUnit,
    buildCountRecordTripUnits,
} from './countRecordUtils';
import {
    addDaysToYmd,
    buildDayComparison,
    buildIntervalSparkline,
    computeCumulativeSeries,
    computeHourlyActiveWork,
    computeHourlyBuckets,
    computeHourlyHeatmap,
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

function clamp(n: number, min: number, max: number) {
    return Math.min(max, Math.max(min, n));
}

function pointerIndexFromX(clientX: number, rect: DOMRect, count: number) {
    if (count <= 1) return 0;
    const ratio = clamp((clientX - rect.left) / rect.width, 0, 1);
    return Math.round(ratio * (count - 1));
}

function ChartTip({
    title,
    value,
    leftPct,
    className = 'bottom-full mb-2',
}: {
    title: string;
    value: string;
    leftPct: number;
    className?: string;
}) {
    const left = clamp(leftPct, 6, 94);
    return (
        <div
            className={`chart-tip-pop pointer-events-none absolute z-20 -translate-x-1/2 rounded-lg bg-slate-900/95 px-2.5 py-1.5 text-[10px] font-semibold text-white shadow-lg ring-1 ring-white/10 dark:bg-slate-800 ${className}`}
            style={{ left: `${left}%` }}
        >
            <p className="leading-tight text-white/70">{title}</p>
            <p className="tabular-nums leading-tight">{value}</p>
        </div>
    );
}

type BarChartItem = {
    label: string;
    value: number;
    barTopLabel: string;
    tooltipTitle: string;
    tooltipValue: string;
    subLabel?: string;
};

function InteractiveBarChart({
    items,
    color,
    barMaxPx = 72,
    containerClass = 'h-24',
}: {
    items: BarChartItem[];
    color: string;
    barMaxPx?: number;
    containerClass?: string;
}) {
    const [activeIdx, setActiveIdx] = useState<number | null>(null);
    const max = Math.max(...items.map((i) => i.value), 1);

    return (
        <div className="relative pb-1">
            <div
                className={`flex ${containerClass} items-end justify-between gap-0.5 px-0.5`}
                onPointerLeave={() => setActiveIdx(null)}
            >
                {items.map((item, i) => {
                    const isActive = activeIdx === i;
                    const dimmed = activeIdx != null && !isActive;
                    return (
                        <button
                            key={`${item.label}-${i}`}
                            type="button"
                            className={`flex min-w-0 flex-1 flex-col items-center justify-end gap-0.5 rounded-t-sm outline-none transition-opacity focus-visible:ring-2 focus-visible:ring-fuchsia-400/50 ${dimmed ? 'opacity-45' : 'opacity-100'}`}
                            onPointerEnter={() => setActiveIdx(i)}
                            onClick={() => setActiveIdx((cur) => (cur === i ? null : i))}
                            aria-pressed={isActive}
                        >
                            <span className="hidden text-[8px] font-bold tabular-nums text-slate-500 dark:text-slate-400 sm:block">
                                {item.barTopLabel}
                            </span>
                            <div
                                className={`chart-bar-grow w-full rounded-t-sm transition-shadow ${isActive ? 'ring-2 ring-white/60 dark:ring-white/30' : ''}`}
                                style={{
                                    height: `${(item.value / max) * barMaxPx}px`,
                                    backgroundColor: color,
                                    minHeight: 4,
                                    animationDelay: `${Math.min(i * 35, 500)}ms`,
                                }}
                            />
                            <span className="w-full truncate text-center text-[7px] text-slate-400 dark:text-slate-500">
                                {item.label}
                            </span>
                            {item.subLabel ? (
                                <span className="text-[7px] text-slate-300 dark:text-slate-600">{item.subLabel}</span>
                            ) : null}
                        </button>
                    );
                })}
            </div>
            {activeIdx != null && items[activeIdx] ? (
                <ChartTip
                    title={items[activeIdx].tooltipTitle}
                    value={items[activeIdx].tooltipValue}
                    leftPct={((activeIdx + 0.5) / items.length) * 100}
                />
            ) : null}
        </div>
    );
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

function labelToHourOfDay(label: string): number | null {
    const m = /^(\d{1,2}):(\d{2})$/.exec(label);
    if (!m) return null;
    return Number(m[1]) + Number(m[2]) / 60;
}

function hourOfDayToLabel(hour: number): string {
    const h = Math.floor(hour);
    const m = Math.round((hour - h) * 60);
    return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
}

function YesterdayComparisonChart({
    today,
    yesterday,
    deltaPct,
    color,
    roundLabel,
}: {
    today: { label: string; value: number }[];
    yesterday: { label: string; value: number }[];
    deltaPct: number | null;
    color: string;
    roundLabel: string;
}) {
    const { t } = useShareLocale();
    const containerRef = useRef<HTMLDivElement>(null);
    const [activeFrac, setActiveFrac] = useState<number | null>(null);

    const updateFrac = useCallback((clientX: number) => {
        const el = containerRef.current;
        if (!el) return;
        const rect = el.getBoundingClientRect();
        setActiveFrac(clamp((clientX - rect.left) / rect.width, 0, 1));
    }, []);

    const onPointerMove = useCallback(
        (e: PointerEvent<HTMLDivElement>) => updateFrac(e.clientX),
        [updateFrac],
    );
    const onPointerDown = useCallback(
        (e: PointerEvent<HTMLDivElement>) => updateFrac(e.clientX),
        [updateFrac],
    );

    const todayPts = today
        .map((p) => ({ h: labelToHourOfDay(p.label), v: p.value }))
        .filter((p): p is { h: number; v: number } => p.h != null);
    const yesterdayPts = yesterday
        .map((p) => ({ h: labelToHourOfDay(p.label), v: p.value }))
        .filter((p): p is { h: number; v: number } => p.h != null);

    if (todayPts.length < 2) {
        return (
            <p className="flex h-28 items-center justify-center text-xs font-medium text-slate-400 dark:text-slate-500">
                {t('needTwoRounds')}
            </p>
        );
    }

    const allPts = [...todayPts, ...yesterdayPts];
    const minH = Math.min(...allPts.map((p) => p.h));
    const maxH = Math.max(...allPts.map((p) => p.h));
    const spanH = Math.max(maxH - minH, 0.5);
    const maxV = Math.max(...allPts.map((p) => p.v), 1);
    const width = 100;
    const height = 80;

    const toCoords = (pts: { h: number; v: number }[]) =>
        pts.map((p) => ({
            x: ((p.h - minH) / spanH) * width,
            y: height - (p.v / maxV) * height,
        }));
    const todayCoords = toCoords(todayPts);
    const yesterdayCoords = toCoords(yesterdayPts);
    const gradId = `vsy-${color.replace(/[^a-zA-Z0-9]/g, '')}`;

    const valueAtHour = (pts: { h: number; v: number }[], hour: number): number => {
        let val = 0;
        for (const p of pts) {
            if (p.h <= hour) val = p.v;
            else break;
        }
        return val;
    };

    const activeHour = activeFrac != null ? minH + activeFrac * spanH : null;
    const deltaBadge =
        deltaPct == null ? (
            <span className="rounded-full bg-slate-100 px-2 py-0.5 text-[9px] font-bold text-slate-500 dark:bg-slate-800 dark:text-slate-400">
                {t('noYesterdayData')}
            </span>
        ) : Math.round(Math.abs(deltaPct)) === 0 ? (
            <span className="rounded-full bg-slate-100 px-2 py-0.5 text-[9px] font-bold text-slate-500 dark:bg-slate-800 dark:text-slate-400">
                {t('paceSameYesterday')}
            </span>
        ) : deltaPct > 0 ? (
            <span className="rounded-full bg-emerald-100 px-2 py-0.5 text-[9px] font-bold text-emerald-700 dark:bg-emerald-500/15 dark:text-emerald-400">
                ▲ {t('moreThanYesterday', { pct: Math.round(Math.abs(deltaPct)) })}
            </span>
        ) : (
            <span className="rounded-full bg-rose-100 px-2 py-0.5 text-[9px] font-bold text-rose-700 dark:bg-rose-500/15 dark:text-rose-400">
                ▼ {t('lessThanYesterday', { pct: Math.round(Math.abs(deltaPct)) })}
            </span>
        );

    return (
        <div className="space-y-1.5">
            <div className="flex flex-wrap items-center justify-between gap-1.5">
                <div className="flex items-center gap-3 text-[9px] font-semibold">
                    <span className="flex items-center gap-1 text-slate-600 dark:text-slate-300">
                        <span className="h-1.5 w-3 rounded-full" style={{ backgroundColor: color }} />
                        {t('todayLabel')}
                    </span>
                    <span className="flex items-center gap-1 text-slate-400 dark:text-slate-500">
                        <span className="h-0 w-3 border-t-2 border-dashed border-slate-400 dark:border-slate-500" />
                        {t('yesterdayLabel')}
                    </span>
                </div>
                {deltaBadge}
            </div>
            <div
                ref={containerRef}
                className="relative h-28 touch-none"
                onPointerMove={onPointerMove}
                onPointerDown={onPointerDown}
                onPointerLeave={() => setActiveFrac(null)}
            >
                <svg viewBox={`0 0 ${width} ${height}`} className="h-full w-full" preserveAspectRatio="none">
                    <defs>
                        <linearGradient id={gradId} x1="0" y1="0" x2="0" y2="1">
                            <stop offset="0%" stopColor={color} stopOpacity="0.2" />
                            <stop offset="100%" stopColor={color} stopOpacity="0" />
                        </linearGradient>
                    </defs>
                    {[0.25, 0.5, 0.75].map((pct) => (
                        <line
                            key={pct}
                            x1={0}
                            y1={height * (1 - pct)}
                            x2={width}
                            y2={height * (1 - pct)}
                            stroke="currentColor"
                            className="text-slate-200 dark:text-slate-700"
                            strokeWidth="0.3"
                            vectorEffect="non-scaling-stroke"
                        />
                    ))}
                    {yesterdayCoords.length >= 2 ? (
                        <polyline
                            points={yesterdayCoords.map((c) => `${c.x},${c.y}`).join(' ')}
                            fill="none"
                            stroke="currentColor"
                            className="chart-area-fade text-slate-400 dark:text-slate-500"
                            strokeWidth="1.2"
                            strokeDasharray="3 2.5"
                            strokeLinecap="round"
                        />
                    ) : null}
                    <path
                        className="chart-area-fade"
                        d={`M${todayCoords[0]!.x},${height} ${todayCoords.map((c) => `L${c.x},${c.y}`).join(' ')} L${todayCoords[todayCoords.length - 1]!.x},${height} Z`}
                        fill={`url(#${gradId})`}
                    />
                    <polyline
                        points={todayCoords.map((c) => `${c.x},${c.y}`).join(' ')}
                        fill="none"
                        stroke={color}
                        strokeWidth="1.6"
                        strokeLinecap="round"
                        className="chart-line-draw"
                        pathLength={1}
                    />
                    {activeFrac != null ? (
                        <line
                            x1={activeFrac * width}
                            y1={0}
                            x2={activeFrac * width}
                            y2={height}
                            stroke="currentColor"
                            className="text-slate-300 dark:text-slate-600"
                            strokeWidth="0.5"
                            strokeDasharray="2 2"
                            vectorEffect="non-scaling-stroke"
                        />
                    ) : null}
                </svg>
                {activeHour != null ? (
                    <ChartTip
                        title={hourOfDayToLabel(activeHour)}
                        value={`${t('todayLabel')} ${valueAtHour(todayPts, activeHour)} · ${t('yesterdayLabel')} ${valueAtHour(yesterdayPts, activeHour)} ${roundLabel}`}
                        leftPct={activeFrac! * 100}
                    />
                ) : null}
            </div>
            <div className="flex justify-between text-[9px] text-slate-400 dark:text-slate-500">
                <span>{hourOfDayToLabel(minH)}</span>
                <span>{hourOfDayToLabel(maxH)}</span>
            </div>
        </div>
    );
}

function CumulativeLineChart({
    points,
    color,
    roundLabel,
}: {
    points: { label: string; value: number }[];
    color: string;
    roundLabel: string;
}) {
    const { t } = useShareLocale();
    const containerRef = useRef<HTMLDivElement>(null);
    const [activeIdx, setActiveIdx] = useState<number | null>(null);

    const updateIdx = useCallback(
        (clientX: number) => {
            const el = containerRef.current;
            if (!el || points.length < 2) return;
            setActiveIdx(pointerIndexFromX(clientX, el.getBoundingClientRect(), points.length));
        },
        [points.length],
    );

    const onPointerMove = useCallback(
        (e: PointerEvent<HTMLDivElement>) => updateIdx(e.clientX),
        [updateIdx],
    );
    const onPointerDown = useCallback(
        (e: PointerEvent<HTMLDivElement>) => updateIdx(e.clientX),
        [updateIdx],
    );

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
    const active = activeIdx != null ? points[activeIdx] : null;
    const tipLeft = activeIdx != null ? (activeIdx / (points.length - 1)) * 100 : 50;

    return (
        <div className="space-y-1">
            <div
                ref={containerRef}
                className="relative h-28 touch-none"
                onPointerMove={onPointerMove}
                onPointerDown={onPointerDown}
                onPointerLeave={() => setActiveIdx(null)}
            >
                <svg viewBox={`0 0 ${width} ${height}`} className="h-full w-full" preserveAspectRatio="none">
                    <defs>
                        <linearGradient id={gradId} x1="0" y1="0" x2="0" y2="1">
                            <stop offset="0%" stopColor={color} stopOpacity="0.25" />
                            <stop offset="100%" stopColor={color} stopOpacity="0" />
                        </linearGradient>
                    </defs>
                    <path
                        className="chart-area-fade"
                        d={`M0,${height} L${coords[0]!.x},${coords[0]!.y} ${coords.map((c) => `L${c.x},${c.y}`).join(' ')} L${width},${height} Z`}
                        fill={`url(#${gradId})`}
                    />
                    <polyline
                        points={linePoints}
                        fill="none"
                        stroke={color}
                        strokeWidth="1.5"
                        strokeLinecap="round"
                        className="chart-line-draw"
                        pathLength={1}
                    />
                    {activeIdx != null && coords[activeIdx] ? (
                        <>
                            <line
                                x1={coords[activeIdx].x}
                                y1={0}
                                x2={coords[activeIdx].x}
                                y2={height}
                                stroke="currentColor"
                                className="text-slate-300 dark:text-slate-600"
                                strokeWidth="0.5"
                                strokeDasharray="2 2"
                                vectorEffect="non-scaling-stroke"
                            />
                            <circle
                                cx={coords[activeIdx].x}
                                cy={coords[activeIdx].y}
                                r="1.8"
                                fill={color}
                                stroke="white"
                                strokeWidth="0.4"
                                vectorEffect="non-scaling-stroke"
                            />
                        </>
                    ) : null}
                </svg>
                {active ? (
                    <ChartTip
                        title={active.label}
                        value={t('chartCumulativeShort', { value: active.value, unit: roundLabel })}
                        leftPct={tipLeft}
                    />
                ) : null}
            </div>
            <div className="flex justify-between text-[9px] text-slate-400 dark:text-slate-500">
                <span>{points[0]?.label}</span>
                <span>{points[points.length - 1]?.label}</span>
            </div>
        </div>
    );
}

function HourlyHeatmap({
    cells,
    color,
    roundLabel,
}: {
    cells: { hour: number; count: number; label: string; intensity: number; isLunch?: boolean }[];
    color: string;
    roundLabel: string;
}) {
    const { t } = useShareLocale();
    const [activeIdx, setActiveIdx] = useState<number | null>(null);
    const active = cells.filter((c) => c.count > 0);
    if (active.length === 0) {
        return (
            <p className="flex h-12 items-center justify-center text-xs font-medium text-slate-400 dark:text-slate-500">
                {t('noHourlyData')}
            </p>
        );
    }
    const selected = activeIdx != null ? cells[activeIdx] : null;
    return (
        <div className="space-y-2">
            <div
                className="grid grid-cols-12 gap-0.5 sm:grid-cols-24"
                onPointerLeave={() => setActiveIdx(null)}
            >
                {cells.map((c, i) => {
                    const isActive = activeIdx === i;
                    return (
                        <button
                            key={c.hour}
                            type="button"
                            title={
                                c.isLunch
                                    ? `${c.label}: ${t('lunchBreak')}`
                                    : `${c.label}: ${c.count} ${t('roundUnit')}`
                            }
                            className={`relative aspect-square min-h-[10px] rounded-sm outline-none transition-transform focus-visible:ring-2 focus-visible:ring-fuchsia-400/50 ${
                                isActive ? 'z-10 scale-110 ring-2 ring-fuchsia-400 ring-offset-1 dark:ring-offset-slate-900' : 'hover:scale-110'
                            } ${
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
                            onPointerEnter={() => setActiveIdx(i)}
                            onClick={() => setActiveIdx((cur) => (cur === i ? null : i))}
                            aria-pressed={isActive}
                        />
                    );
                })}
            </div>
            <div className="flex justify-between text-[8px] text-slate-400 dark:text-slate-500">
                <span>00:00</span>
                <span>06:00</span>
                <span>12:00</span>
                <span>18:00</span>
                <span>23:00</span>
            </div>
            {selected ? (
                <p className="rounded-lg bg-slate-100 px-3 py-2 text-center text-xs font-semibold text-slate-700 dark:bg-slate-800 dark:text-slate-200">
                    {selected.isLunch
                        ? `${selected.label} — ${t('lunchBreak')}`
                        : `${selected.label} — ${selected.count} ${roundLabel}`}
                </p>
            ) : (
                <p className="text-center text-[9px] text-slate-400 dark:text-slate-500">{t('chartTouchHint')}</p>
            )}
        </div>
    );
}

function HourlyBarChart({
    buckets,
    color,
    valueKey = 'count',
    unitLabel,
    roundLabel,
}: {
    buckets: { label: string; count: number; speed?: number }[];
    color: string;
    valueKey?: 'count' | 'speed';
    unitLabel?: string;
    roundLabel?: string;
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
    const suffix = unitLabel ?? roundLabel ?? '';
    const items: BarChartItem[] = buckets.map((b, i) => {
        const val = values[i]!;
        return {
            label: b.label,
            value: val,
            barTopLabel: String(val),
            tooltipTitle: b.label,
            tooltipValue: suffix ? `${val} ${suffix}` : String(val),
            subLabel: unitLabel,
        };
    });
    return <InteractiveBarChart items={items} color={color} />;
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
    const items: BarChartItem[] = buckets.map((b) => {
        const formatted = formatActiveHours(b.activeHours, locale);
        return {
            label: b.label,
            value: b.activeHours,
            barTopLabel: formatted,
            tooltipTitle: b.label,
            tooltipValue: formatted,
        };
    });
    return <InteractiveBarChart items={items} color={color} barMaxPx={80} containerClass="h-28" />;
}

function MinuteTimelineChart({
    buckets,
    color,
}: {
    buckets: { label: string; speed: number }[];
    color: string;
}) {
    const { t } = useShareLocale();
    const containerRef = useRef<HTMLDivElement>(null);
    const [activeIdx, setActiveIdx] = useState<number | null>(null);

    const updateIdx = useCallback(
        (clientX: number) => {
            const el = containerRef.current;
            if (!el || buckets.length === 0) return;
            setActiveIdx(pointerIndexFromX(clientX, el.getBoundingClientRect(), buckets.length));
        },
        [buckets.length],
    );

    const onPointerMove = useCallback(
        (e: PointerEvent<HTMLDivElement>) => updateIdx(e.clientX),
        [updateIdx],
    );
    const onPointerDown = useCallback(
        (e: PointerEvent<HTMLDivElement>) => updateIdx(e.clientX),
        [updateIdx],
    );

    if (buckets.length === 0) {
        return (
            <p className="flex h-24 items-center justify-center text-xs font-medium text-slate-400 dark:text-slate-500">
                {t('noSpeedData')}
            </p>
        );
    }
    const width = 100;
    const height = 40;
    const max = Math.max(...buckets.map((b) => b.speed), 1);
    const maxIdx = buckets.reduce((best, b, i) => (b.speed > buckets[best]!.speed ? i : best), 0);
    const coords = buckets.map((b, i) => ({
        x: (i / Math.max(buckets.length - 1, 1)) * width,
        y: height - (b.speed / max) * height,
    }));
    const areaPath =
        coords.length >= 2
            ? `M0,${height} ${coords.map((c) => `L${c.x},${c.y}`).join(' ')} L${width},${height} Z`
            : '';
    const linePath = coords.map((c, i) => `${i === 0 ? 'M' : 'L'}${c.x},${c.y}`).join(' ');
    const gradId = `min-${color.replace(/[^a-zA-Z0-9]/g, '')}`;
    const timeLabelIndices = [
        0,
        Math.floor(buckets.length / 3),
        Math.floor((buckets.length * 2) / 3),
        buckets.length - 1,
    ].filter((v, i, arr) => arr.indexOf(v) === i);
    const active = activeIdx != null ? buckets[activeIdx] : null;
    const tipLeft = activeIdx != null ? (activeIdx / Math.max(buckets.length - 1, 1)) * 100 : 50;

    return (
        <div className="space-y-2">
            <div
                ref={containerRef}
                className="relative h-32 touch-none"
                onPointerMove={onPointerMove}
                onPointerDown={onPointerDown}
                onPointerLeave={() => setActiveIdx(null)}
            >
                <svg viewBox={`0 0 ${width} ${height}`} className="h-full w-full" preserveAspectRatio="none">
                    {[0.25, 0.5, 0.75].map((pct) => (
                        <line
                            key={pct}
                            x1={0}
                            y1={height * (1 - pct)}
                            x2={width}
                            y2={height * (1 - pct)}
                            stroke="currentColor"
                            className="text-slate-200 dark:text-slate-700"
                            strokeWidth="0.3"
                            vectorEffect="non-scaling-stroke"
                        />
                    ))}
                    <defs>
                        <linearGradient id={gradId} x1="0" y1="0" x2="0" y2="1">
                            <stop offset="0%" stopColor={color} stopOpacity="0.35" />
                            <stop offset="100%" stopColor={color} stopOpacity="0" />
                        </linearGradient>
                    </defs>
                    {areaPath ? <path className="chart-area-fade" d={areaPath} fill={`url(#${gradId})`} /> : null}
                    {linePath ? (
                        <path
                            d={linePath}
                            fill="none"
                            stroke={color}
                            strokeWidth="1.5"
                            strokeLinecap="round"
                            className="chart-line-draw"
                            pathLength={1}
                        />
                    ) : null}
                    <circle
                        cx={coords[maxIdx]!.x}
                        cy={coords[maxIdx]!.y}
                        r="1.5"
                        fill={color}
                        stroke="white"
                        strokeWidth="0.35"
                        vectorEffect="non-scaling-stroke"
                    />
                    {activeIdx != null && coords[activeIdx] ? (
                        <>
                            <line
                                x1={coords[activeIdx].x}
                                y1={0}
                                x2={coords[activeIdx].x}
                                y2={height}
                                stroke="currentColor"
                                className="text-slate-300 dark:text-slate-600"
                                strokeWidth="0.5"
                                strokeDasharray="2 2"
                                vectorEffect="non-scaling-stroke"
                            />
                            <circle
                                cx={coords[activeIdx].x}
                                cy={coords[activeIdx].y}
                                r="1.8"
                                fill={color}
                                stroke="white"
                                strokeWidth="0.4"
                                vectorEffect="non-scaling-stroke"
                            />
                        </>
                    ) : null}
                </svg>
                <div
                    className="pointer-events-none absolute whitespace-nowrap text-[8px] font-bold text-slate-600 dark:text-slate-300"
                    style={{
                        left: `${(coords[maxIdx]!.x / width) * 100}%`,
                        top: `${(coords[maxIdx]!.y / height) * 100}%`,
                        transform: 'translate(-50%, -130%)',
                    }}
                >
                    {t('chartMaxSpeed', { value: buckets[maxIdx]!.speed })}
                </div>
                {active ? (
                    <ChartTip
                        title={active.label}
                        value={`${active.speed} ${t('roundsPerMinute')}`}
                        leftPct={tipLeft}
                    />
                ) : null}
            </div>
            <div className="flex justify-between text-[8px] text-slate-400 dark:text-slate-500">
                {timeLabelIndices.map((idx) => (
                    <span key={idx}>{buckets[idx]?.label}</span>
                ))}
            </div>
            <p className="text-center text-[9px] text-slate-400 dark:text-slate-500">{t('chartTouchHint')}</p>
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
    const yesterdayCumulative = useMemo(() => {
        const yesterdayKey = addDaysToYmd(dayKey, -1);
        if (mode === 'sand') {
            const sand = buildCountRecordSandUnit(yesterdayKey, transactions);
            return computeCumulativeSeries(sand?.lapTimes ?? [], yesterdayKey);
        }
        const units = buildCountRecordTripUnits(yesterdayKey, transactions, employees);
        const timeline = mergeTripLapTimeline(units, yesterdayKey);
        return computeCumulativeSeries(timelineToLapStamps(timeline), yesterdayKey);
    }, [mode, dayKey, transactions, employees]);
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
            <div className="chart-grid grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-12">
                <ChartBlock title={t('morningAfternoonSplit')} className="sm:col-span-2 lg:col-span-4">
                    <PeriodSplitBar split={periodSplit} roundLabel={roundLabel} />
                </ChartBlock>

                <ChartBlock title={t('peakHour')} className="sm:col-span-1 lg:col-span-3">
                    <PeakHourCard peak={peakHour} roundLabel={roundLabel} color={color} />
                </ChartBlock>

                <ChartBlock title={t('heatmapHourly')} className="sm:col-span-1 lg:col-span-5">
                    <HourlyHeatmap cells={hourlyHeatmap} color={color} roundLabel={roundLabel} />
                </ChartBlock>

                <ChartBlock title={t('cumulativeByTime', { unit: roundLabel })} className="lg:col-span-6">
                    <CumulativeLineChart points={cumulative} color={color} roundLabel={roundLabel} />
                </ChartBlock>

                <ChartBlock title={t('countPerHour', { unit: roundLabel })} className="lg:col-span-6">
                    <HourlyBarChart buckets={hourly} color={color} roundLabel={roundLabel} />
                </ChartBlock>

                <ChartBlock title={t('vsYesterdayCumulative')} className="lg:col-span-6">
                    <YesterdayComparisonChart
                        today={cumulative}
                        yesterday={yesterdayCumulative}
                        deltaPct={modeComparison.roundsDeltaPct}
                        color={color}
                        roundLabel={roundLabel}
                    />
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
