import type { Employee, Transaction } from '../../types';
import { isMacroVehicleId } from './dailyStepRecorderUtils';

export const VEHICLE_BUTTON_COLORS = [
    '#1565C0',
    '#2E7D32',
    '#E65100',
    '#6A1B9A',
    '#00838F',
    '#C62828',
    '#4527A0',
    '#558B2F',
] as const;

/** Daily sand-wash round target used by V.4 overview + analytics */
export const SAND_TARGET_ROUNDS = 800;

export function formatDashboardMetric(v: number): string {
    if (Math.abs(v) < 1e-9) return '0';
    if (Math.abs(v - Math.round(v)) < 1e-9) return String(Math.round(v));
    const s = v.toFixed(1);
    return s.endsWith('.0') ? s.slice(0, -2) : s;
}

export function isCountRecordVehicleRow(t: Transaction): boolean {
    if (t.category !== 'DailyLog') return false;
    if (String(t.subCategory ?? '').trim().toLowerCase() !== 'vehicletrip') return false;
    return !String(t.description ?? '').includes('ทรายที่ล้างที่บ้าน');
}

/** แถวการนับ «บันทึกและนับจำนวน → การร่อนทราย» */
export function isCountRecordSandTapRow(t: Transaction): boolean {
    if (t.category !== 'DailyLog') return false;
    if (String(t.subCategory ?? '').trim().toLowerCase() !== 'sand') return false;
    const desc = String(t.description ?? '');
    if (desc.includes('เครื่องร่อน')) return false;
    if (desc.includes('จำนวนถัง')) return false;
    if (desc.includes('ทรายที่ล้างที่บ้าน')) return false;
    return desc.includes('ร่อนทราย');
}

export function getLapTimes(t: Transaction): string[] {
    const wa = t.workAssignments as Record<string, string[] | undefined> | undefined;
    const laps = wa?.lapTimes;
    if (!Array.isArray(laps)) return [];
    return laps.map((x) => String(x));
}

export function countRecordRowHasLapTimes(t: Transaction): boolean {
    return getLapTimes(t).length > 0;
}

export function countRecordRowHasSavedData(t: Transaction): boolean {
    if (isCountRecordVehicleRow(t)) {
        const trips = Number((t as { perCarTrips?: number; tripCount?: number }).perCarTrips ?? (t as { tripCount?: number }).tripCount ?? 0);
        return trips > 0 || countRecordRowHasLapTimes(t);
    }
    if (isCountRecordSandTapRow(t)) {
        const drums = Number((t as { drumsObtained?: number }).drumsObtained ?? 0);
        return drums > 0 || countRecordRowHasLapTimes(t);
    }
    return false;
}

/** Lap hour >= 17:00 counts as OT (subset of afternoon for analytics) */
export const OT_START_HOUR = 17;

export function countRecordLapHour(lap: string): number | null {
    const s = lap.trim();
    const sp = s.indexOf(' ');
    if (sp < 0) return null;
    const time = s.slice(sp + 1);
    const colon = time.indexOf(':');
    const hourStr = colon < 0 ? time : time.slice(0, colon);
    const h = parseInt(hourStr.trim(), 10);
    return Number.isFinite(h) ? h : null;
}

export function countRecordLapPeriods(t: Transaction): {
    morning: number;
    afternoon: number;
    unknown: number;
    ot: number;
} {
    const laps = getLapTimes(t);
    let morning = 0;
    let afternoon = 0;
    let unknown = 0;
    let ot = 0;
    for (const lap of laps) {
        const h = countRecordLapHour(lap);
        if (h == null) unknown += 1;
        else if (h < 12) morning += 1;
        else {
            afternoon += 1;
            if (h >= OT_START_HOUR) ot += 1;
        }
    }
    return { morning, afternoon, unknown, ot };
}

/** แยกจำนวนเที่ยวออกเป็นช่วงเช้า/บ่าย — สอดคล้อง mobile; ot จาก lap (>= 17:00) */
export function vehicleTripPeriodSplit(t: Transaction): { morning: number; afternoon: number; ot: number } {
    const lapOt = countRecordLapPeriods(t).ot;
    const tm = Number((t as { tripMorning?: number }).tripMorning ?? 0);
    const ta = Number((t as { tripAfternoon?: number }).tripAfternoon ?? 0);
    if (tm !== 0 || ta !== 0) return { morning: tm, afternoon: ta, ot: lapOt };

    const periods = countRecordLapPeriods(t);
    if (periods.morning > 0 || periods.afternoon > 0 || periods.unknown > 0) {
        return {
            morning: periods.morning + periods.unknown,
            afternoon: periods.afternoon,
            ot: periods.ot,
        };
    }

    const total = Number((t as { perCarTrips?: number; tripCount?: number }).perCarTrips ?? (t as { tripCount?: number }).tripCount ?? 0);
    return { morning: total, afternoon: 0, ot: 0 };
}

