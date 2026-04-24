import { useMemo, useState } from 'react';
import DailyStepRecorder from '../modules/Dashboard/DailyStepRecorder';
import DataVerificationModule from '../modules/DataQuality/DataVerificationModule';
import { AppSettings, Transaction } from '../types';
import { getDayTransactionFingerprint, writeWizardDraftForDate, clearAllWizardDrafts, WizardDraftPayload } from '../modules/Dashboard/wizardDraftUtils';
import { normalizeDate } from '../utils';

const baseSettings: AppSettings = {
    appName: 'E2E Harness',
    appSubtext: '',
    appIcon: '',
    cars: ['รถ A', 'รถ B'],
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
    vehCar: 'รถ A',
    vehDriver: '',
    vehWage: '200',
    vehMachineWage: '3000',
    vehDetails: 'ทดสอบจาก draft',
    vehWorkType: 'FullDay',
    editingVehicleTxId: null,
    tripEntries: [{ id: 't1', vehicle: '', driver: '', work: '', cubicPerTrip: '' }],
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

export default function E2EHarness() {
    const [transactions, setTransactions] = useState<Transaction[]>([
        {
            id: 'seed_trip_1',
            date: normalizeDate('2026-04-20'),
            type: 'Expense',
            category: 'DailyLog',
            subCategory: 'VehicleTrip',
            description: 'seed trip',
            amount: 0,
            totalCubic: 800,
        } as Transaction,
        {
            id: 'seed_sand_1',
            date: normalizeDate('2026-04-20'),
            type: 'Expense',
            category: 'DailyLog',
            subCategory: 'Sand',
            description: 'seed sand',
            amount: 0,
            drumsObtained: 52,
            drumsWashedAtHome: 52,
            sandBatchId: 'BATCH-SEED-001',
            sandHomeBatchUsages: [{ batchId: 'BATCH-SEED-001', sourceDate: normalizeDate('2026-04-20'), drums: 52 }],
        } as Transaction,
    ]);
    const [settings, setSettings] = useState<AppSettings>({
        ...baseSettings,
        appDefaults: {
            sandRoundWorkflowById: {},
            sandHomeBatchAllocations: [],
        },
    });
    const e2eDate = normalizeDate('2026-04-22');
    const txFingerprint = useMemo(
        () => getDayTransactionFingerprint(transactions.filter(t => normalizeDate(t.date) === e2eDate)),
        [transactions, e2eDate]
    );

    return (
        <div className="mx-auto max-w-6xl space-y-4 p-4">
            <h1 className="text-xl font-bold">E2E Harness</h1>
            <div className="flex flex-wrap gap-2">
                <button
                    type="button"
                    className="rounded border px-3 py-1"
                    onClick={() => {
                        setTransactions(prev => [
                            ...prev,
                            {
                                id: `manual_${Date.now()}`,
                                date: e2eDate,
                                type: 'Expense',
                                category: 'Fuel',
                                description: 'manual tx',
                                amount: 100,
                            },
                        ]);
                    }}
                >
                    Add Transaction
                </button>
                <button
                    type="button"
                    className="rounded border px-3 py-1"
                    onClick={() => {
                        writeWizardDraftForDate(e2eDate, basePayload, txFingerprint);
                    }}
                >
                    Seed Matching Draft
                </button>
                <button
                    type="button"
                    className="rounded border px-3 py-1"
                    onClick={() => {
                        writeWizardDraftForDate(e2eDate, basePayload, '0:stale');
                    }}
                >
                    Seed Conflict Draft
                </button>
                <button
                    type="button"
                    className="rounded border px-3 py-1"
                    onClick={() => {
                        clearAllWizardDrafts();
                    }}
                >
                    Clear All Drafts
                </button>
            </div>
            <DailyStepRecorder
                employees={[]}
                settings={settings}
                transactions={transactions}
                initialDate={e2eDate}
                initialStep={4}
                onSaveTransaction={(t) => setTransactions(prev => [...prev, t])}
                onDeleteTransaction={(id) => setTransactions(prev => prev.filter(t => t.id !== id))}
                setSettings={setSettings}
            />
            <div className="rounded border p-3">
                <h2 className="mb-2 font-semibold">Data Verification Harness</h2>
                <DataVerificationModule
                    monthOverviewMode={false}
                    transactions={transactions}
                    settings={settings}
                    setSettings={setSettings}
                    currentAdmin={{ id: 'admin1', username: 'admin', password: '', displayName: 'Admin', role: 'SuperAdmin', createdAt: '2026-01-01' }}
                />
            </div>
        </div>
    );
}
