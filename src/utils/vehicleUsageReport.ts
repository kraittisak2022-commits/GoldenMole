import type { Employee, Transaction } from '../types';
import { normalizeDate } from './index';
import { transactionVehicleLabel, type VehicleCatalogRow } from './vehicleCatalog';
import {
    countsAsWizardVehicleUsageRecord,
    isMacroVehicleId,
    transactionCountsAsVehicleTripMenu,
} from '../modules/Dashboard/dailyStepRecorderUtils';
import { driverDisplayName } from '../modules/Dashboard/countRecordUtils';

export type VehicleUsageKind = 'macro' | 'dump_trip' | 'hire';
export type VehiclePrintGroup = 'overview' | 'macro' | 'dump' | 'hire';

export interface VehicleUsageFilters {
    start: string;
    end: string;
    vehicleId?: string;
    kind?: VehicleUsageKind | '';
    vehicleCatalog?: VehicleCatalogRow[];
}

export interface VehicleUsageRow {
    id: string;
    date: string;
    kind: VehicleUsageKind;
    vehicleId: string;
    driverLabel: string;
    workType: 'FullDay' | 'HalfDay' | '';
    workDetails: string;
    trips: number;
    cubic: number;
    amount: number;
    description: string;
}

export interface VehicleUsageTotals {
    macroCount: number;
    macroFullDays: number;
    macroHalfDays: number;
    dumpTripCount: number;
    dumpTrips: number;
    dumpCubic: number;
    hireCount: number;
    hireAmount: number;
    vehicleCount: number;
    count: number;
}

export interface VehicleUsageReport {
    rows: VehicleUsageRow[];
    totals: VehicleUsageTotals;
    byVehicle: Array<{
        vehicleId: string;
        kind: VehicleUsageKind;
        count: number;
        trips: number;
        cubic: number;
        amount: number;
        fullDays: number;
        halfDays: number;
    }>;
    byDay: Array<{
        date: string;
        macroCount: number;
        dumpTrips: number;
        dumpCubic: number;
        hireCount: number;
        count: number;
    }>;
}

const UNNAMED = 'ไม่ระบุรถ';

function stripRecorderSuffix(details: string): string {
    return details.replace(/\s*\(ผู้กรอก:[^)]+\)\s*$/, '').trim();
}

function tripMetrics(t: Transaction): { trips: number; cubic: number } {
    const mode = String((t as { tripBillingMode?: string }).tripBillingMode ?? '').trim().toLowerCase();
    const isLumpSum = mode === 'lumpsum' || mode === 'เหมา';
    const cubic = Number(
        (t as { perCarCubic?: number; totalCubic?: number }).perCarCubic
            ?? (t as { totalCubic?: number }).totalCubic
            ?? 0,
    );
    if (isLumpSum) {
        return { trips: 0, cubic: Number.isFinite(cubic) ? cubic : 0 };
    }
    const trips = Number(
        (t as { perCarTrips?: number; tripCount?: number }).perCarTrips
            ?? (t as { tripCount?: number }).tripCount
            ?? 0,
    );
    return {
        trips: Number.isFinite(trips) ? trips : 0,
        cubic: Number.isFinite(cubic) ? cubic : 0,
    };
}

export function vehicleKindLabel(kind: VehicleUsageKind): string {
    switch (kind) {
        case 'macro': return 'รถแม็คโคร';
        case 'dump_trip': return 'เที่ยวรถดั๊ม / สิบล้อ / ดรัม';
        default: return 'การใช้รถ (ค่าจ้าง)';
    }
}

export function vehiclePrintGroupTitle(group: VehiclePrintGroup, locale: 'th' | 'zh' = 'th'): string {
    if (locale === 'zh') {
        switch (group) {
            case 'macro': return '挖掘机使用报告';
            case 'dump': return '自卸/十轮/滚筒趟次报告';
            case 'hire': return '车辆雇佣报告';
            default: return '车辆使用报表总览';
        }
    }
    switch (group) {
        case 'macro': return 'รายงานการใช้รถแม็คโคร';
        case 'dump': return 'รายงานเที่ยวรถดั๊ม สิบล้อ ดรัม';
        case 'hire': return 'รายงานการใช้รถ (ค่าจ้าง)';
        default: return 'สรุปภาพรวมรายงานการใช้รถ';
    }
}

