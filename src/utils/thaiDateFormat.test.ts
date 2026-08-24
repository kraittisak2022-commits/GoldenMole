import { describe, expect, it } from 'vitest';
import { daysInMonth, formatDateBELong, ymdFromParts } from './index';

describe('Thai date helpers', () => {
    it('formatDateBELong uses Thai month names and Buddhist year', () => {
        expect(formatDateBELong('2026-08-24')).toBe('24 สิงหาคม 2569');
        expect(formatDateBELong('2026-02-01')).toBe('1 กุมภาพันธ์ 2569');
    });

    it('ymdFromParts clamps days to the month length', () => {
        expect(daysInMonth(2026, 2)).toBe(28);
        expect(ymdFromParts(2026, 2, 31)).toBe('2026-02-28');
        expect(ymdFromParts(2026, 8, 5)).toBe('2026-08-05');
    });
});
