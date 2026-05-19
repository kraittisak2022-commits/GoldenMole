import { useState } from 'react';
import DailyStepRecorder from '../modules/Dashboard/DailyStepRecorder';
import DataVerificationModule from '../modules/DataQuality/DataVerificationModule';
import { AppSettings, Transaction } from '../types';
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