function classifyVehicleRow(
    t: Transaction,
    catalog: VehicleCatalogRow[] = [],
): VehicleUsageKind | null {
    const label = transactionVehicleLabel(t, catalog);
    if (t.category === 'Vehicle' && isMacroVehicleId(label || t.vehicleId)) {
        return 'macro';
    }
    if (transactionCountsAsVehicleTripMenu(t)) return 'dump_trip';
    if (countsAsWizardVehicleUsageRecord(t)) return 'hire';
    return null;
}

function aggregateVehicleUsageRows(rows: VehicleUsageRow[]): Omit<VehicleUsageReport, 'rows'> {
    const totals: VehicleUsageTotals = {
        macroCount: 0,
        macroFullDays: 0,
        macroHalfDays: 0,
        dumpTripCount: 0,
        dumpTrips: 0,
        dumpCubic: 0,
        hireCount: 0,
        hireAmount: 0,
        vehicleCount: 0,
        count: rows.length,
    };
    const byVehicleMap = new Map<string, VehicleUsageReport['byVehicle'][number]>();
    const byDayMap = new Map<string, VehicleUsageReport['byDay'][number]>();
    const vehicleIds = new Set<string>();

    for (const row of rows) {
        vehicleIds.add(row.vehicleId);
        if (row.kind === 'macro') {
            totals.macroCount += 1;
            if (row.workType === 'HalfDay') totals.macroHalfDays += 1;
            else totals.macroFullDays += 1;
        } else if (row.kind === 'dump_trip') {
            totals.dumpTripCount += 1;
            totals.dumpTrips += row.trips;
            totals.dumpCubic += row.cubic;
        } else {
            totals.hireCount += 1;
            totals.hireAmount += row.amount;
        }

        const vKey = `${row.kind}|${row.vehicleId}`;
        const prevV = byVehicleMap.get(vKey) || {
            vehicleId: row.vehicleId,
            kind: row.kind,
            count: 0,
            trips: 0,
            cubic: 0,
            amount: 0,
            fullDays: 0,
            halfDays: 0,
        };
        prevV.count += 1;
        prevV.trips += row.trips;
        prevV.cubic += row.cubic;
        prevV.amount += row.amount;
        if (row.kind === 'macro') {
            if (row.workType === 'HalfDay') prevV.halfDays += 1;
            else prevV.fullDays += 1;
        }
        byVehicleMap.set(vKey, prevV);

        const prevD = byDayMap.get(row.date) || {
            date: row.date,
            macroCount: 0,
            dumpTrips: 0,
            dumpCubic: 0,
            hireCount: 0,
            count: 0,
        };
        prevD.count += 1;
        if (row.kind === 'macro') prevD.macroCount += 1;
        if (row.kind === 'dump_trip') {
            prevD.dumpTrips += row.trips;
            prevD.dumpCubic += row.cubic;
        }
        if (row.kind === 'hire') prevD.hireCount += 1;
        byDayMap.set(row.date, prevD);
    }

    totals.vehicleCount = vehicleIds.size;

    const byVehicle = [...byVehicleMap.values()].sort((a, b) => {
        const k = a.kind.localeCompare(b.kind);
        if (k !== 0) return k;
        return a.vehicleId.localeCompare(b.vehicleId, 'th');
    });
    const byDay = [...byDayMap.values()].sort((a, b) => a.date.localeCompare(b.date));

    return { totals, byVehicle, byDay };
}

export function buildVehicleUsageReport(
    transactions: Transaction[],
    employees: Employee[],
    filters: VehicleUsageFilters,
): VehicleUsageReport {
    const start = normalizeDate(filters.start);
    const end = normalizeDate(filters.end);
    const from = start <= end ? start : end;
    const to = start <= end ? end : start;
    const catalog = filters.vehicleCatalog || [];
    const wantVehicle = (filters.vehicleId || '').trim();
    const wantKind = filters.kind || '';

    const rows: VehicleUsageRow[] = [];

    for (const t of transactions) {
        const date = normalizeDate(t.date);
        if (date < from || date > to) continue;
        const kind = classifyVehicleRow(t, catalog);
        if (!kind) continue;
        if (wantKind && kind !== wantKind) continue;

        const vehicleId = transactionVehicleLabel(t, catalog)
            || String(t.vehicleId ?? '').trim()
            || UNNAMED;
        if (wantVehicle && vehicleId !== wantVehicle) continue;

        const driverId = String(t.driverId ?? '').trim();
        const workDetails = stripRecorderSuffix(String(t.workDetails ?? t.description ?? ''));
        const workType = t.workType === 'HalfDay' ? 'HalfDay' : t.workType === 'FullDay' ? 'FullDay' : '';
        const metrics = kind === 'dump_trip' ? tripMetrics(t) : { trips: 0, cubic: 0 };
        const amount = kind === 'hire'
            ? Number(t.amount || 0) || Number((t as { vehicleWage?: number }).vehicleWage || 0)
            : 0;

        rows.push({
            id: t.id,
            date,
            kind,
            vehicleId,
            driverLabel: driverId ? driverDisplayName(driverId, employees) : '—',
            workType: kind === 'macro' ? (workType || 'FullDay') : '',
            workDetails,
            trips: metrics.trips,
            cubic: metrics.cubic,
            amount,
            description: workDetails || vehicleKindLabel(kind),
        });
    }

    rows.sort((a, b) => {
        const d = a.date.localeCompare(b.date);
        if (d !== 0) return d;
        const k = a.kind.localeCompare(b.kind);
        if (k !== 0) return k;
        return a.vehicleId.localeCompare(b.vehicleId, 'th');
    });

    return { rows, ...aggregateVehicleUsageRows(rows) };
}

