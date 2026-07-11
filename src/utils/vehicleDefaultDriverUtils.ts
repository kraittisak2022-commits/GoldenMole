import type { AppSettings, Employee } from '../types';

const DRIVER_POSITION = 'คนขับรถ';

export function getEmpPositions(e: Employee): string[] {
    return e.positions ?? (e.position ? [e.position] : []);
}

export function getDriverEmployees(employees: Employee[]): Employee[] {
    return employees.filter((e) => getEmpPositions(e).includes(DRIVER_POSITION));
}

export function getVehicleDefaultDriversMap(settings: AppSettings): Record<string, string> {
    return { ...(settings.appDefaults?.vehicleDefaultDrivers ?? {}) };
}

export function getVehicleDefaultDriverId(vehicleId: string, settings: AppSettings): string | null {
    const vehicle = vehicleId.trim();
    if (!vehicle) return null;
    const map = settings.appDefaults?.vehicleDefaultDrivers ?? {};
    const driverId = map[vehicle]?.trim();
    return driverId || null;
}

export function setVehicleDefaultDriver(
    map: Record<string, string>,
    vehicle: string,
    driverId?: string | null,
): Record<string, string> {
    const key = vehicle.trim();
    if (!key) return map;
    const next = { ...map };
    const id = driverId?.trim();
    if (!id) {
        delete next[key];
    } else {
        next[key] = id;
    }
    return next;
}

export function renameVehicleDefaultDriver(
    map: Record<string, string>,
    oldName: string,
    newName: string,
): Record<string, string> {
    const oldKey = oldName.trim();
    const newKey = newName.trim();
    if (!oldKey || !newKey || oldKey === newKey) return map;
    const next = { ...map };
    if (oldKey in next) {
        next[newKey] = next[oldKey]!;
        delete next[oldKey];
    }
    return next;
}

export function removeVehicleDefaultDriver(
    map: Record<string, string>,
    vehicle: string,
): Record<string, string> {
    const key = vehicle.trim();
    if (!key || !(key in map)) return map;
    const next = { ...map };
    delete next[key];
    return next;
}

export function driverLabel(employees: Employee[], driverId: string | null | undefined): string {
    const id = driverId?.trim();
    if (!id) return '—';
    const emp = employees.find((e) => e.id === id);
    if (!emp) return id;
    if (emp.nickname?.trim()) return emp.nickname.trim();
    if (emp.name?.trim()) return emp.name.trim();
    return id;
}

export function driverOptionLabel(
    employee: Employee,
    defaultDriverId: string | null | undefined,
): string {
    const label = employee.nickname?.trim() || employee.name?.trim() || employee.id;
    if (defaultDriverId && employee.id === defaultDriverId) {
        return `${label} (ค่าเริ่มต้น)`;
    }
    return label;
}
