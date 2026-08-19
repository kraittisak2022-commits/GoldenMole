export interface VehicleCatalogRow {
    id: string;
    name: string;
    defaultDriverId: string | null;
    sortOrder: number;
}

export function vehiclesToCarsAndDrivers(rows: VehicleCatalogRow[]): {
    cars: string[];
    vehicleDefaultDrivers: Record<string, string>;
} {
    const sorted = [...rows].sort((a, b) => a.sortOrder - b.sortOrder || a.name.localeCompare(b.name, 'th'));
    const cars: string[] = [];
    const vehicleDefaultDrivers: Record<string, string> = {};
    for (const row of sorted) {
        const name = row.name.trim();
        if (!name) continue;
        cars.push(name);
        const driverId = row.defaultDriverId?.trim();
        if (driverId) vehicleDefaultDrivers[name] = driverId;
    }
    return { cars, vehicleDefaultDrivers };
}

export function makeVehicleId(name: string): string {
    const key = name.trim();
    let hash = 0;
    for (let i = 0; i < key.length; i += 1) {
        hash = ((hash << 5) - hash + key.charCodeAt(i)) | 0;
    }
    return `v_${Math.abs(hash).toString(16)}`;
}

export function catalogFromCarsAndDrivers(
    cars: string[],
    drivers: Record<string, string>,
    existing: VehicleCatalogRow[] = [],
): VehicleCatalogRow[] {
    const byName = new Map(existing.map((row) => [row.name.trim(), row]));
    const usedIds = new Set<string>();
    const next: VehicleCatalogRow[] = [];
    cars.forEach((raw, index) => {
        const name = raw.trim();
        if (!name) return;
        const prev = byName.get(name);
        let id = prev?.id || makeVehicleId(name);
        if (usedIds.has(id)) id = `${id}_${index}`;
        usedIds.add(id);
        const driverId = drivers[name]?.trim() || null;
        next.push({
            id,
            name,
            defaultDriverId: driverId,
            sortOrder: index,
        });
    });
    return next;
}
