import { describe, expect, it } from 'vitest';
import type { Employee, Transaction } from '../types';
import {
    buildVehicleUsageReport,
    filterVehicleUsageByDate,
    filterVehicleUsageReport,
    vehiclePrintGroupTitle,
} from './vehicleUsageReport';

const employees: Employee[] = [
    { id: 'e1', name: 'สมชาย', nickname: 'ชาย', type: 'Daily', positions: ['คนขับรถแม็คโคร'] },
    { id: 'e2', name: 'สมหมาย', nickname: 'หมาย', type: 'Daily', positions: ['คนขับรถ'] },
];

describe('buildVehicleUsageReport', () => {
    it('groups macro, dump trip, and hire rows', () => {
        const transactions: Transaction[] = [
            {
                id: 'm1',
                date: '2026-08-10',
                type: 'Expense',
                category: 'Vehicle',
                description: 'แม็คโคร',
                amount: 0,
                vehicleId: 'แม็คโคร 01',
                driverId: 'e1',
                workType: 'FullDay',
                workDetails: 'ขุดลาน',
            },
            {
                id: 'd1',
                date: '2026-08-10',
                type: 'Expense',
                category: 'DailyLog',
                subCategory: 'VehicleTrip',
                description: 'เที่ยวรถ',
                amount: 0,
                vehicleId: 'รถดรัมโอเว่น',
                driverId: 'e2',
                perCarTrips: 3,
                perCarCubic: 9,
            } as Transaction,
            {
                id: 'h1',
                date: '2026-08-11',
                type: 'Expense',
                category: 'Vehicle',
                description: 'ค่าจ้างรถ',
                amount: 4500,
                vehicleId: 'รถสิบล้อ',
                driverId: 'e2',
                vehicleWage: 4500,
            } as Transaction,
        ];

        const report = buildVehicleUsageReport(transactions, employees, {
            start: '2026-08-01',
            end: '2026-08-31',
        });

        expect(report.totals.macroCount).toBe(1);
        expect(report.totals.macroFullDays).toBe(1);
        expect(report.totals.dumpTrips).toBe(3);
        expect(report.totals.dumpCubic).toBe(9);
        expect(report.totals.hireCount).toBe(1);
        expect(report.totals.count).toBe(3);
        expect(report.byVehicle).toHaveLength(3);

        const macroOnly = filterVehicleUsageReport(report, 'macro');
        expect(macroOnly.rows).toHaveLength(1);
        expect(macroOnly.rows[0].driverLabel).toBe('ชาย');
        expect(vehiclePrintGroupTitle('overview')).toContain('การใช้รถ');

        const macroDay = filterVehicleUsageByDate(macroOnly, '2026-08-10');
        expect(macroDay.rows).toHaveLength(1);
        expect(filterVehicleUsageByDate(macroOnly, '2026-08-11').rows).toHaveLength(0);
    });
});
