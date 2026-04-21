import { useMemo, useState, useRef, useCallback } from 'react';
import { Coins, Wallet, Droplets, Truck, TrendingUp, AlertTriangle, Calendar } from 'lucide-react';
import Card from '../../components/ui/Card';
import DonutChartSimple from '../../components/charts/DonutChart';
import BarChart from '../../components/charts/BarChart';
import LineChart from '../../components/charts/LineChart';
import FormatNumber from '../../components/ui/FormatNumber';
import { Transaction } from '../../types';

interface StatCardProps {
    title: string;
    value: number;
    icon: any;
    color: string;
    subValue?: string;
    unit?: string;
}

export const StatCard = ({ title, value, icon: Icon, color, subValue, unit = '฿' }: StatCardProps) => (
    <Card className="p-4 sm:p-5 flex flex-col justify-between min-h-[110px] sm:h-32 relative overflow-hidden">
        <div className={`absolute top-0 right-0 p-3 opacity-10`}><Icon size={80} color={color} /></div>
        <div className="flex items-center gap-2 text-slate-500 dark:text-slate-400 mb-1"><Icon size={18} color={color} /> <span className="text-sm font-medium">{title}</span></div>
        <div>
            <h3 className="text-2xl sm:text-3xl font-bold text-slate-800 dark:text-white break-words">
                {unit === '฿' ? <FormatNumber value={value} /> : <>{value.toLocaleString()} {unit}</>}
            </h3>
            {subValue && <p className="text-xs text-slate-400 dark:text-slate-500 mt-1">{subValue}</p>}
        </div>
        <div className="h-1 w-full bg-slate-100 dark:bg-white/10 mt-auto rounded-full overflow-hidden"><div className="h-full rounded-full" style={{ width: '60%', backgroundColor: color }}></div></div>
    </Card>
);

// ─── Interactive Sand Chart ─────────────────────────────────────────────
interface InteractiveChartProps {
    wData: number[]; tData: number[]; labels: string[];
    maxV: number; minV: number; range: number; days: number;
    filtered: Transaction[];
    dateStrings?: string[];
}

