import { Transaction, WorkType } from '../../types';

export const WIZARD_DRAFT_STORAGE_KEY = 'cm_daily_wizard_draft_v2';
export const WIZARD_DRAFT_SCHEMA_VERSION = 2;
const MAX_DRAFT_DAYS = 12;

export type WizardDraftPayload = {
    step: number;
    laborSearch: string;
    selectedEmps: string[];
    laborStatus: 'Work' | 'OT' | 'Leave';
    halfDayEmpIds: string[];
    drumsWashedAtHome: string;
    otHours: string;
    otDesc: string;
    otRate: string;
    workAssignments: Record<string, string[]>;
    customCategories: Array<{ id: string; label: string }>;
    newCategoryName: string;
    vehCar: string;
    vehDriver: string;
    vehWage: string;
    vehMachineWage: string;
    vehDetails: string;
    vehWorkType: WorkType;
    editingVehicleTxId: string | null;
    tripEntries: Array<{ id: string; vehicle: string; driver: string; work: string; cubicPerTrip: string }>;
    tripMorning: string;
    tripAfternoon: string;
    sand1Morning: string;
    sand1Afternoon: string;
    sand2Morning: string;
    sand2Afternoon: string;
    sand1Operators: string[];
    sand2Operators: string[];
    sandDrumsObtained: string;
    sandMorningStart: string;
    sandAfternoonStart: string;
    sandEveningEnd: string;
    fuelAmount: string;
    fuelLiters: string;
    fuelType: string;
    fuelUnit: string;
    fuelDetails: string;
    fuelVehicle: string;
    fuelVehicleLiters: string;
    fuelVehicleType: 'Diesel' | 'Benzine';
    fuelVehicleDetails: string;
    incomeType: string;
    incomeQty: string;
    incomeUnitPrice: string;
    incomeTotal: string;
    newIncomeType: string;
    incomeTypeAddOpen: boolean;
    eventDesc: string;
    eventType: string;
    eventPriority: string;
};

export type WizardDraftEntry = {
    schemaVersion: number;
    savedAt: number;
    txFingerprint: string;
    payload: WizardDraftPayload;
};

type WizardDraftStore = { v: 2; byDate: Record<string, WizardDraftEntry> };

const isStr = (v: unknown): v is string => typeof v === 'string';
const strOr = (v: unknown, fallback = '') => (isStr(v) ? v : fallback);
const strArr = (v: unknown): string[] => (Array.isArray(v) ? v.filter(isStr) : []);
const boolOr = (v: unknown, fallback = false) => (typeof v === 'boolean' ? v : fallback);
const isRecord = (v: unknown): v is Record<string, unknown> => !!v && typeof v === 'object' && !Array.isArray(v);

function sanitizeWorkAssignments(raw: unknown): Record<string, string[]> {
    if (!isRecord(raw)) return {};
    const out: Record<string, string[]> = {};
    Object.entries(raw).forEach(([k, v]) => {
        if (isStr(k) && Array.isArray(v)) out[k] = v.filter(isStr);
    });
    return out;
}

function sanitizeTripEntries(raw: unknown): WizardDraftPayload['tripEntries'] {
    if (!Array.isArray(raw)) return [];
    return raw
        .filter(isRecord)
        .map(v => ({
            id: strOr(v.id, `${Date.now()}_${Math.random().toString(36).slice(2, 6)}`),
            vehicle: strOr(v.vehicle),
            driver: strOr(v.driver),
            work: strOr(v.work),
            cubicPerTrip: strOr(v.cubicPerTrip),
        }));
}

function sanitizeCustomCategories(raw: unknown): Array<{ id: string; label: string }> {
    if (!Array.isArray(raw)) return [];
    return raw
        .filter(isRecord)
        .map(v => ({ id: strOr(v.id), label: strOr(v.label) }))
        .filter(v => !!v.id && !!v.label);
}

