import { useMemo, useState, useCallback, useRef } from 'react';
import {
    Target,
    TrendingUp,
    TrendingDown,
    Scale,
    Wallet,
    PiggyBank,
    BarChart3,
    Info,
} from 'lucide-react';
import Card from '../../components/ui/Card';
import FormatNumber from '../../components/ui/FormatNumber';
import { StatCard } from './DashboardOverview';
import { Transaction } from '../../types';

type DateFilter = { start: string; end: string };

function countInclusiveDays(startStr: string, endStr: string): number {
    const a = new Date(startStr + 'T12:00:00+07:00');
    const b = new Date(endStr + 'T12:00:00+07:00');
    return Math.max(1, Math.round((b.getTime() - a.getTime()) / (86400000)) + 1);
}

function shiftDateStr(dateStr: string, deltaDays: number): string {
    const d = new Date(dateStr + 'T12:00:00+07:00');
    d.setDate(d.getDate() + deltaDays);
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
}

function getPreviousPeriodFilter(filter: DateFilter): DateFilter {
    const n = countInclusiveDays(filter.start, filter.end);
    const prevEnd = shiftDateStr(filter.start, -1);
    const prevStart = shiftDateStr(prevEnd, -(n - 1));
    return { start: prevStart, end: prevEnd };
}

function filterByRange(transactions: Transaction[], range: DateFilter): Transaction[] {
    return transactions.filter((t) => {
        const d = t.date.slice(0, 10);
        return d >= range.start && d <= range.end;
    });
}

function aggregateFinancial(transactions: Transaction[]) {
    const income = transactions.filter((t) => t.type === 'Income').reduce((s, t) => s + t.amount, 0);
    const expense = transactions.filter((t) => t.type === 'Expense').reduce((s, t) => s + t.amount, 0);
    return { income, expense, profit: income - expense };
}

function buildDailyPoints(transactions: Transaction[], filter: DateFilter) {
    const n = countInclusiveDays(filter.start, filter.end);
    const points: { date: string; label: string; income: number; expense: number; profit: number }[] = [];
    for (let i = 0; i < n; i++) {
        const dateStr = shiftDateStr(filter.start, i);
        if (dateStr > filter.end) break;
        const dayTx = transactions.filter((t) => t.date.slice(0, 10) === dateStr);
        const income = dayTx.filter((t) => t.type === 'Income').reduce((s, t) => s + t.amount, 0);
        const expense = dayTx.filter((t) => t.type === 'Expense').reduce((s, t) => s + t.amount, 0);
        const d = new Date(dateStr + 'T12:00:00+07:00');
        const label = `${d.getDate()}/${d.getMonth() + 1}`;
        points.push({ date: dateStr, label, income, expense, profit: income - expense });
    }
    return points;
}

function buildDailyAggregateIndex(transactions: Transaction[]) {
    const byDate: Record<string, { income: number; expense: number; washed: number; transported: number; entries: number }> = {};
    transactions.forEach((t) => {
        const dateStr = t.date.slice(0, 10);
        if (!byDate[dateStr]) {
            byDate[dateStr] = { income: 0, expense: 0, washed: 0, transported: 0, entries: 0 };
        }
        const day = byDate[dateStr];
        day.entries += 1;
        if (t.type === 'Income') day.income += t.amount;
        if (t.type === 'Expense') day.expense += t.amount;
        if (t.category === 'DailyLog' && t.subCategory === 'Sand') {
            day.washed += (t.sandMorning || 0) + (t.sandAfternoon || 0);
        }
        if ((t.category === 'DailyLog' && t.subCategory === 'VehicleTrip') || t.category === 'Vehicle') {
            day.transported += 3;
        }
    });
    return byDate;
}

function marginPercent(fin: { income: number; profit: number }): number {
    if (fin.income > 0) return (fin.profit / fin.income) * 100;
    return fin.profit > 0 ? 100 : 0;
}

function expenseToIncomeRatio(fin: { income: number; expense: number }): number {
    if (fin.income > 0) return (fin.expense / fin.income) * 100;
    return fin.expense > 0 ? 100 : 0;
}

/** อัตราส่วนล้างต่อ max(ล้าง,ขน) — เหมือนฐานคะแนนสมดุลทราย */
function sandBalanceRatio(washed: number, transported: number): number {
    const sandTotal = washed + transported;
    if (sandTotal <= 0) return 0;
    return (washed / Math.max(washed, transported)) * 100;
}

/** % เปลี่ยนแปลงเทียบค่าก่อนหน้า (ค่าปัจจุบัน vs ค่าช่วงก่อน) */
function pctChangeVsPrev(cur: number, prev: number): number | null {
    if (prev === 0 && cur === 0) return 0;
    if (prev === 0) return null;
    return ((cur - prev) / Math.abs(prev)) * 100;
}