export function isWorkDetailsBroken(details?: string | null): boolean {
    const d = String(details ?? '');
    const lastBroken = d.lastIndexOf('รถเสีย');
    if (lastBroken < 0) return false;
    const lastNormal = d.lastIndexOf('รถปกติ');
    return lastNormal < lastBroken;
}

export function driverDisplayName(driverId: string, employees: Employee[]): string {
    const id = driverId.trim();
    if (!id) return 'ยังไม่ระบุ';
    const emp = employees.find((e) => e.id === id);
    if (!emp) return id;
    if (emp.nickname?.trim()) return emp.nickname.trim();
    if (emp.name?.trim()) return emp.name.trim();
    return id;
}

export interface CountRecordTripUnit {
    id: string;
    vehicleId: string;
    driverId: string;
    driverLabel: string;
    rounds: number;
    morning: number;
    afternoon: number;
    /** Laps from 17:00 onward (subset of afternoon) */
    ot: number;
    lapTimes: string[];
    broken: boolean;
}

export interface CountRecordSandUnit {
    id: string;
    rounds: number;
    morning: number;
    afternoon: number;
    /** Laps from 17:00 onward (subset of afternoon) */
    ot: number;
    lapTimes: string[];
}

function tripRoundsFromTx(t: Transaction): number {
    const laps = getLapTimes(t);
    let tripRounds = Math.round(Number((t as { perCarTrips?: number; tripCount?: number }).perCarTrips ?? (t as { tripCount?: number }).tripCount ?? 0));
    if (laps.length > tripRounds) tripRounds = laps.length;
    return tripRounds;
}

function sandRoundsFromTx(t: Transaction): number {
    const laps = getLapTimes(t);
    const fromDrums = Math.round(Number((t as { drumsObtained?: number }).drumsObtained ?? 0));
    if (laps.length > 0) return laps.length > fromDrums ? laps.length : fromDrums;
    return fromDrums;
}

function sandRowScore(t: Transaction): number {
    const laps = getLapTimes(t);
    if (laps.length > 0) return laps.length * 1000;
    return Math.round(Number((t as { drumsObtained?: number }).drumsObtained ?? 0));
}

function sandRowIsEmpty(t: Transaction): boolean {
    const laps = getLapTimes(t);
    const drums = Math.round(Number((t as { drumsObtained?: number }).drumsObtained ?? 0));
    return laps.length === 0 && drums <= 0;
}

export function buildCountRecordTripUnits(
    dayKey: string,
    transactions: Transaction[],
    employees: Employee[],
): CountRecordTripUnit[] {
    const units: CountRecordTripUnit[] = [];
    for (const t of transactions) {
        if (String(t.date ?? '').trim().slice(0, 10) !== dayKey.trim()) continue;
        if (!isCountRecordVehicleRow(t)) continue;
        const vid = String(t.vehicleId ?? '').trim();
        if (!vid || isMacroVehicleId(vid)) continue;
        const periods = vehicleTripPeriodSplit(t);
        units.push({
            id: t.id,
            vehicleId: vid,
            driverId: String(t.driverId ?? '').trim(),
            driverLabel: driverDisplayName(String(t.driverId ?? ''), employees),
            rounds: tripRoundsFromTx(t),
            morning: periods.morning,
            afternoon: periods.afternoon,
            ot: periods.ot,
            lapTimes: getLapTimes(t),
            broken: isWorkDetailsBroken(t.workDetails),
        });
    }
    return units;
}

/** ทุกแถวร่อนทราย (count tap) ของวันนั้น — รวม empty เพื่อล้าง orphan ได้ */
export function listCountRecordSandTapRows(dayKey: string, transactions: Transaction[]): Transaction[] {
    const key = dayKey.trim();
    const out: Transaction[] = [];
    for (const t of transactions) {
        if (String(t.date ?? '').trim().slice(0, 10) !== key) continue;
        if (!isCountRecordSandTapRow(t)) continue;
        out.push(t);
    }
    return out;
}

