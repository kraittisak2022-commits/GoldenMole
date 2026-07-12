import { describe, expect, it } from 'vitest';
import type { Transaction } from '../../types';
import {
    activeDurationSec,
    buildDayComparison,
    buildIntervalSparkline,
    computeCumulativeSeries,
    computeHourlyActiveWork,
    computeHourlyBuckets,
    computeHourlyEfficiency,
    computeHourlyHeatmap,
    computeHourlySandSpeed,
    computeIntervalStats,
    computeLapIntervals,
    computeMinuteSandSpeed,
    computeMovingAverage,
    computePaceDeltaPercent,
    computePeakHour,
    computeSandWorkDurationSummary,
    computeTripFleetWorkSpan,
    computeWorkSpan,
    formatActiveHours,
    formatLapClock,
    formatPaceDelta,
    formatWorkSpanLabel,
    isLunchHour,
    lunchOverlapMs,
    mergeTripLapTimeline,
    parseLapStamp,
    timelineToLapStamps,
} from './countRecordAnalytics';
import { buildCountRecordTripUnits } from './countRecordUtils';

function trip(partial: Partial<Transaction> & { lapTimes?: string[] }): Transaction {
    const { lapTimes, ...rest } = partial;
    return {
        id: 't1',
        date: '2026-06-26',
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'VehicleTrip',
        description: 'รถดรัม',
        amount: 0,
        vehicleId: 'รถดรัมโอเว่น',
        workAssignments: lapTimes ? { lapTimes } : undefined,
        ...rest,
    };
}

function sand(partial: Partial<Transaction> & { lapTimes?: string[]; drumsObtained?: number }): Transaction {
    const { lapTimes, drumsObtained, ...rest } = partial;
    return {
        id: 's1',
        date: '2026-06-26',
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'Sand',
        description: 'ร่อนทราย',
        amount: 0,
        drumsObtained,
        workAssignments: lapTimes ? { lapTimes } : undefined,
        ...rest,
    };
}

describe('parseLapStamp', () => {
    it('parses dd/MM HH:mm:ss with year from dayKey', () => {
        const ms = parseLapStamp('26/06 08:10:00', '2026-06-26');
        expect(ms).not.toBeNull();
        const d = new Date(ms! + 7 * 60 * 60 * 1000);
        expect(d.getUTCHours()).toBe(8);
        expect(d.getUTCMinutes()).toBe(10);
    });

    it('returns null for invalid stamp', () => {
        expect(parseLapStamp('bad', '2026-06-26')).toBeNull();
        expect(parseLapStamp('26/06', '2026-06-26')).toBeNull();
    });
});

describe('computeLapIntervals', () => {
    it('computes seconds between consecutive laps', () => {
        const { intervalsSec, labels } = computeLapIntervals(
            ['26/06 08:00:00', '26/06 08:07:00', '26/06 08:15:30'],
            '2026-06-26',
        );
        expect(intervalsSec).toEqual([420, 510]);
        expect(labels).toEqual(['รอบ 1→2', 'รอบ 2→3']);
    });

    it('returns empty for single lap', () => {
        const { intervalsSec } = computeLapIntervals(['26/06 08:00:00'], '2026-06-26');
        expect(intervalsSec).toEqual([]);
    });

    it('excludes lunch break from interval spanning 12:00–13:00', () => {
        const { intervalsSec } = computeLapIntervals(
            ['26/06 11:50:00', '26/06 13:10:00'],
            '2026-06-26',
        );
        expect(intervalsSec).toEqual([20 * 60]);
    });
});

describe('lunch overlap', () => {
    it('deducts one hour for full-day span crossing lunch', () => {
        const start = parseLapStamp('26/06 08:00:00', '2026-06-26')!;
        const end = parseLapStamp('26/06 17:00:00', '2026-06-26')!;
        expect(lunchOverlapMs(start, end)).toBe(60 * 60 * 1000);
        expect(activeDurationSec(start, end)).toBe(8 * 60 * 60);
    });
});

describe('computeSandWorkDurationSummary', () => {
    it('returns active hours excluding lunch', () => {
        const summary = computeSandWorkDurationSummary(
            ['26/06 08:00:00', '26/06 12:30:00', '26/06 17:00:00'],
            '2026-06-26',
        );
        expect(summary).not.toBeNull();
        expect(summary!.totalActiveHours).toBe(8);
        expect(summary!.lunchDeductedHours).toBe(1);
        expect(formatActiveHours(summary!.totalActiveHours)).toBe('8 ชม.');
    });
});