const InteractiveChart = ({ wData, tData, labels, maxV, days, filtered, dateStrings }: InteractiveChartProps) => {
    const [hoverIdx, setHoverIdx] = useState<number | null>(null);
    const [selectedIdx, setSelectedIdx] = useState<number | null>(null);
    const [tooltipPos, setTooltipPos] = useState({ x: 0, y: 0 });
    const svgRef = useRef<SVGSVGElement>(null);

    // Chart dimensions (in viewBox units)
    const W = 900, H = 320;
    const pad = { top: 24, right: 24, bottom: 44, left: 52 };
    const chartW = W - pad.left - pad.right;
    const chartH = H - pad.top - pad.bottom;
    const maxY = Math.ceil(maxV * 1.15) || 1;

    const getX = useCallback((i: number) => pad.left + (i / (days - 1)) * chartW, [days, chartW, pad.left]);
    const getY = useCallback((v: number) => pad.top + ((maxY - v) / maxY) * chartH, [maxY, chartH, pad.top]);

    const getDateStr = useCallback((dayIdx: number) => {
        if (dateStrings && dateStrings[dayIdx]) return dateStrings[dayIdx];
        const d = new Date();
        d.setDate(d.getDate() - (days - 1 - dayIdx));
        return d.toISOString().split('T')[0];
    }, [days, dateStrings]);

    const getDayTransactions = useCallback((dayIdx: number) => {
        const dateStr = getDateStr(dayIdx);
        return filtered.filter((t: Transaction) => t.date === dateStr);
    }, [filtered, getDateStr]);

    const getFullDate = useCallback((dateStr: string) => {
        if (!dateStr) return '';
        const d = new Date(dateStr + 'T12:00:00+07:00');
        return d.toLocaleDateString('th-TH', { timeZone: 'Asia/Bangkok', weekday: 'long', day: 'numeric', month: 'short', year: 'numeric' });
    }, []);

    const handleMouseMove = useCallback((e: React.MouseEvent<SVGSVGElement>) => {
        const svg = svgRef.current;
        if (!svg) return;
        const rect = svg.getBoundingClientRect();
        const scaleX = W / rect.width;
        const svgX = (e.clientX - rect.left) * scaleX;
        // Find nearest data point index
        let nearestIdx = 0;
        let nearestDist = Infinity;
        for (let i = 0; i < days; i++) {
            const dist = Math.abs(svgX - getX(i));
            if (dist < nearestDist) { nearestDist = dist; nearestIdx = i; }
        }
        if (nearestDist < chartW / (days - 1) * 0.6) {
            setHoverIdx(nearestIdx);
            setTooltipPos({ x: e.clientX - rect.left, y: e.clientY - rect.top });
        } else {
            setHoverIdx(null);
        }
    }, [days, getX, chartW, W]);

    const handleClick = useCallback(() => {
        if (hoverIdx !== null) {
            setSelectedIdx((prev: number | null) => prev === hoverIdx ? null : hoverIdx);
        }
    }, [hoverIdx]);

    // Build paths
    const wPoints = wData.map((v, i) => `${getX(i)},${getY(v)}`).join(' ');
    const tPoints = tData.map((v, i) => `${getX(i)},${getY(v)}`).join(' ');
    const wAreaPath = `M${getX(0)},${getY(wData[0])} ${wData.map((v, i) => `L${getX(i)},${getY(v)}`).join(' ')} L${getX(days - 1)},${pad.top + chartH} L${getX(0)},${pad.top + chartH} Z`;
    const tAreaPath = `M${getX(0)},${getY(tData[0])} ${tData.map((v, i) => `L${getX(i)},${getY(v)}`).join(' ')} L${getX(days - 1)},${pad.top + chartH} L${getX(0)},${pad.top + chartH} Z`;

    // Y-axis labels
    const ySteps = 4;
    const yLabels = Array.from({ length: ySteps + 1 }, (_, i) => Math.round((maxY / ySteps) * i));

    const selectedTrans = selectedIdx !== null ? getDayTransactions(selectedIdx) : [];
    const selectedDate = selectedIdx !== null ? getDateStr(selectedIdx) : '';

    return (
        <div>
            {/* Chart Container */}
            <div className="relative px-1 sm:px-2 h-[260px] sm:h-[300px]">
                <svg
                    ref={svgRef}
                    viewBox={`0 0 ${W} ${H}`}
                    preserveAspectRatio="xMidYMid meet"
                    width="100%" height="100%"
                    className="block cursor-crosshair select-none"
                    onMouseMove={handleMouseMove}
                    onMouseLeave={() => setHoverIdx(null)}
                    onClick={handleClick}
                >
                    <defs>
                        <linearGradient id="iwashGrad2" x1="0" y1="0" x2="0" y2="1">
                            <stop offset="0%" stopColor="#3b82f6" stopOpacity="0.25" />
                            <stop offset="100%" stopColor="#3b82f6" stopOpacity="0.02" />
                        </linearGradient>
                        <linearGradient id="itransGrad2" x1="0" y1="0" x2="0" y2="1">
                            <stop offset="0%" stopColor="#f59e0b" stopOpacity="0.18" />
                            <stop offset="100%" stopColor="#f59e0b" stopOpacity="0.02" />
                        </linearGradient>
                        <filter id="dotGlow">
                            <feGaussianBlur stdDeviation="2" result="blur" />
                            <feMerge><feMergeNode in="blur" /><feMergeNode in="SourceGraphic" /></feMerge>
                        </filter>
                    </defs>

                    {/* Background */}
                    <rect x={pad.left} y={pad.top} width={chartW} height={chartH}
                        fill="transparent" rx="4" />

                    {/* Horizontal grid + Y labels */}
                    {yLabels.map((val, i) => {
                        const y = getY(val);
                        return (
                            <g key={`y${i}`}>
                                <line x1={pad.left} y1={y} x2={pad.left + chartW} y2={y}
                                    stroke="#64748b" strokeWidth="0.5" strokeDasharray="6,4" opacity="0.15" />
                                <text x={pad.left - 10} y={y + 4} textAnchor="end"
                                    fill="#94a3b8" fontSize="11" fontFamily="sans-serif">{val}</text>
                            </g>
                        );
                    })}

                    {/* Vertical grid lines (subtle) */}
                    {labels.map((_, i) => (
                        <line key={`vg${i}`} x1={getX(i)} y1={pad.top} x2={getX(i)} y2={pad.top + chartH}
                            stroke="#64748b" strokeWidth="0.3" opacity="0.08" />
                    ))}

                    {/* X-axis labels */}
                    {labels.map((label, i) => (
                        <text key={`xl${i}`} x={getX(i)} y={H - 12} textAnchor="middle"
                            fill="#94a3b8" fontSize="12" fontFamily="sans-serif">{label}</text>
                    ))}

                    {/* Area fills */}
                    <path d={wAreaPath} fill="url(#iwashGrad2)" />
                    <path d={tAreaPath} fill="url(#itransGrad2)" />

                    {/* Lines with smooth rendering */}
                    <polyline points={wPoints} fill="none" stroke="#3b82f6" strokeWidth="2.5"
                        strokeLinecap="round" strokeLinejoin="round" />
                    <polyline points={tPoints} fill="none" stroke="#f59e0b" strokeWidth="2.5"
                        strokeLinecap="round" strokeLinejoin="round" />

                    {/* Hover vertical guide line */}
                    {hoverIdx !== null && (
                        <g>
                            <line x1={getX(hoverIdx)} y1={pad.top} x2={getX(hoverIdx)} y2={pad.top + chartH}
                                stroke="#6366f1" strokeWidth="1.2" opacity="0.4" strokeDasharray="5,3" />
                            {/* Highlight background column */}
                            <rect x={getX(hoverIdx) - chartW / days / 2} y={pad.top}
                                width={chartW / days} height={chartH}
                                fill="#6366f1" opacity="0.04" rx="4" />
                        </g>
                    )}

                    {/* Data points - wash (blue) */}
                    {wData.map((v, i) => (
                        <g key={`wd${i}`}>
                            {/* Outer glow on hover */}
                            {hoverIdx === i && (
                                <circle cx={getX(i)} cy={getY(v)} r="12"
                                    fill="#3b82f6" opacity="0.15" />
                            )}
                            <circle cx={getX(i)} cy={getY(v)}
                                r={hoverIdx === i ? 6.5 : selectedIdx === i ? 6 : 4}
                                fill={hoverIdx === i ? '#3b82f6' : '#fff'}
                                stroke="#3b82f6" strokeWidth="2.5" />
                            {/* Value label on hover */}
                            {hoverIdx === i && (
                                <text x={getX(i)} y={getY(v) - 12} textAnchor="middle"
                                    fill="#3b82f6" fontSize="11" fontWeight="bold" fontFamily="sans-serif">
                                    {v}
                                </text>
                            )}
                        </g>
                    ))}

                    {/* Data points - transport (amber) */}
                    {tData.map((v, i) => (
                        <g key={`td${i}`}>
                            {hoverIdx === i && (
                                <circle cx={getX(i)} cy={getY(v)} r="12"
                                    fill="#f59e0b" opacity="0.15" />
                            )}
                            <circle cx={getX(i)} cy={getY(v)}
                                r={hoverIdx === i ? 6.5 : selectedIdx === i ? 6 : 4}
                                fill={hoverIdx === i ? '#f59e0b' : '#fff'}
                                stroke="#f59e0b" strokeWidth="2.5" />
                            {hoverIdx === i && (
                                <text x={getX(i)} y={getY(v) + 18} textAnchor="middle"
                                    fill="#f59e0b" fontSize="11" fontWeight="bold" fontFamily="sans-serif">
                                    {v}
                                </text>
                            )}
                        </g>
                    ))}

                    {/* Selected indicator rings */}
                    {selectedIdx !== null && (
                        <g>
                            <circle cx={getX(selectedIdx)} cy={getY(wData[selectedIdx])} r="11"
                                fill="none" stroke="#3b82f6" strokeWidth="1.5" opacity="0.5" strokeDasharray="3,2" />
                            <circle cx={getX(selectedIdx)} cy={getY(tData[selectedIdx])} r="11"
                                fill="none" stroke="#f59e0b" strokeWidth="1.5" opacity="0.5" strokeDasharray="3,2" />
                        </g>
                    )}
                </svg>

                {/* Hover Tooltip — positioned relative to chart container */}
                {hoverIdx !== null && (
                    <div
                        className="absolute z-50 pointer-events-none transition-all duration-100 ease-out"
                        style={{
                            left: tooltipPos.x > (svgRef.current?.getBoundingClientRect().width || 600) * 0.65
                                ? tooltipPos.x - 210 : tooltipPos.x + 20,
                            top: Math.max(4, Math.min(tooltipPos.y - 60, 200)),
                        }}
                    >
                        <div className="bg-slate-900/95 backdrop-blur-lg text-white rounded-xl px-4 py-3 shadow-2xl border border-white/10 min-w-[190px]"
                            style={{ boxShadow: '0 8px 32px rgba(0,0,0,0.3), 0 0 0 1px rgba(255,255,255,0.05)' }}>
                            <div className="text-[11px] text-slate-400 mb-2.5 font-medium border-b border-white/10 pb-2">
                                📅 {getFullDate(getDateStr(hoverIdx))}
                            </div>
                            <div className="flex items-center gap-2.5 mb-2">
                                <div className="w-3 h-3 rounded-full bg-blue-500 shadow-sm shadow-blue-500/50" />
                                <span className="text-xs text-slate-300 flex-1">ล้างทราย</span>
                                <span className="text-sm font-bold text-blue-400">{wData[hoverIdx]} <span className="text-[10px] font-normal text-slate-500">คิว</span></span>
                            </div>
                            <div className="flex items-center gap-2.5 mb-2.5">
                                <div className="w-3 h-3 rounded-full bg-amber-500 shadow-sm shadow-amber-500/50" />
                                <span className="text-xs text-slate-300 flex-1">ขนทราย</span>
                                <span className="text-sm font-bold text-amber-400">{tData[hoverIdx]} <span className="text-[10px] font-normal text-slate-500">คิว</span></span>
                            </div>
                            <div className="border-t border-white/10 pt-2 flex justify-between items-center">
                                <span className="text-[11px] text-slate-500">ผลต่าง (ล้าง-ขน)</span>
                                <span className={`text-sm font-bold ${(wData[hoverIdx] - tData[hoverIdx]) >= 0 ? 'text-emerald-400' : 'text-red-400'}`}>
                                    {wData[hoverIdx] - tData[hoverIdx] >= 0 ? '+' : ''}{wData[hoverIdx] - tData[hoverIdx]} คิว
                                </span>
                            </div>
                            <div className="mt-2.5 text-[10px] text-center text-slate-500 bg-white/5 rounded-md py-1">
                                👆 คลิกเพื่อดูรายละเอียด
                            </div>
                        </div>
                    </div>
                )}
            </div>

            {/* Day Detail Panel (on click) */}
            {selectedIdx !== null && (
                <div className="mx-4 mb-4 mt-1 animate-fade-in">
                    <div className="bg-slate-50 dark:bg-white/[0.03] border border-slate-200 dark:border-white/[0.08] rounded-xl p-4 sm:p-5">
                        <div className="flex items-center justify-between mb-4">
                            <h4 className="font-bold text-slate-700 dark:text-slate-200 text-sm flex items-center gap-2">
                                📋 <span>{getFullDate(selectedDate)}</span>
                            </h4>
                            <button onClick={(e) => { e.stopPropagation(); setSelectedIdx(null); }}
                                className="text-xs text-slate-400 hover:text-red-500 transition-all px-2.5 py-1 rounded-lg hover:bg-red-50 dark:hover:bg-red-500/10 border border-transparent hover:border-red-200 dark:hover:border-red-500/20">
                                ✕ ปิด
                            </button>
                        </div>

                        {/* Summary cards */}
                        <div className="grid grid-cols-2 sm:grid-cols-3 gap-2 sm:gap-3 mb-4">
                            <div className="bg-blue-50 dark:bg-blue-500/10 rounded-xl p-3 text-center border border-blue-100 dark:border-blue-500/20">
                                <div className="text-xl font-bold text-blue-600">{wData[selectedIdx]}</div>
                                <div className="text-[10px] text-blue-500 mt-0.5">คิว ล้างทราย</div>
                            </div>
                            <div className="bg-amber-50 dark:bg-amber-500/10 rounded-xl p-3 text-center border border-amber-100 dark:border-amber-500/20">
                                <div className="text-xl font-bold text-amber-600">{tData[selectedIdx]}</div>
                                <div className="text-[10px] text-amber-500 mt-0.5">คิว ขนทราย</div>
                            </div>
                            <div className={`rounded-xl p-3 text-center border ${(wData[selectedIdx] - tData[selectedIdx]) >= 0
                                ? 'bg-emerald-50 dark:bg-emerald-500/10 border-emerald-100 dark:border-emerald-500/20'
                                : 'bg-red-50 dark:bg-red-500/10 border-red-100 dark:border-red-500/20'}`}>
                                <div className={`text-xl font-bold ${(wData[selectedIdx] - tData[selectedIdx]) >= 0 ? 'text-emerald-600' : 'text-red-600'}`}>
                                    {wData[selectedIdx] - tData[selectedIdx] >= 0 ? '+' : ''}{wData[selectedIdx] - tData[selectedIdx]}
                                </div>
                                <div className="text-[10px] text-slate-500 mt-0.5">คิว ผลต่าง</div>
                            </div>
                        </div>

                        {/* Transaction list */}
                        <div className="text-xs font-semibold text-slate-500 dark:text-slate-400 mb-2 flex items-center gap-1.5">
                            💳 รายการธุรกรรม ({selectedTrans.length} รายการ)
                        </div>
                        {selectedTrans.length > 0 ? (
                            <div className="space-y-1.5 max-h-52 overflow-y-auto hide-scrollbar">
                                {selectedTrans.map((t: Transaction, i: number) => (
                                    <div key={i} className="flex items-center justify-between bg-white dark:bg-white/[0.03] border border-slate-100 dark:border-white/[0.05] rounded-lg px-3 py-2.5 hover:bg-slate-50 dark:hover:bg-white/[0.05] transition-colors">
                                        <div className="flex items-center gap-2.5">
                                            <div className={`w-2.5 h-2.5 rounded-full ${t.type === 'Income' ? 'bg-emerald-500' : 'bg-red-500'}`} />
                                            <span className="text-xs text-slate-700 dark:text-slate-300 font-medium">{t.description}</span>
                                        </div>
                                        <div className="flex items-center gap-2">
                                            <span className="text-[10px] text-slate-400 px-1.5 py-0.5 bg-slate-100 dark:bg-white/[0.06] rounded-md">{t.category}</span>
                                            <span className={`text-xs font-bold ${t.type === 'Income' ? 'text-emerald-600' : 'text-red-500'}`}>
                                                {t.type === 'Income' ? '+' : '-'}฿{t.amount.toLocaleString()}
                                            </span>
                                        </div>
                                    </div>
                                ))}
                            </div>
                        ) : (
                            <div className="text-center py-8 text-slate-400 dark:text-slate-600 text-xs bg-white/50 dark:bg-white/[0.02] rounded-lg border border-dashed border-slate-200 dark:border-white/[0.06]">
                                📭 ไม่มีรายการธุรกรรมในวันนี้
                            </div>
                        )}
                    </div>
                </div>
            )}
        </div>
    );
};