function normalizePayload(raw: unknown): WizardDraftPayload | null {
    if (!isRecord(raw)) return null;
    return {
        step: Number(raw.step) || 0,
        laborSearch: strOr(raw.laborSearch),
        selectedEmps: strArr(raw.selectedEmps),
        laborStatus: raw.laborStatus === 'OT' || raw.laborStatus === 'Leave' ? raw.laborStatus : 'Work',
        halfDayEmpIds: strArr(raw.halfDayEmpIds),
        drumsWashedAtHome: strOr(raw.drumsWashedAtHome),
        otHours: strOr(raw.otHours),
        otDesc: strOr(raw.otDesc),
        otRate: strOr(raw.otRate),
        workAssignments: sanitizeWorkAssignments(raw.workAssignments),
        customCategories: sanitizeCustomCategories(raw.customCategories),
        newCategoryName: strOr(raw.newCategoryName),
        vehCar: strOr(raw.vehCar),
        vehDriver: strOr(raw.vehDriver),
        vehWage: strOr(raw.vehWage),
        vehMachineWage: strOr(raw.vehMachineWage),
        vehDetails: strOr(raw.vehDetails),
        vehWorkType: raw.vehWorkType === 'HalfDay' ? 'HalfDay' : 'FullDay',
        editingVehicleTxId: isStr(raw.editingVehicleTxId) ? raw.editingVehicleTxId : null,
        tripEntries: sanitizeTripEntries(raw.tripEntries),
        tripMorning: strOr(raw.tripMorning),
        tripAfternoon: strOr(raw.tripAfternoon),
        sand1Morning: strOr(raw.sand1Morning),
        sand1Afternoon: strOr(raw.sand1Afternoon),
        sand2Morning: strOr(raw.sand2Morning),
        sand2Afternoon: strOr(raw.sand2Afternoon),
        sand1Operators: strArr(raw.sand1Operators),
        sand2Operators: strArr(raw.sand2Operators),
        sandDrumsObtained: strOr(raw.sandDrumsObtained),
        sandMorningStart: strOr(raw.sandMorningStart),
        sandAfternoonStart: strOr(raw.sandAfternoonStart),
        sandEveningEnd: strOr(raw.sandEveningEnd),
        fuelAmount: strOr(raw.fuelAmount),
        fuelLiters: strOr(raw.fuelLiters),
        fuelType: strOr(raw.fuelType, 'Diesel'),
        fuelUnit: strOr(raw.fuelUnit, 'ลิตร'),
        fuelDetails: strOr(raw.fuelDetails),
        fuelVehicle: strOr(raw.fuelVehicle),
        fuelVehicleLiters: strOr(raw.fuelVehicleLiters),
        fuelVehicleType: raw.fuelVehicleType === 'Benzine' ? 'Benzine' : 'Diesel',
        fuelVehicleDetails: strOr(raw.fuelVehicleDetails),
        incomeType: strOr(raw.incomeType),
        incomeQty: strOr(raw.incomeQty),
        incomeUnitPrice: strOr(raw.incomeUnitPrice),
        incomeTotal: strOr(raw.incomeTotal),
        newIncomeType: strOr(raw.newIncomeType),
        incomeTypeAddOpen: boolOr(raw.incomeTypeAddOpen),
        eventDesc: strOr(raw.eventDesc),
        eventType: strOr(raw.eventType, 'info'),
        eventPriority: strOr(raw.eventPriority, 'normal'),
    };
}

function readDraftStore(): WizardDraftStore {
    if (typeof localStorage === 'undefined') return { v: 2, byDate: {} };
    try {
        const raw = localStorage.getItem(WIZARD_DRAFT_STORAGE_KEY);
        if (!raw) return { v: 2, byDate: {} };
        const parsed = JSON.parse(raw) as { v?: number; byDate?: Record<string, unknown> };
        if (parsed.v !== 2 || !parsed.byDate || typeof parsed.byDate !== 'object') return { v: 2, byDate: {} };
        const byDate: Record<string, WizardDraftEntry> = {};
        Object.entries(parsed.byDate).forEach(([date, entryRaw]) => {
            if (!isRecord(entryRaw)) return;
            const payload = normalizePayload(entryRaw.payload);
            if (!payload) return;
            byDate[date] = {
                schemaVersion: Number(entryRaw.schemaVersion) || WIZARD_DRAFT_SCHEMA_VERSION,
                savedAt: Number(entryRaw.savedAt) || Date.now(),
                txFingerprint: strOr(entryRaw.txFingerprint),
                payload,
            };
        });
        return { v: 2, byDate };
    } catch {
        return { v: 2, byDate: {} };
    }
}

function saveDraftStore(store: WizardDraftStore): boolean {
    if (typeof localStorage === 'undefined') return false;
    try {
        localStorage.setItem(WIZARD_DRAFT_STORAGE_KEY, JSON.stringify(store));
        return true;
    } catch {
        return false;
    }
}

export function getDayTransactionFingerprint(txs: Transaction[]): string {
    const normalized = [...txs]
        .map(t => `${t.id}|${t.category}|${t.subCategory || ''}|${t.amount || 0}|${t.description || ''}`)
        .sort()
        .join('\n');
    return `${txs.length}:${normalized}`;
}

export function readWizardDraftEntry(dateStr: string): WizardDraftEntry | null {
    const store = readDraftStore();
    return store.byDate[dateStr] || null;
}

export function writeWizardDraftForDate(dateStr: string, payload: WizardDraftPayload, txFingerprint: string): boolean {
    const store = readDraftStore();
    store.byDate[dateStr] = {
        schemaVersion: WIZARD_DRAFT_SCHEMA_VERSION,
        savedAt: Date.now(),
        txFingerprint,
        payload,
    };
    const keys = Object.keys(store.byDate).sort((a, b) => store.byDate[b].savedAt - store.byDate[a].savedAt);
    for (let i = MAX_DRAFT_DAYS; i < keys.length; i += 1) delete store.byDate[keys[i]];
    return saveDraftStore(store);
}

export function clearWizardDraftForDate(dateStr: string): boolean {
    const store = readDraftStore();
    delete store.byDate[dateStr];
    return saveDraftStore(store);
}
