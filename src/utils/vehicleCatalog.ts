export interface VehicleCatalogRow {
    id: string;
    name: string;
    defaultDriverId: string | null;
    sortOrder: number;
}

export function looksLikeCatalogVehicleId(raw?: string | null): boolean {
    const s = (raw ?? '').trim();
    return s.startsWith('v_') && s.length >= 4;
}

export function findVehicleCatalogRow(
    raw: string,
    catalog: VehicleCatalogRow[] = [],
): VehicleCatalogRow | undefined {
    const key = raw.trim();
    if (!key || catalog.length === 0) return undefined;
    const exact = catalog.find((row) => row.id === key || row.name === key);
    if (exact) return exact;
    return undefined;
}

/**
 * ชื่อรถสำหรับแสดงบน UI — ใช้ vehicleName ก่อน แล้วค่อย lookup จากแคตตาล็อก
 * (แถวใหม่มักเก็บ vehicleId เป็นรหัส v_… และชื่อจริงอยู่ใน vehicleName)
 */
export function transactionVehicleLabel(
    t: { vehicleId?: string | null; vehicleName?: string | null },
    catalog: VehicleCatalogRow[] = [],
): string {
    const name = String(t.vehicleName ?? '').trim();
    if (name && !looksLikeCatalogVehicleId(name)) return name;

    const id = String(t.vehicleId ?? '').trim();
    if (!id) return name;

    const hit = findVehicleCatalogRow(id, catalog) ?? (name ? findVehicleCatalogRow(name, catalog) : undefined);
    if (hit?.name) return hit.name.trim();

    if (name) return name;
    return id;
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
