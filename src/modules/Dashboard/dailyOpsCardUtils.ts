import type { Employee, Transaction } from '../../types';
import { normalizeDate } from '../../utils';
import {
    classifyAttendancePositionGroup,
    isSandYardOrMacroDriverEmployee,
    type AttendancePositionGroup,
} from '../../utils/advanceEmployeeFilter';
import { buildFuelUsageReport, filterFuelUsageReport } from '../../utils/fuelUsageReport';
import { leaveRecordCoversDay } from '../../utils/laborLeaveSpan';
import { transactionVehicleLabel, type VehicleCatalogRow } from '../../utils/vehicleCatalog';
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

export interface AttendancePerson {
    id: string;
    name: string;
    ot: boolean;
    group: AttendancePositionGroup;
}

export interface AttendanceSummary {
    present: number;
    leave: number;
    absent: number;
    presentPeople: AttendancePerson[];
    leavePeople: AttendancePerson[];
    absentPeople: AttendancePerson[];
}

const stripRecorderSuffix = (details: string): string =>
    details.replace(/\s*\(ผู้กรอก:[^)]+\)\s*$/, '').trim();

function isMacroWorkRow(t: Transaction, dayKey: string, catalog: VehicleCatalogRow[] = []): boolean {
    if (normalizeDate(t.date) !== normalizeDate(dayKey)) return false;
    if (t.category !== 'Vehicle') return false;
    const label = transactionVehicleLabel(t, catalog);
    if (!isMacroVehicleId(label)) return false;
    return Boolean(label);
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

function macroFuelLitersByVehicle(
    dayKey: string,
    transactions: Transaction[],
    catalog: VehicleCatalogRow[] = [],
): Map<string, number> {
    const report = filterFuelUsageReport(
        buildFuelUsageReport(transactions, { start: dayKey, end: dayKey }),
        'macro',
    );
    const map = new Map<string, number>();
    for (const row of report.byVehicle) {
        const raw = String(row.vehicleId ?? '').trim();
        if (!raw) continue;
        const key = transactionVehicleLabel({ vehicleId: raw }, catalog);
        map.set(key, (map.get(key) ?? 0) + row.liters);
    }
    return map;
}

export function buildMacroUsageSummary(
    dayKey: string,
    transactions: Transaction[],
    employees: Employee[],
    catalog: VehicleCatalogRow[] = [],
): MacroUsageSummary {
    const fuelByVehicle = macroFuelLitersByVehicle(dayKey, transactions, catalog);
    const workByVehicle = new Map<string, Transaction>();

    for (const t of transactions) {
        if (!isMacroWorkRow(t, dayKey, catalog)) continue;
        const vehicleId = transactionVehicleLabel(t, catalog);
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
    const byId = new Map(employees.map((e) => [e.id, e]));
    const rosterIds = new Set(
        employees
            .filter((e) => !e.inactive && isSandYardOrMacroDriverEmployee(e))
            .map((e) => e.id),
    );
    const presentIds = new Set<string>();
    const otIds = new Set<string>();

    for (const t of transactions) {
        if (normalizeDate(t.date) !== day) continue;
        if (t.category !== 'Labor') continue;
        if (t.laborStatus !== 'Work' && t.laborStatus !== 'OT') continue;
        for (const id of t.employeeIds ?? []) {
            const eid = String(id).trim();
            if (!eid || !rosterIds.has(eid)) continue;
            presentIds.add(eid);
            if (t.laborStatus === 'OT') otIds.add(eid);
        }
    }

    const leaveIds = new Set<string>();
    for (const t of transactions) {
        if (!leaveRecordCoversDay(t, dayKey)) continue;
        for (const id of t.employeeIds ?? []) {
            const eid = String(id).trim();
            if (eid && rosterIds.has(eid)) leaveIds.add(eid);
        }
    }

    const toPerson = (id: string): AttendancePerson => {
        const emp = byId.get(id);
        return {
            id,
            name: employeeDisplayName(id, employees),
            ot: otIds.has(id),
            group: emp ? classifyAttendancePositionGroup(emp) : 'other',
        };
    };

    const presentPeople: AttendancePerson[] = [...presentIds]
        .map(toPerson)
        .sort((a, b) => a.name.localeCompare(b.name, 'th'));

    const leavePeople: AttendancePerson[] = [...leaveIds]
        .filter((id) => !presentIds.has(id))
        .map(toPerson)
        .sort((a, b) => a.name.localeCompare(b.name, 'th'));

    const absentPeople: AttendancePerson[] = [...rosterIds]
        .filter((id) => !presentIds.has(id) && !leaveIds.has(id))
        .map(toPerson)
        .sort((a, b) => a.name.localeCompare(b.name, 'th'));

    return {
        present: presentPeople.length,
        leave: leavePeople.length,
        absent: absentPeople.length,
        presentPeople,
        leavePeople,
        absentPeople,
    };
}
