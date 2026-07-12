import { useMemo, useState, type ReactNode } from 'react';
import { BarChart3, ChevronDown } from 'lucide-react';
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
    computeHourlyHeatmap,
    computeHourlySandSpeed,
    computeIntervalStats,
    computeLapIntervals,
    computeMinuteSandSpeed,
    computeMovingAverage,
    computeSandWorkDurationSummary,
    formatActiveHours,
    formatDurationSec,
    mergeTripLapTimeline,
    timelineToLapStamps,
} from './countRecordAnalytics';
import CountRecordStatTiles from './CountRecordStatTiles';

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
    movingAvgWindow = 5,
}: {
    values: number[];
    labels: string[];
    color: string;
    unit?: string;
    movingAvgWindow?: number;
}) {
    if (values.length === 0) {
        return (
            <p className="py-6 text-center text-xs font-medium text-slate-400">
                ต้องมีอย่างน้อย 2 รอบเพื่อวิเคราะห์ช่วงเวลา
            </p>
        );
    }
    const max = Math.max(...values, 1);
    const minVal = Math.min(...values);
    const maxVal = Math.max(...values);
    const movingAvg = computeMovingAverage(values, movingAvgWindow);
    const maPoints = movingAvg
        .map((v, i) => (v != null ? { x: i, y: v } : null))
        .filter((p): p is { x: number; y: number } => p != null);

    const chartH = 120;
    const chartW = 100;
    const maLine =
        maPoints.length >= 2
            ? maPoints
                  .map((p, i) => {
                      const x = (p.x / (values.length - 1)) * chartW;
                      const y = chartH - (p.y / max) * chartH;
                      return `${i === 0 ? 'M' : 'L'}${x},${y}`;
                  })
                  .join(' ')
            : '';

    return (
        <div className="relative">
            {maLine && (
                <svg
                    viewBox={`0 0 ${chartW} ${chartH}`}
                    className="pointer-events-none absolute inset-x-0 top-4 z-10 h-36 w-full px-1"
                    preserveAspectRatio="none"
                >
                    <path d={maLine} fill="none" stroke="#fbbf24" strokeWidth="1.5" strokeDasharray="3 2" opacity="0.85" />
                </svg>
            )}
            <div className="flex h-36 items-end justify-between gap-1.5 px-1 pt-4">
                {values.map((val, i) => {
                    const isMin = val === minVal && values.length > 1;
                    const isMax = val === maxVal && values.length > 1;
                    const barColor = isMin ? '#34d399' : isMax ? '#f87171' : color;
                    return (
                        <div key={i} className="group relative flex h-full min-w-0 flex-1 flex-col items-center justify-end">
                            <span className="mb-1 text-[9px] font-bold tabular-nums text-slate-500 opacity-0 transition-opacity group-hover:opacity-100">
                                {formatDurationSec(val)}
                            </span>
                            <div className="relative flex w-full flex-1 items-end overflow-hidden rounded-md bg-slate-100">
                                <div
                                    className="chart-bar-grow w-full rounded-t-md"
                                    style={{ height: `${(val / max) * 100}%`, backgroundColor: barColor }}
                                />
                            </div>
                            <span className="mt-1 w-full truncate text-center text-[9px] font-medium text-slate-400">
                                {labels[i]}
                            </span>
                            <span className="text-[8px] tabular-nums text-slate-300">{unit}</span>
                        </div>
                    );
                })}
            </div>
            <p className="mt-1 text-center text-[9px] text-slate-400">
                เส้นประ = ค่าเฉลี่ยเคลื่อนที่ {movingAvgWindow} รอบ · เขียว=เร็วสุด · แดง=ช้าสุด
            </p>
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

function HourlyHeatmap({ cells, color }: { cells: { hour: number; count: number; label: string; intensity: number }[]; color: string }) {
    const active = cells.filter((c) => c.count > 0);
    if (active.length === 0) {
        return (
            <p className="flex h-12 items-center justify-center text-xs font-medium text-slate-400">
                ยังไม่มีข้อมูลรายชั่วโมง
            </p>
        );
    }
    return (
        <div className="space-y-2">
            <div className="grid grid-cols-12 gap-0.5 sm:grid-cols-24">
                {cells.map((c) => (
                    <div
                        key={c.hour}
                        title={`${c.label}: ${c.count} รอบ`}
                        className="group relative aspect-square min-h-[10px] rounded-sm transition-transform hover:scale-110"
                        style={{
                            backgroundColor: c.count > 0 ? color : '#e2e8f0',
                            opacity: c.count > 0 ? 0.25 + c.intensity * 0.75 : 0.35,
                        }}
                    />
                ))}
            </div>
            <div className="flex justify-between text-[8px] text-slate-400">
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
    if (buckets.length === 0) {
        return (
            <p className="flex h-24 items-center justify-center text-xs font-medium text-slate-400">
                ยังไม่มีข้อมูลรายชั่วโมง
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
                        <span className="text-[8px] font-bold tabular-nums text-slate-500">{val}</span>
                        <div
                            className="chart-bar-grow w-full rounded-t-sm"
                            style={{ height: `${(val / max) * 72}px`, backgroundColor: color, minHeight: 4 }}
                        />
                        <span className="w-full truncate text-center text-[7px] text-slate-400">{b.label}</span>
                        {unitLabel && <span className="text-[7px] text-slate-300">{unitLabel}</span>}
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
    if (buckets.length === 0) {
        return (
            <p className="flex h-24 items-center justify-center text-xs font-medium text-slate-400">
                ยังไม่มีข้อมูลเวลาทำงาน
            </p>
        );
    }
    const max = Math.max(...buckets.map((b) => b.activeHours), 0.1);
    return (
        <div className="flex h-28 items-end justify-between gap-1 px-0.5">
            {buckets.map((b, i) => (
                <div key={i} className="flex min-w-0 flex-1 flex-col items-center justify-end gap-0.5">
                    <span className="text-[8px] font-bold tabular-nums text-slate-500">
                        {formatActiveHours(b.activeHours)}
                    </span>
                    <div
                        className="chart-bar-grow w-full rounded-t-md"
                        style={{ height: `${(b.activeHours / max) * 80}px`, backgroundColor: color, minHeight: 4 }}
                    />
                    <span className="w-full truncate text-center text-[7px] text-slate-400">{b.label}</span>
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
    if (buckets.length === 0) {
        return (
            <p className="flex h-24 items-center justify-center text-xs font-medium text-slate-400">
                ยังไม่มีข้อมูลรายนาที
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
                            <span className="w-full truncate text-center text-[6px] text-slate-400">{b.label}</span>
                        )}
                    </div>
                ))}
            </div>
            <p className="text-center text-[9px] text-slate-400">รอบ/นาที · เลื่อนดูรายละเอียด</p>
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
        <div className={`rounded-xl border border-slate-200/80 bg-white p-3 shadow-sm ${className}`}>
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

    const roundLabel = mode === 'sand' ? 'รอบ' : 'เที่ยว';
    const hasAnyLaps = lapTimes.length > 0;

    if (!hasAnyLaps && modeComparison.todayRounds <= 0) return null;

    return (
        <div className="mt-3 space-y-3 border-t border-slate-200/60 pt-3">
            <div className="flex items-center gap-2">
                <BarChart3 size={14} className="text-slate-400" style={{ color }} />
                <p className="text-[11px] font-bold uppercase tracking-[0.12em] text-slate-500">วิเคราะห์จังหวะ</p>
            </div>

            <CountRecordStatTiles
                stats={stats}
                comparison={modeComparison}
                roundLabel={roundLabel}
                sparkline={sparkline}
                accentColor={color}
                mode={mode}
                sandWorkSummary={sandWorkSummary}
            />

            {/* Bento grid */}
            <div className="grid grid-cols-1 gap-3 lg:grid-cols-12">
                <ChartBlock
                    title={`ช่วงเวลาระหว่าง${roundLabel} (หักพักเที่ยง)`}
                    className="lg:col-span-7"
                >
                    <IntervalBarChart values={intervals.intervalsSec} labels={intervals.labels} color={color} />
                </ChartBlock>

                <ChartBlock title="Heatmap รายชั่วโมง" className="lg:col-span-5">
                    <HourlyHeatmap cells={hourlyHeatmap} color={color} />
                </ChartBlock>

                <ChartBlock title={`ยอดสะสม${roundLabel}ตามเวลา`} className="lg:col-span-6">
                    <CumulativeLineChart points={cumulative} color={color} />
                </ChartBlock>

                <ChartBlock title={`จำนวน${roundLabel}ต่อชั่วโมง`} className="lg:col-span-6">
                    <HourlyBarChart buckets={hourly} color={color} />
                </ChartBlock>

                {mode === 'sand' && (
                    <>
                        <ChartBlock title="เวลาทำงานรายชั่วโมง (ชม.)" className="lg:col-span-6">
                            <WorkHoursBarChart buckets={hourlyActiveWork} color={color} />
                        </ChartBlock>
                        <ChartBlock title="ความเร็วร่อนต่อชั่วโมง (รอบ/ชม.)" className="lg:col-span-6">
                            <HourlyBarChart
                                buckets={hourlySandSpeed}
                                color={color}
                                valueKey="speed"
                                unitLabel="รอบ/ชม."
                            />
                        </ChartBlock>
                        <ChartBlock title="Timeline ความเร็วร่อนต่อนาที" className="lg:col-span-12">
                            <MinuteTimelineChart buckets={minuteSandSpeed} color={color} />
                        </ChartBlock>
                    </>
                )}
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