export function filterVehicleUsageReport(
    report: VehicleUsageReport,
    group: Exclude<VehiclePrintGroup, 'overview'>,
): VehicleUsageReport {
    const kind: VehicleUsageKind = group === 'dump' ? 'dump_trip' : group === 'hire' ? 'hire' : 'macro';
    const rows = report.rows.filter((r) => r.kind === kind);
    return { rows, ...aggregateVehicleUsageRows(rows) };
}

export function filterVehicleUsageByVehicle(
    report: VehicleUsageReport,
    vehicleId: string,
): VehicleUsageReport {
    const want = vehicleId.trim();
    const rows = want ? report.rows.filter((r) => r.vehicleId === want) : report.rows;
    return { rows, ...aggregateVehicleUsageRows(rows) };
}

export function filterVehicleUsageByDate(
    report: VehicleUsageReport,
    date: string,
): VehicleUsageReport {
    const want = normalizeDate(date);
    const rows = want ? report.rows.filter((r) => r.date === want) : report.rows;
    return { rows, ...aggregateVehicleUsageRows(rows) };
}

export function vehiclePrintOverviewSections(report: VehicleUsageReport): Array<{
    id: string;
    title: string;
    count: number;
    items: Array<{ group: Exclude<VehiclePrintGroup, 'overview'>; title: string; count: number; metric: string }>;
}> {
    const macro = report.rows.filter((r) => r.kind === 'macro');
    const dump = report.rows.filter((r) => r.kind === 'dump_trip');
    const hire = report.rows.filter((r) => r.kind === 'hire');
    return [
        {
            id: 'receive_vs_use',
            title: 'ภาพรวมการใช้รถ',
            count: report.totals.count,
            items: [
                {
                    group: 'macro',
                    title: vehiclePrintGroupTitle('macro'),
                    count: macro.length,
                    metric: `${report.totals.macroFullDays} เต็มวัน · ${report.totals.macroHalfDays} ครึ่งวัน`,
                },
                {
                    group: 'dump',
                    title: vehiclePrintGroupTitle('dump'),
                    count: dump.length,
                    metric: `${dump.length} รายการ`,
                },
                {
                    group: 'hire',
                    title: vehiclePrintGroupTitle('hire'),
                    count: hire.length,
                    metric: `${hire.length} รายการ`,
                },
            ],
        },
    ];
}

