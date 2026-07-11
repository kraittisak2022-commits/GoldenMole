import { describe, expect, it } from 'vitest';
import type { Transaction } from '../../types';
import {
    countRecordLapPeriods,
    diffCountRecordIncrements,
    isCountRecordSandTapRow,
    vehicleTripPeriodSplit,
} from './countRecordUtils';

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

describe('vehicleTripPeriodSplit', () => {
    it('uses explicit morning/afternoon when present', () => {
        const s = vehicleTripPeriodSplit(trip({ tripMorning: 2, tripAfternoon: 3 }));
        expect(s.morning).toBe(2);
        expect(s.afternoon).toBe(3);
    });

    it('splits counter lapTimes by time of day (before/after 12:00)', () => {
        const s = vehicleTripPeriodSplit(
            trip({
                perCarTrips: 4,
                tripCount: 4,
                lapTimes: ['26/06 08:10:00', '26/06 11:55:00', '26/06 13:05:00', '26/06 15:40:00'],
            }),
        );
        expect(s.morning).toBe(2);
        expect(s.afternoon).toBe(2);
    });

    it('counts unparseable laps as morning', () => {
        const s = vehicleTripPeriodSplit(trip({ perCarTrips: 2, lapTimes: ['bad', '26/06 14:00:00'] }));
        expect(s.morning).toBe(1);
        expect(s.afternoon).toBe(1);
    });

    it('falls back to total trips as morning when no laps', () => {
        const s = vehicleTripPeriodSplit(trip({ perCarTrips: 5, tripCount: 5 }));
        expect(s.morning).toBe(5);
        expect(s.afternoon).toBe(0);
    });
});

describe('isCountRecordSandTapRow', () => {
    it('matches sand tap rows only', () => {
        expect(
            isCountRecordSandTapRow({
                id: 's1',
                date: '2026-06-26',
                type: 'Expense',
                category: 'DailyLog',
                subCategory: 'Sand',
                description: 'ร่อนทราย: 3 รอบ',
                amount: 0,
            }),
        ).toBe(true);
        expect(
            isCountRecordSandTapRow({
                id: 's2',
                date: '2026-06-26',
                type: 'Expense',
                category: 'DailyLog',
                subCategory: 'Sand',
                description: 'เครื่องร่อนใหม่',
                amount: 0,
            }),
        ).toBe(false);
    });
});

describe('countRecordLapPeriods', () => {
    it('splits morning and afternoon laps', () => {
        const p = countRecordLapPeriods(
            trip({ lapTimes: ['26/06 08:00:00', '26/06 14:00:00', 'bad'] }),
        );
        expect(p.morning).toBe(1);
        expect(p.afternoon).toBe(1);
        expect(p.unknown).toBe(1);
    });
});

describe('diffCountRecordIncrements', () => {
    it('detects trip and sand increments', () => {
        const prev: Transaction[] = [
            trip({ id: 'v1', perCarTrips: 2, lapTimes: ['26/06 08:00:00', '26/06 09:00:00'] }),
            sand({ id: 's1', drumsObtained: 1, lapTimes: ['26/06 07:00:00'] }),
        ];
        const next: Transaction[] = [
            trip({ id: 'v1', perCarTrips: 3, lapTimes: ['26/06 08:00:00', '26/06 09:00:00', '26/06 10:00:00'] }),
            sand({ id: 's1', drumsObtained: 2, lapTimes: ['26/06 07:00:00', '26/06 08:00:00'] }),
        ];
        const inc = diffCountRecordIncrements('2026-06-26', prev, next, []);
        expect(inc).toHaveLength(2);
        expect(inc.find((i) => i.kind === 'trip')?.delta).toBe(1);
        expect(inc.find((i) => i.kind === 'sand')?.delta).toBe(1);
    });

    it('detects trip and sand decrements', () => {
        const prev: Transaction[] = [
            trip({ id: 'v1', perCarTrips: 3, lapTimes: ['26/06 08:00:00', '26/06 09:00:00', '26/06 10:00:00'] }),
            sand({ id: 's1', drumsObtained: 2, lapTimes: ['26/06 07:00:00', '26/06 08:00:00'] }),
        ];
        const next: Transaction[] = [
            trip({ id: 'v1', perCarTrips: 2, lapTimes: ['26/06 08:00:00', '26/06 09:00:00'] }),
            sand({ id: 's1', drumsObtained: 1, lapTimes: ['26/06 07:00:00'] }),
        ];
        const inc = diffCountRecordIncrements('2026-06-26', prev, next, []);
        expect(inc).toHaveLength(2);
        expect(inc.find((i) => i.kind === 'trip')?.delta).toBe(-1);
        expect(inc.find((i) => i.kind === 'sand')?.delta).toBe(-1);
    });

    it('detects removed trip unit', () => {
        const prev: Transaction[] = [
            trip({ id: 'v1', perCarTrips: 2, lapTimes: ['26/06 08:00:00', '26/06 09:00:00'] }),
        ];
        const next: Transaction[] = [];
        const inc = diffCountRecordIncrements('2026-06-26', prev, next, []);
        expect(inc).toHaveLength(1);
        expect(inc[0]?.delta).toBe(-2);
        expect(inc[0]?.kind).toBe('trip');
    });
});
