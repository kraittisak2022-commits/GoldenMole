import { describe, expect, it } from 'vitest';
import type { AppSettings, Employee } from '../types';
import {
    driverLabel,
    driverOptionLabel,
    getDriverEmployees,
    getVehicleDefaultDriverId,
    removeVehicleDefaultDriver,
    renameVehicleDefaultDriver,
    setVehicleDefaultDriver,
} from './vehicleDefaultDriverUtils';

const baseSettings: AppSettings = {
    appName: 'Test',
    appSubtext: '',
    appIcon: '',
    cars: ['รถดรัมโอเว่น'],
    jobDescriptions: [],
    incomeTypes: [],
    expenseTypes: [],
    maintenanceTypes: [],
    locations: [],
    landGroups: [],
    appDefaults: {
        vehicleDefaultDrivers: {
            'รถดรัมโอเว่น': 'd1',
        },
    },
};

const driver: Employee = {
    id: 'd1',
    name: 'สมชาย',
    nickname: 'พี่นุ',
    type: 'Daily',
    baseWage: 500,
    positions: ['คนขับรถ'],
};

describe('vehicleDefaultDriverUtils', () => {
    it('filters driver employees', () => {
        const list = getDriverEmployees([
            driver,
            { id: 'x1', name: 'A', type: 'Daily', baseWage: 0, positions: ['รับจ้างรายวัน'] },
        ]);
        expect(list).toHaveLength(1);
        expect(list[0]?.id).toBe('d1');
    });

    it('reads default driver from settings', () => {
        expect(getVehicleDefaultDriverId('รถดรัมโอเว่น', baseSettings)).toBe('d1');
        expect(getVehicleDefaultDriverId('ไม่มี', baseSettings)).toBeNull();
    });

    it('sets and clears default driver', () => {
        let map: Record<string, string> = {};
        map = setVehicleDefaultDriver(map, 'รถ A', 'd2');
        expect(map['รถ A']).toBe('d2');
        map = setVehicleDefaultDriver(map, 'รถ A', '');
        expect(map['รถ A']).toBeUndefined();
    });

    it('renames and removes vehicle keys', () => {
        let map = { 'รถเก่า': 'd1' };
        map = renameVehicleDefaultDriver(map, 'รถเก่า', 'รถใหม่');
        expect(map['รถใหม่']).toBe('d1');
        expect(map['รถเก่า']).toBeUndefined();
        map = removeVehicleDefaultDriver(map, 'รถใหม่');
        expect(map['รถใหม่']).toBeUndefined();
    });

    it('formats driver labels', () => {
        expect(driverLabel([driver], 'd1')).toBe('พี่นุ');
        expect(driverOptionLabel(driver, 'd1')).toContain('ค่าเริ่มต้น');
        expect(driverOptionLabel(driver, 'other')).toBe('พี่นุ');
    });
});
