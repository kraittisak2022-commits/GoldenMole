import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { Truck, Droplets, AlertTriangle, Timer, Sun, Sunset, Moon, Clock, UserRound, Pencil, Trophy, Medal, Boxes, Gauge, Target } from 'lucide-react';
import { useShareLocale } from '../Share/shareI18n';
import type { Employee, Transaction } from '../../types';
import {
    VEHICLE_BUTTON_COLORS,
    SAND_TARGET_ROUNDS,
    buildCountRecordSandUnit,
    buildCountRecordTripUnits,
    countRecordMenuStatusLabel,
    formatDashboardMetric,
} from './countRecordUtils';
import CountIncrementPop from './CountIncrementPop';
import {
    addDaysToYmd,
    computeSandWorkDurationSummary,
    computeTripFleetWorkSpan,
    computeTripTargetEta,
    computeWorkSpan,
    findPriorDayWithModeData,
    formatActiveHours,
    formatComparisonDayLabel,
    formatWorkSpanLabel,
} from './countRecordAnalytics';
import type { CountRecordIncrement } from './countRecordUtils';

interface CountRecordOverviewProps {
    dayKey: string;
    transactions: Transaction[];
    employees?: Employee[];
    compact?: boolean;
    showHeader?: boolean;
    pulseToken?: number;
    increments?: CountRecordIncrement[];
    /** Public share view — portrait 1 col, mobile landscape 2 cols */
    shareMode?: boolean;
    /** SuperAdmin — open round manager filtered by kind */
    onManageRounds?: (kind: 'trip' | 'sand') => void;
    /** Resolve catalog vehicle ids (v_…) to display names */
    vehicleCatalog?: Array<{ id: string; name: string; defaultDriverId: string | null; sortOrder: number }>;
}

const SAND_RECENT_LAPS = 5;
const QUEUE_PER_TRIP = 4;
const TRIP_TARGET_TRIPS = 250;

function TargetProgressBar({
    current,
    target,
    color,
}: {
    current: number;
    target: number;
    color: string;
}) {
    const { t } = useShareLocale();
    const pct = target > 0 ? Math.min((current / target) * 100, 100) : 0;
    return (
        <div className="mt-2 space-y-1">
            <div className="flex items-center justify-between text-[10px] font-semibold">
                <span className="text-slate-500 dark:text-slate-400">{t('sandTargetLabel')}</span>
                <span className="tabular-nums text-slate-700 dark:text-slate-200">
                    {t('sandTargetProgress', { current: formatDashboardMetric(current), target: formatDashboardMetric(target) })}
                    {' · '}
                    {Math.round(pct)}%
                </span>
            </div>
            <div className="h-2 overflow-hidden rounded-full bg-slate-200/80 dark:bg-slate-700">
                <div
                    className="chart-bar-grow h-full rounded-full transition-all"
                    style={{ width: `${pct}%`, backgroundColor: color }}
                />
            </div>
        </div>
    );
}

function EfficiencyVsYesterdayBadge({
    deltaPct,
    priorLabel,
    isCalendarYesterday,
}: {
    deltaPct: number | null;
    priorLabel: string;
    isCalendarYesterday: boolean;
}) {
    const { t } = useShareLocale();
    if (deltaPct == null) {
        return (
            <span className="rounded-full bg-slate-100 px-2 py-0.5 text-[9px] font-bold text-slate-500 dark:bg-slate-800 dark:text-slate-400">
                {!priorLabel || !isCalendarYesterday ? t('noPriorDayData') : t('noYesterdayData')}
            </span>
        );
    }
    if (Math.round(Math.abs(deltaPct)) === 0) {
        return (
            <span className="rounded-full bg-slate-100 px-2 py-0.5 text-[9px] font-bold text-slate-500 dark:bg-slate-800 dark:text-slate-400">
                {isCalendarYesterday ? t('paceSameYesterday') : t('paceSamePriorDay', { label: priorLabel })}
            </span>
        );
    }
    if (deltaPct > 0) {
        return (
            <span className="rounded-full bg-emerald-100 px-2 py-0.5 text-[9px] font-bold text-emerald-700 dark:bg-emerald-500/15 dark:text-emerald-400">
                ▲{' '}
                {isCalendarYesterday
                    ? t('moreEfficientYesterday', { pct: Math.round(Math.abs(deltaPct)) })
                    : t('moreEfficientPriorDay', { label: priorLabel, pct: Math.round(Math.abs(deltaPct)) })}
            </span>
        );
    }
    return (
        <span className="rounded-full bg-rose-100 px-2 py-0.5 text-[9px] font-bold text-rose-700 dark:bg-rose-500/15 dark:text-rose-400">
            ▼{' '}
            {isCalendarYesterday
                ? t('lessEfficientYesterday', { pct: Math.round(Math.abs(deltaPct)) })
                : t('lessEfficientPriorDay', { label: priorLabel, pct: Math.round(Math.abs(deltaPct)) })}
        </span>
    );
}