/** คะแนนรวม 0–100 + รายการย่อยพร้อม % เปรียบเทียบช่วงก่อน */
function computeCompositeScore(args: {
    cur: { income: number; expense: number; profit: number };
    prev: { income: number; expense: number; profit: number };
    sandWashed: number;
    sandTransported: number;
    prevSandWashed: number;
    prevSandTransported: number;
}): {
    score: number;
    breakdown: {
        label: string;
        weight: string;
        scorePart: number;
        changeLabel: string;
        trend: 'up' | 'down' | 'flat' | 'neutral';
        tooltip: string;
    }[];
} {
    const { cur, prev, sandWashed, sandTransported, prevSandWashed, prevSandTransported } = args;

    const marginScore =
        cur.income > 0 ? Math.max(0, Math.min(100, (cur.profit / cur.income) * 100)) : cur.profit > 0 ? 100 : 0;

    let growthScore = 50;
    if (prev.profit !== 0) {
        const ch = ((cur.profit - prev.profit) / Math.abs(prev.profit)) * 50;
        growthScore = Math.max(0, Math.min(100, 50 + ch));
    } else if (cur.profit > 0) {
        growthScore = 85;
    }

    const expenseRatio = cur.income > 0 ? (cur.expense / cur.income) * 100 : cur.expense > 0 ? 100 : 0;
    const costControlScore = Math.max(0, Math.min(100, 100 - expenseRatio * 0.6));

    const sandTotal = sandWashed + sandTransported;
    const sandScore =
        sandTotal <= 0 ? 70 : Math.max(0, Math.min(100, (sandWashed / Math.max(sandWashed, sandTransported)) * 100));

    const wM = 0.35;
    const wG = 0.25;
    const wC = 0.25;
    const wS = 0.15;
    const score = Math.round(marginScore * wM + growthScore * wG + costControlScore * wC + sandScore * wS);

    const curM = marginPercent(cur);
    const prevM = marginPercent(prev);
    const deltaMarginPp = curM - prevM;

    const profitDeltaPct = pctChangeVsPrev(cur.profit, prev.profit);

    const curEI = expenseToIncomeRatio(cur);
    const prevEI = expenseToIncomeRatio(prev);
    const costRatioDeltaPct = pctChangeVsPrev(curEI, prevEI);

    const curSandR = sandBalanceRatio(sandWashed, sandTransported);
    const prevSandR = sandBalanceRatio(prevSandWashed, prevSandTransported);
    const sandDeltaPct = pctChangeVsPrev(curSandR, prevSandR);

    const fmtSignedPct = (n: number | null, invertGood?: boolean) => {
        if (n === null) return { text: 'ไม่มีฐานเทียบ', trend: 'neutral' as const };
        const abs = Math.abs(n);
        const rounded = abs >= 10 ? Math.round(n) : Math.round(n * 10) / 10;
        const sign = rounded > 0 ? '+' : rounded < 0 ? '−' : '';
        const good = invertGood ? rounded < 0 : rounded > 0;
        const bad = invertGood ? rounded > 0 : rounded < 0;
        return {
            text: `${sign}${Math.abs(rounded)}% เทียบช่วงก่อน`,
            trend: rounded === 0 ? ('flat' as const) : good ? ('up' as const) : bad ? ('down' as const) : ('flat' as const),
        };
    };

    const marginChange = (() => {
        const rounded =
            Math.abs(deltaMarginPp) >= 10 ? Math.round(deltaMarginPp) : Math.round(deltaMarginPp * 10) / 10;
        const sign = rounded >= 0 ? '+' : '−';
        const good = deltaMarginPp > 0;
        return {
            text: `${sign}${Math.abs(rounded)} พ.ค. เทียบช่วงก่อน`,
            trend: rounded === 0 ? ('flat' as const) : good ? ('up' as const) : ('down' as const),
        };
    })();

    const profitChangeStr = profitDeltaPct === null ? { text: 'ไม่มีฐานเทียบกำไร', trend: 'neutral' as const } : fmtSignedPct(profitDeltaPct, false);
    const costChangeStr =
        costRatioDeltaPct === null ? { text: 'ไม่มีฐานเทียบสัดส่วน', trend: 'neutral' as const } : fmtSignedPct(costRatioDeltaPct, true);
    const sandChangeStr =
        sandDeltaPct === null ? { text: 'ไม่มีฐานเทียบอัตราทราย', trend: 'neutral' as const } : fmtSignedPct(sandDeltaPct, false);

    return {
        score: Math.max(0, Math.min(100, score)),
        breakdown: [
            {
                label: 'ความคุ้มทุน (อัตรากำไรต่อรายรับ)',
                weight: '35%',
                scorePart: Math.round(marginScore),
                changeLabel: marginChange.text,
                trend: marginChange.trend,
                tooltip:
                    `ช่วงนี้: อัตรากำไร ${curM.toFixed(1)}% (กำไร ${cur.profit.toLocaleString()} บ. / รายรับ ${cur.income.toLocaleString()} บ.)\n` +
                    `ช่วงก่อน: ${prevM.toFixed(1)}% (กำไร ${prev.profit.toLocaleString()} บ. / รายรับ ${prev.income.toLocaleString()} บ.)\n` +
                    `การเปลี่ยนแปลง: ${deltaMarginPp >= 0 ? '+' : ''}${deltaMarginPp.toFixed(1)} พอยต์เปอร์เซ็นต์ (พ.ค.) เทียบช่วงก่อน`,
            },
            {
                label: 'เทียบกำไรช่วงก่อน',
                weight: '25%',
                scorePart: Math.round(growthScore),
                changeLabel: profitChangeStr.text,
                trend: profitChangeStr.trend,
                tooltip:
                    `กำไรช่วงนี้: ${cur.profit.toLocaleString()} บ.\n` +
                    `กำไรช่วงก่อน: ${prev.profit.toLocaleString()} บ.\n` +
                    (profitDeltaPct === null
                        ? 'ไม่สามารถคิด % เปลี่ยนแปลงได้เมื่อฐานเป็น 0'
                        : `เปลี่ยนแปลง: ${profitDeltaPct >= 0 ? '+' : ''}${Math.round(profitDeltaPct * 10) / 10}% ของกำไรช่วงก่อน`),
            },
            {
                label: 'ควบคุมต้นทุนต่อรายรับ',
                weight: '25%',
                scorePart: Math.round(costControlScore),
                changeLabel: costChangeStr.text,
                trend: costChangeStr.trend,
                tooltip:
                    `อัตรารายจ่ายต่อรายรับ — ช่วงนี้: ${curEI.toFixed(1)}% (${cur.expense.toLocaleString()} / ${cur.income.toLocaleString() || '—'})\n` +
                    `ช่วงก่อน: ${prevEI.toFixed(1)}%\n` +
                    (costRatioDeltaPct === null
                        ? 'เทียบ % ไม่ได้เมื่อฐานเป็น 0'
                        : `ดีขึ้นเมื่อค่า % ลดลง (ต้นทุนต่อบาทรายรับลด)`),
            },
            {
                label: 'สมดุลทราย (ล้าง vs ขน)',
                weight: '15%',
                scorePart: Math.round(sandScore),
                changeLabel: sandChangeStr.text,
                trend: sandChangeStr.trend,
                tooltip:
                    `ช่วงนี้ — ล้าง ${sandWashed.toLocaleString()} คิว, ขน ${sandTransported.toLocaleString()} คิว (อัตราสมดุล ${curSandR.toFixed(1)}%)\n` +
                    `ช่วงก่อน — ล้าง ${prevSandWashed.toLocaleString()} คิว, ขน ${prevSandTransported.toLocaleString()} คิว (${prevSandR.toFixed(1)}%)\n` +
                    (sandDeltaPct === null ? '' : `เปลี่ยนแปลงอัตราสมดุล: ${sandDeltaPct >= 0 ? '+' : ''}${Math.round(sandDeltaPct * 10) / 10}% เทียบช่วงก่อน`),
            },
        ],
    };
}

interface ScatterProfitProps {
    points: { label: string; date: string; income: number; expense: number; profit: number }[];
}

