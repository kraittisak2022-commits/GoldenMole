import type { Transaction } from '../types';
import type { FuelStockBalances } from './index';
import {
    FUEL_SAND_SIEVE_SUB_CATEGORY,
    FUEL_SAND_SIEVE_VEHICLE_ID,
    FUEL_STOCK_IN_SUB_CATEGORY,
    FUEL_TRANSFER_SUB_CATEGORY,
    FUEL_VEHICLE_USAGE_SUB_CATEGORY,
    FUEL_WITHDRAW_SUB_CATEGORY,
    fuelTxToLiters,
    fuelUsageTankOf,
    inferFuelMovement,
    normalizeDate,
    normalizeFuelTank,
} from './index';
import { FUEL_SAND_SIEVE_LITERS_PER_HOUR } from './fuelSieveEstimate';
import { isMacroVehicleId } from '../modules/Dashboard/dailyStepRecorderUtils';

export type FuelUsageKind = 'stock_in' | 'vehicle' | 'withdraw' | 'transfer' | 'sand_sieve' | 'other_out';
export type FuelPrintGroup = 'macro' | 'sieve_generator' | 'other_fill';
export type FuelTypeFilter = 'Diesel' | 'Benzine';

export interface FuelUsageFilters {
    start: string;
    end: string;
    vehicleId?: string;
    fuelType?: FuelTypeFilter | '';
    kind?: FuelUsageKind | '';
    /** ลิตรร่อนทรายประมาณรายวัน — สร้างแถว sand_sieve เสมือน */
    estimatedSieveByDay?: Record<string, number>;
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
    subCategory?: string;
    workType?: string;
    /** แถวประมาณจากชั่วโมงร่อนทราย (ไม่มีแถวจริงในฐานข้อมูล) */
    estimated?: boolean;
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

/** ชื่อรถเก่า → ชื่อมาตรฐานปัจจุบัน */
const TAPLIEN_LEGACY_VEHICLE_IDS = new Set([
    'รถตาเปลื่ยน',
    'ISUZU KB',
    'รถISUZUKB',
    'ISUZUตา',
    'IsuzuKB',
]);

function normalizeFuelReportVehicleId(raw: string): string {
    const v = raw.trim();
    if (TAPLIEN_LEGACY_VEHICLE_IDS.has(v)) return 'รถตาเปลื่ยน (ISUZU KB)';
    return v;
}

export function fuelKindLabel(kind: FuelUsageKind): string {
    switch (kind) {
        case 'stock_in': return 'รับเข้า (ถังหลัก)';
        case 'vehicle': return 'ใช้แล้ว (รถ/แม็คโคร)';
        case 'withdraw': return 'เบิกไปถังสำรอง';
        case 'transfer': return 'โอนถัง';
        case 'sand_sieve': return 'ใช้แล้ว (ร่อนทราย)';
        default: return 'ใช้แล้ว (อื่น ๆ)';
    }
}

export function fuelTypeLabel(fuelType: FuelTypeFilter): string {
    return fuelType === 'Benzine' ? 'เบนซิน' : 'ดีเซล';
}

export function tankLabel(tank: 'main' | 'reserve'): string {
    return tank === 'reserve' ? 'ถังสำรอง' : 'ถังหลัก';
}

export function fuelPrintGroupTitle(group: FuelPrintGroup): string {
    switch (group) {
        case 'macro': return 'รายงานใช้น้ำมันรถแม็คโคร';
        case 'sieve_generator': return 'รายงานการใช้น้ำมันเครื่องจักรร่อนทราย เครื่องปั่นไฟ';
        default: return 'รายงานเติมน้ำมันอื่นๆทั้งหมด';
    }
}

/** จัดกลุ่มแถวสำหรับพิมพ์แยก 3 ฉบับ */
export function fuelPrintGroupOf(row: FuelUsageRow): FuelPrintGroup {
    const workType = (row.workType ?? '').trim().toLowerCase();
    const sub = (row.subCategory ?? '').trim();

    if (row.kind === 'sand_sieve') return 'sieve_generator';
    if (workType === 'generator') return 'sieve_generator';

    if (sub === FUEL_VEHICLE_USAGE_SUB_CATEGORY) return 'macro';
    if (row.kind === 'vehicle' && workType !== 'car' && isMacroVehicleId(row.vehicleId)) return 'macro';

    return 'other_fill';
}

function withdrawPurpose(t: Transaction): string {
    return String(t.workType ?? '').trim().toLowerCase();
}

/**
 * จัดประเภทแถวน้ำมันสำหรับรายงาน
 *
 * - รับเข้า: เพิ่มเข้าถังหลักเท่านั้น (ไม่นับโอนเข้าถังสำรอง)
 * - เบิกไปถังสำรอง: โอนหลัก→สำรอง / เติมเครื่องจักร — ยังไม่นับเป็นใช้
 * - ใช้แล้ว: VehicleUsage, เติมรถ, เครื่องปั่นไฟ, อื่นระบุ, ร่อนทราย, นายกเบิก ฯลฯ
 * - แถวคู่ Transfer ฝั่งรับเข้าถังสำรองถูกข้าม (นับฝั่ง stock_out ครั้งเดียว)
 */
export function classifyFuelTx(t: Transaction): FuelUsageKind | null {
    if (t.category !== 'Fuel' || t.type !== 'Expense') return null;

    const sub = String(t.subCategory ?? '').trim();
    const movement = inferFuelMovement(t);
    const tank = normalizeFuelTank(t.fuelTank);
    const purpose = withdrawPurpose(t);

    // คู่โอนเข้าถังสำรอง — ไม่แสดงซ้ำ (ฝั่ง stock_out นับเป็นเบิก)
    if (sub === FUEL_TRANSFER_SUB_CATEGORY && movement === 'stock_in') {
        return null;
    }

    // รับเข้าถังหลักจริง (ซื้อ/เพิ่มสต็อก)
    if (
        sub === FUEL_STOCK_IN_SUB_CATEGORY
        || (movement === 'stock_in' && tank === 'main' && sub !== FUEL_TRANSFER_SUB_CATEGORY)
    ) {
        return 'stock_in';
    }

    // โอนหลัก → สำรอง (เติมเครื่องจักร) = เบิก ยังไม่ใช้
    if (sub === FUEL_TRANSFER_SUB_CATEGORY && movement === 'stock_out') {
        return 'withdraw';
    }
    if (sub === FUEL_WITHDRAW_SUB_CATEGORY && purpose === 'machine') {
        return 'withdraw';
    }

    // ใช้แล้วจากถังสำรอง (ร่อนทราย)
    if (sub === FUEL_SAND_SIEVE_SUB_CATEGORY) {
        return 'sand_sieve';
    }

    // เมนูเบิกน้ำมันที่ตัดออกจากถังหลักแล้ว = ใช้แล้ว
    if (sub === FUEL_WITHDRAW_SUB_CATEGORY) {
        if (purpose === 'car') return 'vehicle';
        return 'other_out'; // generator | mayor | other | ไม่ระบุ
    }

    // การใช้น้ำมันรถ / แม็คโคร
    if (sub === FUEL_VEHICLE_USAGE_SUB_CATEGORY || t.vehicleId) {
        return 'vehicle';
    }

    // legacy: ไม่มีรถ = รับเข้าถังหลัก
    if (movement === 'stock_in') return 'stock_in';
    return 'other_out';
}

function resolveFuelType(t: Transaction): FuelTypeFilter {
    return t.fuelType === 'Benzine' ? 'Benzine' : 'Diesel';
}

/** น้ำมันที่ถูกใช้ไปแล้ว — ไม่รวมรับเข้า และไม่รวมเบิกไปถังสำรอง */
function isUsageKind(kind: FuelUsageKind): boolean {
    return kind === 'vehicle' || kind === 'sand_sieve' || kind === 'other_out';
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

function aggregateFuelUsageRows(rows: FuelUsageRow[]): Omit<FuelUsageReport, 'rows'> {
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

    return {
        totals,
        byVehicle: Array.from(vehicleMap.entries())
            .map(([vehicleId, v]) => ({ vehicleId, ...v }))
            .sort((a, b) => b.liters - a.liters || a.vehicleId.localeCompare(b.vehicleId, 'th')),
        byDay: Array.from(dayMap.entries())
            .map(([date, v]) => ({ date, ...v }))
            .sort((a, b) => a.date.localeCompare(b.date)),
        byFuelType: Array.from(typeMap.entries())
            .map(([fuelType, v]) => ({ fuelType, ...v }))
            .sort((a, b) => b.liters - a.liters),
    };
}

export function filterFuelUsageReport(report: FuelUsageReport, group: FuelPrintGroup): FuelUsageReport {
    const rows = report.rows.filter(r => fuelPrintGroupOf(r) === group);
    return { rows, ...aggregateFuelUsageRows(rows) };
}

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
        const rawVehicleId = (t.vehicleId || '').trim();
        const vehicleId = normalizeFuelReportVehicleId(
            rawVehicleId
                || (kind === 'sand_sieve' ? FUEL_SAND_SIEVE_VEHICLE_ID : '')
                || (kind === 'vehicle' || kind === 'other_out' ? UNNAMED_VEHICLE : ''),
        );
        if (vehicleFilter && vehicleId !== vehicleFilter) continue;
        const fuelType = resolveFuelType(t);
        if (fuelTypeFilter && fuelType !== fuelTypeFilter) continue;
        if (kindFilter && kind !== kindFilter) continue;
        rows.push({
            id: t.id,
            date,
            kind,
            fuelType,
            tank: fuelUsageTankOf(t),
            vehicleId,
            liters: fuelTxToLiters(t),
            amount: Number(t.amount) || 0,
            description: (t.description || t.workDetails || '').trim(),
            subCategory: String(t.subCategory ?? '').trim() || undefined,
            workType: String(t.workType ?? '').trim() || undefined,
        });
    }