const DashboardOverview = ({ transactions, dateFilter }: { transactions: Transaction[], dateFilter: any }) => {
    const start = new Date(dateFilter.start);
    const end = new Date(dateFilter.end);
    const filtered = transactions.filter(t => {
        const d = t.date.slice(0, 10);
        return d >= dateFilter.start && d <= dateFilter.end;
    });
    const income = filtered.filter(t => t.type === 'Income').reduce((s, t) => s + t.amount, 0);
    const expense = filtered.filter(t => t.type === 'Expense').reduce((s, t) => s + t.amount, 0);

    // จำนวนวันในช่วงที่เลือก
    const numDays = Math.max(1, Math.ceil((end.getTime() - start.getTime()) / (1000 * 60 * 60 * 24)) + 1);

    // Cost Breakdown — ครบทุกหมวด: ค่าแรง, รถ, น้ำมัน, ซ่อมบำรุง, ที่ดิน, งานประจำวัน (DailyLog)
    const categories = [
        { key: 'Labor', label: 'ค่าแรง', color: '#10b981' },
        { key: 'Vehicle', label: 'การใช้รถ', color: '#f59e0b' },
        { key: 'Fuel', label: 'น้ำมัน', color: '#ea580c' },
        { key: 'Maintenance', label: 'ซ่อมบำรุง', color: '#64748b' },
        { key: 'Land', label: 'ที่ดิน', color: '#8b5cf6' },
        { key: 'DailyLog', label: 'งานประจำวัน (เที่ยวรถ/ทราย/เหตุการณ์)', color: '#0ea5e9' },
    ];
    const catData = categories.map(({ key, label, color }) => {
        const value = key === 'DailyLog'
            ? filtered.filter(t => t.category === 'DailyLog' && t.type === 'Expense').reduce((s, t) => s + t.amount, 0)
            : filtered.filter(t => t.category === key && t.type === 'Expense').reduce((s, t) => s + t.amount, 0);
        return { label, value, color };
    }).filter(d => d.value > 0);

    // แนวโน้มรายจ่ายตามช่วงวันที่เลือก (แต่ละวัน)
    const dailyData = useMemo(() => {
        const out: number[] = [];
        const labels: string[] = [];
        for (let i = 0; i < numDays; i++) {
            const d = new Date(start);
            d.setDate(d.getDate() + i);
            const dateStr = d.toISOString().split('T')[0];
            if (dateStr > dateFilter.end) break;
            labels.push(`${d.getDate()}/${d.getMonth() + 1}`);
            out.push(filtered.filter(t => t.date.slice(0, 10) === dateStr && t.type === 'Expense').reduce((s, t) => s + t.amount, 0));
        }
        return { data: out, labels };
    }, [filtered, dateFilter, numDays, start]);

    // ==============================================
    // SAND ANALYTICS (ทรายล้าง / ทรายขน / ทรายคงเหลือ) — จากข้อมูล DailyLog จริง
    // ==============================================
    const sandAnalytics = useMemo(() => {
        const days = numDays;
        const sandWashedPerDay: number[] = [];
        const sandTransportedPerDay: number[] = [];
        const drumsObtainedPerDay: number[] = [];
        const drumsHomePerDay: number[] = [];
        const drumsRemainingCumulativePerDay: number[] = [];
        const dayLabels: string[] = [];

        const dateStrings: string[] = [];
        for (let i = 0; i < days; i++) {
            const d = new Date(start);
            d.setDate(d.getDate() + i);
            const dateStr = d.toISOString().split('T')[0];
            if (dateStr > dateFilter.end) break;
            dateStrings.push(dateStr);
            dayLabels.push(`${d.getDate()}/${d.getMonth() + 1}`);

            // ล้างทราย: จาก DailyLog subCategory Sand (sandMorning + sandAfternoon)
            const daySand = filtered.filter(t => t.date?.slice(0, 10) === dateStr && t.category === 'DailyLog' && t.subCategory === 'Sand');
            const washed = daySand.reduce((s, t) => s + (t.sandMorning || 0) + (t.sandAfternoon || 0), 0);
            sandWashedPerDay.push(washed);
            const drumsObtained = daySand.length > 0 ? Math.max(0, ...daySand.map(t => Number((t as any).drumsObtained || 0))) : 0;
            const drumsHome = daySand.length > 0 ? Math.max(0, ...daySand.map(t => Number((t as any).drumsWashedAtHome || 0))) : 0;
            drumsObtainedPerDay.push(drumsObtained);
            drumsHomePerDay.push(drumsHome);

            // ขนทราย: จาก DailyLog VehicleTrip (จำนวนเที่ยว * ประมาณคิวต่อเที่ยว) หรือ Vehicle
            const dayTrips = filtered.filter(t => t.date?.slice(0, 10) === dateStr && (t.category === 'DailyLog' && t.subCategory === 'VehicleTrip' || t.category === 'Vehicle'));
            const cubicPerTrip = 3;
            const transported = dayTrips.length * cubicPerTrip;
            sandTransportedPerDay.push(transported);
        }

        const totalWashed = sandWashedPerDay.reduce((s, v) => s + v, 0);
        const totalTransported = sandTransportedPerDay.reduce((s, v) => s + v, 0);
        const totalDrumsObtained = drumsObtainedPerDay.reduce((s, v) => s + v, 0);
        const totalDrumsHome = drumsHomePerDay.reduce((s, v) => s + v, 0);
        const avgWashedPerDay = days > 0 ? Math.round(totalWashed / days) : 0;
        const avgTransportedPerDay = days > 0 ? Math.round(totalTransported / days) : 0;
        const sandRemaining = totalWashed - totalTransported;
        const netPerDay = avgWashedPerDay - avgTransportedPerDay;
        let drumCum = 0;
        for (let i = 0; i < drumsObtainedPerDay.length; i++) {
            drumCum += Math.max(0, drumsObtainedPerDay[i] - drumsHomePerDay[i]);
            drumsRemainingCumulativePerDay.push(drumCum);
        }
        const drumsRemaining = drumsRemainingCumulativePerDay[drumsRemainingCumulativePerDay.length - 1] || 0;
        const daysRemaining = netPerDay > 0 ? '∞ (ผลิตเกินขน)' :
            netPerDay === 0 ? '0 (สมดุล)' :
                `${Math.max(0, Math.ceil(Math.abs(sandRemaining) / Math.abs(netPerDay)))} วัน`;

        return {
            sandWashedPerDay, sandTransportedPerDay, dayLabels, dateStrings,
            drumsObtainedPerDay, drumsHomePerDay, drumsRemainingCumulativePerDay,
            totalWashed, totalTransported, avgWashedPerDay, avgTransportedPerDay,
            sandRemaining, daysRemaining, netPerDay, totalDrumsObtained, totalDrumsHome, drumsRemaining
        };
    }, [filtered, dateFilter, numDays, start]);

    return (
        <div className="space-y-6 animate-fade-in">
            {/* Financial Summary */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                <StatCard title="กำไรสุทธิ (Net Profit)" value={income - expense} icon={Coins} color="#10b981" />
                <StatCard title="รายรับรวม (Income)" value={income} icon={Wallet} color="#3b82f6" />
                <StatCard title="รายจ่ายรวม (Expense)" value={expense} icon={Wallet} color="#ef4444" />
            </div>

            {/* Cost Breakdown + Expense Trend */}
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <Card className="p-4 sm:p-6 min-h-[320px] sm:h-80 flex flex-col justify-center items-center">
                    <h3 className="font-bold mb-4 w-full text-left text-slate-700 dark:text-slate-200">สัดส่วนค่าใช้จ่าย (Cost Breakdown)</h3>
                    <DonutChartSimple data={catData} />
                    <div className="flex flex-wrap gap-4 mt-4 justify-center">
                        {catData.map((c, i) => (
                            <div key={i} className="flex items-center gap-1 text-xs dark:text-slate-300">
                                <div className="w-2 h-2 rounded-full" style={{ background: c.color }} /> {c.label}
                            </div>
                        ))}
                    </div>
                </Card>
                <Card className="p-4 sm:p-6 min-h-[320px] sm:h-80">
                    <h3 className="font-bold mb-6 text-slate-700 dark:text-slate-200">แนวโน้มรายจ่าย ({numDays} วัน)</h3>
                    <BarChart data={dailyData.data} labels={dailyData.labels} color="#ef4444" />
                </Card>
            </div>

            {/* ======= SAND ANALYTICS SECTION ======= */}
            <div className="mt-2">
                <h2 className="text-lg font-bold text-slate-700 dark:text-slate-200 mb-4 flex items-center gap-2">
                    <Droplets size={22} className="text-blue-500" />
                    วิเคราะห์ทราย (Sand Analytics)
                </h2>
            </div>

            {/* Sand Stats Cards */}
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 xl:grid-cols-7 gap-4">
                <Card className="p-5 relative overflow-hidden">
                    <div className="absolute top-0 right-0 p-3 opacity-10"><Droplets size={70} color="#3b82f6" /></div>
                    <div className="flex items-center gap-2 text-blue-500 mb-2">
                        <Droplets size={18} />
                        <span className="text-sm font-medium">ล้างทรายรวม</span>
                    </div>
                    <h3 className="text-2xl font-bold text-slate-800 dark:text-white">{sandAnalytics.totalWashed.toLocaleString()} คิว</h3>
                    <p className="text-xs text-slate-400 dark:text-slate-500 mt-1">เฉลี่ย {sandAnalytics.avgWashedPerDay} คิว/วัน</p>
                </Card>

                <Card className="p-5 relative overflow-hidden">
                    <div className="absolute top-0 right-0 p-3 opacity-10"><Truck size={70} color="#f59e0b" /></div>
                    <div className="flex items-center gap-2 text-amber-500 mb-2">
                        <Truck size={18} />
                        <span className="text-sm font-medium">ขนทรายรวม</span>
                    </div>
                    <h3 className="text-2xl font-bold text-slate-800 dark:text-white">{sandAnalytics.totalTransported.toLocaleString()} คิว</h3>
                    <p className="text-xs text-slate-400 dark:text-slate-500 mt-1">เฉลี่ย {sandAnalytics.avgTransportedPerDay} คิว/วัน</p>
                </Card>

                <Card className="p-5 relative overflow-hidden">
                    <div className="absolute top-0 right-0 p-3 opacity-10"><TrendingUp size={70} color={sandAnalytics.sandRemaining >= 0 ? '#10b981' : '#ef4444'} /></div>
                    <div className="flex items-center gap-2 mb-2" style={{ color: sandAnalytics.sandRemaining >= 0 ? '#10b981' : '#ef4444' }}>
                        <TrendingUp size={18} />
                        <span className="text-sm font-medium">ทรายคงเหลือ</span>
                    </div>
                    <h3 className="text-2xl font-bold" style={{ color: sandAnalytics.sandRemaining >= 0 ? '#10b981' : '#ef4444' }}>
                        {sandAnalytics.sandRemaining.toLocaleString()} คิว
                    </h3>
                    <p className="text-xs text-slate-400 dark:text-slate-500 mt-1">ล้าง - ขน = คงเหลือ</p>
                </Card>

                <Card className="p-5 relative overflow-hidden">
                    <div className="absolute top-0 right-0 p-3 opacity-10"><Calendar size={70} color="#8b5cf6" /></div>
                    <div className="flex items-center gap-2 text-purple-500 mb-2">
                        {sandAnalytics.netPerDay < 0 ? <AlertTriangle size={18} className="text-amber-500" /> : <Calendar size={18} />}
                        <span className="text-sm font-medium">คาดการณ์</span>
                    </div>
                    <h3 className="text-xl font-bold text-slate-800 dark:text-white">{sandAnalytics.daysRemaining}</h3>
                    <p className="text-xs text-slate-400 dark:text-slate-500 mt-1">ทรายพอล้างอีก</p>
                </Card>
                <Card className="p-5 relative overflow-hidden">
                    <div className="absolute top-0 right-0 p-3 opacity-10"><Droplets size={70} color="#16a34a" /></div>
                    <div className="flex items-center gap-2 text-emerald-600 mb-2">
                        <Droplets size={18} />
                        <span className="text-sm font-medium">จำนวนถังที่ได้</span>
                    </div>
                    <h3 className="text-2xl font-bold text-emerald-700 dark:text-emerald-300">{sandAnalytics.totalDrumsObtained.toLocaleString()} ถัง</h3>
                    <p className="text-xs text-slate-400 dark:text-slate-500 mt-1">รวมในช่วงที่เลือก</p>
                </Card>
                <Card className="p-5 relative overflow-hidden">
                    <div className="absolute top-0 right-0 p-3 opacity-10"><Droplets size={70} color="#dc2626" /></div>
                    <div className="flex items-center gap-2 text-rose-600 mb-2">
                        <Droplets size={18} />
                        <span className="text-sm font-medium">ล้างที่บ้าน</span>
                    </div>
                    <h3 className="text-2xl font-bold text-rose-700 dark:text-rose-300">{sandAnalytics.totalDrumsHome.toLocaleString()} ถัง</h3>
                    <p className="text-xs text-slate-400 dark:text-slate-500 mt-1">รวมในช่วงที่เลือก</p>
                </Card>
                <Card className="p-5 relative overflow-hidden">
                    <div className="absolute top-0 right-0 p-3 opacity-10"><TrendingUp size={70} color="#0ea5e9" /></div>
                    <div className="flex items-center gap-2 text-sky-600 mb-2">
                        <TrendingUp size={18} />
                        <span className="text-sm font-medium">จำนวนถังคงเหลือ</span>
                    </div>
                    <h3 className="text-2xl font-bold text-sky-700 dark:text-sky-300">{sandAnalytics.drumsRemaining.toLocaleString()} ถัง</h3>
                    <p className="text-xs text-slate-400 dark:text-slate-500 mt-1">สะสมสุทธิ (ได้ - ล้างบ้าน)</p>
                </Card>
            </div>

            {/* Sand Charts */}
            <div className="grid grid-cols-1 gap-6">
                {/* Interactive Dual Line Chart */}
                <Card className="p-0 overflow-visible">
                    <div className="px-6 pt-6 flex flex-col sm:flex-row sm:items-center justify-between mb-2 gap-2">
                        <h3 className="font-bold text-slate-700 dark:text-slate-200">📈 กราฟเส้น: ล้างทราย vs ขนทราย ({sandAnalytics.dayLabels.length} วัน)</h3>
                        <div className="flex gap-4">
                            <span className="flex items-center gap-1.5 text-xs dark:text-slate-300">
                                <div className="w-8 h-[3px] rounded-full bg-blue-500" /> ล้างทราย
                            </span>
                            <span className="flex items-center gap-1.5 text-xs dark:text-slate-300">
                                <div className="w-8 h-[3px] rounded-full bg-amber-500" /> ขนทราย
                            </span>
                        </div>
                    </div>
                    {(() => {
                        const wData = sandAnalytics.sandWashedPerDay;
                        const tData = sandAnalytics.sandTransportedPerDay;
                        const labels = sandAnalytics.dayLabels;
                        const allVals = [...wData, ...tData];
                        const maxV = Math.max(...allVals, 1);
                        const minV = Math.min(...allVals, 0);
                        const range = maxV - minV || 1;
                        const days = 7;

                        return <InteractiveChart wData={wData} tData={tData} labels={labels} maxV={maxV} minV={minV} range={range} days={wData.length} filtered={filtered} dateStrings={sandAnalytics.dateStrings} />;
                    })()}

                    {/* Overall % Summary */}
                    <div className="px-6 pb-5 pt-3 flex gap-4 flex-wrap">
                        {(() => {
                            const wFirst = sandAnalytics.sandWashedPerDay[0] || 1;
                            const wLast = sandAnalytics.sandWashedPerDay[sandAnalytics.sandWashedPerDay.length - 1];
                            const tFirst = sandAnalytics.sandTransportedPerDay[0] || 1;
                            const tLast = sandAnalytics.sandTransportedPerDay[sandAnalytics.sandTransportedPerDay.length - 1];
                            const wPct = Math.round(((wLast - wFirst) / wFirst) * 100);
                            const tPct = Math.round(((tLast - tFirst) / tFirst) * 100);
                            return (
                                <>
                                    <div className="flex items-center gap-2 bg-blue-50 dark:bg-blue-500/10 px-4 py-2 rounded-xl">
                                        <Droplets size={16} className="text-blue-500" />
                                        <span className="text-xs text-blue-700 dark:text-blue-300">ล้างทราย {sandAnalytics.dayLabels.length} วัน:</span>
                                        <span className={`text-sm font-bold ${wPct >= 0 ? 'text-emerald-600' : 'text-red-500'}`}>
                                            {wPct > 0 ? '↑' : wPct < 0 ? '↓' : '−'}{Math.abs(wPct)}%
                                        </span>
                                    </div>
                                    <div className="flex items-center gap-2 bg-amber-50 dark:bg-amber-500/10 px-4 py-2 rounded-xl">
                                        <Truck size={16} className="text-amber-500" />
                                        <span className="text-xs text-amber-700 dark:text-amber-300">ขนทราย {sandAnalytics.dayLabels.length} วัน:</span>
                                        <span className={`text-sm font-bold ${tPct >= 0 ? 'text-emerald-600' : 'text-red-500'}`}>
                                            {tPct > 0 ? '↑' : tPct < 0 ? '↓' : '−'}{Math.abs(tPct)}%
                                        </span>
                                    </div>
                                </>
                            );
                        })()}
                    </div>
                </Card>
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                {/* Bar Comparison: Washed vs Transported */}
                <Card className="p-6">
                    <h3 className="font-bold mb-4 text-slate-700 dark:text-slate-200">เปรียบเทียบ: ล้างทราย vs ขนทราย ({sandAnalytics.dayLabels.length} วัน)</h3>
                    <div className="h-60">
                        <div className="flex gap-4 mb-3">
                            <span className="flex items-center gap-1 text-xs dark:text-slate-300"><div className="w-3 h-3 rounded-sm bg-blue-500" /> ล้างทราย (คิว)</span>
                            <span className="flex items-center gap-1 text-xs dark:text-slate-300"><div className="w-3 h-3 rounded-sm bg-amber-500" /> ขนทราย (คิว)</span>
                        </div>
                        <div className="flex items-end gap-2 h-48">
                            {sandAnalytics.dayLabels.map((label, i) => {
                                const maxVal = Math.max(...sandAnalytics.sandWashedPerDay, ...sandAnalytics.sandTransportedPerDay, 1);
                                const wH = (sandAnalytics.sandWashedPerDay[i] / maxVal) * 100;
                                const tH = (sandAnalytics.sandTransportedPerDay[i] / maxVal) * 100;
                                return (
                                    <div key={i} className="flex-1 flex flex-col items-center">
                                        <div className="w-full flex gap-0.5 items-end h-40">
                                            <div className="flex-1 bg-blue-500 rounded-t-md transition-all duration-500" style={{ height: `${wH}%` }} title={`ล้าง: ${sandAnalytics.sandWashedPerDay[i]} คิว`} />
                                            <div className="flex-1 bg-amber-500 rounded-t-md transition-all duration-500" style={{ height: `${tH}%` }} title={`ขน: ${sandAnalytics.sandTransportedPerDay[i]} คิว`} />
                                        </div>
                                        <span className="text-[10px] text-slate-400 dark:text-slate-500 mt-1">{label}</span>
                                    </div>
                                );
                            })}
                        </div>
                    </div>
                </Card>

                {/* Sand Production Trend Line */}
                <Card className="p-6">
                    <h3 className="font-bold mb-4 text-slate-700 dark:text-slate-200">ทรายคงเหลือสะสม (Cumulative)</h3>
                    <div className="h-60">
                        {(() => {
                            let cum = 0;
                            const cumData = sandAnalytics.sandWashedPerDay.map((w, i) => {
                                cum += w - sandAnalytics.sandTransportedPerDay[i];
                                return cum;
                            });
                            return (
                                <>
                                    <LineChart data={cumData} color={cum >= 0 ? '#10b981' : '#ef4444'} height={180} />
                                    <div className="flex justify-between mt-2">
                                        {sandAnalytics.dayLabels.map((l, i) => (
                                            <span key={i} className="text-[10px] text-slate-400 dark:text-slate-500">{l}</span>
                                        ))}
                                    </div>
                                    <div className="mt-3 flex gap-4 text-xs text-slate-500 dark:text-slate-400">
                                        <span>เริ่มต้น: 0 คิว</span>
                                        <span className={cum >= 0 ? 'text-emerald-600 font-bold' : 'text-red-500 font-bold'}>
                                            ปัจจุบัน: {cum.toLocaleString()} คิว
                                        </span>
                                    </div>
                                </>
                            );
                        })()}
                    </div>
                </Card>
            </div>
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <Card className="p-6">
                    <h3 className="font-bold mb-4 text-slate-700 dark:text-slate-200">กราฟรายวัน: ถังที่ได้ vs ล้างที่บ้าน</h3>
                    <div className="h-60">
                        <div className="flex gap-4 mb-3">
                            <span className="flex items-center gap-1 text-xs dark:text-slate-300"><div className="w-3 h-3 rounded-sm bg-emerald-500" /> ถังที่ได้</span>
                            <span className="flex items-center gap-1 text-xs dark:text-slate-300"><div className="w-3 h-3 rounded-sm bg-rose-500" /> ล้างที่บ้าน</span>
                        </div>
                        <div className="flex items-end gap-2 h-48">
                            {sandAnalytics.dayLabels.map((label, i) => {
                                const maxVal = Math.max(...sandAnalytics.drumsObtainedPerDay, ...sandAnalytics.drumsHomePerDay, 1);
                                const inH = (sandAnalytics.drumsObtainedPerDay[i] / maxVal) * 100;
                                const outH = (sandAnalytics.drumsHomePerDay[i] / maxVal) * 100;
                                return (
                                    <div key={i} className="flex-1 flex flex-col items-center">
                                        <div className="w-full flex gap-0.5 items-end h-40">
                                            <div className="flex-1 bg-emerald-500 rounded-t-md transition-all duration-500" style={{ height: `${inH}%` }} title={`ได้: ${sandAnalytics.drumsObtainedPerDay[i]} ถัง`} />
                                            <div className="flex-1 bg-rose-500 rounded-t-md transition-all duration-500" style={{ height: `${outH}%` }} title={`ล้างบ้าน: ${sandAnalytics.drumsHomePerDay[i]} ถัง`} />
                                        </div>
                                        <span className="text-[10px] text-slate-400 dark:text-slate-500 mt-1">{label}</span>
                                    </div>
                                );
                            })}
                        </div>
                    </div>
                </Card>
                <Card className="p-6">
                    <h3 className="font-bold mb-4 text-slate-700 dark:text-slate-200">กราฟสะสม: จำนวนถังคงเหลือ</h3>
                    <div className="h-60">
                        <LineChart data={sandAnalytics.drumsRemainingCumulativePerDay} color="#0ea5e9" height={180} />
                        <div className="flex justify-between mt-2">
                            {sandAnalytics.dayLabels.map((l, i) => (
                                <span key={i} className="text-[10px] text-slate-400 dark:text-slate-500">{l}</span>
                            ))}
                        </div>
                        <div className="mt-3 flex gap-4 text-xs text-slate-500 dark:text-slate-400">
                            <span>เริ่มต้น: 0 ถัง</span>
                            <span className="text-sky-700 dark:text-sky-300 font-bold">
                                คงเหลือสะสม: {sandAnalytics.drumsRemaining.toLocaleString()} ถัง
                            </span>
                        </div>
                    </div>
                </Card>
            </div>
        </div>
    );
};

export default DashboardOverview;
