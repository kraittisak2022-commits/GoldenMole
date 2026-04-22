import {
    clearWizardDraftForDate,
    getDayTransactionFingerprint,
    readWizardDraftEntry,
    writeWizardDraftForDate,
    WizardDraftPayload,
    WIZARD_DRAFT_STORAGE_KEY,
} from './wizardDraftUtils';

const basePayload: WizardDraftPayload = {
    step: 3,
    laborSearch: '',
    selectedEmps: ['emp-1'],
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

describe('wizardDraftUtils', () => {
    beforeEach(() => {
        localStorage.clear();
    });

    it('restores a valid draft after write (refresh scenario)', () => {
        const ok = writeWizardDraftForDate('2026-04-22', basePayload, 'fp-1');
        expect(ok).toBe(true);

        const restored = readWizardDraftEntry('2026-04-22');
        expect(restored).not.toBeNull();
        expect(restored?.payload.step).toBe(3);
        expect(restored?.txFingerprint).toBe('fp-1');
    });

    it('clears draft after flow completion', () => {
        writeWizardDraftForDate('2026-04-22', basePayload, 'fp-2');
        const cleared = clearWizardDraftForDate('2026-04-22');
        expect(cleared).toBe(true);
        expect(readWizardDraftEntry('2026-04-22')).toBeNull();
    });

    it('validates and sanitizes legacy/corrupted payload fields', () => {
        localStorage.setItem(
            WIZARD_DRAFT_STORAGE_KEY,
            JSON.stringify({
                v: 2,
                byDate: {
                    '2026-04-22': {
                        schemaVersion: 2,
                        savedAt: Date.now(),
                        txFingerprint: 'fp-3',
                        payload: {
                            ...basePayload,
                            laborStatus: 'INVALID',
                            tripEntries: [{ id: 7, vehicle: 'A', driver: null, work: 'x', cubicPerTrip: 4 }],
                        },
                    },
                },
            })
        );

        const restored = readWizardDraftEntry('2026-04-22');
        expect(restored?.payload.laborStatus).toBe('Work');
        expect(restored?.payload.tripEntries[0].id).toBeTruthy();
        expect(restored?.payload.tripEntries[0].driver).toBe('');
    });

    it('produces fingerprint sensitive to transaction changes', () => {
        const a = getDayTransactionFingerprint([
            { id: '1', date: '2026-04-22', type: 'Expense', category: 'Fuel', description: 'A', amount: 100 },
        ]);
        const b = getDayTransactionFingerprint([
            { id: '1', date: '2026-04-22', type: 'Expense', category: 'Fuel', description: 'A', amount: 101 },
        ]);
        expect(a).not.toEqual(b);
    });
});