const BreakEvenScatter = ({ points }: ScatterProfitProps) => {
    const [hover, setHover] = useState<number | null>(null);
    const svgRef = useRef<SVGSVGElement>(null);
    const W = 880;
    const H = 420;
    const pad = { top: 28, right: 28, bottom: 48, left: 56 };

    const maxVal = useMemo(() => {
        let m = 1;
        for (const p of points) {
            m = Math.max(m, p.income, p.expense);
        }
        return m * 1.12;
    }, [points]);

    const chartW = W - pad.left - pad.right;
    const chartH = H - pad.top - pad.bottom;

    const x = useCallback((v: number) => pad.left + (v / maxVal) * chartW, [maxVal, chartW, pad.left]);
    const y = useCallback((v: number) => pad.top + chartH - (v / maxVal) * chartH, [maxVal, chartH, pad.top]);

    const lineEnd = maxVal;

    const handleMove = useCallback(
        (e: React.MouseEvent<SVGSVGElement>) => {
            const svg = svgRef.current;
            if (!svg || points.length === 0) return;
            const rect = svg.getBoundingClientRect();
            const scale = W / rect.width;
            const mx = (e.clientX - rect.left) * scale;
            const my = (e.clientY - rect.top) * scale;
            let best = -1;
            let bestD = 24;
            points.forEach((p, i) => {
                const px = x(p.expense);
                const py = y(p.income);
                const d = Math.hypot(mx - px, my - py);
                if (d < bestD) {
                    bestD = d;
                    best = i;
                }
            });
            setHover(best >= 0 ? best : null);
        },
        [points, x, y]
    );

    const yTicks = 5;
    const tickVals = Array.from({ length: yTicks + 1 }, (_, i) => (maxVal / yTicks) * i);

    return (
        <div className="relative">
            <svg
                ref={svgRef}
                viewBox={`0 0 ${W} ${H}`}
                className="w-full h-[min(420px,70vh)] select-none"
                onMouseMove={handleMove}
                onMouseLeave={() => setHover(null)}
            >
                <defs>
                    <linearGradient id="beLine" x1="0" y1="1" x2="1" y2="0">
                        <stop offset="0%" stopColor="#94a3b8" stopOpacity="0.4" />
                        <stop offset="100%" stopColor="#94a3b8" stopOpacity="0.8" />
                    </linearGradient>
                </defs>
                <text x={W / 2} y={18} textAnchor="middle" className="fill-slate-500 dark:fill-slate-400" fontSize="12">
                    แกน X = รายจ่ายรายวัน · แกน Y = รายรับรายวัน · เส้นทแยง = จุดคุ้มทุน (รายรับ = รายจ่าย)
                </text>
                {tickVals.map((v, i) => {
                    const yy = y(v);
                    return (
                        <g key={`gy${i}`}>
                            <line
                                x1={pad.left}
                                y1={yy}
                                x2={pad.left + chartW}
                                y2={yy}
                                stroke="#64748b"
                                strokeWidth="0.6"
                                opacity="0.12"
                            />
                            <text x={pad.left - 8} y={yy + 4} textAnchor="end" fontSize="10" className="fill-slate-400">
                                {Math.round(v).toLocaleString()}
                            </text>
                        </g>
                    );
                })}
                {tickVals.map((v, i) => {
                    const xx = x(v);
                    return (
                        <g key={`gx${i}`}>
                            <line
                                x1={xx}
                                y1={pad.top}
                                x2={xx}
                                y2={pad.top + chartH}
                                stroke="#64748b"
                                strokeWidth="0.6"
                                opacity="0.12"
                            />
                            <text x={xx} y={H - 18} textAnchor="middle" fontSize="10" className="fill-slate-400">
                                {Math.round(v).toLocaleString()}
                            </text>
                        </g>
                    );
                })}
                <text
                    x={pad.left + chartW / 2}
                    y={H - 4}
                    textAnchor="middle"
                    fontSize="11"
                    className="fill-slate-600 dark:fill-slate-300"
                >
                    รายจ่าย (บาท)
                </text>
                <text
                    x={14}
                    y={pad.top + chartH / 2}
                    textAnchor="middle"
                    fontSize="11"
                    className="fill-slate-600 dark:fill-slate-300"
                    transform={`rotate(-90 14 ${pad.top + chartH / 2})`}
                >
                    รายรับ (บาท)
                </text>
                <line
                    x1={x(0)}
                    y1={y(0)}
                    x2={x(lineEnd)}
                    y2={y(lineEnd)}
                    stroke="url(#beLine)"
                    strokeWidth="2"
                    strokeDasharray="8 6"
                />
                {points.map((p, i) => {
                    const cx = x(p.expense);
                    const cy = y(p.income);
                    const profit = p.profit >= 0;
                    const r = hover === i ? 9 : 6;
                    return (
                        <g key={`pt${i}`}>
                            <circle
                                cx={cx}
                                cy={cy}
                                r={r + 6}
                                fill={profit ? '#22c55e' : '#ef4444'}
                                opacity={hover === i ? 0.2 : 0.08}
                            />
                            <circle
                                cx={cx}
                                cy={cy}
                                r={r}
                                fill={profit ? '#16a34a' : '#dc2626'}
                                stroke="#fff"
                                strokeWidth="1.5"
                            />
                        </g>
                    );
                })}
            </svg>
            {hover !== null && points[hover] ? (
                <div className="absolute top-10 right-2 sm:right-6 bg-white/95 dark:bg-slate-900/95 border border-slate-200 dark:border-white/10 rounded-xl px-3 py-2 text-xs shadow-lg max-w-[260px] z-10">
                    <div className="font-semibold text-slate-700 dark:text-slate-200">
                        {new Date(points[hover].date + 'T12:00:00+07:00').toLocaleDateString('th-TH', {
                            weekday: 'short',
                            day: 'numeric',
                            month: 'short',
                            year: 'numeric',
                            timeZone: 'Asia/Bangkok',
                        })}
                    </div>
                    <div className="text-[10px] text-slate-400 mt-0.5">รหัสวันที่ {points[hover].date}</div>
                    <div className="mt-2 space-y-0.5 text-slate-600 dark:text-slate-300 border-t border-slate-100 dark:border-white/10 pt-2">
                        <div>
                            รายรับ (แกน Y): <span className="font-mono">฿{points[hover].income.toLocaleString()}</span>
                        </div>
                        <div>
                            รายจ่าย (แกน X): <span className="font-mono">฿{points[hover].expense.toLocaleString()}</span>
                        </div>
                        <div className={points[hover].profit >= 0 ? 'text-emerald-600 font-bold' : 'text-red-500 font-bold'}>
                            ผลต่าง (รายรับ − รายจ่าย): ฿{points[hover].profit.toLocaleString()}
                        </div>
                        <div className="text-[10px] text-slate-500 pt-1">
                            เหนือเส้นประทแยง y = x → รายรับ {'>'} รายจ่าย (วันนี้มีกำไรรายวัน)
                        </div>
                    </div>
                </div>
            ) : null}
            <div className="flex flex-wrap gap-4 text-[11px] text-slate-500 dark:text-slate-400 px-2 pb-2">
                <span className="flex items-center gap-1.5">
                    <span className="w-3 h-3 rounded-full bg-emerald-600" /> วันที่มีกำไร (เหนือเส้นคุ้มทุน)
                </span>
                <span className="flex items-center gap-1.5">
                    <span className="w-3 h-3 rounded-full bg-red-600" /> วันขาดทุน (ใต้เส้นคุ้มทุน)
                </span>
            </div>
        </div>
    );
};