    // แถวร่อนทรายประมาณ — ให้ยอด "ใช้แล้ว" กระทบกับคงเหลือ
    const estimated = filters.estimatedSieveByDay || {};
    if (!vehicleFilter && (!fuelTypeFilter || fuelTypeFilter === 'Diesel') && (!kindFilter || kindFilter === 'sand_sieve')) {
        for (const [dayRaw, liters] of Object.entries(estimated)) {
            const date = normalizeDate(dayRaw);
            if (!liters || date < start || date > end) continue;
            rows.push({
                id: `${date}_fuel_sand_sieve_est`,
                date,
                kind: 'sand_sieve',
                fuelType: 'Diesel',
                tank: 'reserve',
                vehicleId: FUEL_SAND_SIEVE_VEHICLE_ID,
                liters,
                amount: 0,
                description: `ประมาณจากชั่วโมงร่อนทราย ${FUEL_SAND_SIEVE_LITERS_PER_HOUR} ลิตร/ชม.`,
                estimated: true,
                subCategory: FUEL_SAND_SIEVE_SUB_CATEGORY,
            });
        }
    }

    rows.sort((a, b) => {
        const d = a.date.localeCompare(b.date);
        if (d !== 0) return d;
        return a.id.localeCompare(b.id);
    });

    return { rows, ...aggregateFuelUsageRows(rows) };
}