describe('moving average and sparkline', () => {
    it('computes moving average with null prefix', () => {
        const ma = computeMovingAverage([100, 200, 300, 400, 500], 3);
        expect(ma).toEqual([null, null, 200, 300, 400]);
    });

    it('builds sparkline from last N intervals', () => {
        const spark = buildIntervalSparkline([10, 20, 30, 40, 50, 60, 70], 4);
        expect(spark).toEqual([40, 50, 60, 70]);
    });
});

describe('hourly heatmap', () => {
    it('returns 24 cells with intensity', () => {
        const cells = computeHourlyHeatmap(
            ['26/06 08:10:00', '26/06 08:40:00', '26/06 14:00:00'],
            '2026-06-26',
        );
        expect(cells).toHaveLength(24);
        expect(cells.find((c) => c.hour === 8)?.count).toBe(2);
        expect(cells.find((c) => c.hour === 14)?.count).toBe(1);
        expect(cells.find((c) => c.hour === 8)?.intensity).toBe(1);
    });

    it('excludes lunch hour laps from heatmap counts', () => {
        const cells = computeHourlyHeatmap(
            ['26/06 08:10:00', '26/06 12:30:00', '26/06 14:00:00'],
            '2026-06-26',
        );
        const lunch = cells.find((c) => c.hour === 12);
        expect(lunch?.isLunch).toBe(true);
        expect(lunch?.count).toBe(0);
        expect(cells.find((c) => c.hour === 8)?.count).toBe(1);
        expect(cells.find((c) => c.hour === 14)?.count).toBe(1);
    });
});

describe('lunch exclusion from hourly analytics', () => {
    const lapsWithLunch = ['26/06 08:10:00', '26/06 12:30:00', '26/06 14:00:00'];
    const dayKey = '2026-06-26';

    it('isLunchHour matches 12:00–12:59 only', () => {
        expect(isLunchHour(11)).toBe(false);
        expect(isLunchHour(12)).toBe(true);
        expect(isLunchHour(13)).toBe(false);
    });

    it('excludes lunch laps from hourly buckets and efficiency', () => {
        const buckets = computeHourlyBuckets(lapsWithLunch, dayKey);
        expect(buckets.some((b) => b.hour === 12)).toBe(false);
        expect(buckets.find((b) => b.hour === 8)?.count).toBe(1);
        expect(buckets.find((b) => b.hour === 14)?.count).toBe(1);

        const efficiency = computeHourlyEfficiency(lapsWithLunch, dayKey);
        expect(efficiency.some((b) => b.hour === 12)).toBe(false);
    });

    it('excludes lunch minutes from minute sand speed', () => {
        const speed = computeMinuteSandSpeed(lapsWithLunch, dayKey);
        expect(speed.find((b) => b.label === '12:30')).toBeUndefined();
        expect(speed.find((b) => b.label === '08:10')?.speed).toBe(1);
    });

    it('does not pick lunch hour as peak', () => {
        const onlyLunch = ['26/06 12:15:00', '26/06 12:45:00'];
        const cells = computeHourlyHeatmap(onlyLunch, dayKey);
        expect(computePeakHour(cells)).toBeNull();
    });

    it('still includes lunch laps in cumulative series totals', () => {
        const cumulative = computeCumulativeSeries(lapsWithLunch, dayKey);
        expect(cumulative).toHaveLength(3);
        expect(cumulative[cumulative.length - 1]?.value).toBe(3);
    });
});

describe('sand speed and work hour buckets', () => {
    const laps = [
        '26/06 08:10:00',
        '26/06 08:40:00',
        '26/06 09:15:00',
        '26/06 14:00:00',
    ];

    it('computes hourly sand speed', () => {
        const speed = computeHourlySandSpeed(laps, '2026-06-26');
        expect(speed.some((b) => b.label === '08:00' && b.speed === 2)).toBe(true);
        expect(speed.some((b) => b.label === '09:00' && b.speed === 1)).toBe(true);
        expect(speed.some((b) => b.label === '14:00' && b.speed === 1)).toBe(true);
    });

    it('computes minute sand speed for active minutes', () => {
        const speed = computeMinuteSandSpeed(laps, '2026-06-26');
        expect(speed.find((b) => b.label === '08:10')?.speed).toBe(1);
        expect(speed.find((b) => b.label === '08:40')?.speed).toBe(1);
    });

    it('computes hourly active work buckets', () => {
        const buckets = computeHourlyActiveWork(
            ['26/06 08:00:00', '26/06 17:00:00'],
            '2026-06-26',
        );
        expect(buckets.length).toBeGreaterThan(0);
        const lunchHour = buckets.find((b) => b.hour === 12);
        expect(lunchHour?.activeMinutes).toBe(0);
        const morning = buckets.find((b) => b.hour === 8);
        expect(morning?.activeHours).toBe(1);
    });
});