export function buildCountRecordSandUnit(dayKey: string, transactions: Transaction[]): CountRecordSandUnit | null {
    let sandRow: Transaction | null = null;
    for (const t of transactions) {
        if (String(t.date ?? '').trim().slice(0, 10) !== dayKey.trim()) continue;
        if (!isCountRecordSandTapRow(t)) continue;
        if (sandRowIsEmpty(t)) continue;
        if (!sandRow || sandRowScore(t) > sandRowScore(sandRow)) sandRow = t;
    }
    if (!sandRow) return null;
    const periods = countRecordLapPeriods(sandRow);
    return {
        id: sandRow.id,
        rounds: sandRoundsFromTx(sandRow),
        morning: periods.morning,
        afternoon: periods.afternoon,
        ot: periods.ot,
        lapTimes: getLapTimes(sandRow),
    };
}

export function countRecordMenuStatusLabel(
    dayKey: string,
    transactions: Transaction[],
    locale: 'th' | 'zh' = 'th',
): string | null {
    const vehicles = new Set<string>();
    let tripTotal = 0;
    let sandRounds = 0;
    let sandMorning = 0;
    let sandAfternoon = 0;

    for (const t of transactions) {
        if (String(t.date ?? '').trim().slice(0, 10) !== dayKey.trim()) continue;
        if (!countRecordRowHasSavedData(t)) continue;
        if (isCountRecordVehicleRow(t)) {
            const vid = String(t.vehicleId ?? '').trim();
            if (vid) vehicles.add(vid);
            tripTotal += Number((t as { perCarTrips?: number; tripCount?: number }).perCarTrips ?? (t as { tripCount?: number }).tripCount ?? 0);
        } else if (isCountRecordSandTapRow(t)) {
            sandRounds += Number((t as { drumsObtained?: number }).drumsObtained ?? 0);
            const p = countRecordLapPeriods(t);
            sandMorning += p.morning;
            sandAfternoon += p.afternoon;
        }
    }

    const parts: string[] = [];
    if (tripTotal > 0 || vehicles.size > 0) {
        if (locale === 'zh') {
            parts.push(`${vehicles.size} 辆 · ${formatDashboardMetric(tripTotal)} 趟`);
        } else {
            parts.push(`${vehicles.size} คัน · ${formatDashboardMetric(tripTotal)} เที่ยว`);
        }
    }
    if (sandRounds > 0) {
        let sand =
            locale === 'zh'
                ? `洗沙 ${formatDashboardMetric(sandRounds)} 轮`
                : `ร่อน ${formatDashboardMetric(sandRounds)} รอบ`;
        if (sandMorning > 0 || sandAfternoon > 0) {
            sand +=
                locale === 'zh'
                    ? ` (上午 ${sandMorning} · 下午 ${sandAfternoon})`
                    : ` (เช้า ${sandMorning} · บ่าย ${sandAfternoon})`;
        }
        parts.push(sand);
    }
    if (parts.length === 0) return null;
    return parts.join(' · ');
}

export function isCountRecordRelatedTransaction(t: Transaction): boolean {
    return isCountRecordVehicleRow(t) || isCountRecordSandTapRow(t);
}

export function countRecordDayFingerprint(dayKey: string, transactions: Transaction[]): string {
    const rows: string[] = [];
    for (const t of transactions) {
        if (String(t.date ?? '').trim().slice(0, 10) !== dayKey.trim()) continue;
        if (!isCountRecordRelatedTransaction(t)) continue;
        const laps = getLapTimes(t).join(',');
        rows.push(
            `${t.id}|${t.vehicleId ?? ''}|${t.driverId ?? ''}|${(t as { perCarTrips?: number }).perCarTrips ?? (t as { tripCount?: number }).tripCount ?? 0}|${(t as { drumsObtained?: number }).drumsObtained ?? 0}|${laps}|${t.workDetails ?? ''}`,
        );
    }
    rows.sort();
    return rows.join(';');
}

export interface CountRecordActivity {
    id: string;
    at: number;
    message: string;
    kind: 'trip' | 'sand' | 'delete';
}

