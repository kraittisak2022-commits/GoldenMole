import { describe, expect, it } from 'vitest';
import type { Employee } from '../types';
import {
    collectEmployeePositionTokens,
    coercePositionSources,
    employeeEligibleForAdvancePicker,
    isExcludedFromAdvanceEmployeePicker,
} from './advanceEmployeeFilter';

const base = (overrides: Partial<Employee> = {}): Employee => ({
    id: '1',
    name: 'Test',
    nickname: 'T',
    type: 'Daily',
    ...overrides,
});

describe('coercePositionSources', () => {
    it('accepts array', () => {
        expect(coercePositionSources(['ร่อนทราย', 'คนขับรถ'], null)).toEqual([
            'ร่อนทราย',
            'คนขับรถ',
        ]);
    });

    it('accepts JSON string array', () => {
        expect(coercePositionSources('["คนขับรถ"]', null)).toEqual(['คนขับรถ']);
    });

    it('does not throw when positions is a plain string', () => {
        expect(() => coercePositionSources('คนขับรถ', null)).not.toThrow();
        expect(coercePositionSources('คนขับรถ', null)).toEqual(['คนขับรถ']);
    });

    it('does not throw when positions is a non-array object', () => {
        expect(() => coercePositionSources({ a: 'ร่อนทราย' }, 'คนขับรถ')).not.toThrow();
    });
});

describe('advance employee filter', () => {
    it('excludes when any position matches', () => {
        const e = base({ positions: ['ร่อนทราย', 'คนขับรถ'] });
        expect(isExcludedFromAdvanceEmployeePicker(e)).toBe(true);
        expect(employeeEligibleForAdvancePicker(e)).toBe(false);
    });

    it('excludes legacy position field', () => {
        const e = base({ positions: ['ร่อนทราย'], position: 'รับจ้างรายวัน' });
        expect(isExcludedFromAdvanceEmployeePicker(e)).toBe(true);
    });

    it('handles positions stored as string (legacy row)', () => {
        const e = base({ positions: 'คนขับรถ' as unknown as string[] });
        expect(isExcludedFromAdvanceEmployeePicker(e)).toBe(true);
    });

    it('eligible when no excluded title', () => {
        const e = base({ positions: ['ร่อนทราย'] });
        expect(employeeEligibleForAdvancePicker(e)).toBe(true);
    });

    it('collects unique tokens', () => {
        expect(
            collectEmployeePositionTokens(
                base({ positions: ['ร่อนทราย'], position: 'ร่อนทราย' }),
            ),
        ).toEqual(['ร่อนทราย']);
    });
});
