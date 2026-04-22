import { useMemo, useState } from 'react';
import DailyStepRecorder from '../modules/Dashboard/DailyStepRecorder';
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
    const [transactions, setTransactions] = useState<Transaction[]>([]);
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
                settings={baseSettings}
                transactions={transactions}
                initialDate={e2eDate}
                initialStep={1}
                onSaveTransaction={(t) => setTransactions(prev => [...prev, t])}
                onDeleteTransaction={(id) => setTransactions(prev => prev.filter(t => t.id !== id))}
            />
        </div>
    );
}
