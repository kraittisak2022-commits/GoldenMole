import { describe, expect, it } from 'vitest';
import {
    catalogFromCarsAndDrivers,
    makeVehicleId,
    vehiclesToCarsAndDrivers,
} from './vehicleCatalog';

describe('vehicleCatalog', () => {
    it('builds cars and driver map from table rows in sort order', () => {
        const overlay = vehiclesToCarsAndDrivers([
            { id: 'b', name: 'รถ B', defaultDriverId: 'd2', sortOrder: 1 },
            { id: 'a', name: 'รถ A', defaultDriverId: 'd1', sortOrder: 0 },
            { id: 'c', name: 'รถ C', defaultDriverId: '  ', sortOrder: 2 },
        ]);
        expect(overlay.cars).toEqual(['รถ A', 'รถ B', 'รถ C']);
        expect(overlay.vehicleDefaultDrivers).toEqual({ 'รถ A': 'd1', 'รถ B': 'd2' });
    });

    it('reuses existing ids by name when replacing the catalog', () => {
        const existing = [
            { id: 'keep-me', name: 'รถดั๊มโอเว่น', defaultDriverId: 'old', sortOrder: 0 },
        ];
        const next = catalogFromCarsAndDrivers(
            ['รถดั๊มโอเว่น', 'รถดั๊มพี่โก'],
            { 'รถดั๊มโอเว่น': 'd1', 'รถดั๊มพี่โก': 'd2' },
            existing,
        );
        expect(next[0]).toMatchObject({ id: 'keep-me', name: 'รถดั๊มโอเว่น', defaultDriverId: 'd1', sortOrder: 0 });
        expect(next[1]?.id).toBe(makeVehicleId('รถดั๊มพี่โก'));
        expect(next[1]).toMatchObject({ name: 'รถดั๊มพี่โก', defaultDriverId: 'd2', sortOrder: 1 });
    });

    it('drops vehicles that are no longer in the cars list', () => {
        const next = catalogFromCarsAndDrivers(
            ['รถใหม่'],
            {},
            [{ id: 'gone', name: 'รถเก่า', defaultDriverId: 'd1', sortOrder: 0 }],
        );
        expect(next.map((r) => r.name)).toEqual(['รถใหม่']);
    });
});
