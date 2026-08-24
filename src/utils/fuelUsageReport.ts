import type { Transaction } from '../types';
import {
    FUEL_SAND_SIEVE_SUB_CATEGORY,
    FUEL_TRANSFER_SUB_CATEGORY,
    FUEL_WITHDRAW_SUB_CATEGORY,
    fuelTxToLiters,
    inferFuelMovement,
    normalizeDate,
    normalizeFuelTank,
} from './index';

export type FuelUsageKind = 'stock_in' | 'vehicle' | 'withdraw' | 'transfer' | 'sand_sieve' | 'other_out';
export type FuelTypeFilter = 'Diesel' | 'Benzine';

export interface FuelUsageFilters {
    start: string;
    end: string;
    vehicleId?: string;
    fuelType?: FuelTypeFilter | '';
    kind?: FuelUsageKind | '';
}

export interface FuelUsageRow {
    id: string;
    date: string;
    kind: FuelUsageKind;
    fuelType: FuelTypeFilter;
    tank: 'main' | 'reserve';
    vehicleId: string;
    liters: number;
    amount: number;
    description: string;
}

export interface FuelUsageTotals {
    stockInLiters: number;
    stockInAmount: number;
    vehicleLiters: number;
    vehicleAmount: number;
    withdrawLiters: number;
    transferLiters: number;
    sandSieveLiters: number;
    otherOutLiters: number;
    usageLiters: number;
    usageAmount: number;
    count: number;
}

export interface FuelUsageReport {
    rows: FuelUsageRow[];
    totals: FuelUsageTotals;
    byVehicle: Array<{ vehicleId: string; liters: number; amount: number; count: number }>;
    byDay: Array<{ date: string; stockInLiters: number; usageLiters: number; usageAmount: number; count: number }>;
    byFuelType: Array<{ fuelType: FuelTypeFilter; liters: number; amount: number }>;
}

const UNNAMED_VEHICLE = 'ไม่ระบุรถ';

export function fuelKindLabel(kind: FuelUsageKind): string {
    switch (kind) {
        case 'stock_in': return 'รับเข้า';
        case 'vehicle': return 'เติมรถ';
        case 'withdraw': return 'เบิกจากถัง';
        case 'transfer': return 'โอนถัง';
        case 'sand_sieve': return 'ร่อนทราย';
        default: return 'ใช้อื่น ๆ';
    }
}

export function fuelTypeLabel(fuelType: FuelTypeFilter): string {
    return fuelType === 'Benzine' ? 'เบนซิน' : 'ดีเซล';
}

export function tankLabel(tank: 'main' | 'reserve'): string {
    return tank === 'reserve' ? 'ถังสำรอง' : 'ถังหลัก';
}

export function classifyFuelTx(t: Transaction): FuelUsageKind | null {
    if (t.category !== 'Fuel' || t.type !== 'Expense') return null;
    if (inferFuelMovement(t) === 'stock_in') return 'stock_in';
    if (t.subCategory === FUEL_WITHDRAW_SUB_CATEGORY) return 'withdraw';
    if (t.subCategory === FUEL_TRANSFER_SUB_CATEGORY) return 'transfer';
    if (t.subCategory === FUEL_SAND_SIEVE_SUB_CATEGORY) return 'sand_sieve';
    if (t.vehicleId) return 'vehicle';
    return 'other_out';
}

function resolveFuelType(t: Transaction): FuelTypeFilter {
    return t.fuelType === 'Benzine' ? 'Benzine' : 'Diesel';
}

function isUsageKind(kind: FuelUsageKind): boolean {
    return kind === 'vehicle' || kind === 'withdraw' || kind === 'sand_sieve' || kind === 'other_out';
}

export function monthBoundsFromYmd(ymd: string): { start: string; end: string } {
    const day = normalizeDate(ymd);
    const [y, m] = day.split('-').map(Number);
    const start = `${y}-${String(m).padStart(2, '0')}-01`;
    const last = new Date(Date.UTC(y, m, 0));
    return { start, end: last.toISOString().slice(0, 10) };
}

export function shiftMonthBounds(ymd: string, delta: number): { start: string; end: string } {
    const day = normalizeDate(ymd);
    const [y, m] = day.split('-').map(Number);
    const shifted = new Date(Date.UTC(y, m - 1 + delta, 1));
    return monthBoundsFromYmd(shifted.toISOString().slice(0, 10));
}

export function yearBoundsFromYmd(ymd: string): { start: string; end: string } {
    const y = normalizeDate(ymd).slice(0, 4);
    return { start: `${y}-01-01`, end: `${y}-12-31` };
}

const emptyTotals = (): FuelUsageTotals => ({
    stockInLiters: 0,
    stockInAmount: 0,
    vehicleLiters: 0,
    vehicleAmount: 0,
    withdrawLiters: 0,
    transferLiters: 0,
    sandSieveLiters: 0,
    otherOutLiters: 0,
    usageLiters: 0,
    usageAmount: 0,
    count: 0,
});

