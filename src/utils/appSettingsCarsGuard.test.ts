import { describe, expect, it } from 'vitest';
import {
    MOCK_SEED_CARS,
    isExactMockSeedCars,
    resolveCarsForSave,
} from './appSettingsCarsGuard';

describe('resolveCarsForSave', () => {
    const realCars = ['รถดั๊มนายกพนม', 'รถแม็คโคร SK200-10 (พี่เดอะฮัก)'];

    it('keeps existing cars when incoming is empty', () => {
        expect(resolveCarsForSave([], realCars)).toEqual(realCars);
    });

    it('keeps existing cars when incoming is the mock seed list', () => {
        expect(resolveCarsForSave([...MOCK_SEED_CARS], realCars)).toEqual(realCars);
    });

    it('allows a real non-empty list through', () => {
        expect(resolveCarsForSave(realCars, MOCK_SEED_CARS as unknown as string[])).toEqual(realCars);
    });

    it('detects the exact mock seed list', () => {
        expect(isExactMockSeedCars([...MOCK_SEED_CARS])).toBe(true);
        expect(isExactMockSeedCars(realCars)).toBe(false);
    });
});
