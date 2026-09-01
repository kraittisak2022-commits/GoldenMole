import type { Employee, Transaction } from '../../types';
import { normalizeDate } from '../../utils';
import {
    OT_START_HOUR,
    SAND_TARGET_ROUNDS,
    buildCountRecordSandUnit,
    buildCountRecordTripUnits,
    type CountRecordTripUnit,
} from './countRecordUtils';

const TZ_OFFSET_MS = 7 * 60 * 60 * 1000;
const MS_PER_MIN = 60 * 1000;

export const LUNCH_START_HOUR = 12;
export const LUNCH_END_HOUR = 13;

export { SAND_TARGET_ROUNDS };

export function isLunchHour(hour: number): boolean {
    return hour >= LUNCH_START_HOUR && hour < LUNCH_END_HOUR;
}

/** Lunch window on same calendar day as startMs (Bangkok) */
export function lunchWindowMs(dayKey: string, refMs: number): { startMs: number; endMs: number } {
    const d = new Date(refMs + TZ_OFFSET_MS);
    const yy = d.getUTCFullYear();
    const mm = d.getUTCMonth();
    const dd = d.getUTCDate();
    const startMs = Date.UTC(yy, mm, dd, LUNCH_START_HOUR, 0, 0) - TZ_OFFSET_MS;
    const endMs = Date.UTC(yy, mm, dd, LUNCH_END_HOUR, 0, 0) - TZ_OFFSET_MS;
    void dayKey;
    return { startMs, endMs };
}

export function lunchOverlapMs(startMs: number, endMs: number): number {
    if (endMs <= startMs) return 0;
    const { startMs: lunchStart, endMs: lunchEnd } = lunchWindowMs('', startMs);
    const overlapStart = Math.max(startMs, lunchStart);
    const overlapEnd = Math.min(endMs, lunchEnd);
    return Math.max(0, overlapEnd - overlapStart);
}

export function activeDurationSec(startMs: number, endMs: number): number {
    if (endMs <= startMs) return 0;
    const rawMs = endMs - startMs;
    const lunchMs = lunchOverlapMs(startMs, endMs);
    return Math.max(0, Math.round((rawMs - lunchMs) / 1000));
}

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

