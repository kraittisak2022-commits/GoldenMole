/** รายชื่อรถชุด mock ใน App.tsx — ห้ามใช้ทับรายชื่อจริงในฐานข้อมูล */
export const MOCK_SEED_CARS = [
    'รถแม็คโคร SK200-8 (น้องโกลเด้น)',
    'รถแม็คโคร SK200-8 (พี่ยักษ์ใหญ่)',
    'รถดรัมโอเว่น',
    'รถดรัมนายก',
    'รถดรัมนายกนิต',
] as const;

export function isExactMockSeedCars(cars: string[] | undefined): boolean {
    if (!cars || cars.length !== MOCK_SEED_CARS.length) return false;
    return MOCK_SEED_CARS.every((name, i) => cars[i] === name);
}

/** กัน saveSettings เขียน cars ว่าง หรือชุด mock ทับรายชื่อที่มีอยู่แล้ว */
export function resolveCarsForSave(
    incoming: string[] | undefined,
    existing: string[] | undefined,
): string[] {
    const next = incoming ?? [];
    const prev = existing ?? [];
    if (next.length === 0 && prev.length > 0) return prev;
    if (isExactMockSeedCars(next) && prev.length > 0 && !isExactMockSeedCars(prev)) {
        return prev;
    }
    return next;
}
