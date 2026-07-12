import { TrendingDown, TrendingUp, Minus, Clock, BarChart2, Timer } from 'lucide-react';
import { useShareLocale } from '../Share/shareI18n';
import {
    formatActiveHours,
    formatAvgPaceSec,
    formatAvgPaceUnit,
    formatPaceDelta,
    type DayModeComparison,
    type IntervalStats,
    type SandWorkDurationSummary,
} from './countRecordAnalytics';
import { formatDashboardMetric } from './countRecordUtils';

interface CountRecordStatTilesProps {
    stats: IntervalStats;
    comparison: DayModeComparison;
    roundLabel: string;
    sparkline: number[];
    accentColor: string;
    mode: 'sand' | 'trip';
    sandWorkSummary?: SandWorkDurationSummary | null;
    tripWorkSummary?: SandWorkDurationSummary | null;
    onOpenDetail?: () => void;
}

const WORK_TARGET_HOURS = 8;

function MiniSparkline({ values, color }: { values: number[]; color: string }) {
    if (values.length < 2) {
        return <div className="h-8 w-full rounded-lg bg-white/10" />;
    }
    const w = 100;
    const h = 32;
    const max = Math.max(...values, 1);
    const coords = values.map((v, i) => ({
        x: (i / (values.length - 1)) * w,
        y: h - (v / max) * h,
    }));
    const line = coords.map((c) => `${c.x},${c.y}`).join(' ');
    return (
        <svg viewBox={`0 0 ${w} ${h}`} className="h-8 w-full" preserveAspectRatio="none">
            <polyline points={line} fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" opacity="0.9" />
        </svg>
    );
}

function PaceGauge({ pct, color }: { pct: number | null; color: string }) {
    const { locale } = useShareLocale();
    const { faster } = formatPaceDelta(pct, locale);
    const abs = pct != null ? Math.min(Math.abs(Math.round(pct)), 100) : 0;
    const sweep = (abs / 100) * 180;
    const gaugeColor = faster === true ? '#34d399' : faster === false ? '#fbbf24' : '#94a3b8';
    const Icon = faster === true ? TrendingDown : faster === false ? TrendingUp : Minus;

    return (
        <div className="relative flex h-16 items-end justify-center">
            <svg viewBox="0 0 100 56" className="h-14 w-24 gauge-sweep">
                <path d="M 8 50 A 42 42 0 0 1 92 50" fill="none" stroke="rgba(255,255,255,0.15)" strokeWidth="8" strokeLinecap="round" />
                <path
                    d="M 8 50 A 42 42 0 0 1 92 50"
                    fill="none"
                    stroke={gaugeColor}
                    strokeWidth="8"
                    strokeLinecap="round"
                    strokeDasharray={`${(sweep / 180) * 132} 132`}
                    style={{ filter: `drop-shadow(0 0 6px ${gaugeColor}66)` }}
                />
            </svg>
            <div className="absolute bottom-0 flex flex-col items-center">
                <div className="flex items-center gap-0.5">
                    <Icon size={12} style={{ color: gaugeColor }} />
                    <span className="text-lg font-black tabular-nums leading-none text-white">
                        {pct != null ? `${abs}%` : '—'}
                    </span>
                </div>
            </div>
        </div>
    );
}

function CompareBars({ today, yesterday, color }: { today: number; yesterday: number; color: string }) {
    const { t } = useShareLocale();
    const max = Math.max(today, yesterday, 1);
    const todayPct = (today / max) * 100;
    const yesterdayPct = (yesterday / max) * 100;
    return (
        <div className="mt-2 space-y-2">
            <div className="space-y-1">
                <div className="flex items-center justify-between text-[9px] font-semibold text-white/70">
                    <span>{t('todayLabel')}</span>
                    <span className="tabular-nums text-white">{formatDashboardMetric(today)}</span>
                </div>
                <div className="h-2 overflow-hidden rounded-full bg-black/20">
                    <div
                        className="chart-bar-grow h-full rounded-full"
                        style={{ width: `${todayPct}%`, backgroundColor: color }}
                    />
                </div>
            </div>
            <div className="space-y-1">
                <div className="flex items-center justify-between text-[9px] font-semibold text-white/50">
                    <span>{t('yesterdayLabel')}</span>
                    <span className="tabular-nums">{formatDashboardMetric(yesterday)}</span>
                </div>
                <div className="h-2 overflow-hidden rounded-full bg-black/20">
                    <div
                        className="chart-bar-grow h-full rounded-full bg-white/30"
                        style={{ width: `${yesterdayPct}%` }}
                    />
                </div>
            </div>
        </div>
    );
}