export function diffCountRecordActivities(
    dayKey: string,
    prevTransactions: Transaction[],
    nextTransactions: Transaction[],
    employees: Employee[],
    locale: 'th' | 'zh' = 'th',
): CountRecordActivity[] {
    const at = Date.now();
    const prevTrips = buildCountRecordTripUnits(dayKey, prevTransactions, employees);
    const nextTrips = buildCountRecordTripUnits(dayKey, nextTransactions, employees);
    const prevSand = buildCountRecordSandUnit(dayKey, prevTransactions);
    const nextSand = buildCountRecordSandUnit(dayKey, nextTransactions);
    const out: CountRecordActivity[] = [];

    const prevTripMap = new Map(prevTrips.map((u) => [u.id, u]));
    for (const u of nextTrips) {
        const old = prevTripMap.get(u.id);
        if (!old) {
            if (u.rounds > 0) {
                const lap = u.lapTimes[u.lapTimes.length - 1];
                out.push({
                    id: `${u.id}-new-${at}`,
                    at,
                    kind: 'trip',
                    message: lap
                        ? locale === 'zh'
                            ? `${u.vehicleId} • 第 ${u.rounds} 趟 • ${lap}`
                            : `${u.vehicleId} • เที่ยวที่ ${u.rounds} • ${lap}`
                        : locale === 'zh'
                          ? `${u.vehicleId} • ${u.rounds} 趟`
                          : `${u.vehicleId} • ${u.rounds} เที่ยว`,
                });
            }
            continue;
        }
        if (u.rounds > old.rounds) {
            const lap = u.lapTimes[u.lapTimes.length - 1] ?? '';
            out.push({
                id: `${u.id}-${u.rounds}-${at}`,
                at,
                kind: 'trip',
                message: lap
                    ? locale === 'zh'
                        ? `${u.vehicleId} • 第 ${u.rounds} 趟 • ${lap}`
                        : `${u.vehicleId} • เที่ยวที่ ${u.rounds} • ${lap}`
                    : locale === 'zh'
                      ? `${u.vehicleId} • 增至 ${u.rounds} 趟`
                      : `${u.vehicleId} • เพิ่มเป็น ${u.rounds} เที่ยว`,
            });
        }
    }

    if (nextSand && (!prevSand || nextSand.rounds > prevSand.rounds)) {
        const lap = nextSand.lapTimes[nextSand.lapTimes.length - 1] ?? '';
        out.push({
            id: `${nextSand.id}-${nextSand.rounds}-${at}`,
            at,
            kind: 'sand',
            message: lap
                ? locale === 'zh'
                    ? `第 ${nextSand.rounds} 轮 • ${lap}`
                    : `รอบที่ ${nextSand.rounds} • ${lap}`
                : locale === 'zh'
                  ? `洗沙 • ${nextSand.rounds} 轮`
                  : `ร่อนทราย • ${nextSand.rounds} รอบ`,
        });
    }

    return out;
}

export interface CountRecordIncrement {
    id: string;
    kind: 'trip' | 'sand';
    delta: number;
    unitId?: string;
    vehicleId?: string;
    at: number;
}

export function diffCountRecordIncrements(
    dayKey: string,
    prevTransactions: Transaction[],
    nextTransactions: Transaction[],
    employees: Employee[],
): CountRecordIncrement[] {
    const at = Date.now();
    const prevTrips = buildCountRecordTripUnits(dayKey, prevTransactions, employees);
    const nextTrips = buildCountRecordTripUnits(dayKey, nextTransactions, employees);
    const prevSand = buildCountRecordSandUnit(dayKey, prevTransactions);
    const nextSand = buildCountRecordSandUnit(dayKey, nextTransactions);
    const out: CountRecordIncrement[] = [];

    const prevTripMap = new Map(prevTrips.map((u) => [u.id, u]));
    const nextTripMap = new Map(nextTrips.map((u) => [u.id, u]));

    for (const u of nextTrips) {
        const old = prevTripMap.get(u.id);
        if (!old) {
            if (u.rounds > 0) {
                out.push({
                    id: `${u.id}-new-${at}`,
                    at,
                    kind: 'trip',
                    delta: u.rounds,
                    unitId: u.id,
                    vehicleId: u.vehicleId,
                });
            }
            continue;
        }
        if (u.rounds !== old.rounds) {
            out.push({
                id: `${u.id}-${u.rounds}-${at}`,
                at,
                kind: 'trip',
                delta: u.rounds - old.rounds,
                unitId: u.id,
                vehicleId: u.vehicleId,
            });
        }
    }

    for (const old of prevTrips) {
        if (!nextTripMap.has(old.id) && old.rounds > 0) {
            out.push({
                id: `${old.id}-removed-${at}`,
                at,
                kind: 'trip',
                delta: -old.rounds,
                unitId: old.id,
                vehicleId: old.vehicleId,
            });
        }
    }

    const prevSandRounds = prevSand?.rounds ?? 0;
    const nextSandRounds = nextSand?.rounds ?? 0;
    if (nextSandRounds !== prevSandRounds) {
        const sandId = nextSand?.id ?? prevSand?.id ?? 'sand';
        out.push({
            id: `${sandId}-${nextSandRounds}-${at}`,
            at,
            kind: 'sand',
            delta: nextSandRounds - prevSandRounds,
            unitId: sandId,
        });
    }

    return out;
}