function TripSummaryHero({
    tripTotal,
    tripUnits,
    dayKey,
    tripFleetWorkSpan,
    vehicleEfficiency,
    showEfficiency,
}: {
    tripTotal: number;
    tripUnits: ReturnType<typeof buildCountRecordTripUnits>;
    dayKey: string;
    tripFleetWorkSpan: string | null;
    vehicleEfficiency: {
        perVehToday: number;
        countToday: number;
        deltaPct: number | null;
        priorLabel: string;
        isCalendarYesterday: boolean;
    };
    showEfficiency: boolean;
}) {
    const { t } = useShareLocale();
    const targetPct = TRIP_TARGET_TRIPS > 0 ? Math.min((tripTotal / TRIP_TARGET_TRIPS) * 100, 100) : 0;
    const atOrOverTarget = tripTotal >= TRIP_TARGET_TRIPS;
    const eta = computeTripTargetEta(tripUnits, dayKey, TRIP_TARGET_TRIPS);
    const etaLine = eta.reached
        ? t('targetReached')
        : eta.etaClock
          ? t('etaReachTarget', { time: eta.etaClock })
          : t('needTwoRounds');

    return (
        <div className="press-pop relative w-full overflow-hidden rounded-2xl bg-gradient-to-br from-blue-600 via-blue-600 to-indigo-700 px-4 py-4 shadow-lg shadow-blue-900/20">
            <div className="absolute -right-8 -top-8 h-28 w-28 rounded-full bg-white/10 blur-2xl" />
            <div className="absolute inset-0 bg-[radial-gradient(circle_at_30%_20%,rgba(255,255,255,0.12),transparent_50%)]" />

            <div className="relative">
                <div className="flex items-start justify-between gap-2">
                    <p className="text-[10px] font-bold uppercase tracking-[0.16em] text-white/70">{t('tripTotalTitle')}</p>
                    {tripFleetWorkSpan ? <WorkSpanBadge label={tripFleetWorkSpan} onDark /> : null}
                </div>

                <p className="mt-2 text-5xl font-black tabular-nums leading-none text-white">
                    {formatDashboardMetric(tripTotal)}
                    <span className="ml-2 text-lg font-bold text-white/80">{t('tripUnit')}</span>
                </p>

                <div className="mt-3 space-y-1">
                    <div className="flex items-center justify-between gap-2 text-[10px] font-semibold text-white/80">
                        <span className="inline-flex items-center gap-1">
                            <Target size={10} />
                            {t('tripTargetLabel')}
                        </span>
                        <span className="tabular-nums">
                            {t('tripTargetProgress', {
                                current: formatDashboardMetric(tripTotal),
                                target: formatDashboardMetric(TRIP_TARGET_TRIPS),
                            })}
                            {' · '}
                            {Math.round(targetPct)}%
                        </span>
                    </div>
                    <div className="h-2 overflow-hidden rounded-full bg-white/20">
                        <div
                            className={`chart-bar-grow h-full rounded-full ${atOrOverTarget ? 'bg-emerald-300' : 'bg-white'}`}
                            style={{ width: `${targetPct}%` }}
                        />
                    </div>
                    <p
                        className={`pt-0.5 text-[11px] font-semibold ${
                            eta.reached ? 'text-emerald-200' : 'text-sky-100'
                        }`}
                    >
                        {etaLine}
                        {!eta.reached && eta.hoursLeft != null
                            ? ` · ${formatActiveHours(eta.hoursLeft)}`
                            : ''}
                    </p>
                </div>

                <div
                    className={`mt-4 border-t border-white/15 pt-4 ${showEfficiency ? 'grid grid-cols-2 divide-x divide-white/15' : ''}`}
                >
                    <div className={showEfficiency ? 'pr-3' : ''}>
                        <div className="flex items-center gap-1.5 text-[9px] font-bold uppercase tracking-wider text-white/60">
                            <Boxes size={11} />
                            {t('queueCount')}
                        </div>
                        <p className="mt-1 text-2xl font-black tabular-nums text-white">
                            {formatDashboardMetric(tripTotal * QUEUE_PER_TRIP)}
                            <span className="ml-1 text-sm font-bold text-white/75">{t('queueUnit')}</span>
                        </p>
                        <p className="mt-0.5 text-[9px] font-medium text-white/55">{t('queuePerTripNote')}</p>
                    </div>

                    {showEfficiency ? (
                        <div className="pl-3">
                            <div className="flex flex-wrap items-center justify-between gap-1">
                                <div className="flex items-center gap-1.5 text-[9px] font-bold uppercase tracking-wider text-white/60">
                                    <Gauge size={11} />
                                    {t('perVehicleTitle')}
                                </div>
                                <EfficiencyVsYesterdayBadge
                                    deltaPct={vehicleEfficiency.deltaPct}
                                    priorLabel={vehicleEfficiency.priorLabel}
                                    isCalendarYesterday={vehicleEfficiency.isCalendarYesterday}
                                />
                            </div>
                            <p className="mt-1 text-lg font-black tabular-nums leading-tight text-white">
                                {t('perVehicleAvg', {
                                    v: formatDashboardMetric(Math.round(vehicleEfficiency.perVehToday * 10) / 10),
                                })}
                            </p>
                            <p className="mt-0.5 text-[9px] font-medium text-white/55">
                                {t('vehicleCountLabel', { n: vehicleEfficiency.countToday })}
                            </p>
                        </div>
                    ) : null}
                </div>
            </div>
        </div>
    );
}