function WorkRing({ hours, targetHours, color }: { hours: number; targetHours: number; color: string }) {
    const pct = Math.min(hours / targetHours, 1);
    const circumference = 2 * Math.PI * 28;
    const offset = circumference * (1 - pct);
    return (
        <div className="relative flex h-16 w-16 items-center justify-center">
            <svg viewBox="0 0 64 64" className="h-16 w-16 -rotate-90 gauge-sweep">
                <circle cx="32" cy="32" r="28" fill="none" stroke="rgba(255,255,255,0.12)" strokeWidth="6" />
                <circle
                    cx="32"
                    cy="32"
                    r="28"
                    fill="none"
                    stroke={color}
                    strokeWidth="6"
                    strokeLinecap="round"
                    strokeDasharray={circumference}
                    strokeDashoffset={offset}
                    style={{ filter: `drop-shadow(0 0 4px ${color}88)` }}
                />
            </svg>
            <span className="absolute text-xs font-black tabular-nums text-white">
                {Math.round(pct * 100)}%
            </span>
        </div>
    );
}

const CountRecordStatTiles = ({
    stats,
    comparison,
    roundLabel,
    sparkline,
    accentColor,
    mode,
    sandWorkSummary,
    tripWorkSummary,
    onOpenDetail,
}: CountRecordStatTilesProps) => {
    const { t, locale } = useShareLocale();
    const paceUnit = formatAvgPaceUnit(stats.avg, locale);
    const roundsPct = comparison.roundsDeltaPct;
    const roundsSign = roundsPct != null && roundsPct > 0 ? '+' : '';
    const workSummary = mode === 'sand' ? sandWorkSummary : tripWorkSummary;

    const tileBtn =
        'press-pop relative w-full overflow-hidden rounded-2xl p-3 text-left text-white shadow-lg transition-transform active:scale-[0.97] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/40 sm:p-3.5';

    return (
        <div className="space-y-2">
            <p className="text-center text-[9px] font-medium text-slate-400 dark:text-slate-500 sm:text-left">{t('tapForDetail')}</p>
            <div className="grid grid-cols-2 gap-2 sm:grid-cols-4 sm:gap-3">
                {/* Avg pace + sparkline */}
                <button
                    type="button"
                    onClick={onOpenDetail}
                    className={tileBtn}
                    style={{ background: `linear-gradient(145deg, ${accentColor} 0%, #0f172a 100%)` }}
                >
                    <div className="absolute -right-4 -top-4 h-16 w-16 rounded-full bg-white/10 blur-xl" />
                    <div className="relative">
                        <div className="flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wider text-white/70">
                            <Timer size={11} />
                            {t('avgPaceLabel')}
                        </div>
                        <div className="mt-1 flex items-baseline gap-1">
                            <span className="text-2xl font-black tabular-nums leading-none sm:text-3xl">
                                {formatAvgPaceSec(stats.avg)}
                            </span>
                            {paceUnit && <span className="text-xs font-semibold text-white/70">{paceUnit}/{roundLabel}</span>}
                        </div>
                        <div className="mt-2">
                            <MiniSparkline values={sparkline} color="#fef08a" />
                        </div>
                        {stats.last != null && (
                            <p className="mt-1 text-[9px] font-medium text-white/50">
                                {t('lastPace', { sec: Math.round(stats.last) })}
                            </p>
                        )}
                    </div>
                </button>

                {/* Pace vs yesterday gauge */}
                <button type="button" onClick={onOpenDetail} className={`${tileBtn} bg-gradient-to-br from-slate-800 to-slate-950`}>
                    <div className="flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wider text-white/60">
                        <TrendingDown size={11} />
                        {t('paceVsYesterday')}
                    </div>
                    <PaceGauge pct={comparison.paceDeltaPct} color={accentColor} />
                    <p className="mt-0.5 text-center text-[9px] font-medium text-white/50">
                        {formatPaceDelta(comparison.paceDeltaPct, locale).text}
                    </p>
                </button>

                {/* Today vs yesterday bars */}
                <button type="button" onClick={onOpenDetail} className={`${tileBtn} bg-gradient-to-br from-indigo-900 to-slate-950`}>
                    <div className="flex items-center justify-between gap-1">
                        <div className="flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wider text-white/60">
                            <BarChart2 size={11} />
                            {t('totalRounds')}
                        </div>
                        {roundsPct != null && (
                            <span
                                className={`rounded-md px-1.5 py-0.5 text-[9px] font-bold tabular-nums ${
                                    roundsPct > 0 ? 'bg-emerald-500/20 text-emerald-300' : roundsPct < 0 ? 'bg-rose-500/20 text-rose-300' : 'bg-white/10 text-white/60'
                                }`}
                            >
                                {roundsSign}{Math.round(roundsPct)}%
                            </span>
                        )}
                    </div>
                    <CompareBars today={comparison.todayRounds} yesterday={comparison.yesterdayRounds} color={accentColor} />
                </button>

                {/* Work hours ring (sand/trip) or min/max range fallback */}
                {workSummary ? (
                    <button
                        type="button"
                        onClick={onOpenDetail}
                        className={tileBtn}
                        style={{
                            background:
                                mode === 'sand'
                                    ? 'linear-gradient(145deg, #be185d 0%, #0f172a 100%)'
                                    : `linear-gradient(145deg, ${accentColor} 0%, #0f172a 100%)`,
                        }}
                    >
                        <div className="flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wider text-white/70">
                            <Clock size={11} />
                            {mode === 'sand' ? t('workTime') : t('workTimeFleet')}
                        </div>
                        <div className="mt-1 flex items-center gap-3">
                            <WorkRing
                                hours={workSummary.totalActiveHours}
                                targetHours={WORK_TARGET_HOURS}
                                color={mode === 'sand' ? '#f9a8d4' : '#93c5fd'}
                            />
                            <div>
                                <p className="text-lg font-black tabular-nums leading-none">
                                    {formatActiveHours(workSummary.totalActiveHours, locale)}
                                </p>
                                <p className="mt-1 text-[9px] font-medium text-white/50">
                                    {t('targetHours', { hours: WORK_TARGET_HOURS })}
                                </p>
                                {workSummary.startClock && workSummary.endClock && (
                                    <p className="text-[9px] text-white/60">
                                        {workSummary.startClock} – {workSummary.endClock}
                                    </p>
                                )}
                            </div>
                        </div>
                    </button>
                ) : (
                    <button type="button" onClick={onOpenDetail} className={`${tileBtn} bg-gradient-to-br from-slate-700 to-slate-950`}>
                        <div className="flex items-center gap-1.5 text-[10px] font-bold uppercase tracking-wider text-white/60">
                            <Clock size={11} />
                            {t('workSpan')}
                        </div>
                        <div className="mt-2 space-y-2">
                            {stats.min != null && (
                                <div className="flex items-center justify-between rounded-lg bg-white/5 px-2 py-1.5">
                                    <span className="text-[9px] font-semibold text-emerald-300">{t('fastest')}</span>
                                    <span className="text-sm font-black tabular-nums">{Math.round(stats.min)} {t('secUnit')}</span>
                                </div>
                            )}
                            {stats.max != null && (
                                <div className="flex items-center justify-between rounded-lg bg-white/5 px-2 py-1.5">
                                    <span className="text-[9px] font-semibold text-amber-300">{t('slowest')}</span>
                                    <span className="text-sm font-black tabular-nums">{Math.round(stats.max)} {t('secUnit')}</span>
                                </div>
                            )}
                        </div>
                    </button>
                )}
            </div>
        </div>
    );
};

export default CountRecordStatTiles;