describe('computeIntervalStats', () => {
    it('computes avg/median/min/max/last', () => {
        const s = computeIntervalStats([300, 600, 900]);
        expect(s.avg).toBe(600);
        expect(s.median).toBe(600);
        expect(s.min).toBe(300);
        expect(s.max).toBe(900);
        expect(s.last).toBe(900);
    });
});

describe('paceDelta', () => {
    it('negative means faster than yesterday', () => {
        const pct = computePaceDeltaPercent(400, 500);
        expect(pct).toBe(-20);
        const { text, faster } = formatPaceDelta(pct);
        expect(faster).toBe(true);
        expect(text).toContain('เร็วกว่า');
    });

    it('positive means slower than yesterday', () => {
        const pct = computePaceDeltaPercent(600, 500);
        expect(pct).toBe(20);
        const { faster } = formatPaceDelta(pct);
        expect(faster).toBe(false);
    });

    it('handles missing yesterday data', () => {
        const { text, faster } = formatPaceDelta(null);
        expect(faster).toBeNull();
        expect(text).toContain('ไม่มีข้อมูลเมื่อวาน');
    });
});

describe('mergeTripLapTimeline', () => {
    it('merges multiple vehicles sorted by time', () => {
        const units = buildCountRecordTripUnits(
            '2026-06-26',
            [
                trip({
                    id: 'a',
                    vehicleId: 'รถ A',
                    lapTimes: ['26/06 10:00:00', '26/06 10:30:00'],
                    perCarTrips: 2,
                }),
                trip({
                    id: 'b',
                    vehicleId: 'รถ B',
                    lapTimes: ['26/06 09:00:00', '26/06 09:20:00'],
                    perCarTrips: 2,
                }),
            ],
            [],
        );
        const events = mergeTripLapTimeline(units, '2026-06-26');
        expect(events.map((e) => e.vehicleId)).toEqual(['รถ B', 'รถ B', 'รถ A', 'รถ A']);
        const stamps = timelineToLapStamps(events);
        const intervals = computeLapIntervals(stamps, '2026-06-26');
        expect(intervals.intervalsSec.length).toBe(3);
    });
});

describe('buildDayComparison', () => {
    it('compares today vs yesterday rounds and pace', () => {
        const txs: Transaction[] = [
            sand({
                id: 's-today',
                date: '2026-06-26',
                lapTimes: ['26/06 08:00:00', '26/06 08:10:00', '26/06 08:25:00'],
                drumsObtained: 3,
            }),
            sand({
                id: 's-yesterday',
                date: '2026-06-25',
                lapTimes: ['25/06 08:00:00', '25/06 08:20:00'],
                drumsObtained: 2,
            }),
            trip({
                id: 'v-today',
                date: '2026-06-26',
                lapTimes: ['26/06 09:00:00', '26/06 09:05:00'],
                perCarTrips: 2,
            }),
        ];
        const cmp = buildDayComparison('2026-06-26', txs, []);
        expect(cmp.sand.todayRounds).toBe(3);
        expect(cmp.sand.yesterdayRounds).toBe(2);
        expect(cmp.sand.roundsDeltaPct).toBe(50);
        expect(cmp.sand.paceDeltaPct).not.toBeNull();
        expect(cmp.trip.todayRounds).toBe(2);
    });
});

describe('formatLapClock', () => {
    it('extracts HH:mm from stamp', () => {
        expect(formatLapClock('26/06 08:10:00')).toBe('08:10');
        expect(formatLapClock('bad')).toBeNull();
    });
});

describe('computeWorkSpan', () => {
    it('returns first and last lap clocks', () => {
        const span = computeWorkSpan(
            ['26/06 08:12:00', '26/06 12:00:00', '26/06 16:45:30'],
            '2026-06-26',
        );
        expect(span.startClock).toBe('08:12');
        expect(span.endClock).toBe('16:45');
        expect(formatWorkSpanLabel(span)).toBe('เริ่ม 08:12 · เลิก 16:45');
    });

    it('handles single lap', () => {
        const span = computeWorkSpan(['26/06 09:00:00'], '2026-06-26');
        expect(formatWorkSpanLabel(span)).toBe('เริ่ม 09:00');
    });
});

describe('computeTripFleetWorkSpan', () => {
    it('spans across all vehicles', () => {
        const units = buildCountRecordTripUnits(
            '2026-06-26',
            [
                trip({ id: 'a', vehicleId: 'รถ A', lapTimes: ['26/06 16:00:00'], perCarTrips: 1 }),
                trip({ id: 'b', vehicleId: 'รถ B', lapTimes: ['26/06 08:00:00'], perCarTrips: 1 }),
            ],
            [],
        );
        const span = computeTripFleetWorkSpan(units, '2026-06-26');
        expect(span.startClock).toBe('08:00');
        expect(span.endClock).toBe('16:00');
    });
});
