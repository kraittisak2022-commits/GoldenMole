import { describe, expect, it } from 'vitest';
import {
    computeCompositeScore,
    countInclusiveDays,
    getPreviousPeriodFilter,
    pctChangeVsPrev,
} from './DashboardV5.utils';

describe('DashboardV5 metrics logic', () => {
    it('counts inclusive days correctly', () => {
        expect(countInclusiveDays('2026-04-01', '2026-04-01')).toBe(1);
        expect(countInclusiveDays('2026-04-01', '2026-04-07')).toBe(7);
    });

    it('builds previous period with equal day count', () => {
        const prev = getPreviousPeriodFilter({ start: '2026-04-10', end: '2026-04-16' });
        expect(prev).toEqual({ start: '2026-04-03', end: '2026-04-09' });
    });

    it('handles zero baseline safely in percent change', () => {
        expect(pctChangeVsPrev(0, 0)).toBe(0);
        expect(pctChangeVsPrev(100, 0)).toBeNull();
    });

    it('computes composite score in a bounded range', () => {
        const out = computeCompositeScore({
            cur: { income: 120000, expense: 80000, profit: 40000 },
            prev: { income: 100000, expense: 85000, profit: 15000 },
            sandWashed: 120,
            sandTransported: 100,
            prevSandWashed: 80,
            prevSandTransported: 90,
        });
        expect(out.score).toBeGreaterThanOrEqual(0);
        expect(out.score).toBeLessThanOrEqual(100);
        expect(out.breakdown).toHaveLength(4);
    });
});
