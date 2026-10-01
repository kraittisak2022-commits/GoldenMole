import { describe, expect, it } from 'vitest';
import {
    LINE_DAILY_SEND_LIMIT,
    LINE_DAILY_URGENT_SEND_LIMIT,
    isDailySendBudgetExhausted,
    isUrgentDigestSend,
    readDailySendBudget,
} from './line_quota';

const ymd = '2026-10-01';
const withCount = (count: number, day = ymd) => ({ lineDailySendBudget: { ymd: day, count } });

describe('LINE daily send budget', () => {
    it('allows normal sends up to 5 and urgent sends up to 10', () => {
        expect(LINE_DAILY_SEND_LIMIT).toBe(5);
        expect(LINE_DAILY_URGENT_SEND_LIMIT).toBe(10);

        expect(isDailySendBudgetExhausted(withCount(4), ymd)).toBe(false);
        expect(isDailySendBudgetExhausted(withCount(5), ymd)).toBe(true);

        expect(isDailySendBudgetExhausted(withCount(5), ymd, true)).toBe(false);
        expect(isDailySendBudgetExhausted(withCount(9), ymd, true)).toBe(false);
        expect(isDailySendBudgetExhausted(withCount(10), ymd, true)).toBe(true);
    });

    it('resets the count on a new Bangkok day', () => {
        const budget = readDailySendBudget(withCount(10, '2026-09-30'), ymd);
        expect(budget).toEqual({ ymd, count: 0, limit: 5, urgentLimit: 10 });
        expect(isDailySendBudgetExhausted(withCount(10, '2026-09-30'), ymd)).toBe(false);
    });

    it('treats first daily report, explicit flag, and digest signals as urgent', () => {
        expect(isUrgentDigestSend({ decision: 'send_first' })).toBe(true);
        expect(isUrgentDigestSend({ decision: 'send_update' })).toBe(false);
        expect(isUrgentDigestSend({ decision: 'send_update', explicit: true })).toBe(true);
        expect(isUrgentDigestSend({ decision: 'send_update', extra: true })).toBe(true);
    });
});
