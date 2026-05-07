import { act, fireEvent, render, screen } from '@testing-library/react';
import DailyStepRecorder, { computeSandBatchStock, pickLatestByDayOrder } from './DailyStepRecorder';
import { AppSettings, Transaction } from '../../types';
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
    appDefaults: {
        vehicleDefaultMachineWage: 4500,
    },
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
        expect(screen.queryByText(/มีข้อมูลรายการของวันนี้เปลี่ยนไปจากตอนที่บันทึกแบบร่าง/)).not.toBeInTheDocument();
        fireEvent.click(screen.getByRole('button', { name: /ดูรายละเอียด/ }));
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

describe('computeSandBatchStock', () => {
    const baseSandTx = (over: Partial<Transaction> & Record<string, unknown>): Transaction => ({
        id: String(over.id || `s_${Math.random()}`),
        date: String(over.date || '2026-04-24'),
        type: 'Expense',
        category: 'DailyLog',
        subCategory: 'Sand',
        description: '',
        amount: 0,
        ...over,
    } as Transaction);

    it('does not double count obtained or used when sand1 + sand2 share the same lot on a single day', () => {
        // Real-world layout: bookkeeper runs both machines on 2026-04-24, obtains 10 drums total
        // for lot BATCH-A, washes 5 at home from the same lot. Save handler persists TWO rows
        // (s1 + s2) with identical drumsObtained=10 and identical sandHomeBatchUsages.
        const txs: Transaction[] = [
            baseSandTx({
                id: 's1',
                date: '2026-04-24',
                sandBatchId: 'BATCH-A',
                drumsObtained: 10,
                sandHomeBatchUsages: [{ batchId: 'BATCH-A', sourceDate: '2026-04-24', drums: 5 }],
            }),
            baseSandTx({
                id: 's2',
                date: '2026-04-24',
                sandBatchId: 'BATCH-A',
                drumsObtained: 10,
                sandHomeBatchUsages: [{ batchId: 'BATCH-A', sourceDate: '2026-04-24', drums: 5 }],
            }),
        ];
        const stock = computeSandBatchStock(txs);
        expect(stock).toHaveLength(1);
        expect(stock[0]).toMatchObject({ batchId: 'BATCH-A', obtained: 10, used: 5, available: 5 });
    });

    it('attributes used drums to the consumed lot, not the carrier row lot', () => {
        // Yesterday produced BATCH-A (10 drums, none washed). Today produces BATCH-B,
        // and home-washes 4 drums from the older BATCH-A (FIFO).
        const txs: Transaction[] = [
            baseSandTx({
                id: 'yesterday',
                date: '2026-04-23',
                sandBatchId: 'BATCH-A',
                drumsObtained: 10,
                sandHomeBatchUsages: [],
            }),
            baseSandTx({
                id: 'today',
                date: '2026-04-24',
                sandBatchId: 'BATCH-B',
                drumsObtained: 6,
                sandHomeBatchUsages: [{ batchId: 'BATCH-A', sourceDate: '2026-04-23', drums: 4 }],
            }),
        ];
        const stock = computeSandBatchStock(txs);
        const a = stock.find(s => s.batchId === 'BATCH-A');
        const b = stock.find(s => s.batchId === 'BATCH-B');
        // BATCH-A was consumed by 4 — must reduce A's available, not B's.
        expect(a).toMatchObject({ obtained: 10, used: 4, available: 6 });
        expect(b).toMatchObject({ obtained: 6, used: 0, available: 6 });
    });

    it('keeps the earliest sourceDate when multiple rows describe the same lot', () => {
        const txs: Transaction[] = [
            baseSandTx({ id: 's_apr24', date: '2026-04-24', sandBatchId: 'BATCH-X', drumsObtained: 0 }),
            baseSandTx({ id: 's_apr20', date: '2026-04-20', sandBatchId: 'BATCH-X', drumsObtained: 8 }),
        ];
        const stock = computeSandBatchStock(txs);
        expect(stock).toHaveLength(1);
        expect(stock[0]).toMatchObject({ batchId: 'BATCH-X', sourceDate: '2026-04-20' });
    });

    it('ignores rows without a batch id and zero/invalid usages', () => {
        const txs: Transaction[] = [
            baseSandTx({ id: 'noBatch', date: '2026-04-24', drumsObtained: 99 }),
            baseSandTx({
                id: 'zero',
                date: '2026-04-24',
                sandBatchId: 'BATCH-Z',
                drumsObtained: 5,
                sandHomeBatchUsages: [
                    { batchId: '', sourceDate: '2026-04-24', drums: 2 },
                    { batchId: 'BATCH-Z', sourceDate: '2026-04-24', drums: 0 },
                    { batchId: 'BATCH-Z', sourceDate: '2026-04-24', drums: -3 },
                ],
            }),
        ];
        const stock = computeSandBatchStock(txs);
        expect(stock).toHaveLength(1);
        expect(stock[0]).toMatchObject({ batchId: 'BATCH-Z', obtained: 5, used: 0, available: 5 });
    });
});