export function computeLapIntervals(
    lapTimes: string[],
    dayKey: string,
    locale: 'th' | 'zh' = 'th',
): LapIntervalResult {
    const intervalsSec: number[] = [];
    const labels: string[] = [];

    for (let i = 1; i < lapTimes.length; i++) {
        const prev = parseLapStamp(lapTimes[i - 1]!, dayKey);
        const curr = parseLapStamp(lapTimes[i]!, dayKey);
        if (prev == null || curr == null) continue;
        const sec = activeDurationSec(prev, curr);
        if (sec <= 0) continue;
        intervalsSec.push(sec);
        labels.push(
            locale === 'zh' ? `第 ${i}→${i + 1} 轮` : `รอบ ${i}→${i + 1}`,
        );
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
        if (h >= 0 && h < 24 && !isLunchHour(h)) counts[h]! += 1;
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

export type FormatLocale = 'th' | 'zh';

export function formatWorkSpanLabel(span: WorkSpan, locale: FormatLocale = 'th'): string | null {
    if (!span.startClock) return null;
    if (!span.endClock || span.startClock === span.endClock) {
        return locale === 'zh' ? `开始 ${span.startClock}` : `เริ่ม ${span.startClock}`;
    }
    return locale === 'zh'
        ? `开始 ${span.startClock} · 结束 ${span.endClock}`
        : `เริ่ม ${span.startClock} · เลิก ${span.endClock}`;
}

export interface SandWorkDurationSummary {
    totalActiveHours: number;
    lunchDeductedHours: number;
    startClock: string | null;
    endClock: string | null;
}

export function computeSandWorkDurationSummary(lapTimes: string[], dayKey: string): SandWorkDurationSummary | null {
    const span = computeWorkSpan(lapTimes, dayKey);
    if (!span.startStamp || !span.endStamp) return null;
    const startMs = parseLapStamp(span.startStamp, dayKey);
    const endMs = parseLapStamp(span.endStamp, dayKey);
    if (startMs == null || endMs == null) return null;
    const rawSec = Math.max(0, Math.round((endMs - startMs) / 1000));
    const activeSec = activeDurationSec(startMs, endMs);
    const lunchDeductedSec = Math.max(0, rawSec - activeSec);
    return {
        totalActiveHours: activeSec / 3600,
        lunchDeductedHours: lunchDeductedSec / 3600,
        startClock: span.startClock,
        endClock: span.endClock,
    };
}

export interface HourlyActiveWorkBucket {
    hour: number;
    activeMinutes: number;
    activeHours: number;
    label: string;
}

export function computeHourlyActiveWork(lapTimes: string[], dayKey: string): HourlyActiveWorkBucket[] {
    const span = computeWorkSpan(lapTimes, dayKey);
    if (!span.startStamp || !span.endStamp) return [];
    const startMs = parseLapStamp(span.startStamp, dayKey);
    const endMs = parseLapStamp(span.endStamp, dayKey);
    if (startMs == null || endMs == null || endMs <= startMs) return [];

    const startD = new Date(startMs + TZ_OFFSET_MS);
    const startHour = startD.getUTCHours();
    const endD = new Date(endMs + TZ_OFFSET_MS);
    const endHour = endD.getUTCHours();

    const buckets: HourlyActiveWorkBucket[] = [];
    for (let hour = startHour; hour <= endHour; hour++) {
        const hourStartD = new Date(startMs + TZ_OFFSET_MS);
        hourStartD.setUTCHours(hour, 0, 0, 0);
        const hourStartMs = hourStartD.getTime() - TZ_OFFSET_MS;
        const hourEndMs = hourStartMs + 60 * MS_PER_MIN;

        const segStart = Math.max(startMs, hourStartMs);
        const segEnd = Math.min(endMs, hourEndMs);
        if (segEnd <= segStart) continue;

        const activeSec = activeDurationSec(segStart, segEnd);
        const activeMinutes = activeSec / 60;
        buckets.push({
            hour,
            activeMinutes,
            activeHours: activeMinutes / 60,
            label: `${String(hour).padStart(2, '0')}:00`,
        });
    }
    return buckets;
}

export interface SpeedBucket {
    label: string;
    speed: number;
    count: number;
}

export function computeHourlySandSpeed(lapTimes: string[], dayKey: string): SpeedBucket[] {
    const buckets = computeHourlyBuckets(lapTimes, dayKey);
    return buckets.map((b) => ({
        label: b.label,
        speed: b.count,
        count: b.count,
    }));
}

export function computeMinuteSandSpeed(lapTimes: string[], dayKey: string): SpeedBucket[] {
    const counts = new Map<string, number>();
    for (const lap of lapTimes) {
        const ms = parseLapStamp(lap, dayKey);
        if (ms == null) continue;
        const d = new Date(ms + TZ_OFFSET_MS);
        if (isLunchHour(d.getUTCHours())) continue;
        const hh = String(d.getUTCHours()).padStart(2, '0');
        const mm = String(d.getUTCMinutes()).padStart(2, '0');
        const key = `${hh}:${mm}`;
        counts.set(key, (counts.get(key) ?? 0) + 1);
    }
    return [...counts.entries()]
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([label, count]) => ({
            label,
            speed: count,
            count,
        }));
}

export function formatActiveHours(hours: number, locale: FormatLocale = 'th'): string {
    if (!Number.isFinite(hours) || hours <= 0) return locale === 'zh' ? '0 小时' : '0 ชม.';
    if (hours < 1) {
        const mins = Math.round(hours * 60);
        return locale === 'zh' ? `${mins} 分钟` : `${mins} นาที`;
    }
    const rounded = Math.round(hours * 10) / 10;
    return locale === 'zh' ? `${rounded} 小时` : `${rounded} ชม.`;
}

/** Simple moving average; null until window is full */
export function computeMovingAverage(values: number[], window = 5): (number | null)[] {
    if (window <= 0 || values.length === 0) return [];
    return values.map((_, i) => {
        if (i < window - 1) return null;
        const slice = values.slice(i - window + 1, i + 1);
        const sum = slice.reduce((s, v) => s + v, 0);
        return sum / window;
    });
}

/** Last N interval seconds for sparkline (most recent) */
export function buildIntervalSparkline(intervalsSec: number[], limit = 10): number[] {
    if (intervalsSec.length === 0) return [];
    return intervalsSec.slice(-limit);
}

export interface HourlyHeatmapCell {
    hour: number;
    count: number;
    label: string;
    intensity: number;
    isLunch: boolean;
}

/** All 24 hours with intensity 0–1 for heatmap strip */
export function computeHourlyHeatmap(lapTimes: string[], dayKey: string): HourlyHeatmapCell[] {
    const counts = new Array<number>(24).fill(0);
    for (const lap of lapTimes) {
        const ms = parseLapStamp(lap, dayKey);
        if (ms == null) continue;
        const d = new Date(ms + TZ_OFFSET_MS);
        const h = d.getUTCHours();
        if (h >= 0 && h < 24 && !isLunchHour(h)) counts[h]! += 1;
    }
    const max = Math.max(...counts.filter((_, hour) => !isLunchHour(hour)), 1);
    return counts.map((count, hour) => ({
        hour,
        count: isLunchHour(hour) ? 0 : count,
        label: `${String(hour).padStart(2, '0')}:00`,
        intensity: isLunchHour(hour) ? 0 : count / max,
        isLunch: isLunchHour(hour),
    }));
}

export function formatAvgPaceSec(sec: number | null): string {
    if (sec == null || !Number.isFinite(sec)) return '—';
    if (sec < 60) return `${Math.round(sec)}`;
    const m = Math.floor(sec / 60);
    const s = Math.round(sec % 60);
    return s > 0 ? `${m}:${String(s).padStart(2, '0')}` : `${m}`;
}

export function formatAvgPaceUnit(sec: number | null, locale: FormatLocale = 'th'): string {
    if (sec == null || !Number.isFinite(sec)) return '';
    if (locale === 'zh') return sec < 60 ? '秒' : '分钟';
    return sec < 60 ? 'วิน.' : 'นาที';
}

export function formatPaceValue(sec: number | null, locale: FormatLocale = 'th'): string {
    if (sec == null || !Number.isFinite(sec)) return '—';
    const u = formatAvgPaceUnit(sec, locale);
    return u ? `${formatAvgPaceSec(sec)} ${u}` : formatAvgPaceSec(sec);
}

export function formatDurationSec(sec: number | null, locale: FormatLocale = 'th'): string {
    if (sec == null || !Number.isFinite(sec)) return '—';
    if (sec < 60) {
        return locale === 'zh' ? `${Math.round(sec)} 秒` : `${Math.round(sec)} วิน.`;
    }
    const m = Math.floor(sec / 60);
    const s = Math.round(sec % 60);
    if (m < 60) {
        if (locale === 'zh') return s > 0 ? `${m} 分钟 ${s} 秒` : `${m} 分钟`;
        return s > 0 ? `${m} นาที ${s} วิน.` : `${m} นาที`;
    }
    const h = Math.floor(m / 60);
    const rm = m % 60;
    if (locale === 'zh') return rm > 0 ? `${h} 小时 ${rm} 分钟` : `${h} 小时`;
    return rm > 0 ? `${h} ชม. ${rm} นาที` : `${h} ชม.`;
}

export const PRIOR_DAY_LOOKBACK_DAYS = 14;

/** หาวันย้อนหลังล่าสุดที่มีรอบ > 0 (ทราย/เที่ยวแยกกัน) */
export function findPriorDayWithModeData(
    fromDayKey: string,
    mode: 'sand' | 'trip',
    transactions: Transaction[],
    employees: Employee[],
    maxLookbackDays = PRIOR_DAY_LOOKBACK_DAYS,
): string | null {
    for (let offset = 1; offset <= maxLookbackDays; offset++) {
        const key = addDaysToYmd(fromDayKey, -offset);
        if (mode === 'sand') {
            const sand = buildCountRecordSandUnit(key, transactions);
            if ((sand?.rounds ?? 0) > 0) return key;
        } else {
            const trips = buildCountRecordTripUnits(key, transactions, employees);
            const rounds = trips.reduce((s, u) => s + u.rounds, 0);
            if (rounds > 0) return key;
        }
    }
    return null;
}

/** ป้ายวันเปรียบเทียบ: เมื่อวาน / DD/MM / '' */
export function formatComparisonDayLabel(
    dayKey: string | null,
    focusDayKey: string,
    locale: FormatLocale = 'th',
): string {
    if (!dayKey) return '';
    const calendarYesterday = addDaysToYmd(focusDayKey, -1);
    if (dayKey === calendarYesterday) {
        return locale === 'zh' ? '昨天' : 'เมื่อวาน';
    }
    const [, mm, dd] = dayKey.split('-');
    if (!mm || !dd) return dayKey;
    return `${dd}/${mm}`;
}

export function formatPaceDelta(
    pct: number | null,
    locale: FormatLocale = 'th',
    /** omit = เมื่อวาน; '' = ไม่มีวันอ้างอิง (ไม่มีข้อมูลเปรียบเทียบ) */
    priorLabel?: string,
): { text: string; faster: boolean | null } {
    if (pct == null || !Number.isFinite(pct)) {
        if (priorLabel === '') {
            return { text: locale === 'zh' ? '无对比数据' : 'ไม่มีข้อมูลเปรียบเทียบ', faster: null };
        }
        const label = priorLabel?.trim() || (locale === 'zh' ? '昨天' : 'เมื่อวาน');
        return {
            text: locale === 'zh' ? `无${label}数据` : `ไม่มีข้อมูล${label}`,
            faster: null,
        };
    }
    const label = priorLabel?.trim() || (locale === 'zh' ? '昨天' : 'เมื่อวาน');
    const abs = Math.abs(Math.round(pct));
    if (abs < 1) {
        return {
            text: locale === 'zh' ? `与${label}相同` : `เท่า${label}`,
            faster: null,
        };
    }
    if (pct < 0) {
        return {
            text: locale === 'zh' ? `比${label}快 ${abs}%` : `เร็วกว่า${label} ${abs}%`,
            faster: true,
        };
    }
    return {
        text: locale === 'zh' ? `比${label}慢 ${abs}%` : `ช้ากว่า${label} ${abs}%`,
        faster: false,
    };
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
    /** วันที่ใช้เทียบจริง (null = ไม่มีข้อมูลในช่วง lookback) */
    referenceDayKey: string | null;
    isCalendarYesterday: boolean;
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
    referenceDayKey: string | null,
    focusDayKey: string,
): DayModeComparison {
    const todayIntervals = computeLapIntervals(todayLaps, dayKey);
    const yesterdayIntervals = computeLapIntervals(yesterdayLaps, yesterdayKey);
    const todayStats = computeIntervalStats(todayIntervals.intervalsSec);
    const yesterdayStats = computeIntervalStats(yesterdayIntervals.intervalsSec);
    const calendarYesterday = addDaysToYmd(focusDayKey, -1);
    const hasData = yesterdayRounds > 0 && referenceDayKey != null;

    return {
        todayRounds,
        yesterdayRounds,
        roundsDeltaPct: computeRoundsDeltaPercent(todayRounds, yesterdayRounds),
        todayAvgSec: todayStats.avg,
        yesterdayAvgSec: yesterdayStats.avg,
        paceDeltaPct: computePaceDeltaPercent(todayStats.avg, yesterdayStats.avg),
        hasYesterdayData: hasData,
        hasYesterdayIntervals: yesterdayIntervals.intervalsSec.length > 0,
        referenceDayKey: hasData ? referenceDayKey : null,
        isCalendarYesterday: hasData && referenceDayKey === calendarYesterday,
    };
}

export function computeTripFleetWorkDurationSummary(
    units: CountRecordTripUnit[],
    dayKey: string,
): SandWorkDurationSummary | null {
    const span = computeTripFleetWorkSpan(units, dayKey);
    if (!span.startStamp || !span.endStamp) return null;
    const startMs = parseLapStamp(span.startStamp, dayKey);
    const endMs = parseLapStamp(span.endStamp, dayKey);
    if (startMs == null || endMs == null) return null;
    const rawSec = Math.max(0, Math.round((endMs - startMs) / 1000));
    const activeSec = activeDurationSec(startMs, endMs);
    const lunchDeductedSec = Math.max(0, rawSec - activeSec);
    return {
        totalActiveHours: activeSec / 3600,
        lunchDeductedHours: lunchDeductedSec / 3600,
        startClock: span.startClock,
        endClock: span.endClock,
    };
}

export interface PeriodSplit {
    morning: number;
    afternoon: number;
    morningPct: number;
    afternoonPct: number;
}

export function computeTripPeriodSplit(units: CountRecordTripUnit[]): PeriodSplit {
    const morning = units.reduce((s, u) => s + u.morning, 0);
    const afternoon = units.reduce((s, u) => s + u.afternoon, 0);
    const total = morning + afternoon;
    return {
        morning,
        afternoon,
        morningPct: total > 0 ? (morning / total) * 100 : 0,
        afternoonPct: total > 0 ? (afternoon / total) * 100 : 0,
    };
}

export function computeSandPeriodSplit(morning: number, afternoon: number): PeriodSplit {
    const total = morning + afternoon;
    return {
        morning,
        afternoon,
        morningPct: total > 0 ? (morning / total) * 100 : 0,
        afternoonPct: total > 0 ? (afternoon / total) * 100 : 0,
    };
}

export interface VehicleComparisonRow {
    vehicleId: string;
    rounds: number;
    morning: number;
    afternoon: number;
}

export function computeVehicleComparison(units: CountRecordTripUnit[]): VehicleComparisonRow[] {
    return [...units]
        .filter((u) => u.rounds > 0)
        .sort((a, b) => b.rounds - a.rounds)
        .map((u) => ({
            vehicleId: u.vehicleId,
            rounds: u.rounds,
            morning: u.morning,
            afternoon: u.afternoon,
        }));
}

export interface PeakHourInfo {
    hour: number;
    count: number;
    label: string;
}

export function computePeakHour(cells: HourlyHeatmapCell[]): PeakHourInfo | null {
    const active = cells.filter((c) => c.count > 0 && !c.isLunch);
    if (active.length === 0) return null;
    const best = active.reduce((a, b) => (b.count > a.count ? b : a));
    return { hour: best.hour, count: best.count, label: best.label };
}

export interface HourlyEfficiencyBucket {
    hour: number;
    label: string;
    count: number;
    roundsPerHour: number;
}

/** ความเร็วเฉลี่ยต่อชั่วโมง (รอบหรือเที่ยว / ชม. ในช่วงนั้น) */
export function computeHourlyEfficiency(lapTimes: string[], dayKey: string): HourlyEfficiencyBucket[] {
    const buckets = computeHourlyBuckets(lapTimes, dayKey);
    return buckets.map((b) => ({
        hour: b.hour,
        label: b.label,
        count: b.count,
        roundsPerHour: b.count,
    }));
}

export function buildDayComparison(
    todayKey: string,
    transactions: Transaction[],
    employees: Employee[],
): DayComparison {
    const calendarYesterday = addDaysToYmd(todayKey, -1);
    const sandRef = findPriorDayWithModeData(todayKey, 'sand', transactions, employees);
    const tripRef = findPriorDayWithModeData(todayKey, 'trip', transactions, employees);
    const sandKey = sandRef ?? calendarYesterday;
    const tripKey = tripRef ?? calendarYesterday;

    const todayTrips = buildCountRecordTripUnits(todayKey, transactions, employees);
    const priorTrips = buildCountRecordTripUnits(tripKey, transactions, employees);
    const todaySand = buildCountRecordSandUnit(todayKey, transactions);
    const priorSand = buildCountRecordSandUnit(sandKey, transactions);

    const todayTripTimeline = mergeTripLapTimeline(todayTrips, todayKey);
    const priorTripTimeline = mergeTripLapTimeline(priorTrips, tripKey);

    const todayTripRounds = todayTrips.reduce((s, u) => s + u.rounds, 0);
    const priorTripRounds = priorTrips.reduce((s, u) => s + u.rounds, 0);

    return {
        sand: buildModeComparison(
            todaySand?.lapTimes ?? [],
            priorSand?.lapTimes ?? [],
            todaySand?.rounds ?? 0,
            priorSand?.rounds ?? 0,
            todayKey,
            sandKey,
            sandRef,
            todayKey,
        ),
        trip: buildModeComparison(
            timelineToLapStamps(todayTripTimeline),
            timelineToLapStamps(priorTripTimeline),
            todayTripRounds,
            priorTripRounds,
            todayKey,
            tripKey,
            tripRef,
            todayKey,
        ),
    };
}

export type SandPeriodKey = 'morning' | 'afternoon' | 'ot';

export interface SandPeriodEfficiencyBucket {
    rounds: number;
    activeHours: number;
    roundsPerHour: number;
}

export interface SandPeriodEfficiency {
    morning: SandPeriodEfficiencyBucket | null;
    afternoon: SandPeriodEfficiencyBucket | null;
    ot: SandPeriodEfficiencyBucket | null;
}

function periodKeyFromHour(hour: number): SandPeriodKey | null {
    if (hour < LUNCH_START_HOUR) return 'morning';
    if (hour >= OT_START_HOUR) return 'ot';
    if (hour >= LUNCH_END_HOUR && hour < OT_START_HOUR) return 'afternoon';
    // Lunch hour 12:00–13:00: count rounds in afternoon bucket but active time excludes lunch via activeDurationSec
    if (isLunchHour(hour)) return 'afternoon';
    return null;
}

function bucketFromLaps(stamps: { stamp: string; timeMs: number }[]): SandPeriodEfficiencyBucket | null {
    if (stamps.length < 2) return null;
    const sorted = [...stamps].sort((a, b) => a.timeMs - b.timeMs);
    const first = sorted[0]!;
    const last = sorted[sorted.length - 1]!;
    const activeSec = activeDurationSec(first.timeMs, last.timeMs);
    const activeHours = activeSec / 3600;
    if (activeHours <= 0) return null;
    const rounds = stamps.length;
    return {
        rounds,
        activeHours,
        roundsPerHour: rounds / activeHours,
    };
}

/** Rounds/hour by morning (<12), afternoon (12–16 incl. lunch stamps), OT (>=17) */
export function computeSandPeriodEfficiency(lapTimes: string[], dayKey: string): SandPeriodEfficiency {
    const buckets: Record<SandPeriodKey, { stamp: string; timeMs: number }[]> = {
        morning: [],
        afternoon: [],
        ot: [],
    };
    for (const stamp of lapTimes) {
        const timeMs = parseLapStamp(stamp, dayKey);
        if (timeMs == null) continue;
        const d = new Date(timeMs + TZ_OFFSET_MS);
        const hour = d.getUTCHours();
        const key = periodKeyFromHour(hour);
        if (!key) continue;
        buckets[key].push({ stamp, timeMs });
    }
    return {
        morning: bucketFromLaps(buckets.morning),
        afternoon: bucketFromLaps(buckets.afternoon),
        ot: bucketFromLaps(buckets.ot),
    };
}

export interface SandTargetEta {
    rounds: number;
    target: number;
    remaining: number;
    reached: boolean;
    progressPct: number;
    etaClock: string | null;
    hoursLeft: number | null;
}

export function computeSandTargetEta(
    lapTimes: string[],
    dayKey: string,
    target: number = SAND_TARGET_ROUNDS,
): SandTargetEta {
    const rounds = lapTimes.length;
    const remaining = Math.max(0, target - rounds);
    const progressPct = target > 0 ? Math.min((rounds / target) * 100, 100) : 0;
    if (remaining === 0) {
        return {
            rounds,
            target,
            remaining: 0,
            reached: true,
            progressPct,
            etaClock: null,
            hoursLeft: 0,
        };
    }

    const { intervalsSec } = computeLapIntervals(lapTimes, dayKey);
    const stats = computeIntervalStats(intervalsSec);
    if (stats.avg == null || stats.avg <= 0) {
        return {
            rounds,
            target,
            remaining,
            reached: false,
            progressPct,
            etaClock: null,
            hoursLeft: null,
        };
    }

    const span = computeWorkSpan(lapTimes, dayKey);
    const lastMs = span.endStamp ? parseLapStamp(span.endStamp, dayKey) : null;
    if (lastMs == null) {
        return {
            rounds,
            target,
            remaining,
            reached: false,
            progressPct,
            etaClock: null,
            hoursLeft: null,
        };
    }

    const hoursLeft = (remaining * stats.avg) / 3600;
    const etaMs = lastMs + remaining * stats.avg * 1000;
    const d = new Date(etaMs + TZ_OFFSET_MS);
    const etaClock = `${String(d.getUTCHours()).padStart(2, '0')}:${String(d.getUTCMinutes()).padStart(2, '0')}`;

    return {
        rounds,
        target,
        remaining,
        reached: false,
        progressPct,
        etaClock,
        hoursLeft,
    };
}

/** Fleet trip ETA toward daily trip target — merges lap stamps across vehicles. */
export function computeTripTargetEta(
    tripUnits: { rounds: number; lapTimes: string[] }[],
    dayKey: string,
    target: number,
): SandTargetEta {
    const totalRounds = tripUnits.reduce((s, u) => s + (u.rounds || 0), 0);
    const allLaps = tripUnits.flatMap((u) => u.lapTimes || []);
    const remaining = Math.max(0, target - totalRounds);
    const progressPct = target > 0 ? Math.min((totalRounds / target) * 100, 100) : 0;
    if (remaining === 0) {
        return {
            rounds: totalRounds,
            target,
            remaining: 0,
            reached: true,
            progressPct,
            etaClock: null,
            hoursLeft: 0,
        };
    }
    const base = computeSandTargetEta(allLaps, dayKey, allLaps.length + remaining);
    return {
        rounds: totalRounds,
        target,
        remaining,
        reached: false,
        progressPct,
        etaClock: base.etaClock,
        hoursLeft: base.hoursLeft,
    };
}

export interface PaceConsistency {
    pctInBand: number;
    medianSec: number;
    sampleSize: number;
}

/** % of intervals within ±25% of median; null if fewer than 3 intervals */
export function computePaceConsistency(intervalsSec: number[]): PaceConsistency | null {
    if (intervalsSec.length < 3) return null;
    const stats = computeIntervalStats(intervalsSec);
    if (stats.median == null || stats.median <= 0) return null;
    const lo = stats.median * 0.75;
    const hi = stats.median * 1.25;
    const inBand = intervalsSec.filter((s) => s >= lo && s <= hi).length;
    return {
        pctInBand: (inBand / intervalsSec.length) * 100,
        medianSec: stats.median,
        sampleSize: intervalsSec.length,
    };
}
