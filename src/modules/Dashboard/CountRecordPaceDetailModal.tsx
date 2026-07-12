import { useEffect } from 'react';
import { X, Timer, TrendingDown, BarChart2, Clock, Truck } from 'lucide-react';
import { useShareLocale } from '../Share/shareI18n';
import {
    computeIntervalStats,
    computeLapIntervals,
    formatActiveHours,
    formatAvgPaceSec,
    formatAvgPaceUnit,
    formatPaceDelta,
    type DayModeComparison,
    type IntervalStats,
    type SandWorkDurationSummary,
} from './countRecordAnalytics';
import { formatDashboardMetric, type CountRecordTripUnit } from './countRecordUtils';

const WORK_TARGET_HOURS = 8;

interface CountRecordPaceDetailModalProps {
    open: boolean;
    onClose: () => void;
    mode: 'sand' | 'trip';
    stats: IntervalStats;
    comparison: DayModeComparison;
    roundLabel: string;
    accentColor: string;
    workSummary?: SandWorkDurationSummary | null;
    tripUnits?: CountRecordTripUnit[];
    dayKey: string;
}

const CountRecordPaceDetailModal = ({
    open,
    onClose,
    mode,
    stats,
    comparison,
    roundLabel,
    accentColor,
    workSummary,
    tripUnits = [],
    dayKey,
}: CountRecordPaceDetailModalProps) => {
    const { t, locale } = useShareLocale();
    const paceUnit = formatAvgPaceUnit(stats.avg, locale);
    const paceDelta = formatPaceDelta(comparison.paceDeltaPct, locale);
    const roundsPct = comparison.roundsDeltaPct;
    const roundsSign = roundsPct != null && roundsPct > 0 ? '+' : '';

    const vehiclePaceRows = tripUnits
        .filter((u) => u.lapTimes.length >= 2)
        .map((u) => {
            const intervals = computeLapIntervals(u.lapTimes, dayKey);
            const vStats = computeIntervalStats(intervals.intervalsSec);
            return {
                vehicleId: u.vehicleId,
                rounds: u.rounds,
                avg: vStats.avg,
            };
        })
        .sort((a, b) => (a.avg ?? Infinity) - (b.avg ?? Infinity));

    useEffect(() => {
        if (!open) return;
        const onKey = (e: KeyboardEvent) => {
            if (e.key === 'Escape') onClose();
        };
        window.addEventListener('keydown', onKey);
        return () => window.removeEventListener('keydown', onKey);
    }, [open, onClose]);

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
                aria-labelledby="pace-detail-title"
                className="relative flex max-h-[92vh] w-full max-w-lg flex-col overflow-hidden rounded-t-[24px] border border-slate-200/80 bg-white shadow-2xl dark:border-slate-700/60 dark:bg-slate-900 sm:rounded-[24px]"
            >
                <header
                    className="flex items-start justify-between gap-3 border-b border-slate-200/80 px-5 py-4 dark:border-slate-700/60"
                    style={{ background: `linear-gradient(135deg, ${accentColor} 0%, #0f172a 100%)` }}
                >
                    <div className="min-w-0">
                        <p className="text-[10px] font-bold uppercase tracking-[0.16em] text-white/60">{t('paceAnalytics')}</p>
                        <h2 id="pace-detail-title" className="text-lg font-bold text-white">
                            {t('paceDetailTitle')}
                        </h2>
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

                <div className="flex-1 space-y-4 overflow-y-auto p-4 sm:p-5">
                    {/* Avg pace */}
                    <section className="rounded-2xl border border-slate-200/80 bg-slate-50 p-4 dark:border-slate-700/60 dark:bg-slate-800/50">
                        <div className="flex items-center gap-2 text-[10px] font-bold uppercase tracking-wider text-slate-500 dark:text-slate-400">
                            <Timer size={12} />
                            {t('avgPaceLabel')}
                        </div>
                        <p className="mt-2 text-3xl font-black tabular-nums text-slate-900 dark:text-slate-100">
                            {formatAvgPaceSec(stats.avg)}
                            {paceUnit && (
                                <span className="ml-1 text-sm font-semibold text-slate-500 dark:text-slate-400">
                                    {paceUnit}/{roundLabel}
                                </span>
                            )}
                        </p>
                        <div className="mt-3 grid grid-cols-3 gap-2">
                            {stats.min != null && (
                                <div className="rounded-xl bg-emerald-50 px-2 py-2 text-center dark:bg-emerald-500/10">
                                    <p className="text-[9px] font-bold text-emerald-700 dark:text-emerald-300">{t('fastest')}</p>
                                    <p className="text-sm font-black tabular-nums text-emerald-900 dark:text-emerald-100">
                                        {Math.round(stats.min)} {t('secUnit')}
                                    </p>
                                </div>
                            )}
                            {stats.max != null && (
                                <div className="rounded-xl bg-amber-50 px-2 py-2 text-center dark:bg-amber-500/10">
                                    <p className="text-[9px] font-bold text-amber-700 dark:text-amber-300">{t('slowest')}</p>
                                    <p className="text-sm font-black tabular-nums text-amber-900 dark:text-amber-100">
                                        {Math.round(stats.max)} {t('secUnit')}
                                    </p>
                                </div>
                            )}
                            {stats.last != null && (
                                <div className="rounded-xl bg-slate-100 px-2 py-2 text-center dark:bg-slate-700/50">
                                    <p className="text-[9px] font-bold text-slate-600 dark:text-slate-300">{t('latestLabel')}</p>
                                    <p className="text-sm font-black tabular-nums text-slate-900 dark:text-slate-100">
                                        {Math.round(stats.last)} {t('secUnit')}
                                    </p>
                                </div>
                            )}
                        </div>
                    </section>

                    {/* Pace vs yesterday */}
                    <section className="rounded-2xl border border-slate-200/80 bg-slate-50 p-4 dark:border-slate-700/60 dark:bg-slate-800/50">
                        <div className="flex items-center gap-2 text-[10px] font-bold uppercase tracking-wider text-slate-500 dark:text-slate-400">
                            <TrendingDown size={12} />
                            {t('paceVsYesterday')}
                        </div>
                        <p className="mt-2 text-lg font-bold text-slate-800 dark:text-slate-100">{paceDelta.text}</p>
                        {comparison.todayAvgSec != null && comparison.yesterdayAvgSec != null && (
                            <p className="mt-1 text-xs text-slate-500 dark:text-slate-400">
                                {t('todayLabel')}: {Math.round(comparison.todayAvgSec)} {t('secUnit')} · {t('yesterdayLabel')}:{' '}
                                {Math.round(comparison.yesterdayAvgSec)} {t('secUnit')}
                            </p>
                        )}
                    </section>

                    {/* Total rounds */}
                    <section className="rounded-2xl border border-slate-200/80 bg-slate-50 p-4 dark:border-slate-700/60 dark:bg-slate-800/50">
                        <div className="flex items-center justify-between gap-2">
                            <div className="flex items-center gap-2 text-[10px] font-bold uppercase tracking-wider text-slate-500 dark:text-slate-400">
                                <BarChart2 size={12} />
                                {t('totalRounds')}
                            </div>
                            {roundsPct != null && (
                                <span
                                    className={`rounded-md px-1.5 py-0.5 text-[9px] font-bold tabular-nums ${
                                        roundsPct > 0
                                            ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-500/15 dark:text-emerald-300'
                                            : roundsPct < 0
                                              ? 'bg-rose-100 text-rose-700 dark:bg-rose-500/15 dark:text-rose-300'
                                              : 'bg-slate-200 text-slate-600 dark:bg-slate-700 dark:text-slate-300'
                                    }`}
                                >
                                    {roundsSign}
                                    {Math.round(roundsPct)}%
                                </span>
                            )}
                        </div>
                        <div className="mt-3 grid grid-cols-2 gap-3">
                            <div className="rounded-xl bg-white px-3 py-2 dark:bg-slate-900">
                                <p className="text-[9px] font-bold text-slate-400">{t('todayLabel')}</p>
                                <p className="text-xl font-black tabular-nums text-slate-900 dark:text-slate-100">
                                    {formatDashboardMetric(comparison.todayRounds)}
                                </p>
                            </div>
                            <div className="rounded-xl bg-white px-3 py-2 dark:bg-slate-900">
                                <p className="text-[9px] font-bold text-slate-400">{t('yesterdayLabel')}</p>
                                <p className="text-xl font-black tabular-nums text-slate-600 dark:text-slate-300">
                                    {formatDashboardMetric(comparison.yesterdayRounds)}
                                </p>
                            </div>
                        </div>
                    </section>

                    {/* Work hours */}
                    {workSummary && (
                        <section className="rounded-2xl border border-slate-200/80 bg-slate-50 p-4 dark:border-slate-700/60 dark:bg-slate-800/50">
                            <div className="flex items-center gap-2 text-[10px] font-bold uppercase tracking-wider text-slate-500 dark:text-slate-400">
                                <Clock size={12} />
                                {mode === 'sand' ? t('workTime') : t('workTimeFleet')}
                            </div>
                            <p className="mt-2 text-2xl font-black tabular-nums text-slate-900 dark:text-slate-100">
                                {formatActiveHours(workSummary.totalActiveHours, locale)}
                            </p>
                            <p className="mt-1 text-xs text-slate-500 dark:text-slate-400">
                                {t('targetHours', { hours: WORK_TARGET_HOURS })}
                            </p>
                            {workSummary.startClock && workSummary.endClock && (
                                <p className="mt-1 text-sm font-semibold text-slate-700 dark:text-slate-200">
                                    {workSummary.startClock} – {workSummary.endClock}
                                </p>
                            )}
                        </section>
                    )}

                    {/* Per-vehicle pace (trip only) */}
                    {mode === 'trip' && vehiclePaceRows.length > 0 && (
                        <section className="rounded-2xl border border-slate-200/80 bg-slate-50 p-4 dark:border-slate-700/60 dark:bg-slate-800/50">
                            <div className="flex items-center gap-2 text-[10px] font-bold uppercase tracking-wider text-slate-500 dark:text-slate-400">
                                <Truck size={12} />
                                {t('perVehiclePace')}
                            </div>
                            <ul className="mt-3 space-y-2">
                                {vehiclePaceRows.map((row) => (
                                    <li
                                        key={row.vehicleId}
                                        className="flex items-center justify-between gap-2 rounded-xl bg-white px-3 py-2 dark:bg-slate-900"
                                    >
                                        <span className="truncate text-xs font-bold text-slate-800 dark:text-slate-200">
                                            {row.vehicleId}
                                        </span>
                                        <span className="shrink-0 text-xs font-semibold tabular-nums text-slate-500 dark:text-slate-400">
                                            {row.avg != null ? `${Math.round(row.avg)} ${t('secUnit')}` : '—'} · {row.rounds}{' '}
                                            {roundLabel}
                                        </span>
                                    </li>
                                ))}
                            </ul>
                        </section>
                    )}
                </div>
            </div>
        </div>
    );
};

export default CountRecordPaceDetailModal;
