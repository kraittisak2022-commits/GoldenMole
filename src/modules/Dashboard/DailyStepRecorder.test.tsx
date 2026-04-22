import { act, render, screen } from '@testing-library/react';
import DailyStepRecorder from './DailyStepRecorder';
import { AppSettings } from '../../types';
import { WizardDraftPayload, WIZARD_DRAFT_STORAGE_KEY, writeWizardDraftForDate } from './wizardDraftUtils';

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
};

const basePayload: WizardDraftPayload = {
    step: 2,
    laborSearch: '',
    selectedEmps: [],
    laborStatus: 'Work',
    halfDayEmpIds: [],
    drumsWashedAtHome: '',
    otHours: '',
    otDesc: '',
    otRate: '',
    workAssignments: {},
    customCategories: [],
    newCategoryName: '',
    vehCar: '',
    vehDriver: '',
    vehWage: '',
    vehMachineWage: '',
    vehDetails: '',
    vehWorkType: 'FullDay',
    editingVehicleTxId: null,
    tripEntries: [{ id: '1', vehicle: '', driver: '', work: '', cubicPerTrip: '' }],
    tripMorning: '',
    tripAfternoon: '',
    sand1Morning: '',
    sand1Afternoon: '',
    sand2Morning: '',
    sand2Afternoon: '',
    sand1Operators: [],
    sand2Operators: [],
    sandDrumsObtained: '',
    sandMorningStart: '',
    sandAfternoonStart: '',
    sandEveningEnd: '',
    fuelAmount: '',
    fuelLiters: '',
    fuelType: 'Diesel',
    fuelUnit: 'ลิตร',
    fuelDetails: '',
    fuelVehicle: '',
    fuelVehicleLiters: '',
    fuelVehicleType: 'Diesel',
    fuelVehicleDetails: '',
    incomeType: '',
    incomeQty: '',
    incomeUnitPrice: '',
    incomeTotal: '',
    newIncomeType: '',
    incomeTypeAddOpen: false,
    eventDesc: '',
    eventType: 'info',
    eventPriority: 'normal',
};

describe('DailyStepRecorder integration', () => {
    beforeEach(() => {
        localStorage.clear();
        sessionStorage.clear();
    });

    it('shows draft conflict warning when tx fingerprint changed', () => {
        writeWizardDraftForDate('2026-04-22', basePayload, 'old-fingerprint');

        render(
            <DailyStepRecorder
                employees={[]}
                settings={baseSettings}
                transactions={[]}
                initialDate="2026-04-22"
                onSaveTransaction={() => {}}
            />
        );

        expect(screen.getByText(/พบแบบร่างที่ยังไม่เสร็จ/)).toBeInTheDocument();
        expect(screen.getByText(/มีข้อมูลรายการของวันนี้เปลี่ยนไปจากตอนที่บันทึกแบบร่าง/)).toBeInTheDocument();
    });

    it('updates autosave status and reacts to cross-tab storage event', async () => {
        vi.useFakeTimers();
        try {
            render(
                <DailyStepRecorder
                    employees={[]}
                    settings={baseSettings}
                    transactions={[]}
                    initialDate="2026-04-23"
                    initialStep={1}
                    onSaveTransaction={() => {}}
                />
            );

            expect(screen.getByRole('status')).toHaveTextContent('กำลังบันทึกแบบร่าง');
            await act(async () => {
                vi.advanceTimersByTime(900);
            });
            expect(screen.getByRole('status').textContent || '').toMatch(/บันทึกล่าสุด/);

            writeWizardDraftForDate('2026-04-23', { ...basePayload, step: 4 }, 'external');
            const newValue = localStorage.getItem(WIZARD_DRAFT_STORAGE_KEY);
            await act(async () => {
                window.dispatchEvent(new StorageEvent('storage', { key: WIZARD_DRAFT_STORAGE_KEY, newValue: newValue || '' }));
                window.dispatchEvent(new StorageEvent('storage', { key: WIZARD_DRAFT_STORAGE_KEY, newValue: newValue || '' }));
            });
            expect(screen.getByText(/พบแบบร่างที่ยังไม่เสร็จ/)).toBeInTheDocument();
        } finally {
            vi.useRealTimers();
        }
    });
});
