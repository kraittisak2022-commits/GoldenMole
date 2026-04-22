import { Transaction } from '../../types';

export type DateFilter = { start: string; end: string };

export function countInclusiveDays(startStr: string, endStr: string): number {
    const a = new Date(startStr + 'T12:00:00+07:00');
    const b = new Date(endStr + 'T12:00:00+07:00');
    return Math.max(1, Math.round((b.getTime() - a.getTime()) / 86400000) + 1);
}

export function shiftDateStr(dateStr: string, deltaDays: number): string {
    const d = new Date(dateStr + 'T12:00:00+07:00');
    d.setDate(d.getDate() + deltaDays);
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
}

export function getPreviousPeriodFilter(filter: DateFilter): DateFilter {
    const n = countInclusiveDays(filter.start, filter.end);
    const prevEnd = shiftDateStr(filter.start, -1);
    const prevStart = shiftDateStr(prevEnd, -(n - 1));
    return { start: prevStart, end: prevEnd };
}

export function pctChangeVsPrev(cur: number, prev: number): number | null {
    if (prev === 0 && cur === 0) return 0;
    if (prev === 0) return null;
    return ((cur - prev) / Math.abs(prev)) * 100;
}

function marginPercent(fin: { income: number; profit: number }): number {
    if (fin.income > 0) return (fin.profit / fin.income) * 100;
    return fin.profit > 0 ? 100 : 0;
}

function expenseToIncomeRatio(fin: { income: number; expense: number }): number {
    if (fin.income > 0) return (fin.expense / fin.income) * 100;
    return fin.expense > 0 ? 100 : 0;
}

function sandBalanceRatio(washed: number, transported: number): number {
    const sandTotal = washed + transported;
    if (sandTotal <= 0) return 0;
    return (washed / Math.max(washed, transported)) * 100;
}

export function computeCompositeScore(args: {
    cur: { income: number; expense: number; profit: number };
    prev: { income: number; expense: number; profit: number };
    sandWashed: number;
    sandTransported: number;
    prevSandWashed: number;
    prevSandTransported: number;
}) {
    const { cur, prev, sandWashed, sandTransported, prevSandWashed, prevSandTransported } = args;
    const marginScore =
        cur.income > 0 ? Math.max(0, Math.min(100, (cur.profit / cur.income) * 100)) : cur.profit > 0 ? 100 : 0;
    let growthScore = 50;
    if (prev.profit !== 0) {
        growthScore = Math.max(0, Math.min(100, 50 + ((cur.profit - prev.profit) / Math.abs(prev.profit)) * 50));
    } else if (cur.profit > 0) {
        growthScore = 85;
    }
    const expenseRatio = cur.income > 0 ? (cur.expense / cur.income) * 100 : cur.expense > 0 ? 100 : 0;
    const costControlScore = Math.max(0, Math.min(100, 100 - expenseRatio * 0.6));
    const sandTotal = sandWashed + sandTransported;
    const sandScore =
        sandTotal <= 0 ? 70 : Math.max(0, Math.min(100, (sandWashed / Math.max(sandWashed, sandTransported)) * 100));
    const score = Math.round(marginScore * 0.35 + growthScore * 0.25 + costControlScore * 0.25 + sandScore * 0.15);

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
        return { text: `${sign}${Math.abs(rounded)}% เทียบช่วงก่อน`, trend: rounded === 0 ? 'flat' : good ? 'up' : bad ? 'down' : 'flat' };
    };

    return {
        score: Math.max(0, Math.min(100, score)),
        breakdown: [
            {
                label: 'ความคุ้มทุน (อัตรากำไรต่อรายรับ)',
                weight: '35%',
                scorePart: Math.round(marginScore),
                changeLabel: `${deltaMarginPp >= 0 ? '+' : '−'}${Math.abs(Math.round(deltaMarginPp * 10) / 10)} พ.ค. เทียบช่วงก่อน`,
                trend: deltaMarginPp === 0 ? 'flat' : deltaMarginPp > 0 ? 'up' : 'down',
                tooltip: `ช่วงนี้: อัตรากำไร ${curM.toFixed(1)}%`,
            },
            {
                label: 'เทียบกำไรช่วงก่อน',
                weight: '25%',
                scorePart: Math.round(growthScore),
                changeLabel: profitDeltaPct === null ? 'ไม่มีฐานเทียบกำไร' : fmtSignedPct(profitDeltaPct).text,
                trend: profitDeltaPct === null ? 'neutral' : fmtSignedPct(profitDeltaPct).trend,
                tooltip: `กำไรช่วงนี้ ${cur.profit.toLocaleString()} บ. เทียบช่วงก่อน ${prev.profit.toLocaleString()} บ.`,
            },
            {
                label: 'ควบคุมต้นทุนต่อรายรับ',
                weight: '25%',
                scorePart: Math.round(costControlScore),
                changeLabel: costRatioDeltaPct === null ? 'ไม่มีฐานเทียบสัดส่วน' : fmtSignedPct(costRatioDeltaPct, true).text,
                trend: costRatioDeltaPct === null ? 'neutral' : fmtSignedPct(costRatioDeltaPct, true).trend,
                tooltip: `อัตรารายจ่ายต่อรายรับ ช่วงนี้ ${curEI.toFixed(1)}%`,
            },
            {
                label: 'สมดุลทราย (ล้าง vs ขน)',
                weight: '15%',
                scorePart: Math.round(sandScore),
                changeLabel: sandDeltaPct === null ? 'ไม่มีฐานเทียบอัตราทราย' : fmtSignedPct(sandDeltaPct).text,
                trend: sandDeltaPct === null ? 'neutral' : fmtSignedPct(sandDeltaPct).trend,
                tooltip: `ล้าง ${sandWashed.toLocaleString()} คิว เทียบ ขน ${sandTransported.toLocaleString()} คิว`,
            },
        ],
    };
}

export function aggregateFinancial(transactions: Transaction[]) {
    const income = transactions.filter((t) => t.type === 'Income').reduce((s, t) => s + t.amount, 0);
    const expense = transactions.filter((t) => t.type === 'Expense').reduce((s, t) => s + t.amount, 0);
    return { income, expense, profit: income - expense };
}