const DashboardV5 = ({ transactions, dateFilter }: { transactions: Transaction[]; dateFilter: DateFilter }) => {
    const [showScoreFormula, setShowScoreFormula] = useState(false);
    const filtered = useMemo(() => filterByRange(transactions, dateFilter), [transactions, dateFilter]);
    const prevFilter = useMemo(() => getPreviousPeriodFilter(dateFilter), [dateFilter]);
    const prevFiltered = useMemo(() => filterByRange(transactions, prevFilter), [transactions, prevFilter]);
    const dailyIndex = useMemo(() => buildDailyAggregateIndex(transactions), [transactions]);

    const curFin = useMemo(() => aggregateFinancial(filtered), [filtered]);
    const prevFin = useMemo(() => aggregateFinancial(prevFiltered), [prevFiltered]);

    const numDays = countInclusiveDays(dateFilter.start, dateFilter.end);

    const sandTotals = useMemo(() => {
        let washed = 0;
        let transported = 0;
        for (let i = 0; i < numDays; i++) {
            const dateStr = shiftDateStr(dateFilter.start, i);
            if (dateStr > dateFilter.end) break;
            const day = dailyIndex[dateStr];
            if (!day) continue;
            washed += day.washed;
            transported += day.transported;
        }
        return { washed, transported };
    }, [dailyIndex, dateFilter, numDays]);

    const prevSandTotals = useMemo(() => {
        const prevN = countInclusiveDays(prevFilter.start, prevFilter.end);
        let washed = 0;
        let transported = 0;
        for (let i = 0; i < prevN; i++) {
            const dateStr = shiftDateStr(prevFilter.start, i);
            if (dateStr > prevFilter.end) break;
            const day = dailyIndex[dateStr];
            if (!day) continue;
            washed += day.washed;
            transported += day.transported;
        }
        return { washed, transported };
    }, [dailyIndex, prevFilter]);

    const dailyPoints = useMemo(() => buildDailyPoints(transactions, dateFilter), [transactions, dateFilter]);

    const dataQuality = useMemo(() => {
        const n = countInclusiveDays(dateFilter.start, dateFilter.end);
        let daysWithRecords = 0;
        let daysWithSandRecords = 0;
        for (let i = 0; i < n; i++) {
            const dateStr = shiftDateStr(dateFilter.start, i);
            if (dateStr > dateFilter.end) break;
            const day = dailyIndex[dateStr];
            if (day && day.entries > 0) {
                daysWithRecords += 1;
                if (day.washed > 0 || day.transported > 0) daysWithSandRecords += 1;
            }
        }
        const coveragePct = n > 0 ? Math.round((daysWithRecords / n) * 100) : 0;
        const sandCoveragePct = n > 0 ? Math.round((daysWithSandRecords / n) * 100) : 0;
        let qualityLabel = 'ต้องระวัง';
        if (coveragePct >= 80) qualityLabel = 'ดี';
        else if (coveragePct >= 50) qualityLabel = 'ปานกลาง';
        return { totalDays: n, daysWithRecords, daysWithSandRecords, coveragePct, sandCoveragePct, qualityLabel };
    }, [dailyIndex, dateFilter]);

    const composite = useMemo(
        () =>
            computeCompositeScore({
                cur: curFin,
                prev: prevFin,
                sandWashed: sandTotals.washed,
                sandTransported: sandTotals.transported,
                prevSandWashed: prevSandTotals.washed,
                prevSandTransported: prevSandTotals.transported,
            }),
        [curFin, prevFin, sandTotals, prevSandTotals]
    );

    const profitChangePct =
        prevFin.profit !== 0
            ? Math.round(((curFin.profit - prevFin.profit) / Math.abs(prevFin.profit)) * 100)
            : curFin.profit > 0
              ? 100
              : 0;

    const marginPct = curFin.income > 0 ? Math.round((curFin.profit / curFin.income) * 1000) / 10 : 0;
    const prevMarginPct = prevFin.income > 0 ? Math.round((prevFin.profit / prevFin.income) * 1000) / 10 : 0;

    const deltaIncomePct = pctChangeVsPrev(curFin.income, prevFin.income);
    const deltaExpensePct = pctChangeVsPrev(curFin.expense, prevFin.expense);
    const deltaWashedPct = pctChangeVsPrev(sandTotals.washed, prevSandTotals.washed);
    const deltaTransportPct = pctChangeVsPrev(sandTotals.transported, prevSandTotals.transported);

    const fmtTableDelta = (v: number | null) => {
        if (v === null) return '—';
        const r = Math.abs(v) >= 10 ? Math.round(v) : Math.round(v * 10) / 10;
        return `${r >= 0 ? '+' : ''}${r}%`;
    };

    const keyInsights = useMemo(() => {
        const insights: string[] = [];
        if (deltaExpensePct !== null && deltaExpensePct >= 12) {
            insights.push(`รายจ่ายเพิ่มขึ้น ${Math.round(deltaExpensePct)}% เทียบช่วงก่อน ควรเช็กหมวดต้นทุนที่เร่งตัว`);
        }
        if (deltaIncomePct !== null && deltaIncomePct <= -10) {
            insights.push(`รายรับลดลง ${Math.abs(Math.round(deltaIncomePct))}% เทียบช่วงก่อน ควรติดตามรายการรายรับหลัก`);
        }
        if (sandTotals.washed > sandTotals.transported) {
            const diff = sandTotals.washed - sandTotals.transported;
            insights.push(`ทรายล้างมากกว่าทรายขน ${diff.toLocaleString()} คิว อาจเกิดคงค้างสะสม`);
        } else if (sandTotals.transported > sandTotals.washed) {
            const diff = sandTotals.transported - sandTotals.washed;
            insights.push(`ทรายขนเร็วกว่าอัตราล้าง ${diff.toLocaleString()} คิว ควรเช็กสต็อกเพื่อไม่ให้ขาดช่วง`);
        }
        if (dataQuality.coveragePct < 60) {
            insights.push(`ข้อมูลบันทึกครอบคลุมเพียง ${dataQuality.coveragePct}% ของช่วงเวลา ผลวิเคราะห์อาจคลาดเคลื่อน`);
        }
        if (insights.length === 0) insights.push('แนวโน้มโดยรวมค่อนข้างเสถียรเมื่อเทียบช่วงก่อน');
        return insights.slice(0, 5);
    }, [deltaExpensePct, deltaIncomePct, sandTotals, dataQuality.coveragePct]);

    const alertItems = useMemo(
        () => [
            {
                id: 'expense-spike',
                label: 'รายจ่ายพุ่ง',
                status: deltaExpensePct !== null && deltaExpensePct >= 15 ? 'high' : 'normal',
                detail: deltaExpensePct === null ? 'ไม่มีฐานเทียบ' : `${fmtTableDelta(deltaExpensePct)} เทียบช่วงก่อน`,
            },
            {
                id: 'income-drop',
                label: 'รายรับลด',
                status: deltaIncomePct !== null && deltaIncomePct <= -12 ? 'high' : 'normal',
                detail: deltaIncomePct === null ? 'ไม่มีฐานเทียบ' : `${fmtTableDelta(deltaIncomePct)} เทียบช่วงก่อน`,
            },
            {
                id: 'coverage',
                label: 'ความครบถ้วนข้อมูล',
                status: dataQuality.coveragePct < 60 ? 'high' : dataQuality.coveragePct < 80 ? 'warn' : 'normal',
                detail: `${dataQuality.coveragePct}% ของวันในช่วงที่เลือก`,
            },
        ],
        [deltaExpensePct, deltaIncomePct, dataQuality.coveragePct]
    );

    const exportCsv = useCallback(() => {
        const rows = [
            ['metric', 'current', 'previous', 'delta_pct'],
            ['income', String(curFin.income), String(prevFin.income), fmtTableDelta(deltaIncomePct)],
            ['expense', String(curFin.expense), String(prevFin.expense), fmtTableDelta(deltaExpensePct)],
            ['profit', String(curFin.profit), String(prevFin.profit), prevFin.profit === 0 ? '—' : `${profitChangePct}%`],
            ['sand_washed', String(sandTotals.washed), String(prevSandTotals.washed), fmtTableDelta(deltaWashedPct)],
            ['sand_transported', String(sandTotals.transported), String(prevSandTotals.transported), fmtTableDelta(deltaTransportPct)],
        ];
        const csv = rows.map((row) => row.map((cell) => `"${String(cell).replace(/"/g, '""')}"`).join(',')).join('\n');
        const blob = new Blob([`\uFEFF${csv}`], { type: 'text/csv;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = `dashboard-v5-${dateFilter.start}-to-${dateFilter.end}.csv`;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        URL.revokeObjectURL(url);
    }, [
        curFin,
        prevFin,
        deltaIncomePct,
        deltaExpensePct,
        profitChangePct,
        sandTotals,
        prevSandTotals,
        deltaWashedPct,
        deltaTransportPct,
        dateFilter.start,
        dateFilter.end,
    ]);

    return (
        <div className="space-y-6 animate-fade-in">
            <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between gap-3">
                <div>
                    <h2 className="text-lg font-bold text-slate-800 dark:text-white flex items-center gap-2">
                        <Target size={22} className="text-amber-500" />
                        ภาพรวม V.5 — เปรียบเทียบประสิทธิภาพและจุดคุ้มทุน
                    </h2>
                    <p className="text-sm text-slate-500 dark:text-slate-400 mt-1 max-w-3xl">
                        เปรียบเทียบช่วงที่เลือกกับช่วงก่อนหน้า (จำนวนวันเท่ากัน) คะแนนรวมสะท้อนความคุ้มทุน การเติบโต
                        การควบคุมต้นทุน และสมดุลทราย กราฟ Scatter แสดงรายวัน: เหนือเส้นทแยง = รายรับมากกว่ารายจ่าย
                    </p>
                </div>
                <div className="flex items-start gap-2 text-xs text-slate-500 dark:text-slate-400 bg-slate-50 dark:bg-white/[0.06] rounded-xl px-3 py-2 border border-slate-200 dark:border-white/10 max-w-sm">
                    <Info size={16} className="shrink-0 mt-0.5" />
                    <span>
                        ช่วงเปรียบเทียบก่อนหน้า: {prevFilter.start} ถึง {prevFilter.end}
                    </span>
                </div>
            </div>
            <div className="flex flex-wrap items-center justify-between gap-3">
                <div className="flex flex-wrap gap-2">
                    {alertItems.map((alert) => {
                        const colorClass =
                            alert.status === 'high'
                                ? 'bg-red-50 text-red-600 border-red-200 dark:bg-red-500/10 dark:text-red-300 dark:border-red-500/30'
                                : alert.status === 'warn'
                                  ? 'bg-amber-50 text-amber-700 border-amber-200 dark:bg-amber-500/10 dark:text-amber-300 dark:border-amber-500/30'
                                  : 'bg-emerald-50 text-emerald-700 border-emerald-200 dark:bg-emerald-500/10 dark:text-emerald-300 dark:border-emerald-500/30';
                        return (
                            <span key={alert.id} className={`text-xs px-2.5 py-1 rounded-full border ${colorClass}`}>
                                {alert.label}: {alert.detail}
                            </span>
                        );
                    })}
                </div>
                <button
                    type="button"
                    onClick={exportCsv}
                    aria-label="ส่งออกข้อมูลสรุปแดชบอร์ดเป็น CSV"
                    className="text-xs px-3 py-1.5 rounded-lg border border-slate-200 dark:border-white/10 bg-white dark:bg-white/[0.04] hover:bg-slate-50 dark:hover:bg-white/[0.08] text-slate-700 dark:text-slate-200"
                >
                    Export CSV
                </button>
            </div>

            <Card className="p-5 sm:p-6">
                <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-3">
                    <div>
                        <h3 className="font-bold text-slate-800 dark:text-slate-100">สัญญาณที่ควรติดตาม (Actionable Insights)</h3>
                        <p className="text-xs text-slate-500 dark:text-slate-400 mt-1">สรุปจากแนวโน้มช่วงที่เลือกเทียบช่วงก่อนหน้า</p>
                    </div>
                    <div className="text-xs text-slate-500 dark:text-slate-400 bg-slate-50 dark:bg-white/[0.05] rounded-lg px-3 py-2 border border-slate-200 dark:border-white/10">
                        อัปเดตล่าสุดจากข้อมูลวันที่ {dateFilter.end} · ใช้ข้อมูล {filtered.length.toLocaleString()} รายการ
                    </div>
                </div>
                <ul className="mt-4 space-y-2.5">
                    {keyInsights.map((insight, i) => (
                        <li key={i} className="text-sm text-slate-700 dark:text-slate-200 bg-slate-50 dark:bg-white/[0.04] border border-slate-200 dark:border-white/[0.08] rounded-lg px-3 py-2.5">
                            {insight}
                        </li>
                    ))}
                </ul>
            </Card>

            <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
                <div
                    title={`กำไรช่วงนี้ ${curFin.profit.toLocaleString()} บ. เทียบช่วงก่อน ${prevFin.profit.toLocaleString()} บ. (${dateFilter.start} ถึง ${dateFilter.end})`}
                    className="rounded-2xl focus-within:ring-2 focus-within:ring-amber-500/20"
                >
                    <StatCard title="กำไรสุทธิ (ช่วงนี้)" value={curFin.profit} icon={curFin.profit >= 0 ? TrendingUp : TrendingDown} color={curFin.profit >= 0 ? '#10b981' : '#ef4444'} />
                </div>
                <div
                    title={`อัตรากำไรต่อรายรับ = กำไร ÷ รายรับ × 100 — ช่วงนี้ ${marginPct}% | ช่วงก่อน ${prevMarginPct}%`}
                    className="rounded-2xl focus-within:ring-2 focus-within:ring-amber-500/20"
                >
                    <StatCard
                        title="อัตรากำไร / รายรับ"
                        value={marginPct}
                        icon={PiggyBank}
                        color="#8b5cf6"
                        unit="%"
                        subValue={`ช่วงก่อน: ${prevMarginPct}%`}
                    />
                </div>
                <div
                    title={
                        prevFin.profit === 0
                            ? 'ไม่มีกำไรช่วงก่อนสำหรับคิด % เปลี่ยนแปลง'
                            : `% เปลี่ยนแปลง = (กำไรช่วงนี้ − กำไรช่วงก่อน) ÷ |กำไรช่วงก่อน| × 100`
                    }
                    className="rounded-2xl focus-within:ring-2 focus-within:ring-amber-500/20"
                >
                    <StatCard
                        title="เปลี่ยนแปลงกำไร vs ช่วงก่อน"
                        value={profitChangePct}
                        icon={profitChangePct >= 0 ? TrendingUp : TrendingDown}
                        color={profitChangePct >= 0 ? '#10b981' : '#ef4444'}
                        unit="%"
                        subValue={prevFin.profit === 0 ? 'ไม่มีฐานเปรียบเทียบกำไร' : 'เทียบกับช่วงก่อนหน้า'}
                    />
                </div>
                <div
                    title={`คะแนนรวมถ่วงน้ำหนักจาก 4 ด้าน (ดูรายละเอียดคะแนนย่อย) — ช่วงเปรียบเทียบก่อน: ${prevFilter.start} ถึง ${prevFilter.end}`}
                    className="rounded-2xl focus-within:ring-2 focus-within:ring-amber-500/20"
                >
                    <Card className="p-4 sm:p-5 flex flex-col justify-between min-h-[110px] sm:h-32 relative overflow-hidden border-amber-200/80 dark:border-amber-500/30">
                        <div className="flex items-center gap-2 text-slate-500 dark:text-slate-400 mb-1">
                            <Scale size={18} className="text-amber-500" />
                            <span className="text-sm font-medium">คะแนนรวมการเปรียบเทียบ (0–100)</span>
                        </div>
                        <div className="flex items-end gap-2">
                            <span className="text-3xl sm:text-4xl font-bold text-amber-600 dark:text-amber-400">{composite.score}</span>
                            <span className="text-sm text-slate-400 mb-1">/ 100</span>
                        </div>
                        <div className="h-1 w-full bg-slate-100 dark:bg-white/10 mt-auto rounded-full overflow-hidden">
                            <div className="h-full rounded-full bg-amber-500" style={{ width: `${composite.score}%` }} />
                        </div>
                    </Card>
                </div>
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <Card className="p-5 sm:p-6">
                    <h3 className="font-bold text-slate-800 dark:text-slate-100 mb-1 flex items-center gap-2">
                        <BarChart3 size={18} className="text-slate-500" />
                        เปรียบเทียบตัวเลขหลัก (ช่วงนี้ vs ช่วงก่อน)
                    </h3>
                    <p className="text-xs text-slate-500 dark:text-slate-400 mb-4">
                        ช่วงก่อนหมายถึง {prevFilter.start} – {prevFilter.end} (จำนวนวันเท่ากับช่วงที่เลือก)
                    </p>
                    <div className="overflow-x-auto">
                        <table className="w-full text-sm">
                            <thead>
                                <tr className="border-b border-slate-200 dark:border-white/10 text-left text-slate-500">
                                    <th className="py-2 pr-2">รายการ</th>
                                    <th className="py-2 pr-2 text-right">ช่วงนี้</th>
                                    <th className="py-2 pr-2 text-right">ช่วงก่อน</th>
                                    <th className="py-2 text-right text-xs font-normal max-w-[120px]" title="เปอร์เซ็นต์เปลี่ยนแปลงเทียบช่วงก่อน (เมื่อฐานเป็น 0 จะแสดง —)">
                                        Δ% เทียบช่วงก่อน
                                    </th>
                                </tr>
                            </thead>
                            <tbody className="text-slate-700 dark:text-slate-200">
                                <tr className="border-b border-slate-100 dark:border-white/[0.06]" title="รายรับรวมในช่วงวันที่เลือก">
                                    <td className="py-2.5">รายรับรวม</td>
                                    <td className="text-right font-mono">
                                        <FormatNumber value={curFin.income} />
                                    </td>
                                    <td className="text-right font-mono text-slate-500">
                                        <FormatNumber value={prevFin.income} />
                                    </td>
                                    <td className="text-right text-xs font-mono text-slate-600 dark:text-slate-300">{fmtTableDelta(deltaIncomePct)}</td>
                                </tr>
                                <tr className="border-b border-slate-100 dark:border-white/[0.06]" title="รายจ่ายรวมในช่วงวันที่เลือก">
                                    <td className="py-2.5">รายจ่ายรวม (ต้นทุน)</td>
                                    <td className="text-right font-mono">
                                        <FormatNumber value={curFin.expense} />
                                    </td>
                                    <td className="text-right font-mono text-slate-500">
                                        <FormatNumber value={prevFin.expense} />
                                    </td>
                                    <td className="text-right text-xs font-mono text-slate-600 dark:text-slate-300">{fmtTableDelta(deltaExpensePct)}</td>
                                </tr>
                                <tr className="border-b border-slate-100 dark:border-white/[0.06]" title="กำไร = รายรับ − รายจ่าย">
                                    <td className="py-2.5 font-semibold">กำไรขาดทุน</td>
                                    <td className={`text-right font-mono font-bold ${curFin.profit >= 0 ? 'text-emerald-600' : 'text-red-500'}`}>
                                        <FormatNumber value={curFin.profit} />
                                    </td>
                                    <td className={`text-right font-mono text-slate-500 ${prevFin.profit >= 0 ? 'text-emerald-600/80' : 'text-red-400/80'}`}>
                                        <FormatNumber value={prevFin.profit} />
                                    </td>
                                    <td className="text-right text-xs font-mono text-slate-600 dark:text-slate-300">
                                        {prevFin.profit === 0 ? '—' : `${profitChangePct >= 0 ? '+' : ''}${profitChangePct}%`}
                                    </td>
                                </tr>
                                <tr title="ปริมาณทรายล้างจากบันทึก DailyLog">
                                    <td className="py-2.5">ทรายล้างรวม (คิว)</td>
                                    <td className="text-right font-mono">{sandTotals.washed.toLocaleString()}</td>
                                    <td className="text-right font-mono text-slate-500">{prevSandTotals.washed.toLocaleString()}</td>
                                    <td className="text-right text-xs font-mono text-slate-600 dark:text-slate-300">{fmtTableDelta(deltaWashedPct)}</td>
                                </tr>
                                <tr title="ประมาณจากเที่ยวรถ × 3 คิว">
                                    <td className="py-2.5">ทรายขนรวม (ประมาณ คิว)</td>
                                    <td className="text-right font-mono">{sandTotals.transported.toLocaleString()}</td>
                                    <td className="text-right font-mono text-slate-500">{prevSandTotals.transported.toLocaleString()}</td>
                                    <td className="text-right text-xs font-mono text-slate-600 dark:text-slate-300">{fmtTableDelta(deltaTransportPct)}</td>
                                </tr>
                            </tbody>
                        </table>
                    </div>
                </Card>

                <Card className="p-5 sm:p-6 !overflow-visible z-[5]">
                    <h3 className="font-bold text-slate-800 dark:text-slate-100 mb-1 flex items-center gap-2">
                        <Scale size={18} className="text-amber-500" />
                        รายละเอียดคะแนนย่อย
                    </h3>
                    <p className="text-xs text-slate-500 dark:text-slate-400 mb-4">
                        แสดงการเปลี่ยนแปลงเทียบช่วงก่อนหน้า (จำนวนวันเท่ากัน) — พ.ค. = พอยต์เปอร์เซ็นต์ของอัตรากำไร
                    </p>
                    <ul className="space-y-3">
                        {composite.breakdown.map((b) => {
                            const trendColor =
                                b.trend === 'neutral'
                                    ? 'text-slate-500'
                                    : b.trend === 'up'
                                      ? 'text-emerald-600 dark:text-emerald-400'
                                      : b.trend === 'down'
                                        ? 'text-red-500 dark:text-red-400'
                                        : 'text-slate-500';
                            return (
                                <li
                                    key={b.label}
                                    className="group relative rounded-xl border border-slate-100 dark:border-white/[0.06] bg-slate-50/80 dark:bg-white/[0.03] px-3 py-2.5 focus-within:ring-2 focus-within:ring-amber-500/20"
                                    tabIndex={0}
                                    aria-label={`รายละเอียดคะแนน: ${b.label}`}
                                >
                                    <div className="flex flex-wrap items-start justify-between gap-2">
                                        <div className="min-w-0 flex-1">
                                            <div className="text-sm font-medium text-slate-700 dark:text-slate-200">{b.label}</div>
                                            <div className={`text-xs font-semibold mt-1 ${trendColor}`}>{b.changeLabel}</div>
                                        </div>
                                        <div className="text-right shrink-0">
                                            <span className="text-[10px] text-slate-400 block">น้ำหนัก {b.weight}</span>
                                            <span className="text-xs text-slate-500 dark:text-slate-400">คะแนนส่วน {b.scorePart}</span>
                                        </div>
                                    </div>
                                    <div
                                        className="pointer-events-none absolute z-20 left-0 right-0 top-full mt-1 opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-opacity duration-150"
                                        role="tooltip"
                                    >
                                        <div className="rounded-xl border border-slate-200 dark:border-white/10 bg-white dark:bg-slate-900 shadow-lg px-3 py-2.5 text-[11px] text-slate-600 dark:text-slate-300 whitespace-pre-line leading-relaxed">
                                            {b.tooltip}
                                        </div>
                                    </div>
                                </li>
                            );
                        })}
                    </ul>
                    <p className="text-xs text-slate-400 mt-4 leading-relaxed">
                        ชี้เมาส์ที่แต่ละแถวเพื่อดูตัวเลขอ้างอิงที่ใช้เปรียบเทียบ — ใช้เป็นตัวช่วยวิเคราะห์ ไม่ใช่คำแนะนำทางบัญชี
                    </p>
                </Card>
            </div>

            <Card className="p-5 sm:p-6">
                <div className="flex flex-col md:flex-row md:items-center md:justify-between gap-3">
                    <div>
                        <h3 className="font-bold text-slate-800 dark:text-slate-100">ความน่าเชื่อถือของข้อมูล (Data Quality)</h3>
                        <p className="text-xs text-slate-500 dark:text-slate-400 mt-1">ช่วยตีความผลวิเคราะห์ตามความครบถ้วนของข้อมูลจริง</p>
                    </div>
                    <span className="text-xs font-semibold px-2.5 py-1 rounded-full bg-slate-100 dark:bg-white/[0.06] text-slate-600 dark:text-slate-300 border border-slate-200 dark:border-white/10">
                        สถานะคุณภาพข้อมูล: {dataQuality.qualityLabel}
                    </span>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 mt-4">
                    <div className="rounded-xl border border-slate-200 dark:border-white/10 bg-slate-50 dark:bg-white/[0.04] px-3 py-3">
                        <div className="text-xs text-slate-500">วันในช่วงที่เลือก</div>
                        <div className="text-lg font-bold text-slate-800 dark:text-slate-100">{dataQuality.totalDays}</div>
                    </div>
                    <div className="rounded-xl border border-slate-200 dark:border-white/10 bg-slate-50 dark:bg-white/[0.04] px-3 py-3">
                        <div className="text-xs text-slate-500">วันมีข้อมูลธุรกรรม</div>
                        <div className="text-lg font-bold text-slate-800 dark:text-slate-100">
                            {dataQuality.daysWithRecords} ({dataQuality.coveragePct}%)
                        </div>
                    </div>
                    <div className="rounded-xl border border-slate-200 dark:border-white/10 bg-slate-50 dark:bg-white/[0.04] px-3 py-3">
                        <div className="text-xs text-slate-500">วันมีข้อมูลทราย</div>
                        <div className="text-lg font-bold text-slate-800 dark:text-slate-100">
                            {dataQuality.daysWithSandRecords} ({dataQuality.sandCoveragePct}%)
                        </div>
                    </div>
                </div>
            </Card>

            <Card className="p-5 sm:p-6">
                <div className="flex flex-wrap items-center justify-between gap-3">
                    <div>
                        <h3 className="font-bold text-slate-800 dark:text-slate-100">วิธีคิดคะแนนรวม (โปร่งใส)</h3>
                        <p className="text-xs text-slate-500 dark:text-slate-400 mt-1">
                            แสดงสูตรโดยย่อของคะแนนรวมเพื่อให้ตรวจสอบได้
                        </p>
                    </div>
                    <button
                        type="button"
                        onClick={() => setShowScoreFormula((s) => !s)}
                        aria-expanded={showScoreFormula}
                        aria-controls="score-formula-detail"
                        className="text-xs px-3 py-1.5 rounded-lg border border-slate-200 dark:border-white/10 bg-white dark:bg-white/[0.04] hover:bg-slate-50 dark:hover:bg-white/[0.08] text-slate-700 dark:text-slate-200"
                    >
                        {showScoreFormula ? 'ซ่อนสูตรคะแนน' : 'ดูวิธีคิดคะแนน'}
                    </button>
                </div>
                {showScoreFormula ? (
                    <div id="score-formula-detail" className="mt-4 space-y-2 text-sm text-slate-700 dark:text-slate-200">
                        <p>คะแนนรวม = (ความคุ้มทุน x 35%) + (เทียบกำไรช่วงก่อน x 25%) + (ควบคุมต้นทุน x 25%) + (สมดุลทราย x 15%)</p>
                        <p className="text-xs text-slate-500 dark:text-slate-400">
                            ความคุ้มทุนใช้อัตรากำไรต่อรายรับ, การเติบโตเทียบกำไรช่วงก่อนหน้า, ควบคุมต้นทุนใช้สัดส่วนรายจ่ายต่อรายรับ, สมดุลทรายใช้สัดส่วนทรายล้างเทียบทรายขน
                        </p>
                    </div>
                ) : null}
            </Card>

            <Card className="p-0 overflow-hidden">
                <div className="px-5 sm:px-6 pt-5 sm:pt-6 pb-2">
                    <h3 className="font-bold text-slate-800 dark:text-slate-100 flex items-center gap-2">
                        <Wallet size={18} className="text-blue-500" />
                        แผนภูมิ Scatter — รายรับ vs รายจ่ายรายวัน (หาจุดคุ้มทุน)
                    </h3>
                    <p className="text-sm text-slate-500 dark:text-slate-400 mt-1">
                        แต่ละจุดคือหนึ่งวันในกรอบวันที่ที่เลือก เส้นประแนวทแยงคือกรณีรายรับเท่ารายจ่าย
                    </p>
                </div>
                <div className="px-2 sm:px-4 pb-4">
                    {dailyPoints.length > 0 ? (
                        <BreakEvenScatter points={dailyPoints} />
                    ) : (
                        <p className="text-center text-slate-400 py-12">ไม่มีข้อมูลในช่วงวันที่เลือก</p>
                    )}
                </div>
            </Card>

            <Card className="p-5 sm:p-6">
                <h3 className="font-bold text-slate-800 dark:text-slate-100 mb-4">วิเคราะห์กำไรขาดทุน (สรุป)</h3>
                <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-sm">
                    <div className="rounded-xl bg-emerald-50 dark:bg-emerald-500/10 border border-emerald-100 dark:border-emerald-500/20 p-4">
                        <div className="text-xs font-medium text-emerald-700 dark:text-emerald-300/90">รายรับ (Revenue)</div>
                        <div className="text-xl font-bold text-emerald-800 dark:text-emerald-200 mt-1">
                            <FormatNumber value={curFin.income} />
                        </div>
                    </div>
                    <div className="rounded-xl bg-red-50 dark:bg-red-500/10 border border-red-100 dark:border-red-500/20 p-4">
                        <div className="text-xs font-medium text-red-700 dark:text-red-300/90">รายจ่าย / ต้นทุน (Expenses)</div>
                        <div className="text-xl font-bold text-red-800 dark:text-red-200 mt-1">
                            <FormatNumber value={curFin.expense} />
                        </div>
                    </div>
                    <div
                        className={`rounded-xl border p-4 ${
                            curFin.profit >= 0
                                ? 'bg-slate-50 dark:bg-white/[0.06] border-slate-200 dark:border-white/10'
                                : 'bg-amber-50 dark:bg-amber-500/10 border-amber-200 dark:border-amber-500/20'
                        }`}
                    >
                        <div className="text-xs font-medium text-slate-600 dark:text-slate-300">กำไรสุทธิ (P&amp;L)</div>
                        <div className={`text-xl font-bold mt-1 ${curFin.profit >= 0 ? 'text-emerald-600' : 'text-red-500'}`}>
                            <FormatNumber value={curFin.profit} />
                        </div>
                        <p className="text-xs text-slate-500 mt-2">
                            อัตราส่วนรายจ่ายต่อรายรับ:{' '}
                            {curFin.income > 0 ? `${((curFin.expense / curFin.income) * 100).toFixed(1)}%` : '—'}
                        </p>
                    </div>
                </div>
            </Card>
        </div>
    );
};

export default DashboardV5;
