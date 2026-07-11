import { useMemo, useState, type ReactNode } from 'react';
import { BarChart3, ChevronDown, Clock, TrendingDown, TrendingUp, Minus } from 'lucide-react';
import type { Employee, Transaction } from '../../types';
import {
    buildCountRecordSandUnit,
    buildCountRecordTripUnits,
    formatDashboardMetric,
} from './countRecordUtils';
import {
    buildDayComparison,
    computeCumulativeSeries,
    computeHourlyBuckets,
    computeIntervalStats,
    computeLapIntervals,
    formatDurationSec,
    formatPaceDelta,
    mergeTripLapTimeline,
    timelineToLapStamps,
    type DayModeComparison,
} from './countRecordAnalytics';

interface CountRecordAnalyticsPanelProps {
    mode: 'sand' | 'trip';
    dayKey: string;
    transactions: Transaction[];
    employees?: Employee[];
    accentColor?: string;
}

function IntervalBarChart({
    values,
    labels,
    color,
    unit = 'วิน.',
}: {
    values: number[];
    labels: string[];
    color: string;
    unit?: string;
}) {
    if (values.length === 0) {
        return (
            <p className="py-6 text-center text-xs font-medium text-slate-400">
                ต้องมีอย่างน้อย 2 รอบเพื่อวิเคราะห์ช่วงเวลา
            </p>
        );
    }
    const max = Math.max(...values, 1);
    return (
        <div className="flex h-36 items-end justify-between gap-1.5 px-1 pt-4">
            {values.map((val, i) => (
                <div key={i} className="group relative flex h-full min-w-0 flex-1 flex-col items-center justify-end">
                    <span className="mb-1 text-[9px] font-bold tabular-nums text-slate-500 opacity-0 transition-opacity group-hover:opacity-100">
                        {formatDurationSec(val)}
                    </span>
                    <div className="relative flex w-full flex-1 items-end overflow-hidden rounded-md bg-slate-100">
                        <div
                            className="w-full rounded-t-md transition-all duration-500"
                            style={{ height: `${(val / max) * 100}%`, backgroundColor: color }}
                        />
                    </div>
                    <span className="mt-1 w-full truncate text-center text-[9px] font-medium text-slate-400">
                        {labels[i]}
                    </span>
                    <span className="text-[8px] tabular-nums text-slate-300">{unit}</span>
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
    if (points.length < 2) {
        return (
            <p className="flex h-28 items-center justify-center text-xs font-medium text-slate-400">
                ต้องมีอย่างน้อย 2 รอบ
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
            <div className="mt-1 flex justify-between text-[9px] text-slate-400">
                <span>{points[0]?.label}</span>
                <span>{points[points.length - 1]?.label}</span>
            </div>
        </div>
    );
}

function HourlyBarChart({
    buckets,
    color,
}: {
    buckets: { label: string; count: number }[];
    color: string;
}) {
    if (buckets.length === 0) {
        return (
            <p className="flex h-24 items-center justify-center text-xs font-medium text-slate-400">
                ยังไม่มีข้อมูลรายชั่วโมง
            </p>
        );
    }
    const max = Math.max(...buckets.map((b) => b.count), 1);
    return (
        <div className="flex h-24 items-end justify-between gap-0.5 px-0.5">
            {buckets.map((b, i) => (
                <div key={i} className="flex min-w-0 flex-1 flex-col items-center justify-end gap-0.5">
                    <span className="text-[8px] font-bold tabular-nums text-slate-500">{b.count}</span>
                    <div
                        className="w-full rounded-t-sm"
                        style={{ height: `${(b.count / max) * 72}px`, backgroundColor: color, minHeight: 4 }}
                    />
                    <span className="w-full truncate text-center text-[7px] text-slate-400">{b.label}</span>
                </div>
            ))}
        </div>
    );
}

function PaceBadge({ comparison }: { comparison: DayModeComparison }) {
    const { text, faster } = formatPaceDelta(comparison.paceDeltaPct);
    const Icon = faster === true ? TrendingDown : faster === false ? TrendingUp : Minus;
    const cls =
        faster === true
            ? 'border-emerald-200 bg-emerald-50 text-emerald-800'
            : faster === false
              ? 'border-amber-200 bg-amber-50 text-amber-800'
              : 'border-slate-200 bg-slate-50 text-slate-600';

    return (
        <span className={`inline-flex items-center gap-1 rounded-lg border px-2 py-1 text-[10px] font-semibold ${cls}`}>
            <Icon size={11} />
            {text}
        </span>
    );
}

function RoundsDeltaBadge({ comparison }: { comparison: DayModeComparison }) {
    if (!comparison.hasYesterdayData || comparison.roundsDeltaPct == null) {
        return (
            <span className="inline-flex items-center gap-1 rounded-lg border border-slate-200 bg-slate-50 px-2 py-1 text-[10px] font-semibold text-slate-500">
                ยอดรวม: {formatDashboardMetric(comparison.todayRounds)} (ไม่มีข้อมูลเมื่อวาน)
            </span>
        );
    }
    const pct = Math.round(comparison.roundsDeltaPct);
    const sign = pct > 0 ? '+' : '';
    const cls =
        pct > 0 ? 'border-blue-200 bg-blue-50 text-blue-800' : pct < 0 ? 'border-rose-200 bg-rose-50 text-rose-800' : 'border-slate-200 bg-slate-50 text-slate-600';
    return (
        <span className={`inline-flex items-center gap-1 rounded-lg border px-2 py-1 text-[10px] font-semibold ${cls}`}>
            ยอดรวม {formatDashboardMetric(comparison.todayRounds)} ({sign}{pct}% vs เมื่อวาน {formatDashboardMetric(comparison.yesterdayRounds)})
        </span>
    );
}

function KpiRow({
    stats,
    comparison,
    roundLabel,
}: {
    stats: ReturnType<typeof computeIntervalStats>;
    comparison: DayModeComparison;
    roundLabel: string;
}) {
    return (
        <div className="flex flex-wrap gap-2">
            <span className="inline-flex items-center gap-1 rounded-lg border border-slate-200 bg-white px-2.5 py-1.5 text-[10px] font-semibold text-slate-700 shadow-sm">
                <Clock size={11} className="text-slate-400" />
                เฉลี่ย {formatDurationSec(stats.avg)}/{roundLabel}
            </span>
            {stats.last != null && (
                <span className="inline-flex items-center gap-1 rounded-lg border border-slate-200 bg-white px-2.5 py-1.5 text-[10px] font-semibold text-slate-700 shadow-sm">
                    รอบล่าสุดห่าง {formatDurationSec(stats.last)}
                </span>
            )}
            {stats.min != null && stats.max != null && stats.min !== stats.max && (
                <span className="inline-flex items-center gap-1 rounded-lg border border-slate-200 bg-white px-2.5 py-1.5 text-[10px] font-semibold text-slate-500 shadow-sm">
                    ต่ำสุด {formatDurationSec(stats.min)} · สูงสุด {formatDurationSec(stats.max)}
                </span>
            )}
            <PaceBadge comparison={comparison} />
            <RoundsDeltaBadge comparison={comparison} />
        </div>
    );
}

function ChartBlock({
    title,
    children,
}: {
    title: string;
    children: ReactNode;
}) {
    return (
        <div className="rounded-xl border border-slate-200/80 bg-white p-3 shadow-sm">
            <p className="mb-2 text-[10px] font-bold uppercase tracking-[0.1em] text-slate-400">{title}</p>
            {children}
        </div>
    );
}

function VehicleAccordion({
    vehicleId,
    lapTimes,
    dayKey,
    color,
    defaultOpen,
}: {
    vehicleId: string;
    lapTimes: string[];
    dayKey: string;
    color: string;
    defaultOpen?: boolean;
}) {
    const [open, setOpen] = useState(defaultOpen ?? false);
    const intervals = useMemo(() => computeLapIntervals(lapTimes, dayKey), [lapTimes, dayKey]);
    const stats = useMemo(() => computeIntervalStats(intervals.intervalsSec), [intervals]);

    if (lapTimes.length === 0) return null;

    return (
        <div className="overflow-hidden rounded-xl border border-slate-200/80 bg-white">
            <button
                type="button"
                onClick={() => setOpen((v) => !v)}
                className="flex w-full items-center justify-between gap-2 px-3 py-2.5 text-left transition hover:bg-slate-50"
            >
                <div className="min-w-0">
                    <p className="truncate text-xs font-bold text-slate-800">{vehicleId}</p>
                    <p className="text-[10px] font-medium text-slate-500">
                        {lapTimes.length} เที่ยว
                        {stats.avg != null ? ` · เฉลี่ย ${formatDurationSec(stats.avg)}/เที่ยว` : ''}
                    </p>
                </div>
                <ChevronDown size={16} className={`shrink-0 text-slate-400 transition-transform ${open ? 'rotate-180' : ''}`} />
            </button>
            {open && (
                <div className="border-t border-slate-100 px-3 pb-3 pt-2">
                    <IntervalBarChart values={intervals.intervalsSec} labels={intervals.labels} color={color} />
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
    const hourly = useMemo(() => computeHourlyBuckets(lapTimes, dayKey), [lapTimes, dayKey]);
    const cumulative = useMemo(() => computeCumulativeSeries(lapTimes, dayKey), [lapTimes, dayKey]);

    const roundLabel = mode === 'sand' ? 'รอบ' : 'เที่ยว';
    const hasAnyLaps = lapTimes.length > 0;

    if (!hasAnyLaps && modeComparison.todayRounds <= 0) return null;

    return (
        <div className="mt-3 space-y-3 border-t border-slate-200/60 pt-3">
            <div className="flex items-center gap-2">
                <BarChart3 size={14} className="text-slate-400" style={{ color }} />
                <p className="text-[11px] font-bold uppercase tracking-[0.12em] text-slate-500">วิเคราะห์จังหวะ</p>
            </div>

            <KpiRow stats={stats} comparison={modeComparison} roundLabel={roundLabel} />

            <ChartBlock title={`ช่วงเวลาระหว่าง${roundLabel} (วินาที)`}>
                <IntervalBarChart values={intervals.intervalsSec} labels={intervals.labels} color={color} />
            </ChartBlock>

            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                <ChartBlock title={`ยอดสะสม${roundLabel}ตามเวลา`}>
                    <CumulativeLineChart points={cumulative} color={color} />
                </ChartBlock>
                <ChartBlock title={`จำนวน${roundLabel}ต่อชั่วโมง`}>
                    <HourlyBarChart buckets={hourly} color={color} />
                </ChartBlock>
            </div>

            {mode === 'trip' && tripUnits.filter((u) => u.lapTimes.length > 0).length > 0 && (
                <div className="space-y-2">
                    <p className="text-[10px] font-bold uppercase tracking-[0.1em] text-slate-400">แยกต่อคัน</p>
                    {tripUnits
                        .filter((u) => u.lapTimes.length > 0)
                        .map((u, i) => (
                            <VehicleAccordion
                                key={u.id}
                                vehicleId={u.vehicleId}
                                lapTimes={u.lapTimes}
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