export function buildFuelUsageReport(transactions: Transaction[], filters: FuelUsageFilters): FuelUsageReport {
    const start = normalizeDate(filters.start);
    const end = normalizeDate(filters.end);
    const vehicleFilter = (filters.vehicleId || '').trim();
    const fuelTypeFilter = filters.fuelType || '';
    const kindFilter = filters.kind || '';

    const rows: FuelUsageRow[] = [];
    for (const t of transactions) {
        const kind = classifyFuelTx(t);
        if (!kind) continue;
        const date = normalizeDate(t.date);
        if (date < start || date > end) continue;
        const vehicleId = (t.vehicleId || '').trim() || (kind === 'vehicle' || kind === 'other_out' ? UNNAMED_VEHICLE : '');
        if (vehicleFilter && vehicleId !== vehicleFilter) continue;
        const fuelType = resolveFuelType(t);
        if (fuelTypeFilter && fuelType !== fuelTypeFilter) continue;
        if (kindFilter && kind !== kindFilter) continue;
        rows.push({
            id: t.id,
            date,
            kind,
            fuelType,
            tank: normalizeFuelTank(t.fuelTank),
            vehicleId,
            liters: fuelTxToLiters(t),
            amount: Number(t.amount) || 0,
            description: (t.description || t.workDetails || '').trim(),
        });
    }

    rows.sort((a, b) => {
        const d = a.date.localeCompare(b.date);
        if (d !== 0) return d;
        return a.id.localeCompare(b.id);
    });

    const totals = emptyTotals();
    totals.count = rows.length;
    const vehicleMap = new Map<string, { liters: number; amount: number; count: number }>();
    const dayMap = new Map<string, { stockInLiters: number; usageLiters: number; usageAmount: number; count: number }>();
    const typeMap = new Map<FuelTypeFilter, { liters: number; amount: number }>();

    for (const row of rows) {
        if (row.kind === 'stock_in') {
            totals.stockInLiters += row.liters;
            totals.stockInAmount += row.amount;
        } else if (row.kind === 'vehicle') {
            totals.vehicleLiters += row.liters;
            totals.vehicleAmount += row.amount;
        } else if (row.kind === 'withdraw') {
            totals.withdrawLiters += row.liters;
        } else if (row.kind === 'transfer') {
            totals.transferLiters += row.liters;
        } else if (row.kind === 'sand_sieve') {
            totals.sandSieveLiters += row.liters;
        } else {
            totals.otherOutLiters += row.liters;
        }
        if (isUsageKind(row.kind)) {
            totals.usageLiters += row.liters;
            totals.usageAmount += row.amount;
        }

        if (row.vehicleId) {
            const prev = vehicleMap.get(row.vehicleId) || { liters: 0, amount: 0, count: 0 };
            prev.liters += row.liters;
            prev.amount += row.amount;
            prev.count += 1;
            vehicleMap.set(row.vehicleId, prev);
        }

        const day = dayMap.get(row.date) || { stockInLiters: 0, usageLiters: 0, usageAmount: 0, count: 0 };
        day.count += 1;
        if (row.kind === 'stock_in') day.stockInLiters += row.liters;
        if (isUsageKind(row.kind)) {
            day.usageLiters += row.liters;
            day.usageAmount += row.amount;
        }
        dayMap.set(row.date, day);

        const ft = typeMap.get(row.fuelType) || { liters: 0, amount: 0 };
        if (isUsageKind(row.kind)) {
            ft.liters += row.liters;
            ft.amount += row.amount;
        }
        typeMap.set(row.fuelType, ft);
    }

    const byVehicle = Array.from(vehicleMap.entries())
        .map(([vehicleId, v]) => ({ vehicleId, ...v }))
        .sort((a, b) => b.liters - a.liters || a.vehicleId.localeCompare(b.vehicleId, 'th'));

    const byDay = Array.from(dayMap.entries())
        .map(([date, v]) => ({ date, ...v }))
        .sort((a, b) => a.date.localeCompare(b.date));

    const byFuelType = Array.from(typeMap.entries())
        .map(([fuelType, v]) => ({ fuelType, ...v }))
        .sort((a, b) => b.liters - a.liters);

    return { rows, totals, byVehicle, byDay, byFuelType };
}