function PeriodPill({
    morning,
    afternoon,
    ot = 0,
    variant = 'onLight',
}: {
    morning: number;
    afternoon: number;
    ot?: number;
    variant?: 'onDark' | 'onLight';
}) {
    const { t } = useShareLocale();
    const afternoonDisplay = Math.max(0, afternoon - ot);
    if (morning <= 0 && afternoonDisplay <= 0 && ot <= 0) return null;

    const morningCls =
        variant === 'onDark'
            ? 'bg-amber-400/30 text-amber-50 ring-1 ring-amber-200/50 shadow-sm'
            : 'bg-amber-100 text-amber-900 ring-1 ring-amber-200 dark:bg-amber-500/15 dark:text-amber-200 dark:ring-amber-400/25';
    const afternoonCls =
        variant === 'onDark'
            ? 'bg-sky-400/30 text-sky-50 ring-1 ring-sky-200/50 shadow-sm'
            : 'bg-indigo-100 text-indigo-900 ring-1 ring-indigo-200 dark:bg-indigo-500/15 dark:text-indigo-200 dark:ring-indigo-400/25';
    const otCls =
        variant === 'onDark'
            ? 'bg-violet-400/30 text-violet-50 ring-1 ring-violet-200/50 shadow-sm'
            : 'bg-violet-100 text-violet-900 ring-1 ring-violet-200 dark:bg-violet-500/15 dark:text-violet-200 dark:ring-violet-400/25';

    return (
        <div className="flex flex-wrap justify-center gap-1.5">
            {morning > 0 && (
                <span className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[10px] font-bold ${morningCls}`}>
                    <Sun size={10} />
                    {t('morning')} {formatDashboardMetric(morning)}
                </span>
            )}
            {afternoonDisplay > 0 && (
                <span className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[10px] font-bold ${afternoonCls}`}>
                    <Sunset size={10} />
                    {t('afternoon')} {formatDashboardMetric(afternoonDisplay)}
                </span>
            )}
            {ot > 0 && (
                <span className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[10px] font-bold ${otCls}`}>
                    <Moon size={10} />
                    {t('ot')} {formatDashboardMetric(ot)}
                </span>
            )}
        </div>
    );
}

function WorkSpanBadge({ label, onDark }: { label: string; onDark?: boolean }) {
    return (
        <p
            className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[11px] font-semibold ${
                onDark ? 'bg-black/20 text-white/90 backdrop-blur-sm' : 'bg-slate-100 text-slate-700 dark:bg-slate-800/60 dark:text-slate-300'
            }`}
        >
            <Clock size={10} />
            {label}
        </p>
    );
}

