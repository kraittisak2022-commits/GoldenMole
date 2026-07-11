import type { Employee, Transaction } from '../../types';
import { normalizeDate } from '../../utils';
import {
    buildCountRecordSandUnit,
    buildCountRecordTripUnits,
    type CountRecordTripUnit,
} from './countRecordUtils';

const TZ_OFFSET_MS = 7 * 60 * 60 * 1000;

export function addDaysToYmd(ymd: string, deltaDays: number): string {
    const base = normalizeDate(ymd);
    const [yy, mm, dd] = base.split('-').map((x) => parseInt(x, 10));
    if (!yy || !mm || !dd) return base;
    const ms = Date.UTC(yy, mm - 1, dd + deltaDays);
    const d = new Date(ms);
    const y = d.getUTCFullYear();
    const m = String(d.getUTCMonth() + 1).padStart(2, '0');
    const day = String(d.getUTCDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
}

/** แปลง lap stamp `dd/MM HH:mm:ss` + ปีจาก dayKey → epoch ms (Bangkok) */
export function parseLapStamp(stamp: string, dayKey: string): number | null {
    const s = stamp.trim();
    const space = s.indexOf(' ');
    if (space < 0) return null;

    const datePart = s.slice(0, space);
    const timePart = s.slice(space + 1);
    const [ddStr, mmStr] = datePart.split('/');
    const [hhStr, minStr, secStr] = timePart.split(':');

    const dd = parseInt(ddStr ?? '', 10);
    const mm = parseInt(mmStr ?? '', 10);
    const hh = parseInt(hhStr ?? '', 10);
    const min = parseInt(minStr ?? '0', 10);
    const sec = parseInt(secStr ?? '0', 10);

    if (!Number.isFinite(dd) || !Number.isFinite(mm) || !Number.isFinite(hh)) return null;

    const [yyStr] = normalizeDate(dayKey).split('-');
    const yy = parseInt(yyStr ?? '', 10);
    if (!Number.isFinite(yy)) return null;

    // Bangkok local → UTC epoch
    const utcMs = Date.UTC(yy, mm - 1, dd, hh, min, sec) - TZ_OFFSET_MS;
    return Number.isFinite(utcMs) ? utcMs : null;
}

export interface LapIntervalResult {
    intervalsSec: number[];
    labels: string[];
}

export function computeLapIntervals(lapTimes: string[], dayKey: string): LapIntervalResult {
    const intervalsSec: number[] = [];
    const labels: string[] = [];

    for (let i = 1; i < lapTimes.length; i++) {
        const prev = parseLapStamp(lapTimes[i - 1]!, dayKey);
        const curr = parseLapStamp(lapTimes[i]!, dayKey);
        if (prev == null || curr == null) continue;
        const sec = Math.round((curr - prev) / 1000);
        if (sec < 0) continue;
        intervalsSec.push(sec);
        labels.push(`รอบ ${i}→${i + 1}`);
    }

    return { intervalsSec, labels };
}

export interface IntervalStats {
    avg: number | null;
    median: number | null;
    min: number | null;
    max: number | null;
    last: number | null;
}

export function computeIntervalStats(intervals: number[]): IntervalStats {
    if (intervals.length === 0) {
        return { avg: null, median: null, min: null, max: null, last: null };
    }
    const sorted = [...intervals].sort((a, b) => a - b);
    const sum = intervals.reduce((s, v) => s + v, 0);
    const mid = Math.floor(sorted.length / 2);
    const median =
        sorted.length % 2 === 0
            ? (sorted[mid - 1]! + sorted[mid]!) / 2
            : sorted[mid]!;
    return {
        avg: sum / intervals.length,
        median,
        min: sorted[0]!,
        max: sorted[sorted.length - 1]!,
        last: intervals[intervals.length - 1]!,
    };
}

export interface HourlyBucket {
    hour: number;
    count: number;
    label: string;
}

export function computeHourlyBuckets(lapTimes: string[], dayKey: string): HourlyBucket[] {
    const counts = new Array<number>(24).fill(0);
    for (const lap of lapTimes) {
        const ms = parseLapStamp(lap, dayKey);
        if (ms == null) continue;
        const d = new Date(ms + TZ_OFFSET_MS);
        const h = d.getUTCHours();
        if (h >= 0 && h < 24) counts[h]! += 1;
    }
    return counts
        .map((count, hour) => ({
            hour,
            count,
            label: `${String(hour).padStart(2, '0')}:00`,
        }))
        .filter((b) => b.count > 0);
}

export interface CumulativePoint {
    label: string;
    value: number;
    timeMs: number;
}

export function computeCumulativeSeries(lapTimes: string[], dayKey: string): CumulativePoint[] {
    const points: CumulativePoint[] = [];
    for (let i = 0; i < lapTimes.length; i++) {
        const ms = parseLapStamp(lapTimes[i]!, dayKey);
        if (ms == null) continue;
        const d = new Date(ms + TZ_OFFSET_MS);
        const hh = String(d.getUTCHours()).padStart(2, '0');
        const mm = String(d.getUTCMinutes()).padStart(2, '0');
        points.push({
            label: `${hh}:${mm}`,
            value: i + 1,
            timeMs: ms,
        });
    }
    return points;
}

export interface TripTimelineEvent {
    vehicleId: string;
    stamp: string;
    timeMs: number;
    roundNo: number;
}

export function mergeTripLapTimeline(tripUnits: CountRecordTripUnit[], dayKey: string): TripTimelineEvent[] {
    const events: TripTimelineEvent[] = [];
    for (const u of tripUnits) {
        for (let i = 0; i < u.lapTimes.length; i++) {
            const stamp = u.lapTimes[i]!;
            const timeMs = parseLapStamp(stamp, dayKey);
            if (timeMs == null) continue;
            events.push({
                vehicleId: u.vehicleId,
                stamp,
                timeMs,
                roundNo: i + 1,
            });
        }
    }
    events.sort((a, b) => a.timeMs - b.timeMs);
    return events;
}

export function timelineToLapStamps(events: TripTimelineEvent[]): string[] {
    return events.map((e) => e.stamp);
}

/** ดึงเวลา HH:mm จาก lap stamp `dd/MM HH:mm:ss` */
export function formatLapClock(stamp: string): string | null {
    const s = stamp.trim();
    const space = s.indexOf(' ');
    const timePart = space >= 0 ? s.slice(space + 1) : s;
    const parts = timePart.split(':');
    if (parts.length < 2) return null;
    const hh = parts[0]?.trim();
    const mm = parts[1]?.trim();
    if (!hh || !mm) return null;
    return `${hh.padStart(2, '0')}:${mm.padStart(2, '0')}`;
}

export interface WorkSpan {
    startStamp: string | null;
    endStamp: string | null;
    startClock: string | null;
    endClock: string | null;
}

export function computeWorkSpan(lapTimes: string[], dayKey: string): WorkSpan {
    const parsed: { stamp: string; timeMs: number }[] = [];
    for (const stamp of lapTimes) {
        const timeMs = parseLapStamp(stamp, dayKey);
        if (timeMs != null) parsed.push({ stamp, timeMs });
    }
    if (parsed.length === 0) {
        return { startStamp: null, endStamp: null, startClock: null, endClock: null };
    }
    parsed.sort((a, b) => a.timeMs - b.timeMs);
    const first = parsed[0]!;
    const last = parsed[parsed.length - 1]!;
    return {
        startStamp: first.stamp,
        endStamp: last.stamp,
        startClock: formatLapClock(first.stamp),
        endClock: formatLapClock(last.stamp),
    };
}

export function computeTripFleetWorkSpan(units: CountRecordTripUnit[], dayKey: string): WorkSpan {
    const timeline = mergeTripLapTimeline(units, dayKey);
    return computeWorkSpan(timelineToLapStamps(timeline), dayKey);
}

export function formatWorkSpanLabel(span: WorkSpan): string | null {
    if (!span.startClock) return null;
    if (!span.endClock || span.startClock === span.endClock) {
        return `เริ่ม ${span.startClock}`;
    }
    return `เริ่ม ${span.startClock} · เลิก ${span.endClock}`;
}

export function formatDurationSec(sec: number | null): string {
    if (sec == null || !Number.isFinite(sec)) return '—';
    if (sec < 60) return `${Math.round(sec)} วิน.`;
    const m = Math.floor(sec / 60);
    const s = Math.round(sec % 60);
    if (m < 60) return s > 0 ? `${m} นาที ${s} วิน.` : `${m} นาที`;
    const h = Math.floor(m / 60);
    const rm = m % 60;
    return rm > 0 ? `${h} ชม. ${rm} นาที` : `${h} ชม.`;
}

export function formatPaceDelta(pct: number | null): { text: string; faster: boolean | null } {
    if (pct == null || !Number.isFinite(pct)) return { text: 'ไม่มีข้อมูลเมื่อวาน', faster: null };
    const abs = Math.abs(Math.round(pct));
    if (abs < 1) return { text: 'เท่าเมื่อวาน', faster: null };
    if (pct < 0) return { text: `เร็วกว่าเมื่อวาน ${abs}%`, faster: true };
    return { text: `ช้ากว่าเมื่อวาน ${abs}%`, faster: false };
}

export function computePaceDeltaPercent(todayAvg: number | null, yesterdayAvg: number | null): number | null {
    if (todayAvg == null || yesterdayAvg == null || yesterdayAvg <= 0) return null;
    return ((todayAvg - yesterdayAvg) / yesterdayAvg) * 100;
}

export function computeRoundsDeltaPercent(todayRounds: number, yesterdayRounds: number): number | null {
    if (yesterdayRounds <= 0) return null;
    return ((todayRounds - yesterdayRounds) / yesterdayRounds) * 100;
}

export interface DayModeComparison {
    todayRounds: number;
    yesterdayRounds: number;
    roundsDeltaPct: number | null;
    todayAvgSec: number | null;
    yesterdayAvgSec: number | null;
    paceDeltaPct: number | null;
    hasYesterdayData: boolean;
    hasYesterdayIntervals: boolean;
}

export interface DayComparison {
    sand: DayModeComparison;
    trip: DayModeComparison;
}

function buildModeComparison(
    todayLaps: string[],
    yesterdayLaps: string[],
    todayRounds: number,
    yesterdayRounds: number,
    dayKey: string,
    yesterdayKey: string,
): DayModeComparison {
    const todayIntervals = computeLapIntervals(todayLaps, dayKey);
    const yesterdayIntervals = computeLapIntervals(yesterdayLaps, yesterdayKey);
    const todayStats = computeIntervalStats(todayIntervals.intervalsSec);
    const yesterdayStats = computeIntervalStats(yesterdayIntervals.intervalsSec);

    return {
        todayRounds,
        yesterdayRounds,
        roundsDeltaPct: computeRoundsDeltaPercent(todayRounds, yesterdayRounds),
        todayAvgSec: todayStats.avg,
        yesterdayAvgSec: yesterdayStats.avg,
        paceDeltaPct: computePaceDeltaPercent(todayStats.avg, yesterdayStats.avg),
        hasYesterdayData: yesterdayRounds > 0,
        hasYesterdayIntervals: yesterdayIntervals.intervalsSec.length > 0,
    };
}

export function buildDayComparison(
    todayKey: string,
    transactions: Transaction[],
    employees: Employee[],
): DayComparison {
    const yesterdayKey = addDaysToYmd(todayKey, -1);

    const todayTrips = buildCountRecordTripUnits(todayKey, transactions, employees);
    const yesterdayTrips = buildCountRecordTripUnits(yesterdayKey, transactions, employees);
    const todaySand = buildCountRecordSandUnit(todayKey, transactions);
    const yesterdaySand = buildCountRecordSandUnit(yesterdayKey, transactions);

    const todayTripTimeline = mergeTripLapTimeline(todayTrips, todayKey);
    const yesterdayTripTimeline = mergeTripLapTimeline(yesterdayTrips, yesterdayKey);

    const todayTripRounds = todayTrips.reduce((s, u) => s + u.rounds, 0);
    const yesterdayTripRounds = yesterdayTrips.reduce((s, u) => s + u.rounds, 0);

    return {
        sand: buildModeComparison(
            todaySand?.lapTimes ?? [],
            yesterdaySand?.lapTimes ?? [],
            todaySand?.rounds ?? 0,
            yesterdaySand?.rounds ?? 0,
            todayKey,
            yesterdayKey,
        ),
        trip: buildModeComparison(
            timelineToLapStamps(todayTripTimeline),
            timelineToLapStamps(yesterdayTripTimeline),
            todayTripRounds,
            yesterdayTripRounds,
            todayKey,
            yesterdayKey,
        ),
    };
}