function csvCell(value: string | number): string {
    const s = String(value);
    if (/[",\n\r]/.test(s)) return `"${s.replace(/"/g, '""')}"`;
    return s;
}

export function fuelUsageToCsv(report: FuelUsageReport, filters: FuelUsageFilters): string {
        const lines: Array<Array<string | number>> = [
        ['รายงานการใช้น้ำมัน', `${normalizeDate(filters.start)} - ${normalizeDate(filters.end)}`],
        [],
        ['ประเภท', 'ลิตร', 'บาท', 'รายการ'],
        ['รับเข้า', report.totals.stockInLiters, report.totals.stockInAmount, ''],
        ['เติมรถ', report.totals.vehicleLiters, report.totals.vehicleAmount, ''],
        ['เบิกจากถัง', report.totals.withdrawLiters, '', ''],
        ['รวมใช้', report.totals.usageLiters, report.totals.usageAmount, report.totals.count],
        [],
        ['สรุปตามรถ'],
        ['รถ', 'ลิตร', 'บาท', 'รายการ'],
        ...report.byVehicle.map(v => [v.vehicleId, v.liters, v.amount, v.count].map(String)),
        [],
        ['รายละเอียด'],
        ['วันที่', 'ประเภท', 'น้ำมัน', 'ถัง', 'รถ', 'ลิตร', 'บาท', 'รายละเอียด'],
        ...report.rows.map(r => [
            r.date,
            fuelKindLabel(r.kind),
            fuelTypeLabel(r.fuelType),
            tankLabel(r.tank),
            r.vehicleId,
            r.liters,
            r.amount,
            r.description,
        ].map(String)),
    ];
    const body = lines.map(cols => cols.map(csvCell).join(',')).join('\n');
    return `\ufeff${body}`;
}

function escHtml(value: string | number): string {
    return String(value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

export function fuelUsageToPrintHtml(opts: {
    appName: string;
    rangeLabel: string;
    report: FuelUsageReport;
    maskAmounts?: boolean;
}): string {
    const money = (n: number) => (opts.maskAmounts ? '•••' : n.toLocaleString('th-TH', { maximumFractionDigits: 2 }));
    const liters = (n: number) => n.toLocaleString('th-TH', { maximumFractionDigits: 2 });
    const t = opts.report.totals;
    const vehicleRows = opts.report.byVehicle.map(v =>
        `<tr><td>${escHtml(v.vehicleId)}</td><td>${escHtml(liters(v.liters))}</td><td>${escHtml(money(v.amount))}</td><td>${escHtml(v.count)}</td></tr>`
    ).join('') || '<tr><td colspan="4">ไม่มีข้อมูล</td></tr>';
    const dayRows = opts.report.byDay.map(d =>
        `<tr><td>${escHtml(d.date)}</td><td>${escHtml(liters(d.stockInLiters))}</td><td>${escHtml(liters(d.usageLiters))}</td><td>${escHtml(money(d.usageAmount))}</td><td>${escHtml(d.count)}</td></tr>`
    ).join('') || '<tr><td colspan="5">ไม่มีข้อมูล</td></tr>';
    const detailRows = opts.report.rows.map(r =>
        `<tr><td>${escHtml(r.date)}</td><td>${escHtml(fuelKindLabel(r.kind))}</td><td>${escHtml(fuelTypeLabel(r.fuelType))}</td><td>${escHtml(r.vehicleId || '-')}</td><td>${escHtml(liters(r.liters))}</td><td>${escHtml(money(r.amount))}</td><td>${escHtml(r.description)}</td></tr>`
    ).join('') || '<tr><td colspan="7">ไม่มีข้อมูล</td></tr>';

    return `<!doctype html><html lang="th"><head><meta charset="utf-8"/><title>รายงานการใช้น้ำมัน</title>
<style>
body{font-family:"Sarabun","Noto Sans Thai",Tahoma,sans-serif;padding:24px;color:#0f172a}
h1{font-size:20px;margin:0 0 4px}
p{margin:0 0 16px;color:#475569}
table{width:100%;border-collapse:collapse;margin:12px 0 20px;font-size:12px}
th,td{border:1px solid #cbd5e1;padding:6px 8px;text-align:left}
th{background:#f1f5f9}
td:nth-child(n+2){text-align:right}
.summary td{font-weight:600}
</style></head><body>
<h1>รายงานการใช้น้ำมัน — ${escHtml(opts.appName)}</h1>
<p>ช่วง ${escHtml(opts.rangeLabel)}</p>
<table class="summary"><thead><tr><th>รายการ</th><th>ลิตร</th><th>บาท</th></tr></thead><tbody>
<tr><td>รับเข้า</td><td>${escHtml(liters(t.stockInLiters))}</td><td>${escHtml(money(t.stockInAmount))}</td></tr>
<tr><td>เติมรถ</td><td>${escHtml(liters(t.vehicleLiters))}</td><td>${escHtml(money(t.vehicleAmount))}</td></tr>
<tr><td>เบิกจากถัง</td><td>${escHtml(liters(t.withdrawLiters))}</td><td>—</td></tr>
<tr><td>รวมใช้</td><td>${escHtml(liters(t.usageLiters))}</td><td>${escHtml(money(t.usageAmount))}</td></tr>
</tbody></table>
<h2 style="font-size:16px">สรุปตามรถ</h2>
<table><thead><tr><th>รถ</th><th>ลิตร</th><th>บาท</th><th>รายการ</th></tr></thead><tbody>${vehicleRows}</tbody></table>
<h2 style="font-size:16px">สรุปรายวัน</h2>
<table><thead><tr><th>วันที่</th><th>รับเข้า (ลิตร)</th><th>ใช้ (ลิตร)</th><th>ค่าใช้จ่าย</th><th>รายการ</th></tr></thead><tbody>${dayRows}</tbody></table>
<h2 style="font-size:16px">รายละเอียด</h2>
<table><thead><tr><th>วันที่</th><th>ประเภท</th><th>น้ำมัน</th><th>รถ</th><th>ลิตร</th><th>บาท</th><th>รายละเอียด</th></tr></thead><tbody>${detailRows}</tbody></table>
</body></html>`;
}
