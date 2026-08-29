import { describe, expect, it } from 'vitest';
import type { Employee } from '../types';
import {
    collectEmployeePositionTokens,
    coercePositionSources,
    employeeEligibleForAdvancePicker,
    isExcludedFromAdvanceEmployeePicker,
    isSandYardOrMacroDriverEmployee,
    isSandYardOrMacroDriverPositionToken,
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
    it('shows when any position is not excluded', () => {
        const e = base({ positions: ['ร่อนทราย', 'คนขับรถ'] });
        expect(isExcludedFromAdvanceEmployeePicker(e)).toBe(false);
        expect(employeeEligibleForAdvancePicker(e)).toBe(true);
    });

    it('shows when legacy position is excluded but list has eligible title', () => {
        const e = base({ positions: ['ร่อนทราย'], position: 'รับจ้างรายวัน' });
        expect(isExcludedFromAdvanceEmployeePicker(e)).toBe(false);
        expect(employeeEligibleForAdvancePicker(e)).toBe(true);
    });

    it('hides only when every position is excluded', () => {
        const e = base({ positions: ['คนขับรถ', 'รับจ้างรายวัน'] });
        expect(isExcludedFromAdvanceEmployeePicker(e)).toBe(true);
        expect(employeeEligibleForAdvancePicker(e)).toBe(false);
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

describe('sand yard / macro driver pool', () => {
    it('matches whitelist titles including alternate spellings', () => {
        expect(isSandYardOrMacroDriverPositionToken('พนักงานท่าทราย')).toBe(true);
        expect(isSandYardOrMacroDriverPositionToken('พนักงานทำทราย')).toBe(true);
        expect(isSandYardOrMacroDriverPositionToken('ท่าทราย')).toBe(true);
        expect(isSandYardOrMacroDriverPositionToken('คนขับรถแม็คโคร')).toBe(true);
        expect(isSandYardOrMacroDriverPositionToken('คนขับรถแมคโคร')).toBe(true);
        expect(isSandYardOrMacroDriverPositionToken('พนักงาน ท่าทราย')).toBe(true);
        expect(isSandYardOrMacroDriverPositionToken('คนขับรถ')).toBe(false);
        expect(isSandYardOrMacroDriverPositionToken('ร่อนทราย')).toBe(false);
    });

    it('matches employee when any position is in the pool', () => {
        expect(isSandYardOrMacroDriverEmployee(base({ positions: ['คนขับรถ', 'พนักงานท่าทราย'] }))).toBe(true);
        expect(isSandYardOrMacroDriverEmployee(base({ position: 'คนขับรถแม็คโคร' }))).toBe(true);
        expect(isSandYardOrMacroDriverEmployee(base({ positions: ['คนขับรถ'] }))).toBe(false);
    });

    it('does not use inactive for the position predicate', () => {
        expect(
            isSandYardOrMacroDriverEmployee(
                base({ positions: ['พนักงานท่าทราย'], inactive: true }),
            ),
        ).toBe(true);
    });
});