function csvCell(value: string | number): string {
    const s = String(value);
    if (/[",\n\r]/.test(s)) return `"${s.replace(/"/g, '""')}"`;
    return s;
}

export function fuelUsageToCsv(
    report: FuelUsageReport,
    filters: FuelUsageFilters,
    balances?: FuelStockBalances
): string {
    const lines: Array<Array<string | number>> = [
        ['รายงานการใช้น้ำมัน', `${normalizeDate(filters.start)} - ${normalizeDate(filters.end)}`],
        [],
        ['ประเภท', 'ลิตร', 'รายการ'],
        ['รับเข้า (ถังหลัก)', report.totals.stockInLiters, ''],
        ['เบิกไปถังสำรอง', report.totals.withdrawLiters, ''],
        ['ใช้แล้ว (รถ/แม็คโคร)', report.totals.vehicleLiters, ''],
        ['ใช้แล้ว (ร่อนทราย)', report.totals.sandSieveLiters, ''],
        ['ใช้แล้ว (อื่น ๆ)', report.totals.otherOutLiters, ''],
        ['รวมใช้แล้ว', report.totals.usageLiters, report.totals.count],
        ['กระทบยอด (รับเข้า − ใช้แล้ว)', report.totals.stockInLiters - report.totals.usageLiters, ''],
    ];
    if (balances) {
        lines.push(
            [],
            ['คงเหลือ ณ วันสิ้นช่วง'],
            ['ถังหลัก (ดีเซล)', balances.Diesel, ''],
            ['ถังสำรอง (ดีเซล)', balances.DieselReserve, ''],
        );
        if (balances.reserveShortfallLiters > 0) {
            lines.push(['ขาดบันทึกโอนเข้าถังสำรอง', balances.reserveShortfallLiters, '']);
        }
    }
    lines.push(
        [],
        ['สรุปตามรถ'],
        ['รถ', 'ลิตร', 'รายการ'],
        ...report.byVehicle.map(v => [v.vehicleId, v.liters, v.count].map(String)),
        [],
        ['รายละเอียด'],
        ['วันที่', 'รถ', 'ลิตร', 'รายละเอียด'],
        ...report.rows.map(r => [
            r.date,
            r.vehicleId,
            r.liters,
            r.description + (r.estimated ? ' (ประมาณ)' : ''),
        ].map(String)),
    );
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
    orgSubtitle?: string;
    rangeLabel: string;
    report: FuelUsageReport;
    group: FuelPrintGroup;
    formatDate?: (ymd: string) => string;
}): string {
    const fmtLiters = (n: number) => n.toLocaleString('th-TH', { maximumFractionDigits: 2 });
    const fmt = opts.formatDate || ((ymd: string) => ymd);
    const t = opts.report.totals;
    const title = fuelPrintGroupTitle(opts.group);
    const totalLiters = opts.report.rows.reduce((sum, r) => sum + r.liters, 0);

    const detailRows = opts.report.rows.map(r => {
        const vehicle = r.vehicleId || '—';
        const desc = r.description + (r.estimated ? ' (ประมาณ)' : '');
        return `<tr>
<td>${escHtml(fmt(r.date))}</td>
<td>${escHtml(vehicle)}</td>
<td class="num">${escHtml(fmtLiters(r.liters))}</td>
<td>${escHtml(desc || '—')}</td>
</tr>`;
    }).join('') || '<tr><td colspan="4" class="empty">ไม่มีข้อมูลในช่วงนี้</td></tr>';

    let summaryBlock: string;
    if (opts.group === 'other_fill') {
        const fillTotal = t.stockInLiters + t.withdrawLiters + t.vehicleLiters + t.otherOutLiters;
        summaryBlock = `<p class="summary">
<span>รับเข้า (ถังหลัก) <strong>${escHtml(fmtLiters(t.stockInLiters))} ลิตร</strong></span>
<span>เบิกไปถังสำรอง <strong>${escHtml(fmtLiters(t.withdrawLiters))} ลิตร</strong></span>
<span>รวมทั้งหมด <strong>${escHtml(fmtLiters(fillTotal))} ลิตร</strong></span>
</p>`;
    } else {
        summaryBlock = `<p class="summary">รวมใช้ <strong>${escHtml(fmtLiters(totalLiters))} ลิตร</strong> · ${escHtml(t.count)} รายการ</p>`;
    }

    const footerNote = opts.group === 'sieve_generator'
        ? `ร่อนทรายที่ไม่มีแถวจริงประมาณที่ ${FUEL_SAND_SIEVE_LITERS_PER_HOUR} ลิตร/ชม. · สรุปปริมาณเป็นลิตรเท่านั้น`
        : 'สรุปปริมาณน้ำมันเป็นลิตรเท่านั้น ไม่รวมค่าใช้จ่าย';

    return `<!doctype html><html lang="th"><head><meta charset="utf-8"/><title>${escHtml(title)}</title>
<style>
@page{margin:16mm 18mm}
*{box-sizing:border-box}
body{font-family:"Sarabun","Noto Sans Thai",Tahoma,sans-serif;margin:0;padding:0;color:#111827;font-size:13px;line-height:1.5}
.header{padding-bottom:14px;margin-bottom:18px;border-bottom:1px solid #111827}
.org{margin:0 0 2px;font-size:12px;color:#6b7280;letter-spacing:.01em}
h1{margin:0 0 4px;font-size:18px;font-weight:700;letter-spacing:-.01em}
.meta{margin:0;font-size:12px;color:#6b7280}
.summary{margin:0 0 20px;font-size:13px;color:#374151;display:flex;flex-wrap:wrap;gap:16px 24px}
.summary strong{font-variant-numeric:tabular-nums;color:#111827}
table{width:100%;border-collapse:collapse;font-size:12px}
thead th{padding:8px 10px;text-align:left;font-weight:600;color:#374151;border-bottom:1px solid #d1d5db;font-size:11px;text-transform:uppercase;letter-spacing:.04em}
tbody td{padding:7px 10px;border-bottom:1px solid #e5e7eb;vertical-align:top}
tbody tr:last-child td{border-bottom:1px solid #d1d5db}
td.num,th.num{text-align:right;font-variant-numeric:tabular-nums;white-space:nowrap}
td.empty{text-align:center;color:#9ca3af;padding:24px}
tfoot td{padding:10px;font-weight:600;border-top:2px solid #111827}
tfoot td.num{text-align:right;font-variant-numeric:tabular-nums}
.footer{margin-top:24px;padding-top:10px;border-top:1px solid #e5e7eb;font-size:11px;color:#9ca3af}
@media print{body{-webkit-print-color-adjust:exact;print-color-adjust:exact}}
</style></head><body>
<div class="header">
${opts.orgSubtitle ? `<p class="org">${escHtml(opts.orgSubtitle)}</p>` : ''}
<h1>${escHtml(title)}</h1>
<p class="meta">${escHtml(opts.appName)} · ${escHtml(opts.rangeLabel)} · ${escHtml(t.count)} รายการ</p>
</div>
${summaryBlock}
<table>
<thead><tr>
<th>วันที่</th>
<th>${opts.group === 'sieve_generator' ? 'เครื่องจักร' : 'รถ'}</th>
<th class="num">ปริมาณ (ลิตร)</th>
<th>รายละเอียด</th>
</tr></thead>
<tbody>${detailRows}</tbody>
<tfoot><tr>
<td colspan="2">รวม</td>
<td class="num">${escHtml(fmtLiters(totalLiters))}</td>
<td></td>
</tr></tfoot>
</table>
<p class="footer">${escHtml(footerNote)}</p>
</body></html>`;
}