function csvCell(value: string | number): string {
    const s = String(value);
    if (/[",\n\r]/.test(s)) return `"${s.replace(/"/g, '""')}"`;
    return s;
}

export function vehicleUsageToCsv(
    report: VehicleUsageReport,
    filters: VehicleUsageFilters,
): string {
    const lines: Array<Array<string | number>> = [
        ['รายงานการใช้รถ', `${normalizeDate(filters.start)} - ${normalizeDate(filters.end)}`],
        [],
        ['ประเภท', 'รายการ'],
        ['รถแม็คโคร', report.totals.macroCount],
        ['เที่ยวรถดั๊ม/สิบล้อ/ดรัม', report.totals.dumpTripCount],
        ['การใช้รถ (ค่าจ้าง)', report.totals.hireCount],
        ['รวม', report.totals.count],
        [],
        ['สรุปตามรถ'],
        ['ประเภท', 'รถ', 'รายการ'],
        ...report.byVehicle.map((v) => [
            vehicleKindLabel(v.kind),
            v.vehicleId,
            v.count,
        ]),
        [],
        ['รายละเอียด'],
        ['วันที่', 'ประเภท', 'รถ', 'คนขับ', 'รายละเอียด'],
        ...report.rows.map((r) => [
            r.date,
            vehicleKindLabel(r.kind),
            r.vehicleId,
            r.driverLabel,
            r.description,
        ]),
    ];
    const body = lines.map((cols) => cols.map(csvCell).join(',')).join('\n');
    return `\ufeff${body}`;
}

function escHtml(value: string | number): string {
    return String(value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

export function vehicleUsageToPrintHtml(opts: {
    appName: string;
    orgSubtitle?: string;
    rangeLabel: string;
    report: VehicleUsageReport;
    group: VehiclePrintGroup;
    formatDate: (ymd: string) => string;
    locale?: 'th' | 'zh';
    vehicleTitle?: string;
    dayTitle?: string;
}): string {
    const locale = opts.locale || 'th';
    const baseTitle = vehiclePrintGroupTitle(opts.group, locale);
    const title = [baseTitle, opts.vehicleTitle, opts.dayTitle].filter(Boolean).join(' · ');
    const th = locale === 'zh'
        ? {
            date: '日期',
            vehicle: '车辆',
            driver: '司机',
            detail: '详情',
            count: '笔数',
            dayTotal: '当日合计',
        }
        : {
            date: 'วันที่',
            vehicle: 'รถ',
            driver: 'คนขับ',
            detail: 'รายละเอียด',
            count: 'รายการ',
            dayTotal: 'รวมวันนั้น',
        };

    const byDate = new Map<string, typeof opts.report.rows>();
    for (const row of opts.report.rows) {
        const list = byDate.get(row.date) || [];
        list.push(row);
        byDate.set(row.date, list);
    }

    const bodyHtml = [...byDate.entries()].map(([date, dayRows]) => {
        const rows = dayRows.map((r) => `<tr>
          <td>${escHtml(r.vehicleId)}</td>
          <td>${escHtml(r.driverLabel)}</td>
          <td>${escHtml(r.description || '—')}</td>
        </tr>`).join('');
        return `
        <section class="day">
          <h2>${escHtml(opts.formatDate(date))}
            <span>${dayRows.length} ${th.count}</span>
          </h2>
          <table>
            <thead>
              <tr>
                <th>${th.vehicle}</th>
                <th>${th.driver}</th>
                <th>${th.detail}</th>
              </tr>
            </thead>
            <tbody>${rows}</tbody>
          </table>
        </section>`;
    }).join('');

    return `<!DOCTYPE html>
<html lang="${locale === 'zh' ? 'zh-CN' : 'th'}">
<head>
<meta charset="utf-8" />
<title>${escHtml(title)}</title>
<style>
  body { font-family: "Sarabun", "Noto Sans Thai", "Microsoft YaHei", sans-serif; color: #0f172a; margin: 24px; }
  h1 { font-size: 18px; margin: 0 0 4px; }
  .meta { color: #64748b; font-size: 12px; margin-bottom: 16px; }
  .day { margin: 0 0 18px; page-break-inside: avoid; border: 1px solid #e2e8f0; border-radius: 10px; overflow: hidden; }
  .day h2 { margin: 0; padding: 10px 12px; background: #f1f5f9; font-size: 14px; display: flex; justify-content: space-between; gap: 8px; }
  .day h2 span { color: #64748b; font-weight: 600; font-size: 12px; }
  table { width: 100%; border-collapse: collapse; font-size: 12px; }
  th, td { border-top: 1px solid #e2e8f0; padding: 8px 10px; text-align: left; vertical-align: top; }
  th { background: #f8fafc; }
  .tiles { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 14px; }
  .tile { border: 1px solid #e2e8f0; border-radius: 8px; padding: 8px 10px; min-width: 120px; }
  .tile b { display: block; font-size: 16px; }
  .tile span { color: #64748b; font-size: 11px; }
  @media print { body { margin: 12px; } .day { break-inside: avoid; } }
</style>
</head>
<body>
  <h1>${escHtml(opts.appName)}</h1>
  ${opts.orgSubtitle ? `<div class="meta">${escHtml(opts.orgSubtitle)}</div>` : ''}
  <div class="meta"><strong>${escHtml(title)}</strong> · ${escHtml(opts.rangeLabel)} · ${opts.report.totals.count} ${th.count}</div>
  <div class="tiles">
    <div class="tile"><span>${th.count}</span><b>${opts.report.totals.count}</b></div>
    <div class="tile"><span>${th.vehicle}</span><b>${opts.report.totals.vehicleCount}</b></div>
  </div>
  ${bodyHtml || `<p>—</p>`}
</body>
</html>`;
}