function TripVehicleCard({
    unit,
    index,
    compact,
    highlight,
    dayKey,
    incrementDelta,
}: {
    unit: ReturnType<typeof buildCountRecordTripUnits>[number];
    index: number;
    compact?: boolean;
    highlight?: boolean;
    dayKey: string;
    incrementDelta?: number;
}) {
    const { t, locale } = useShareLocale();
    const accent = VEHICLE_BUTTON_COLORS[index % VEHICLE_BUTTON_COLORS.length];
    const lastLap = unit.lapTimes[unit.lapTimes.length - 1];
    const workSpanLabel = formatWorkSpanLabel(computeWorkSpan(unit.lapTimes, dayKey), locale);

    return (
        <article
            className={`group relative overflow-hidden rounded-2xl border border-white/10 bg-slate-900 text-white shadow-lg shadow-slate-900/20 transition-all duration-500 ${
                compact ? 'min-h-[148px]' : 'min-h-[168px]'
            } ${highlight ? 'ring-2 ring-white/40 scale-[1.01]' : ''}`}
        >
            <div
                className="absolute inset-0 opacity-90"
                style={{ background: `linear-gradient(145deg, ${accent} 0%, ${accent}cc 42%, #0f172a 100%)` }}
            />
            <div className="absolute -right-6 -top-6 h-24 w-24 rounded-full bg-white/10 blur-2xl" />

            <div className={`relative flex h-full flex-col ${compact ? 'p-3' : 'p-3.5'}`}>
                <div className="flex items-start justify-between gap-2">
                    <span className="rounded-lg bg-black/20 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide text-white/90 backdrop-blur-sm">
                        {t('vehicleNo', { n: index + 1 })}
                    </span>
                    {unit.broken && (
                        <span className="inline-flex items-center gap-1 rounded-lg bg-amber-300/95 px-1.5 py-0.5 text-[10px] font-bold text-amber-950">
                            <AlertTriangle size={10} />
                            {t('brokenVehicle')}
                        </span>
                    )}
                </div>

                <div className="my-2 flex flex-1 flex-col items-center justify-center text-center">
                    <div className="relative">
                        <p
                            key={`${unit.id}-count-${unit.rounds}-${incrementDelta ?? 0}`}
                            className={`font-black tabular-nums tracking-tight leading-none ${compact ? 'text-4xl' : 'text-5xl'} ${
                                incrementDelta != null && incrementDelta !== 0 ? 'count-number-punch' : ''
                            }`}
                        >
                            {unit.rounds}
                        </p>
                        {incrementDelta != null && incrementDelta !== 0 && (
                            <CountIncrementPop
                                key={`${unit.id}-${unit.rounds}-${incrementDelta}`}
                                delta={incrementDelta}
                                color="#fef08a"
                                decrementColor="#fca5a5"
                            />
                        )}
                    </div>
                    <p className="mt-1 text-[11px] font-semibold uppercase tracking-[0.16em] text-white/75">{t('tripUnit')}</p>
                    <div className="mt-2">
                        <PeriodPill morning={unit.morning} afternoon={unit.afternoon} ot={unit.ot} variant="onDark" />
                    </div>
                </div>

                <div className="rounded-xl bg-black/20 px-2.5 py-2 backdrop-blur-sm">
                    <p className={`truncate font-bold leading-tight ${compact ? 'text-xs' : 'text-sm'}`}>{unit.vehicleId}</p>
                    <p className="mt-0.5 flex items-center justify-center gap-1 truncate text-[10px] font-medium text-white/80">
                        <UserRound size={10} />
                        {unit.driverLabel}
                    </p>
                    {workSpanLabel && (
                        <p className="mt-1 flex items-center justify-center gap-1 truncate text-[10px] font-semibold text-white/75">
                            <Clock size={9} />
                            {workSpanLabel}
                        </p>
                    )}
                    {lastLap && (
                        <p className="mt-1 flex items-center justify-center gap-1 truncate text-[10px] text-white/65">
                            <Clock size={9} />
                            {lastLap}
                        </p>
                    )}
                </div>
            </div>
        </article>
    );
}

function SandLapChip({ roundNo, stamp, latest }: { roundNo: number; stamp: string; latest?: boolean }) {
    const { t } = useShareLocale();
    return (
        <span
            className={`inline-flex items-center gap-1.5 rounded-xl border px-2.5 py-1.5 text-[11px] font-semibold ${
                latest
                    ? 'border-pink-300 bg-pink-600 text-white shadow-sm shadow-pink-500/25'
                    : 'border-pink-200/80 bg-white text-pink-900 dark:border-pink-400/25 dark:bg-slate-800 dark:text-pink-200'
            }`}
        >
            <span className={latest ? 'text-pink-100' : 'text-pink-600 dark:text-pink-300'}>{t('roundLabel')} {roundNo}</span>
            <span className={`font-mono tabular-nums ${latest ? 'text-white/90' : 'text-slate-500 dark:text-slate-400'}`}>{stamp}</span>
        </span>
    );
}

function EmptyState({ title, subtitle, icon: Icon }: { title: string; subtitle: string; icon: typeof Truck }) {
    return (
        <div className="flex min-h-[168px] flex-col items-center justify-center rounded-2xl border border-dashed border-slate-200 bg-slate-50/50 px-6 py-8 text-center dark:border-slate-700 dark:bg-slate-800/40">
            <span className="mb-3 flex h-12 w-12 items-center justify-center rounded-2xl bg-white text-slate-400 shadow-sm ring-1 ring-slate-100 dark:bg-slate-800 dark:text-slate-500 dark:ring-slate-700">
                <Icon size={22} strokeWidth={1.75} />
            </span>
            <p className="text-sm font-semibold text-slate-600 dark:text-slate-300">{title}</p>
            <p className="mt-1 max-w-[220px] text-xs leading-relaxed text-slate-400 dark:text-slate-500">{subtitle}</p>
        </div>
    );
}

