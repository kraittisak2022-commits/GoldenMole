import { render, screen } from '@testing-library/react';
import DailyStepRecorder from './DailyStepRecorder';
import { pickLatestByDayOrder } from './dailyStepRecorderUtils';
import { AppSettings, Transaction } from '../../types';

const baseSettings: AppSettings = {
    appName: 'CM',
    appSubtext: '',
    appIcon: '',
    cars: ['รถ A'],
    jobDescriptions: [],
    incomeTypes: ['ขายทราย'],
    expenseTypes: [],
    maintenanceTypes: [],
    locations: ['หน้างาน'],
    landGroups: [],
    appDefaults: {
        vehicleDefaultMachineWage: 4500,
    },
};

describe('DailyStepRecorder integration', () => {
    beforeEach(() => {
        localStorage.clear();
        sessionStorage.clear();
    });

    it('uses org default vehicle machine wage from settings', () => {
        render(
            <DailyStepRecorder
                employees={[{ id: 'd1', name: 'Driver', nickname: 'DRV', type: 'Daily', baseWage: 500, positions: ['คนขับรถ'] } as any]}
                settings={{ ...baseSettings, appDefaults: { ...(baseSettings.appDefaults || {}), vehicleDefaultMachineWage: 4700 } }}
                transactions={[]}
                initialDate="2026-04-24"
                initialStep={2}
                onSaveTransaction={() => {}}
            />
        );
        expect(screen.getByDisplayValue('4700')).toBeInTheDocument();
    });

    it('picks latest attendance by createdAt when day has duplicates', () => {
        const dayTransactions: Transaction[] = [
            {
                id: 'att-old',
                date: '2026-04-24',
                createdAt: '2026-04-24T08:00:00.000Z',
                type: 'Expense',
                category: 'Labor',
                subCategory: 'Attendance',
                laborStatus: 'Work',
                description: 'ค่าแรงเก่า',
                amount: 1000,
                workAssignments: { wash1: ['e1'] },
            },
            {
                id: 'att-new',
                date: '2026-04-24',
                createdAt: '2026-04-24T10:00:00.000Z',
                type: 'Expense',
                category: 'Labor',
                subCategory: 'Attendance',
                laborStatus: 'Work',
                description: 'ค่าแรงใหม่',
                amount: 1500,
                workAssignments: { wash2: ['e2', 'e3'] },
            },
            {
                id: 'other',
                date: '2026-04-24',
                createdAt: '2026-04-24T09:30:00.000Z',
                type: 'Expense',
                category: 'Fuel',
                description: 'เติมน้ำมัน',
                amount: 500,
            },
        ];
        const attendanceOnly = dayTransactions.filter(t => t.category === 'Labor' && t.subCategory === 'Attendance');
        const latest = pickLatestByDayOrder(attendanceOnly, dayTransactions);
        expect(latest?.id).toBe('att-new');
        expect(latest?.description).toBe('ค่าแรงใหม่');
    });
});
