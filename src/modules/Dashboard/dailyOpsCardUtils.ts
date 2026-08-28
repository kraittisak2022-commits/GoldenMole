import type { Employee, Transaction } from '../../types';
import { normalizeDate } from '../../utils';
import { buildFuelUsageReport, filterFuelUsageReport } from '../../utils/fuelUsageReport';
import { leaveRecordCoversDay } from '../../utils/laborLeaveSpan';
import { isMacroVehicleId } from './dailyStepRecorderUtils';
import { driverDisplayName } from './countRecordUtils';

export interface MacroUsageRow {
    vehicleId: string;
    driverLabel: string;
    workType: 'FullDay' | 'HalfDay';
    workDetails: string;
    liters: number;
}

export interface MacroUsageSummary {
    rows: MacroUsageRow[];
    vehicleCount: number;
    totalLiters: number;
}

export interface AttendanceSummary {
    present: number;
    leave: number;
    absent: number;
    presentNames: string[];
}

const stripRecorderSuffix = (details: string): string =>
    details.replace(/\s*\(ผู้กรอก:[^)]+\)\s*$/, '').trim();

function isMacroWorkRow(t: Transaction, dayKey: string): boolean {
    if (normalizeDate(t.date) !== normalizeDate(dayKey)) return false;
    if (t.category !== 'Vehicle') return false;
    if (!isMacroVehicleId(t.vehicleId)) return false;
    const vehicleId = String(t.vehicleId ?? '').trim();
    return Boolean(vehicleId);
}

function employeeDisplayName(employeeId: string, employees: Employee[]): string {
    const id = employeeId.trim();
    if (!id) return 'ยังไม่ระบุ';
    const emp = employees.find((e) => e.id === id);
    if (!emp) return id;
    if (emp.nickname?.trim()) return emp.nickname.trim();
    if (emp.name?.trim()) return emp.name.trim();
    return id;
}

function macroFuelLitersByVehicle(dayKey: string, transactions: Transaction[]): Map<string, number> {
    const report = filterFuelUsageReport(
        buildFuelUsageReport(transactions, { start: dayKey, end: dayKey }),
        'macro',
    );
    const map = new Map<string, number>();
    for (const row of report.byVehicle) {
        const vid = String(row.vehicleId ?? '').trim();
        if (!vid) continue;
        map.set(vid, (map.get(vid) ?? 0) + row.liters);
    }
    return map;
}

export function buildMacroUsageSummary(
    dayKey: string,
    transactions: Transaction[],
    employees: Employee[],
): MacroUsageSummary {
    const fuelByVehicle = macroFuelLitersByVehicle(dayKey, transactions);
    const workByVehicle = new Map<string, Transaction>();

    for (const t of transactions) {
        if (!isMacroWorkRow(t, dayKey)) continue;
        const vehicleId = String(t.vehicleId ?? '').trim();
        workByVehicle.set(vehicleId, t);
    }

    const vehicleIds = new Set<string>([...workByVehicle.keys(), ...fuelByVehicle.keys()]);
    const rows: MacroUsageRow[] = [];

    for (const vehicleId of [...vehicleIds].sort((a, b) => a.localeCompare(b, 'th'))) {
        const work = workByVehicle.get(vehicleId);
        const driverId = String(work?.driverId ?? '').trim();
        const workType = work?.workType === 'HalfDay' ? 'HalfDay' : 'FullDay';
        rows.push({
            vehicleId,
            driverLabel: driverId ? driverDisplayName(driverId, employees) : '—',
            workType,
            workDetails: stripRecorderSuffix(String(work?.workDetails ?? '')),
            liters: fuelByVehicle.get(vehicleId) ?? 0,
        });
    }

    const totalLiters = rows.reduce((sum, row) => sum + row.liters, 0);
    return {
        rows,
        vehicleCount: rows.filter((row) => workByVehicle.has(row.vehicleId)).length,
        totalLiters,
    };
}

export function buildAttendanceSummary(
    dayKey: string,
    transactions: Transaction[],
    employees: Employee[],
): AttendanceSummary {
    const day = normalizeDate(dayKey);
    const presentIds = new Set<string>();

    for (const t of transactions) {
        if (normalizeDate(t.date) !== day) continue;
        if (t.category !== 'Labor') continue;
        if (t.laborStatus !== 'Work' && t.laborStatus !== 'OT') continue;
        for (const id of t.employeeIds ?? []) {
            const eid = String(id).trim();
            if (eid) presentIds.add(eid);
        }
    }

    const leaveIds = new Set<string>();
    for (const t of transactions) {
        if (!leaveRecordCoversDay(t, dayKey)) continue;
        for (const id of t.employeeIds ?? []) {
            const eid = String(id).trim();
            if (eid) leaveIds.add(eid);
        }
    }

    const activeEmployees = employees.filter((e) => !e.inactive);
    const presentNames = [...presentIds]
        .map((id) => employeeDisplayName(id, employees))
        .sort((a, b) => a.localeCompare(b, 'th'));

    const present = presentIds.size;
    const leave = leaveIds.size;
    const absent = Math.max(0, activeEmployees.length - present - leave);

    return { present, leave, absent, presentNames };
}