function CountRecordPanelShell({
    title,
    subtitle,
    icon,
    accentClass,
    children,
    highlight,
}: {
    title: string;
    subtitle?: string;
    icon: ReactNode;
    accentClass: string;
    children: ReactNode;
    highlight?: boolean;
}) {
    return (
        <section
            className={`flex min-h-[280px] flex-col overflow-hidden rounded-[20px] border bg-white shadow-sm transition-all duration-500 dark:bg-slate-900 ${
                highlight ? 'border-slate-300 shadow-md shadow-slate-200/60 dark:border-slate-600 dark:shadow-slate-950/50' : 'border-slate-200/80 shadow-slate-200/30 dark:border-slate-700/60 dark:shadow-slate-950/30'
            }`}
        >
            <header className={`relative overflow-hidden px-4 py-3.5 ${accentClass}`}>
                <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_right,rgba(255,255,255,0.22),transparent_55%)]" />
                <div className="relative flex items-center gap-3">
                    <span className="flex h-10 w-10 items-center justify-center rounded-xl bg-white/15 text-white backdrop-blur-sm ring-1 ring-white/20">
                        {icon}
                    </span>
                    <div className="min-w-0">
                        <h4 className="truncate text-sm font-bold tracking-tight text-white">{title}</h4>
                        {subtitle && <p className="truncate text-[11px] font-medium text-white/75">{subtitle}</p>}
                    </div>
                </div>
            </header>
            <div className="flex-1 bg-gradient-to-b from-slate-50/30 to-white p-3 dark:from-slate-800/30 dark:to-slate-900">{children}</div>
        </section>
    );
}

