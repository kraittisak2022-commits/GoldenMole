import { describe, expect, it } from 'vitest';
import {
    SHARE_PIN_MAX_LENGTH,
    SHARE_PIN_MIN_LENGTH,
    isValidSharePinFormat,
} from './shareAuth';

describe('shareAuth', () => {
    it('accepts 4-6 digit pins', () => {
        expect(isValidSharePinFormat('1234')).toBe(true);
        expect(isValidSharePinFormat('123456')).toBe(true);
        expect(isValidSharePinFormat('123')).toBe(false);
        expect(isValidSharePinFormat('1234567')).toBe(false);
        expect(isValidSharePinFormat('12ab')).toBe(false);
    });

    it('exports pin length constants', () => {
        expect(SHARE_PIN_MIN_LENGTH).toBe(4);
        expect(SHARE_PIN_MAX_LENGTH).toBe(6);
    });
});
