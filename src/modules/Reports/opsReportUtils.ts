import type { Employee, Transaction } from '../../types';
import { normalizeDate } from '../../utils';
import { transactionVehicleLabel, type VehicleCatalogRow } from '../../utils/vehicleCatalog';
import {
    isVehicleTripDrumCarName,
    transactionCountsAsVehicleTripMenu,
} from '../Dashboard/dailyStepRecorderUtils';
import { driverDisplayName, isCountRecordVehicleRow } from '../Dashboard/countRecordUtils';
import {
    buildAttendanceSummary,
    buildMacroUsageSummary,
    type AttendanceSummary,
    type MacroUsageRow,
} from '../Dashboard/dailyOpsCardUtils';

export interface AttendanceDayReport extends AttendanceSummary {
    date: string;
}

function eachDayKey(start: string, end: string): string[] {
    const a = normalizeDate(start);
    const b = normalizeDate(end);
    const from = a <= b ? a : b;
    const to = a <= b ? b : a;
    const days: string[] = [];
    const cursor = new Date(`${from}T12:00:00+07:00`);
    const endDate = new Date(`${to}T12:00:00+07:00`);
    while (cursor.getTime() <= endDate.getTime()) {
        const y = cursor.getFullYear();
        const m = String(cursor.getMonth() + 1).padStart(2, '0');
        const d = String(cursor.getDate()).padStart(2, '0');
        days.push(`${y}-${m}-${d}`);
        cursor.setDate(cursor.getDate() + 1);
    }
    return days;
}

/** สรุปพนักงานรายวันในช่วงวันที่ (พูลท่าทราย + คนขับแม็คโคร) */
export function buildAttendanceRangeReport(
    start: string,
    end: string,
    transactions: Transaction[],
    employees: Employee[],
): AttendanceDayReport[] {
    return eachDayKey(start, end).map((dayKey) => ({
        date: dayKey,
        ...buildAttendanceSummary(dayKey, transactions, employees),
    }));
}

export interface MacroDayUsageRow extends MacroUsageRow {
    date: string;
}

/** รวมการใช้แม็คโครรายวันในช่วงวันที่ */
export function buildMacroUsageRangeReport(
    start: string,
    end: string,
    transactions: Transaction[],
    employees: Employee[],
    catalog: VehicleCatalogRow[] = [],
): MacroDayUsageRow[] {
    const rows: MacroDayUsageRow[] = [];
    for (const dayKey of eachDayKey(start, end)) {
        const summary = buildMacroUsageSummary(dayKey, transactions, employees, catalog);
        for (const row of summary.rows) {
            rows.push({ date: dayKey, ...row });
        }
    }
    return rows;
}

export interface DumpTripUsageRow {
    date: string;
    vehicleId: string;
    driverLabel: string;
    trips: number;
    cubic: number;
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

/** สรุปเที่ยวรถดั๊ม / สิบล้อ / ดรัม ตามวันและคัน */
export function buildDumpTripUsageReport(
    start: string,
    end: string,
    transactions: Transaction[],
    employees: Employee[],
    catalog: VehicleCatalogRow[] = [],
): DumpTripUsageRow[] {
    const a = normalizeDate(start);
    const b = normalizeDate(end);
    const from = a <= b ? a : b;
    const to = a <= b ? b : a;
    const map = new Map<string, DumpTripUsageRow>();

    for (const t of transactions) {
        if (!isCountRecordVehicleRow(t) && !transactionCountsAsVehicleTripMenu(t)) continue;
        const date = normalizeDate(t.date);
        if (date < from || date > to) continue;
        const label = transactionVehicleLabel(
            { vehicleId: t.vehicleId, vehicleName: t.vehicleName },
            catalog,
        );
        if (!isVehicleTripDrumCarName(label) && !isVehicleTripDrumCarName(t.vehicleId)) continue;
        const vehicleId = label || String(t.vehicleId ?? '').trim() || 'ไม่ระบุรถ';
        const key = `${date}|${vehicleId}`;
        const metrics = tripMetrics(t);
        const driverId = String(t.driverId ?? '').trim();
        const existing = map.get(key);
        if (existing) {
            existing.trips += metrics.trips;
            existing.cubic += metrics.cubic;
            if (existing.driverLabel === '—' && driverId) {
                existing.driverLabel = driverDisplayName(driverId, employees);
            }
        } else {
            map.set(key, {
                date,
                vehicleId,
                driverLabel: driverId ? driverDisplayName(driverId, employees) : '—',
                trips: metrics.trips,
                cubic: metrics.cubic,
            });
        }
    }

    return [...map.values()].sort((x, y) => {
        const d = x.date.localeCompare(y.date);
        if (d !== 0) return d;
        return x.vehicleId.localeCompare(y.vehicleId, 'th');
    });
}