const CountRecordOverview = ({
    dayKey,
    transactions,
    employees = [],
    compact = false,
    showHeader = true,
    pulseToken = 0,
    increments = [],
    shareMode = false,
    onManageRounds,
    vehicleCatalog = [],
}: CountRecordOverviewProps) => {
    const { t, locale } = useShareLocale();
    const [highlight, setHighlight] = useState(false);

    useEffect(() => {
        if (pulseToken <= 0) return;
        setHighlight(true);
        const timer = window.setTimeout(() => setHighlight(false), 700);
        return () => window.clearTimeout(timer);
    }, [pulseToken]);

    const latestTripIncrements = useMemo(() => {
        const map = new Map<string, number>();
        for (const inc of increments) {
            if (inc.kind !== 'trip' || !inc.unitId) continue;
            map.set(inc.unitId, inc.delta);
        }
        return map;
    }, [increments]);

    const latestSandIncrement = useMemo(() => {
        const sandInc = increments.find((i) => i.kind === 'sand');
        return sandInc?.delta ?? 0;
    }, [increments]);

    const tripUnits = useMemo(
        () => buildCountRecordTripUnits(dayKey, transactions, employees, vehicleCatalog),
        [dayKey, transactions, employees, vehicleCatalog],
    );
    const sandUnit = useMemo(
        () => buildCountRecordSandUnit(dayKey, transactions),
        [dayKey, transactions],
    );
    const statusLabel = useMemo(
        () => countRecordMenuStatusLabel(dayKey, transactions, locale),
        [dayKey, transactions, locale],
    );

    const tripTotal = tripUnits.reduce((s, u) => s + u.rounds, 0);
    const sandRecentStart = sandUnit ? Math.max(0, sandUnit.lapTimes.length - SAND_RECENT_LAPS) : 0;
    const tripWithLaps = tripUnits.filter((u) => u.lapTimes.length > 0);
    const tripLeaderboard = useMemo(
        () => [...tripWithLaps].sort((a, b) => b.rounds - a.rounds),
        [tripWithLaps],
    );
    const tripFleetWorkSpan = useMemo(
        () => formatWorkSpanLabel(computeTripFleetWorkSpan(tripUnits, dayKey), locale),
        [tripUnits, dayKey, locale],
    );
    const sandWorkSpan = useMemo(
        () => (sandUnit ? formatWorkSpanLabel(computeWorkSpan(sandUnit.lapTimes, dayKey), locale) : null),
        [sandUnit, dayKey, locale],
    );
    const sandWorkSummary = useMemo(
        () => (sandUnit ? computeSandWorkDurationSummary(sandUnit.lapTimes, dayKey) : null),
        [sandUnit, dayKey],
    );
    const priorTripDayKey = useMemo(
        () => findPriorDayWithModeData(dayKey, 'trip', transactions, employees),
        [dayKey, transactions, employees],
    );
    const yesterdayTripUnits = useMemo(() => {
        if (!priorTripDayKey) return [];
        return buildCountRecordTripUnits(priorTripDayKey, transactions, employees, vehicleCatalog);
    }, [priorTripDayKey, transactions, employees, vehicleCatalog]);

    const sandSpeedPerHour = useMemo(() => {
        if (!sandUnit || !sandWorkSummary || sandWorkSummary.totalActiveHours <= 0) return null;
        return sandUnit.rounds / sandWorkSummary.totalActiveHours;
    }, [sandUnit, sandWorkSummary]);

    const sandSpeedPerMinute = useMemo(() => {
        if (!sandUnit || !sandWorkSummary || sandWorkSummary.totalActiveHours <= 0) return null;
        return sandUnit.rounds / (sandWorkSummary.totalActiveHours * 60);
    }, [sandUnit, sandWorkSummary]);

    const vehicleEfficiency = useMemo(() => {
        const countToday = tripUnits.length;
        const yTripTotal = yesterdayTripUnits.reduce((s, u) => s + u.rounds, 0);
        const countYest = yesterdayTripUnits.length;
        const perVehToday = countToday > 0 ? tripTotal / countToday : 0;
        const perVehYest = countYest > 0 && yTripTotal > 0 ? yTripTotal / countYest : null;
        const deltaPct =
            perVehYest != null && perVehYest > 0 ? ((perVehToday - perVehYest) / perVehYest) * 100 : null;
        const priorLabel = formatComparisonDayLabel(priorTripDayKey, dayKey, locale);
        const isCalendarYesterday = priorTripDayKey === addDaysToYmd(dayKey, -1);
        return { perVehToday, countToday, deltaPct, priorLabel, isCalendarYesterday };
    }, [tripUnits, yesterdayTripUnits, tripTotal, priorTripDayKey, dayKey, locale]);

    const isCompactLayout = compact || shareMode;
    const showOverviewHeader = showHeader && !shareMode;
    const panelGridClass = shareMode
        ? 'grid-cols-1 max-md:landscape:grid-cols-2 xl:grid-cols-2'
        : compact
          ? 'grid-cols-1'
          : 'grid-cols-1 xl:grid-cols-2';

    return (
        <div className={isCompactLayout ? 'space-y-3' : 'space-y-5'}>
            {showOverviewHeader && (
                <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
                    <div className="flex items-start gap-3">
                        <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-gradient-to-br from-slate-800 to-slate-950 text-white shadow-lg shadow-slate-900/20">
                            <Timer size={18} />
                        </span>
                        <div>
                            <p className="text-[11px] font-bold uppercase tracking-[0.14em] text-slate-400">
                                {t('countRecord')}
                            </p>
                            <h3 className="text-lg font-bold tracking-tight text-slate-900 dark:text-slate-100">{t('countAndRecord')}</h3>
                            {statusLabel ? (
                                <p className="mt-0.5 text-sm font-medium text-slate-500 dark:text-slate-400">{statusLabel}</p>
                            ) : (
                                <p className="mt-0.5 text-sm text-slate-400 dark:text-slate-500">{t('waitingMobile')}</p>
                            )}
                        </div>
                    </div>

                    <div className="flex flex-wrap gap-2">
                        <span className="inline-flex items-center gap-2 rounded-xl border border-blue-100 bg-blue-50/80 px-3 py-2 text-xs font-semibold text-blue-900 dark:border-blue-400/20 dark:bg-blue-500/10 dark:text-blue-200">
                            <Truck size={14} className="text-blue-600 dark:text-blue-300" />
                            {t('tripSubtitle', { vehicles: tripUnits.length, total: formatDashboardMetric(tripTotal) })}
                        </span>
                        <span className="inline-flex items-center gap-2 rounded-xl border border-pink-100 bg-pink-50/80 px-3 py-2 text-xs font-semibold text-pink-900 dark:border-pink-400/20 dark:bg-pink-500/10 dark:text-pink-200">
                            <Droplets size={14} className="text-pink-600 dark:text-pink-300" />
                            {sandUnit ? `${formatDashboardMetric(sandUnit.rounds)} ${t('roundUnit')}` : `0 ${t('roundUnit')}`}
                        </span>
                    </div>
                </div>
            )}

            <div className={`grid gap-4 ${panelGridClass}`}>
                <CountRecordPanelShell
                    title={t('tripCountTitle')}
                    subtitle={t('tripSubtitle', { vehicles: tripUnits.length, total: formatDashboardMetric(tripTotal) })}
                    icon={<Truck size={18} />}
                    accentClass="bg-gradient-to-r from-blue-700 via-blue-600 to-cyan-600"
                    highlight={highlight}
                >
                    {tripUnits.length === 0 ? (
                        <EmptyState
                            icon={Truck}
                            title={t('noTripsTitle')}
                            subtitle={t('noTripsSubtitle')}
                        />
                    ) : (
                        <div className="space-y-3">
                            {tripTotal > 0 && (
                                <TripSummaryHero
                                    tripTotal={tripTotal}
                                    tripUnits={tripUnits}
                                    dayKey={dayKey}
                                    tripFleetWorkSpan={tripFleetWorkSpan}
                                    vehicleEfficiency={vehicleEfficiency}
                                    showEfficiency={tripUnits.length > 0}
                                />
                            )}

                            <div
                                className={
                                    tripUnits.length <= 2
                                        ? `grid gap-2.5 ${tripUnits.length === 1 ? 'grid-cols-1' : 'grid-cols-2'}`
                                        : 'grid grid-cols-2 gap-2.5'
                                }
                            >
                                {tripUnits.map((unit, i) => (
                                    <TripVehicleCard
                                        key={unit.id}
                                        unit={unit}
                                        index={i}
                                        compact={compact || (shareMode ? tripUnits.length > 3 : tripUnits.length > 2)}
                                        highlight={highlight}
                                        dayKey={dayKey}
                                        incrementDelta={latestTripIncrements.get(unit.id)}
                                    />
                                ))}
                            </div>

                            <div className="rounded-2xl border border-slate-200/80 bg-white p-3 shadow-sm dark:border-slate-700/60 dark:bg-slate-900">
                                {onManageRounds ? (
                                    <button
                                        type="button"
                                        onClick={() => onManageRounds('trip')}
                                        className="group flex w-full items-center justify-between gap-2 text-left transition hover:opacity-90"
                                    >
                                        <p className="text-[11px] font-bold uppercase tracking-[0.12em] text-slate-400 group-hover:text-blue-600 dark:text-slate-500 dark:group-hover:text-blue-400">
                                            {t('latestLog')}
                                        </p>
                                        <span className="inline-flex shrink-0 items-center gap-1 rounded-lg bg-blue-50 px-2 py-1 text-[10px] font-bold text-blue-700 ring-1 ring-blue-200/80 transition group-hover:bg-blue-100 dark:bg-blue-950/50 dark:text-blue-300 dark:ring-blue-800/60 dark:group-hover:bg-blue-900/50">
                                            <Pencil size={10} />
                                            {t('manage')}
                                        </span>
                                    </button>
                                ) : (
                                    <p className="text-[11px] font-bold uppercase tracking-[0.12em] text-slate-400 dark:text-slate-500">
                                        {t('latestLog')}
                                    </p>
                                )}
                                {tripLeaderboard.length > 0 ? (
                                    <ul className="mt-2 space-y-2">
                                        {tripLeaderboard.map((u, rank) => (
                                            <li
                                                key={u.id}
                                                className={`flex items-center justify-between gap-2 rounded-xl px-2.5 py-2 ${
                                                    rank === 0
                                                        ? 'bg-amber-50 ring-2 ring-amber-300/80 dark:bg-amber-500/10 dark:ring-amber-400/40'
                                                        : 'bg-slate-50 dark:bg-slate-800/60'
                                                }`}
                                            >
                                                <div className="flex min-w-0 items-center gap-2">
                                                    {rank === 0 ? (
                                                        <Trophy size={14} className="shrink-0 text-amber-500" />
                                                    ) : rank <= 2 ? (
                                                        <Medal
                                                            size={14}
                                                            className={`shrink-0 ${rank === 1 ? 'text-slate-400' : 'text-amber-700'}`}
                                                        />
                                                    ) : null}
                                                    <div className="min-w-0">
                                                        <p className="truncate text-xs font-bold text-slate-800 dark:text-slate-200">{u.vehicleId}</p>
                                                        <p className="truncate font-mono text-[10px] tabular-nums text-slate-500 dark:text-slate-400">
                                                            {u.lapTimes[u.lapTimes.length - 1]}
                                                        </p>
                                                    </div>
                                                </div>
                                                <span className="shrink-0 rounded-lg bg-blue-600 px-2 py-1 text-[10px] font-bold text-white">
                                                    {u.rounds} {t('tripUnit')}
                                                </span>
                                            </li>
                                        ))}
                                    </ul>
                                ) : (
                                    <p className="mt-2 text-xs font-medium text-slate-400 dark:text-slate-500">{t('noTimestamp')}</p>
                                )}
                            </div>
                        </div>
                    )}
                </CountRecordPanelShell>

                <CountRecordPanelShell
                    title={t('sandTitle')}
                    subtitle={
                        sandUnit
                            ? t('sandSubtitle', { rounds: formatDashboardMetric(sandUnit.rounds) })
                            : t('sandSubtitleEmpty')
                    }
                    icon={<Droplets size={18} />}
                    accentClass="bg-gradient-to-r from-pink-700 via-rose-600 to-fuchsia-600"
                    highlight={highlight}
                >
                    {!sandUnit || sandUnit.rounds <= 0 ? (
                        <EmptyState
                            icon={Droplets}
                            title={t('noSandTitle')}
                            subtitle={t('noSandSubtitle')}
                        />
                    ) : (
                        <div className="space-y-3">
                            <div
                                className={`relative overflow-hidden rounded-2xl bg-gradient-to-br from-pink-600 via-rose-600 to-fuchsia-700 px-5 py-6 text-center text-white shadow-inner shadow-pink-900/20 transition-all duration-500 ${
                                    highlight ? 'ring-2 ring-pink-200/80' : ''
                                }`}
                            >
                                <div className="absolute inset-0 bg-[radial-gradient(circle_at_30%_20%,rgba(255,255,255,0.18),transparent_45%)]" />
                                <div className="relative">
                                    <div className="relative">
                                        <p
                                            key={`sand-count-${sandUnit.rounds}-${latestSandIncrement}`}
                                            className={`text-6xl font-black tabular-nums tracking-tight leading-none ${
                                                latestSandIncrement !== 0 ? 'count-number-punch' : ''
                                            }`}
                                        >
                                            {sandUnit.rounds}
                                        </p>
                                        {latestSandIncrement !== 0 && (
                                            <CountIncrementPop
                                                key={`sand-${sandUnit.rounds}-${latestSandIncrement}`}
                                                delta={latestSandIncrement}
                                                color="#fce7f3"
                                                decrementColor="#fca5a5"
                                            />
                                        )}
                                    </div>
                                    <p className="mt-1 text-xs font-bold uppercase tracking-[0.2em] text-white/80">{t('roundUnit')}</p>
                                    <div className="mt-3 flex justify-center">
                                        <PeriodPill morning={sandUnit.morning} afternoon={sandUnit.afternoon} ot={sandUnit.ot} variant="onDark" />
                                    </div>
                                    {sandWorkSpan && (
                                        <div className="mt-3 flex justify-center">
                                            <WorkSpanBadge label={sandWorkSpan} onDark />
                                        </div>
                                    )}
                                    {sandUnit.lapTimes.length > 0 && (
                                        <p className="mt-3 inline-flex items-center gap-1 rounded-full bg-black/15 px-2.5 py-1 text-[11px] font-mono text-white/85">
                                            <Clock size={10} />
                                            {sandUnit.lapTimes[sandUnit.lapTimes.length - 1]}
                                        </p>
                                    )}
                                </div>
                            </div>

                            <div className="press-pop rounded-2xl border border-pink-200/80 bg-gradient-to-br from-pink-50 to-rose-50 p-4 shadow-sm dark:border-pink-500/25 dark:from-pink-950/40 dark:to-rose-950/30">
                                <p className="text-[10px] font-bold uppercase tracking-[0.14em] text-pink-600 dark:text-pink-300">
                                    {t('sandKpiTitle')}
                                </p>
                                <div className="mt-3 grid grid-cols-2 gap-2">
                                    <div className="rounded-xl bg-white/80 px-3 py-2 text-center dark:bg-slate-900/60">
                                        <p className="text-[9px] font-bold text-pink-600 dark:text-pink-300">
                                            {t('perHourUnit', { unit: t('roundUnit') })}
                                        </p>
                                        <p className="mt-1 text-lg font-black tabular-nums text-pink-900 dark:text-pink-100">
                                            {sandSpeedPerHour != null
                                                ? t('speedPerHourShort', { v: formatDashboardMetric(Math.round(sandSpeedPerHour * 10) / 10) })
                                                : '—'}
                                        </p>
                                    </div>
                                    <div className="rounded-xl bg-white/80 px-3 py-2 text-center dark:bg-slate-900/60">
                                        <p className="text-[9px] font-bold text-pink-600 dark:text-pink-300">{t('roundsPerMinute')}</p>
                                        <p className="mt-1 text-lg font-black tabular-nums text-pink-900 dark:text-pink-100">
                                            {sandSpeedPerMinute != null
                                                ? t('speedPerMinuteShort', { v: formatDashboardMetric(Math.round(sandSpeedPerMinute * 100) / 100) })
                                                : '—'}
                                        </p>
                                    </div>
                                </div>
                                <TargetProgressBar
                                    current={sandUnit.rounds}
                                    target={SAND_TARGET_ROUNDS}
                                    color="#db2777"
                                />
                            </div>

                            {sandUnit.lapTimes.length > 0 && (
                                <div className="rounded-2xl border border-slate-200/80 bg-white p-3 dark:border-slate-700/60 dark:bg-slate-900">
                                    {onManageRounds ? (
                                        <button
                                            type="button"
                                            onClick={() => onManageRounds('sand')}
                                            className="group flex w-full items-center justify-between gap-2 text-left transition hover:opacity-90"
                                        >
                                            <p className="text-[11px] font-bold uppercase tracking-[0.12em] text-slate-400 group-hover:text-pink-600 dark:text-slate-500 dark:group-hover:text-pink-400">
                                                {t('recentLaps')}
                                            </p>
                                            <span className="inline-flex shrink-0 items-center gap-1 rounded-lg bg-pink-50 px-2 py-1 text-[10px] font-bold text-pink-700 ring-1 ring-pink-200/80 transition group-hover:bg-pink-100 dark:bg-pink-950/50 dark:text-pink-300 dark:ring-pink-800/60 dark:group-hover:bg-pink-900/50">
                                                <Pencil size={10} />
                                                {t('manage')}
                                            </span>
                                        </button>
                                    ) : (
                                        <p className="text-[11px] font-bold uppercase tracking-[0.12em] text-slate-400 dark:text-slate-500">
                                            {t('recentLaps')}
                                        </p>
                                    )}
                                    <div className="mt-2 flex flex-wrap gap-1.5">
                                        {sandUnit.lapTimes.slice(sandRecentStart).map((stamp, i) => {
                                            const roundNo = sandRecentStart + i + 1;
                                            const isLatest = roundNo === sandUnit.lapTimes.length;
                                            return (
                                                <SandLapChip
                                                    key={`${stamp}-${roundNo}`}
                                                    roundNo={roundNo}
                                                    stamp={stamp}
                                                    latest={isLatest}
                                                />
                                            );
                                        })}
                                    </div>
                                </div>
                            )}
                        </div>
                    )}
                </CountRecordPanelShell>
            </div>
        </div>
    );
};

export default CountRecordOverview;
