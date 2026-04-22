import { memo, useState, useMemo, useEffect, useCallback, useRef } from 'react';
import { Calendar, Users, Truck, Fuel, CheckCircle2, ChevronRight, FileText, Plus, Trash2, Droplets, AlertTriangle, ClipboardList, Pencil, Wallet } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import DatePicker from '../../components/ui/DatePicker';
import NumberPickerInput from '../../components/ui/NumberPickerInput';
import Select from '../../components/ui/Select';
import { getToday, formatDateBE, normalizeDate } from '../../utils';
import { toDailyWage } from '../../utils/laborWage';
import { Employee, Transaction, AppSettings, WorkType } from '../../types';
import { useSessionDialog } from '../../context/useSessionDialog';
import {
    DraftSaveError,
    WizardDraftPayload,
    WIZARD_DRAFT_STORAGE_KEY,
    clearAllWizardDrafts,
    clearWizardDraftForDate,
    getDayTransactionFingerprint,
    parseTxFingerprintCount,
    readWizardDraftEntry,
    writeWizardDraftForDate,
} from './wizardDraftUtils';

type DraftMergeSection = 'labor' | 'vehicle' | 'trip' | 'sand' | 'fuel' | 'income' | 'event';
const ALL_DRAFT_MERGE_SECTIONS: DraftMergeSection[] = ['labor', 'vehicle', 'trip', 'sand', 'fuel', 'income', 'event'];

interface DailyStepRecorderProps {
    employees: Employee[];
    settings: AppSettings;
    transactions: Transaction[];
    /** วันที่ที่ต้องการให้เปิดหน้า Daily Wizard ทันที (จากเมนูตรวจสอบ) */
    initialDate?: string;
    /** step ที่ต้องการเปิดทันที (จากเมนูตรวจสอบ) */
    initialStep?: number;
    dateFilter?: { start: string; end: string };
    onSaveTransaction: (t: Transaction) => void;
    onDeleteTransaction?: (id: string) => void;
    ensureEmployeeWage?: (emp: Employee) => Promise<number>;
    setSettings?: (updater: AppSettings | ((prev: AppSettings) => AppSettings)) => void;
    /** โหมดเว็บมือถือ: ลดรายละเอียด ซ่อนคอลัมน์สรุปขวาและแท็บรายงาน */
    mobileShell?: boolean;
    /** โหมดสัมผัสสำหรับแท็บเล็ต/ไฮบริด */
    touchLayout?: boolean;
    /** ความหนาแน่นหน้าจอสำหรับ mobile shell */
    densityMode?: 'comfortable' | 'compact';
}

const EmployeeSelectChip = memo(function EmployeeSelectChip({
    label,
    selected,
    touchUI,
    onClick,
}: {
    label: string;
    selected: boolean;
    touchUI: boolean;
    onClick: () => void;
}) {
    return (
        <button
            type="button"
            onClick={onClick}
            className={`rounded-xl text-left font-medium transition-all border-2 touch-manipulation ${touchUI ? 'min-h-[48px] px-3 py-3 text-base' : 'px-3 py-2.5 text-sm'} ${selected ? 'border-slate-800 dark:border-slate-300 bg-slate-50 dark:bg-white/10 text-slate-800 dark:text-slate-100' : 'border-slate-200 dark:border-white/10 bg-white dark:bg-white/5 text-slate-500 dark:text-slate-400 hover:border-slate-300 dark:hover:border-white/20'}`}
        >
            {label}
        </button>
    );
});

function useMediaQuery(query: string) {
    const [matches, setMatches] = useState(() => (typeof window !== 'undefined' ? window.matchMedia(query).matches : false));
    useEffect(() => {
        const mq = window.matchMedia(query);
        const onChange = () => setMatches(mq.matches);
        onChange();
        mq.addEventListener('change', onChange);
        return () => mq.removeEventListener('change', onChange);
    }, [query]);
    return matches;
}

function useDebouncedValue<T>(value: T, delay = 180) {
    const [debounced, setDebounced] = useState(value);
    useEffect(() => {
        const timer = window.setTimeout(() => setDebounced(value), delay);
        return () => window.clearTimeout(timer);
    }, [value, delay]);
    return debounced;
}

const STEPS = [
    { id: 0, label: 'วันที่ทำงาน', shortLabel: 'วันที่', icon: Calendar },
    { id: 1, label: 'ค่าแรง', shortLabel: 'ค่าแรง', icon: Users },
    { id: 2, label: 'การใช้รถ', shortLabel: 'ใช้รถ', icon: Truck },
    { id: 3, label: 'เที่ยวรถ', shortLabel: 'เที่ยว', icon: Truck },
    { id: 4, label: 'ล้างทราย', shortLabel: 'ทราย', icon: Droplets },
    { id: 5, label: 'น้ำมัน', shortLabel: 'น้ำมัน', icon: Fuel },
    { id: 6, label: 'รายรับ', shortLabel: 'รายรับ', icon: Wallet },
    { id: 7, label: 'เหตุการณ์', shortLabel: 'เหตุการณ์', icon: AlertTriangle },
    { id: 8, label: 'ตรวจสอบ', shortLabel: 'สรุป', icon: CheckCircle2 }
];

// Default work categories for labor canvas
const DEFAULT_WORK_CATEGORIES = [
    { id: 'wash1', label: 'ล้างทราย เครื่องร่อน 1 (เก่า)', color: 'bg-blue-500', bgLight: 'bg-blue-50 border-blue-200' },
    { id: 'wash2', label: 'ล้างทราย เครื่องร่อน 2 (ใหม่)', color: 'bg-cyan-500', bgLight: 'bg-cyan-50 border-cyan-200' },
    { id: 'washHome', label: 'ล้างทรายที่บ้าน', color: 'bg-teal-500', bgLight: 'bg-teal-50 border-teal-200' },
];
const DEFAULT_WORK_CATEGORY_IDS = new Set(DEFAULT_WORK_CATEGORIES.map(c => c.id));
const normalizeCategoryLabel = (label: string) => label.trim().replace(/\s+/g, ' ').toLowerCase();
const HIDDEN_WORK_CATEGORY_IDS = new Set(['other']);
const HIDDEN_WORK_CATEGORY_LABELS = new Set(['ทำอื่นๆ'].map(normalizeCategoryLabel));
const isGeneratedCategoryId = (value: string) => /^c_\d+$/.test((value || '').trim());
const isGeneratedCategoryLabel = (value: string) => isGeneratedCategoryId(value);
const CUSTOM_CATEGORY_STYLES = [
    { color: 'bg-purple-500', bgLight: 'bg-purple-50 border-purple-200' },
    { color: 'bg-fuchsia-500', bgLight: 'bg-fuchsia-50 border-fuchsia-200' },
    { color: 'bg-violet-500', bgLight: 'bg-violet-50 border-violet-200' },
    { color: 'bg-indigo-500', bgLight: 'bg-indigo-50 border-indigo-200' },
    { color: 'bg-pink-500', bgLight: 'bg-pink-50 border-pink-200' },
    { color: 'bg-sky-500', bgLight: 'bg-sky-50 border-sky-200' },
];
const hashString = (value: string) => {
    let h = 0;
    for (let i = 0; i < value.length; i++) h = (h * 31 + value.charCodeAt(i)) >>> 0;
    return h;
};
const getCustomCategoryStyle = (id: string) => CUSTOM_CATEGORY_STYLES[hashString(id) % CUSTOM_CATEGORY_STYLES.length];
const makeStableCustomCategoryId = (label: string) => `cfg_${hashString(normalizeCategoryLabel(label)).toString(36)}`;
const sanitizeWorkAssignments = (raw: Record<string, string[]> | undefined | null) => {
    if (!raw || typeof raw !== 'object') return {};
    return Object.fromEntries(
        Object.entries(raw).filter(([catId]) => !HIDDEN_WORK_CATEGORY_IDS.has(catId))
    );
};
const getEmployeeDisplayName = (emp?: Employee) => {
    if (!emp) return '';
    const nickname = String(emp.nickname || '').trim();
    if (nickname) return nickname;
    const name = String(emp.name || '').trim();
    if (name) return name;
    return `#${emp.id}`;
};
const isEmployeeMatchedBySearch = (emp: Employee, search: string) => {
    const q = search.trim();
    if (!q) return true;
    const nickname = String(emp.nickname || '');
    const name = String(emp.name || '');
    return nickname.includes(q) || name.includes(q) || getEmployeeDisplayName(emp).includes(q);
};
const detectDefaultCubicPerTrip = (vehicleName: string, fallback: number) => {
    const name = (vehicleName || '').toLowerCase().replace(/\s+/g, '');
    if (name.includes('10ล้อ') || name.includes('สิบล้อ')) return 6;
    if (name.includes('6ล้อ') || name.includes('หกล้อ')) return 3;
    return fallback;
};
const buildSmartSuggestions = (rawValues: Array<string | undefined>, limit = 8) => {
    const seen = new Set<string>();
    const cleaned = rawValues
        .map(v => String(v || '').trim())
        .filter(Boolean)
        .filter(v => v.length >= 2);
    const result: string[] = [];
    for (let i = cleaned.length - 1; i >= 0; i -= 1) {
        const value = cleaned[i];
        const key = normalizeCategoryLabel(value);
        if (seen.has(key)) continue;
        seen.add(key);
        result.push(value);
        if (result.length >= limit) break;
    }
    return result;
};

/** ค่าพรีเซ็ตก่อน แล้วต่อด้วยค่าจากประวัติ (ไม่ซ้ำ) */
const mergePresetsWithDedupedHistory = (presets: string[], historyRaw: string[], limit = 14): string[] => {
    const hist = buildSmartSuggestions(historyRaw, limit);
    const seen = new Set<string>();
    const out: string[] = [];
    for (const p of presets) {
        const s = String(p).trim();
        if (!s) continue;
        if (seen.has(s)) continue;
        seen.add(s);
        out.push(s);
    }
    for (const h of hist) {
        if (seen.has(h)) continue;
        seen.add(h);
        out.push(h);
        if (out.length >= limit) break;
    }
    return out;
};

/** แจ้งเตือนเท่านั้น (ไม่บล็อกบันทึก): มีพนักงานในงานล้างทรายที่บ้าน แต่ยังไม่ระบุถังล้างที่บ้าน */
function getWashHomeDrumsMismatchMessage(txs: Transaction[]): string | null {
    const labor = txs.filter(
        t => t.category === 'Labor' && (t.subCategory === 'Attendance' || t.laborStatus === 'Work')
    );
    let washHomeWorkers = 0;
    for (const t of labor) {
        const wa = sanitizeWorkAssignments((t as any).workAssignments);
        const homeIds = wa['washHome'];
        const n = Array.isArray(homeIds) ? homeIds.length : 0;
        washHomeWorkers = Math.max(washHomeWorkers, n);
    }
    const sand = txs.filter(t => t.category === 'DailyLog' && t.subCategory === 'Sand');
    const fromSand = sand.length > 0 ? Math.max(0, ...sand.map(t => Number((t as any).drumsWashedAtHome || 0))) : 0;
    const fromLabor = labor.length > 0 ? Math.max(0, ...labor.map(t => Number((t as any).drumsWashedAtHome || 0))) : 0;
    const homeDrums = Math.max(fromSand, fromLabor);
    if (washHomeWorkers >= 1 && homeDrums <= 0) {
        return `มีพนักงานในประเภทงาน "ล้างทรายที่บ้าน" ${washHomeWorkers} คน แต่ยังไม่ระบุจำนวนถังที่ล้างที่บ้านวันนี้ — กรุณาตรวจสอบและกรอกในขั้นล้างทรายหรือบันทึกค่าแรง`;
    }
    return null;
}

const DailyStepRecorder = ({ employees, settings, transactions, initialDate, initialStep, dateFilter, onSaveTransaction, onDeleteTransaction, ensureEmployeeWage, setSettings, mobileShell = false, touchLayout = false, densityMode = 'comfortable' }: DailyStepRecorderProps) => {
    const { alert: sessionAlert, confirm: sessionConfirm } = useSessionDialog();
    const isTouchLayout = useMediaQuery('(max-width: 1023px)');
    /** จอสัมผัส / มือถือ: ปุ่มและช่องกดใหญ่ขึ้น */
    const touchUI = mobileShell || touchLayout || isTouchLayout;
    const isCompactDensity = mobileShell && densityMode === 'compact';
    const navBtnClass = touchUI ? 'min-h-[48px] px-5 text-base font-semibold touch-manipulation focus-ring-strong' : 'focus-ring-strong';
    const stepActionWrapClass = mobileShell
        ? 'sticky bottom-[calc(0.4rem+env(safe-area-inset-bottom,0px))] z-[5] mt-auto flex justify-between gap-3 rounded-2xl border border-slate-200/80 bg-white/95 p-2.5 shadow-sm backdrop-blur dark:border-white/10 dark:bg-slate-900/90'
        : 'mt-auto flex justify-between gap-3 pt-3';
    const [step, setStep] = useState(0);
    const [date, setDate] = useState(() => normalizeDate(initialDate) || getToday());
    const [viewMode, setViewMode] = useState<'record' | 'report'>('record');

    useEffect(() => {
        if (mobileShell) setViewMode('record');
    }, [mobileShell]);
    useEffect(() => {
        const normalized = normalizeDate(initialDate);
        if (!normalized) return;
        setDate(prev => (normalizeDate(prev) === normalized ? prev : normalized));
    }, [initialDate]);
    useEffect(() => {
        if (typeof initialStep !== 'number') return;
        const bounded = Math.max(0, Math.min(initialStep, STEPS.length - 1));
        setStep(prev => (prev === bounded ? prev : bounded));
    }, [initialStep]);
    // ช่วงวันที่สำหรับรายงาน (ใช้ dateFilter เป็นค่าเริ่มต้นถ้ามี)
    const [reportStart, setReportStart] = useState<string>(dateFilter?.start || '');
    const [reportEnd, setReportEnd] = useState<string>(dateFilter?.end || '');

    // Derived: Transactions for the selected date (normalize date so DB ISO string matches YYYY-MM-DD)
    const dayTransactions = useMemo(() => {
        const norm = normalizeDate(date);
        return transactions.filter(t => normalizeDate(t.date) === norm);
    }, [transactions, date]);
    const washHomeDrumsAlertMessage = useMemo(() => getWashHomeDrumsMismatchMessage(dayTransactions), [dayTransactions]);
    const otDescSuggestions = useMemo(() => {
        const fromHistory = transactions
            .filter(t => t.category === 'Labor' && t.subCategory === 'OT')
            .map(t => (t as any).otDescription || t.description);
        return buildSmartSuggestions([...(settings.jobDescriptions || []), ...fromHistory], 10);
    }, [transactions, settings.jobDescriptions]);
    const vehicleDetailSuggestions = useMemo(() => {
        const fromHistory = transactions
            .filter(t => t.category === 'Vehicle')
            .map(t => t.workDetails || t.description);
        return buildSmartSuggestions(fromHistory, 10);
    }, [transactions]);
    const tripWorkSuggestions = useMemo(() => {
        const fromHistory = transactions
            .filter(t => t.category === 'DailyLog' && t.subCategory === 'VehicleTrip')
            .map(t => t.workDetails || t.description);
        return buildSmartSuggestions(fromHistory, 10);
    }, [transactions]);
    const fuelDetailSuggestions = useMemo(() => {
        const fromHistory = transactions
            .filter(t => t.category === 'Fuel')
            .map(t => t.workDetails || t.description);
        return buildSmartSuggestions(fromHistory, 10);
    }, [transactions]);
    const fuelPurchaseAmountTemplates = useMemo(() => {
        const hist = transactions
            .filter(
                t =>
                    t.category === 'Fuel' &&
                    (t.fuelMovement || 'stock_in') === 'stock_in' &&
                    !t.vehicleId &&
                    t.amount != null &&
                    Number(t.amount) > 0
            )
            .map(t => String(Math.round(Number(t.amount))));
        return buildSmartSuggestions(hist, 14);
    }, [transactions]);
    const fuelPurchaseLitersTemplates = useMemo(() => {
        const hist = transactions
            .filter(
                t =>
                    t.category === 'Fuel' &&
                    (t.fuelMovement || 'stock_in') === 'stock_in' &&
                    !t.vehicleId &&
                    t.quantity != null &&
                    Number(t.quantity) > 0
            )
            .map(t => String(Math.round(Number(t.quantity))));
        return buildSmartSuggestions(hist, 12);
    }, [transactions]);
    const fuelVehicleLitersTemplates = useMemo(() => {
        const hist = transactions
            .filter(
                t =>
                    t.category === 'Fuel' &&
                    ((t as any).fuelMovement === 'stock_out' || !!t.vehicleId) &&
                    t.quantity != null &&
                    Number(t.quantity) > 0
            )
            .map(t => String(Math.round(Number(t.quantity))));
        return buildSmartSuggestions(hist, 12);
    }, [transactions]);
    const fuelDetailsQuickChips = useMemo(() => {
        const presets = ['ซื้อที่ปั๊มหน้าแคมป์', 'ขายทราย', 'ขายหิน', 'ขายแร่', 'เพิ่ม'];
        const seen = new Set<string>();
        const out: string[] = [];
        for (const p of presets) {
            const s = p.trim();
            if (!s || seen.has(s)) continue;
            seen.add(s);
            out.push(s);
        }
        for (const s of fuelDetailSuggestions) {
            if (seen.has(s)) continue;
            seen.add(s);
            out.push(s);
            if (out.length >= 18) break;
        }
        return out;
    }, [fuelDetailSuggestions]);
    const eventDescSuggestions = useMemo(() => {
        const fromHistory = transactions
            .filter(t => t.category === 'DailyLog' && t.subCategory === 'Event')
            .map(t => t.description);
        return buildSmartSuggestions(fromHistory, 10);
    }, [transactions]);
    const dayStepStats = useMemo(() => {
        const laborCount = dayTransactions.filter(t => t.category === 'Labor').length;
        const vehicleCount = dayTransactions.filter(t => t.category === 'Vehicle').length;
        const tripCount = dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'VehicleTrip').length;
        const sandCount = dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'Sand').length;
        const fuelCount = dayTransactions.filter(t => t.category === 'Fuel').length;
        const incomeCount = dayTransactions.filter(t => t.category === 'Income' && t.type === 'Income').length;
        const eventCount = dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'Event').length;
        return { laborCount, vehicleCount, tripCount, sandCount, fuelCount, incomeCount, eventCount };
    }, [dayTransactions]);
    const [customCategories, setCustomCategories] = useState<Array<{ id: string; label: string }>>([]);
    const [newCategoryName, setNewCategoryName] = useState('');
    const hasExistingWizardData = useMemo(() => Object.values(dayStepStats).some(count => count > 0), [dayStepStats]);
    const latestLaborAttendance = useMemo(() => {
        const laborAttendance = dayTransactions
            .filter(t => t.category === 'Labor' && t.subCategory === 'Attendance')
            .sort((a, b) => a.id.localeCompare(b.id)) as any[];
        if (laborAttendance.length === 0) return null;
        return laborAttendance[laborAttendance.length - 1];
    }, [dayTransactions]);
    const resumeStep = useMemo(() => {
        if (dayStepStats.eventCount > 0) return 7;
        if (dayStepStats.incomeCount > 0) return 6;
        if (dayStepStats.fuelCount > 0) return 5;
        if (dayStepStats.sandCount > 0) return 4;
        if (dayStepStats.tripCount > 0) return 3;
        if (dayStepStats.vehicleCount > 0) return 2;
        if (dayStepStats.laborCount > 0) return 1;
        return 1;
    }, [dayStepStats]);
    /** จำประเภทงานกำหนดเองจากทุกวัน เพื่อให้วันใหม่แสดงอัตโนมัติ */
    const rememberedCustomCategories = useMemo(() => {
        const customById = new Map<string, { id: string; label: string }>();
        const knownLabelById = new Map<string, string>();
        const seenLabels = new Set<string>();
        const addCategory = (id: string, label: string) => {
            if (!id || !label || DEFAULT_WORK_CATEGORY_IDS.has(id)) return;
            if (HIDDEN_WORK_CATEGORY_IDS.has(id)) return;
            if (isGeneratedCategoryLabel(label)) return;
            const norm = normalizeCategoryLabel(label);
            if (HIDDEN_WORK_CATEGORY_LABELS.has(norm)) return;
            if (!norm || seenLabels.has(norm)) return;
            customById.set(id, { id, label });
            knownLabelById.set(id, label);
            seenLabels.add(norm);
        };
        const configuredFromJobDescriptions = settings.jobDescriptions || [];
        configuredFromJobDescriptions.forEach((label) => {
            const safeLabel = String(label || '').trim();
            if (!safeLabel) return;
            addCategory(makeStableCustomCategoryId(safeLabel), safeLabel);
        });
        const configuredCategories = settings.appDefaults?.laborWorkCategories || [];
        configuredCategories
            .filter((c: any) => c && typeof c.id === 'string' && typeof c.label === 'string')
            .forEach((c: any) => addCategory(c.id, c.label));
        const laborAttendance = transactions.filter(t => t.category === 'Labor' && t.subCategory === 'Attendance') as any[];

        laborAttendance.forEach((tx) => {
            if (Array.isArray(tx.customWorkCategories)) {
                tx.customWorkCategories
                    .filter((c: any) => c && typeof c.id === 'string' && typeof c.label === 'string')
                    .forEach((c: any) => addCategory(c.id, c.label));
            }
        });

        laborAttendance.forEach((tx) => {
            if (tx.workAssignments && typeof tx.workAssignments === 'object') {
                Object.keys(tx.workAssignments)
                    .filter(catId => !DEFAULT_WORK_CATEGORY_IDS.has(catId))
                    .forEach((catId) => {
                        const knownLabel = knownLabelById.get(catId);
                        if (knownLabel) {
                            addCategory(catId, knownLabel);
                            return;
                        }
                        // orphan id แบบ c_เวลา ไม่ควรแสดงเป็นชื่อกล่อง
                        if (isGeneratedCategoryId(catId)) return;
                        addCategory(catId, catId);
                    });
            }
        });
        return Array.from(customById.values());
    }, [transactions, settings.appDefaults?.laborWorkCategories, settings.jobDescriptions]);
    const mobileLaborCanvasPreview = useMemo(() => {
        const assignments = latestLaborAttendance?.workAssignments as Record<string, string[]> | undefined;
        if (!assignments || Object.keys(assignments).length === 0) return [];
        const knownLabels = new Map<string, string>();
        DEFAULT_WORK_CATEGORIES.forEach(c => knownLabels.set(c.id, c.label));
        rememberedCustomCategories.forEach(c => knownLabels.set(c.id, c.label));
        const rows = Object.entries(assignments)
            .filter(([catId]) => !HIDDEN_WORK_CATEGORY_IDS.has(catId))
            .filter(([, empIds]) => Array.isArray(empIds) && empIds.length > 0)
            .map(([catId, empIds]) => {
                const label = knownLabels.get(catId) || catId;
                const names = empIds
                    .map(id => getEmployeeDisplayName(employees.find(e => e.id === id)))
                    .filter(Boolean) as string[];
                return { catId, label, names };
            })
            .sort((a, b) => b.names.length - a.names.length);
        return rows;
    }, [latestLaborAttendance, rememberedCustomCategories, employees]);
    const hasLaborAttendanceToday = dayTransactions.some(t => t.category === 'Labor' && t.subCategory === 'Attendance');
    const addOrSelectCustomCategory = useCallback((rawLabel: string) => {
        const label = rawLabel.trim();
        if (!label) return;
        const target = normalizeCategoryLabel(label);
        setCustomCategories(prev => {
            const exists = prev.some(c => normalizeCategoryLabel(c.label) === target);
            if (exists) return prev;
            const configured = (settings.appDefaults?.laborWorkCategories || []).find(c => normalizeCategoryLabel(c.label) === target);
            const id = configured?.id || makeStableCustomCategoryId(label);
            return [...prev, { id, label }];
        });
        setNewCategoryName('');
    }, [settings.appDefaults?.laborWorkCategories]);
    const settingJobDescriptionSuggestions = useMemo(() => {
        const existingLabels = new Set(customCategories.map(c => normalizeCategoryLabel(c.label)));
        const defaultLabels = new Set(DEFAULT_WORK_CATEGORIES.map(c => normalizeCategoryLabel(c.label)));
        return (settings.jobDescriptions || [])
            .map(v => String(v || '').trim())
            .filter(Boolean)
            .filter(v => !defaultLabels.has(normalizeCategoryLabel(v)))
            .filter(v => !existingLabels.has(normalizeCategoryLabel(v)));
    }, [settings.jobDescriptions, customCategories]);

    /** สรุปวันนี้ (คอลัมน์ขวา) — คำนวณครั้งเดียว */
    const atAGlanceStats = useMemo(() => {
        const laborCount = dayTransactions
            .filter(t => t.category === 'Labor' && t.laborStatus === 'Work')
            .reduce((acc, t) => acc + (t.employeeIds?.length || 0), 0);
        const sandCubic = dayTransactions
            .filter(t => t.category === 'DailyLog' && t.subCategory === 'Sand')
            .reduce((acc, t) => acc + (t.sandMorning || 0) + (t.sandAfternoon || 0), 0);
        const vehicleOrDailyCount = dayTransactions.filter(t => t.category === 'Vehicle' || t.category === 'DailyLog').length;
        const fuelBaht = dayTransactions.filter(t => t.category === 'Fuel').reduce((acc, t) => acc + (t.amount || 0), 0);
        return { laborCount, sandCubic, vehicleOrDailyCount, fuelBaht };
    }, [dayTransactions]);
    const duplicateTxMeta = useMemo(() => {
        const signatureToIds = new Map<string, string[]>();
        const makeSig = (t: Transaction) => [
            t.category || '',
            t.subCategory || '',
            String(t.amount || 0),
            (t.description || '').trim().toLowerCase(),
            t.vehicleId || '',
            t.driverId || '',
            t.employeeId || '',
            (t.employeeIds || []).slice().sort().join(','),
            String((t as any).tripMorning || 0),
            String((t as any).tripAfternoon || 0),
            String((t as any).drumsObtained || 0),
            String((t as any).drumsWashedAtHome || 0),
        ].join('|');
        dayTransactions.forEach((t) => {
            const sig = makeSig(t);
            const prev = signatureToIds.get(sig) || [];
            prev.push(t.id);
            signatureToIds.set(sig, prev);
        });
        const duplicateIds = new Set<string>();
        let groups = 0;
        signatureToIds.forEach((ids) => {
            if (ids.length > 1) {
                groups += 1;
                ids.forEach((id) => duplicateIds.add(id));
            }
        });
        return { duplicateIds, groups, count: duplicateIds.size };
    }, [dayTransactions]);
    const shouldContinueWithWarning = useCallback(
        async (messages: string[], title = 'พบข้อมูลที่อาจซ้ำหรือผิดปกติ') => {
            if (messages.length === 0) return true;
            const text = `- ${messages.join('\n- ')}\n\nต้องการบันทึกต่อหรือไม่?`;
            return sessionConfirm(text, { title });
        },
        [sessionConfirm]
    );

    const getEmpPositions = (e: Employee) => e.positions ?? (e.position ? [e.position] : []);
    const driverEmployees = useMemo(() => employees.filter(e => getEmpPositions(e).includes('คนขับรถ')), [employees]);

    const vehicleMachineWageTemplates = useMemo(() => {
        const hist = transactions
            .filter(t => t.category === 'Vehicle' && (t as any).vehicleWage != null && Number((t as any).vehicleWage) > 0)
            .map(t => String(Math.round(Number((t as any).vehicleWage))));
        return mergePresetsWithDedupedHistory(['3000', '4500'], hist, 14);
    }, [transactions]);
    const vehicleDriverWageTemplates = useMemo(() => {
        const hist = transactions
            .filter(t => t.category === 'Vehicle' && (t as any).driverWage != null && Number((t as any).driverWage) > 0)
            .map(t => String(Math.round(Number((t as any).driverWage))));
        return mergePresetsWithDedupedHistory(['200', '600', '800'], hist, 14);
    }, [transactions]);
    // Labor State
    const [laborSearch, setLaborSearch] = useState('');
    const debouncedLaborSearch = useDebouncedValue(laborSearch, 220);
    const [otVisibleEmployeeCount, setOtVisibleEmployeeCount] = useState(48);
    const [poolVisibleEmployeeCount, setPoolVisibleEmployeeCount] = useState(60);
    const [selectedEmps, setSelectedEmps] = useState<string[]>([]);
    const [laborStatus, setLaborStatus] = useState<'Work' | 'OT' | 'Leave'>('Work');
    /** รายคน: เฉพาะคนที่มาครึ่งวัน (ไม่มีในนี้ = เต็มวันปกติ) */
    const [halfDayEmpIds, setHalfDayEmpIds] = useState<Set<string>>(new Set());
    /** จำนวนถังที่ล้างที่บ้านวันนี้ (แสดงเมื่อมีพนักงานในประเภท ล้างทรายที่บ้าน) */
    const [drumsWashedAtHome, setDrumsWashedAtHome] = useState('');
    const [otHours, setOtHours] = useState('');
    const [otDesc, setOtDesc] = useState('');
    const [otRate, setOtRate] = useState('');
    // Canvas-style work category assignments: { categoryId: employeeId[] }
    const [workAssignments, setWorkAssignments] = useState<Record<string, string[]>>({});
    const [dragEmployee, setDragEmployee] = useState<string | null>(null);
    const filteredLaborEmployees = useMemo(
        () => employees.filter(e => isEmployeeMatchedBySearch(e, debouncedLaborSearch)),
        [employees, debouncedLaborSearch]
    );
    const otVisibleEmployees = useMemo(
        () => filteredLaborEmployees.slice(0, otVisibleEmployeeCount),
        [filteredLaborEmployees, otVisibleEmployeeCount]
    );
    const poolVisibleEmployees = useMemo(
        () => filteredLaborEmployees.slice(0, poolVisibleEmployeeCount),
        [filteredLaborEmployees, poolVisibleEmployeeCount]
    );
    const latestLaborDrumsWashedAtHome = useMemo(() => {
        if (!latestLaborAttendance) return 0;
        return Number((latestLaborAttendance as any).drumsWashedAtHome || 0);
    }, [latestLaborAttendance]);

    // Vehicle State
    const [vehCar, setVehCar] = useState('');
    const [vehDriver, setVehDriver] = useState('');
    const [vehWage, setVehWage] = useState('');
    const [vehMachineWage, setVehMachineWage] = useState('');
    const [vehDetails, setVehDetails] = useState('');
    const [vehWorkType, setVehWorkType] = useState<WorkType>('FullDay');
    const [vehLocation] = useState(settings.locations[0] || '');
    const [editingVehicleTxId, setEditingVehicleTxId] = useState<string | null>(null);

    const applyVehicleDriverAllowance = async (driverId: string, workType: WorkType) => {
        if (!driverId) {
            setVehWage('');
            return;
        }
        const emp = employees.find(x => x.id === driverId);
        if (!emp) return;
        let daily = 0;
        try {
            if (ensureEmployeeWage) {
                const w = await ensureEmployeeWage(emp);
                daily = toDailyWage(emp, w);
            } else if (emp.baseWage != null) {
                daily = toDailyWage(emp, emp.baseWage);
            }
        } catch {
            return;
        }
        if (workType === 'HalfDay') daily /= 2;
        setVehWage(String(daily));
    };

    const loadVehicleForEdit = useCallback((t: Transaction) => {
        const x = t as any;
        setEditingVehicleTxId(t.id);
        setVehCar(t.vehicleId || '');
        setVehDriver(t.driverId || '');
        setVehMachineWage(t.vehicleWage != null ? String(t.vehicleWage) : '');
        setVehWage(t.driverWage != null ? String(t.driverWage) : '');
        setVehDetails(t.workDetails || '');
        setVehWorkType(x.workType === 'HalfDay' ? 'HalfDay' : 'FullDay');
    }, []);

    useEffect(() => {
        setEditingVehicleTxId(null);
    }, [date]);

    // Daily Log State (Vehicle Trips - Multi-card Canvas)
    const [tripEntries, setTripEntries] = useState<Array<{ id: string; vehicle: string; driver: string; work: string; cubicPerTrip: string }>>([
        { id: Date.now().toString(), vehicle: '', driver: '', work: '', cubicPerTrip: '' }
    ]);
    const [tripMorning, setTripMorning] = useState('');
    const [tripAfternoon, setTripAfternoon] = useState('');
    const totalTrips = (Number(tripMorning) || 0) + (Number(tripAfternoon) || 0);
    const addTripCard = () => setTripEntries(prev => [...prev, { id: Date.now().toString(), vehicle: '', driver: '', work: '', cubicPerTrip: '' }]);
    const removeTripCard = (id: string) => setTripEntries(prev => prev.length > 1 ? prev.filter(e => e.id !== id) : prev);
    const updateTripCard = (id: string, field: string, value: string) => setTripEntries(prev => prev.map(e => e.id === id ? { ...e, [field]: value } : e));

    // Sand Washing State
    const [sand1Morning, setSand1Morning] = useState('');
    const [sand1Afternoon, setSand1Afternoon] = useState('');
    const [sand2Morning, setSand2Morning] = useState('');
    const [sand2Afternoon, setSand2Afternoon] = useState('');
    const [sand1Operators, setSand1Operators] = useState<string[]>([]);
    const [sand2Operators, setSand2Operators] = useState<string[]>([]);
    const [sandDrumsObtained, setSandDrumsObtained] = useState('');
    const [sandMorningStart, setSandMorningStart] = useState('');
    const [sandAfternoonStart, setSandAfternoonStart] = useState('');
    const [sandEveningEnd, setSandEveningEnd] = useState('');
    const drumStockSummary = useMemo(() => {
        const selectedDate = normalizeDate(date);
        const perDay = new Map<string, { obtained: number; home: number }>();
        transactions
            .filter(t => t.category === 'DailyLog' && t.subCategory === 'Sand')
            .forEach((t) => {
                const d = normalizeDate(t.date);
                const prev = perDay.get(d) || { obtained: 0, home: 0 };
                const obtained = Math.max(prev.obtained, Number((t as any).drumsObtained || 0));
                const home = Math.max(prev.home, Number((t as any).drumsWashedAtHome || 0));
                perDay.set(d, { obtained, home });
            });

        const cumulativeBeforeToday = Array.from(perDay.entries())
            .filter(([d]) => d < selectedDate)
            .sort(([a], [b]) => a.localeCompare(b))
            .reduce((sum, [, v]) => sum + Math.max(0, v.obtained - v.home), 0);

        const savedToday = perDay.get(selectedDate) || { obtained: 0, home: 0 };
        const todayObtained = String(sandDrumsObtained).trim() === '' ? savedToday.obtained : (Number(sandDrumsObtained) || 0);
        const todayHome = String(drumsWashedAtHome).trim() === '' ? savedToday.home : (Number(drumsWashedAtHome) || 0);
        const todayNet = Math.max(0, todayObtained - todayHome);
        const cumulativeRemaining = cumulativeBeforeToday + todayNet;

        return { cumulativeBeforeToday, todayObtained, todayHome, todayNet, cumulativeRemaining };
    }, [transactions, date, sandDrumsObtained, drumsWashedAtHome]);
    const sand1Total = (Number(sand1Morning) || 0) + (Number(sand1Afternoon) || 0);
    const sand2Total = (Number(sand2Morning) || 0) + (Number(sand2Afternoon) || 0);
    const sandGrandTotal = sand1Total + sand2Total;

    // Fuel State
    const [fuelAmount, setFuelAmount] = useState('');
    const [fuelLiters, setFuelLiters] = useState('');
    const [fuelType, setFuelType] = useState<any>('Diesel');
    const [fuelUnit, setFuelUnit] = useState('ลิตร');
    const [fuelDetails, setFuelDetails] = useState('');
    const [fuelVehicle, setFuelVehicle] = useState('');
    const [fuelVehicleLiters, setFuelVehicleLiters] = useState('');
    const [fuelVehicleType, setFuelVehicleType] = useState<'Diesel' | 'Benzine'>('Diesel');
    const [fuelVehicleDetails, setFuelVehicleDetails] = useState('');

    // Income State (Daily Wizard)
    const [incomeType, setIncomeType] = useState('');
    const [incomeQty, setIncomeQty] = useState('');
    const [incomeUnitPrice, setIncomeUnitPrice] = useState('');
    const [incomeTotal, setIncomeTotal] = useState('');
    const [newIncomeType, setNewIncomeType] = useState('');
    const [incomeTypeAddOpen, setIncomeTypeAddOpen] = useState(false);
    const incomeAddInputRef = useRef<HTMLInputElement>(null);
    const handleIncomeCalc = (field: 'qty' | 'price' | 'total', value: string) => {
        if (field === 'qty') {
            setIncomeQty(value);
            setIncomeTotal(String((Number(value) || 0) * (Number(incomeUnitPrice) || 0)));
            return;
        }
        if (field === 'price') {
            setIncomeUnitPrice(value);
            setIncomeTotal(String((Number(incomeQty) || 0) * (Number(value) || 0)));
            return;
        }
        setIncomeTotal(value);
        if ((Number(incomeQty) || 0) > 0) {
            setIncomeUnitPrice(String((Number(value) || 0) / (Number(incomeQty) || 1)));
        }
    };
    const handleAddIncomeType = () => {
        const label = newIncomeType.trim();
        if (!label) return;
        const exists = (settings.incomeTypes || []).some(v => String(v).trim().toLowerCase() === label.toLowerCase());
        if (exists) {
            void sessionAlert('มีประเภทนี้อยู่แล้ว');
            return;
        }
        setSettings?.((prev: AppSettings) => ({
            ...prev,
            incomeTypes: [...(prev.incomeTypes || []), label],
        }));
        setNewIncomeType('');
        setIncomeType(label);
        incomeAddInputRef.current?.focus();
    };
    const handleRemoveIncomeType = (label: string) => {
        setSettings?.((prev: AppSettings) => ({
            ...prev,
            incomeTypes: (prev.incomeTypes || []).filter(v => v !== label),
        }));
        if (incomeType === label) setIncomeType('');
    };

    // Events State
    const [eventDesc, setEventDesc] = useState('');
    const [eventType, setEventType] = useState('info');
    const [eventPriority, setEventPriority] = useState('normal');
    const [expandedRecordId, setExpandedRecordId] = useState<string | null>(null);
    const [draftOffer, setDraftOffer] = useState<{
        payload: WizardDraftPayload;
        savedAt: number;
        hasConflict: boolean;
        conflictDraftTxCount: number;
        conflictCurrentTxCount: number;
    } | null>(null);
    const [autosaveState, setAutosaveState] = useState<'idle' | 'saving' | 'saved' | 'error'>('idle');
    const [autosaveSavedAt, setAutosaveSavedAt] = useState<number | null>(null);
    const [autosaveErrorReason, setAutosaveErrorReason] = useState<DraftSaveError>('none');
    const [draftMergeSections, setDraftMergeSections] = useState<Record<DraftMergeSection, boolean>>({
        labor: true,
        vehicle: true,
        trip: true,
        sand: true,
        fuel: true,
        income: true,
        event: true,
    });

    const applyWizardDraft = useCallback((p: WizardDraftPayload, sections: DraftMergeSection[] = ALL_DRAFT_MERGE_SECTIONS) => {
        const pick = (section: DraftMergeSection) => sections.includes(section);
        setStep(p.step);
        if (pick('labor')) {
            setLaborSearch(p.laborSearch);
            setSelectedEmps(p.selectedEmps);
            setLaborStatus(p.laborStatus);
            setHalfDayEmpIds(new Set(p.halfDayEmpIds));
            setDrumsWashedAtHome(p.drumsWashedAtHome);
            setOtHours(p.otHours);
            setOtDesc(p.otDesc);
            setOtRate(p.otRate);
            setWorkAssignments(p.workAssignments);
            setCustomCategories(p.customCategories);
            setNewCategoryName(p.newCategoryName);
        }
        if (pick('vehicle')) {
            setVehCar(p.vehCar);
            setVehDriver(p.vehDriver);
            setVehWage(p.vehWage);
            setVehMachineWage(p.vehMachineWage);
            setVehDetails(p.vehDetails);
            setVehWorkType(p.vehWorkType);
            setEditingVehicleTxId(p.editingVehicleTxId);
        }
        if (pick('trip')) {
            setTripEntries(p.tripEntries.length > 0 ? p.tripEntries : [{ id: Date.now().toString(), vehicle: '', driver: '', work: '', cubicPerTrip: '' }]);
            setTripMorning(p.tripMorning);
            setTripAfternoon(p.tripAfternoon);
        }
        if (pick('sand')) {
            setSand1Morning(p.sand1Morning);
            setSand1Afternoon(p.sand1Afternoon);
            setSand2Morning(p.sand2Morning);
            setSand2Afternoon(p.sand2Afternoon);
            setSand1Operators(p.sand1Operators);
            setSand2Operators(p.sand2Operators);
            setSandDrumsObtained(p.sandDrumsObtained);
            setSandMorningStart(p.sandMorningStart);
            setSandAfternoonStart(p.sandAfternoonStart);
            setSandEveningEnd(p.sandEveningEnd);
        }
        if (pick('fuel')) {
            setFuelAmount(p.fuelAmount);
            setFuelLiters(p.fuelLiters);
            setFuelType(p.fuelType);
            setFuelUnit(p.fuelUnit);
            setFuelDetails(p.fuelDetails);
            setFuelVehicle(p.fuelVehicle);
            setFuelVehicleLiters(p.fuelVehicleLiters);
            setFuelVehicleType(p.fuelVehicleType);
            setFuelVehicleDetails(p.fuelVehicleDetails);
        }
        if (pick('income')) {
            setIncomeType(p.incomeType);
            setIncomeQty(p.incomeQty);
            setIncomeUnitPrice(p.incomeUnitPrice);
            setIncomeTotal(p.incomeTotal);
            setNewIncomeType(p.newIncomeType);
            setIncomeTypeAddOpen(p.incomeTypeAddOpen);
        }
        if (pick('event')) {
            setEventDesc(p.eventDesc);
            setEventType(p.eventType);
            setEventPriority(p.eventPriority);
        }
    }, []);

    const wizardDraftPayload: WizardDraftPayload = useMemo(
        () => ({
            step,
            laborSearch,
            selectedEmps,
            laborStatus,
            halfDayEmpIds: [...halfDayEmpIds],
            drumsWashedAtHome,
            otHours,
            otDesc,
            otRate,
            workAssignments,
            customCategories,
            newCategoryName,
            vehCar,
            vehDriver,
            vehWage,
            vehMachineWage,
            vehDetails,
            vehWorkType,
            editingVehicleTxId,
            tripEntries,
            tripMorning,
            tripAfternoon,
            sand1Morning,
            sand1Afternoon,
            sand2Morning,
            sand2Afternoon,
            sand1Operators,
            sand2Operators,
            sandDrumsObtained,
            sandMorningStart,
            sandAfternoonStart,
            sandEveningEnd,
            fuelAmount,
            fuelLiters,
            fuelType,
            fuelUnit,
            fuelDetails,
            fuelVehicle,
            fuelVehicleLiters,
            fuelVehicleType,
            fuelVehicleDetails,
            incomeType,
            incomeQty,
            incomeUnitPrice,
            incomeTotal,
            newIncomeType,
            incomeTypeAddOpen,
            eventDesc,
            eventType,
            eventPriority,
        }),
        [
            step,
            laborSearch,
            selectedEmps,
            laborStatus,
            halfDayEmpIds,
            drumsWashedAtHome,
            otHours,
            otDesc,
            otRate,
            workAssignments,
            customCategories,
            newCategoryName,
            vehCar,
            vehDriver,
            vehWage,
            vehMachineWage,
            vehDetails,
            vehWorkType,
            editingVehicleTxId,
            tripEntries,
            tripMorning,
            tripAfternoon,
            sand1Morning,
            sand1Afternoon,
            sand2Morning,
            sand2Afternoon,
            sand1Operators,
            sand2Operators,
            sandDrumsObtained,
            sandMorningStart,
            sandAfternoonStart,
            sandEveningEnd,
            fuelAmount,
            fuelLiters,
            fuelType,
            fuelUnit,
            fuelDetails,
            fuelVehicle,
            fuelVehicleLiters,
            fuelVehicleType,
            fuelVehicleDetails,
            incomeType,
            incomeQty,
            incomeUnitPrice,
            incomeTotal,
            newIncomeType,
            incomeTypeAddOpen,
            eventDesc,
            eventType,
            eventPriority,
        ]
    );

    const dayTxFingerprint = useMemo(() => getDayTransactionFingerprint(dayTransactions), [dayTransactions]);

    const refreshDraftOffer = useCallback(() => {
        const norm = normalizeDate(date);
        if (typeof sessionStorage !== 'undefined' && sessionStorage.getItem(`cm_draft_dismiss_${norm}`)) {
            setDraftOffer(null);
            return false;
        }
        const entry = readWizardDraftEntry(norm);
        if (entry?.payload && entry.payload.step >= 1) {
            const draftCount = parseTxFingerprintCount(entry.txFingerprint);
            const currentCount = dayTransactions.length;
            setDraftOffer({
                payload: entry.payload,
                savedAt: entry.savedAt,
                hasConflict: !!entry.txFingerprint && entry.txFingerprint !== dayTxFingerprint,
                conflictDraftTxCount: draftCount,
                conflictCurrentTxCount: currentCount,
            });
            setDraftMergeSections({
                labor: true,
                vehicle: true,
                trip: true,
                sand: true,
                fuel: true,
                income: true,
                event: true,
            });
            return true;
        } else {
            setDraftOffer(null);
            return false;
        }
    }, [date, dayTxFingerprint, dayTransactions.length]);

    useEffect(() => {
        refreshDraftOffer();
    }, [refreshDraftOffer]);

    useEffect(() => {
        const onStorage = (event: StorageEvent) => {
            if (event.key !== WIZARD_DRAFT_STORAGE_KEY) return;
            const hasDraft = refreshDraftOffer();
            if (hasDraft) {
                const entry = readWizardDraftEntry(normalizeDate(date));
                if (entry?.savedAt) {
                    setAutosaveState('saved');
                    setAutosaveSavedAt(entry.savedAt);
                    setAutosaveErrorReason('none');
                }
            }
        };
        window.addEventListener('storage', onStorage);
        return () => window.removeEventListener('storage', onStorage);
    }, [date, refreshDraftOffer]);

    useEffect(() => {
        if (typeof window === 'undefined') return;
        if (viewMode !== 'record' || step < 1) return;
        const norm = normalizeDate(date);
        setAutosaveState('saving');
        setAutosaveErrorReason('none');
        const tid = window.setTimeout(() => {
            const result = writeWizardDraftForDate(norm, wizardDraftPayload, dayTxFingerprint);
            if (result.ok) {
                setAutosaveState('saved');
                setAutosaveSavedAt(Date.now());
            } else {
                setAutosaveState('error');
                setAutosaveErrorReason(result.reason);
            }
        }, 750);
        return () => window.clearTimeout(tid);
    }, [wizardDraftPayload, date, viewMode, step, dayTxFingerprint]);

    const stepScrollerRef = useRef<HTMLDivElement | null>(null);
    const [canScrollStepLeft, setCanScrollStepLeft] = useState(false);
    const [canScrollStepRight, setCanScrollStepRight] = useState(false);

    const updateStepScrollState = useCallback(() => {
        const el = stepScrollerRef.current;
        if (!el) {
            setCanScrollStepLeft(false);
            setCanScrollStepRight(false);
            return;
        }
        const maxScroll = Math.max(0, el.scrollWidth - el.clientWidth);
        setCanScrollStepLeft(el.scrollLeft > 4);
        setCanScrollStepRight(el.scrollLeft < maxScroll - 4);
    }, []);

    useEffect(() => {
        const el = stepScrollerRef.current;
        if (!el || !mobileShell) return;
        updateStepScrollState();
        const onScroll = () => updateStepScrollState();
        window.addEventListener('resize', onScroll);
        el.addEventListener('scroll', onScroll, { passive: true });
        return () => {
            window.removeEventListener('resize', onScroll);
            el.removeEventListener('scroll', onScroll);
        };
    }, [mobileShell, updateStepScrollState]);

    useEffect(() => {
        if (!mobileShell) return;
        const el = stepScrollerRef.current;
        if (!el) return;
        const activeBtn = el.querySelector<HTMLButtonElement>(`button[data-step="${step}"]`);
        if (activeBtn) activeBtn.scrollIntoView({ behavior: 'smooth', inline: 'center', block: 'nearest' });
        const t = window.setTimeout(updateStepScrollState, 180);
        return () => window.clearTimeout(t);
    }, [step, mobileShell, updateStepScrollState]);

    // Prefill form state เมื่อเลือกวันที่ที่เคยบันทึกแล้ว
    useEffect(() => {
        // Labor Attendance (canvas)
        const laborAttendance = dayTransactions
            .filter(t => t.category === 'Labor' && t.subCategory === 'Attendance')
            .sort((a, b) => a.id.localeCompare(b.id));
        if (laborAttendance.length > 0) {
            const latest = laborAttendance[laborAttendance.length - 1] as any;
            if (latest.workAssignments) {
                setWorkAssignments(sanitizeWorkAssignments(latest.workAssignments));
            } else {
                setWorkAssignments({});
            }
            if (Array.isArray(latest.customWorkCategories)) {
                const seenLabels = new Set<string>();
                setCustomCategories(latest.customWorkCategories
                    .filter((c: any) => c && typeof c.id === 'string' && typeof c.label === 'string')
                    .filter((c: any) => {
                        if (isGeneratedCategoryLabel(c.label)) return false;
                        const norm = normalizeCategoryLabel(c.label);
                        if (!norm || seenLabels.has(norm)) return false;
                        seenLabels.add(norm);
                        return true;
                    })
                );
            } else if (latest.workAssignments) {
                const recoveredCustom = Object.keys(latest.workAssignments)
                    .filter(catId => !DEFAULT_WORK_CATEGORY_IDS.has(catId))
                    .map((catId) => {
                        const remembered = rememberedCustomCategories.find(c => c.id === catId);
                        if (remembered) return remembered;
                        if (isGeneratedCategoryId(catId)) return null;
                        return { id: catId, label: catId };
                    })
                    .filter((c): c is { id: string; label: string } => !!c);
                setCustomCategories(recoveredCustom);
            } else {
                setCustomCategories([]);
            }
            if (latest.workTypeByEmployee) {
                const half = new Set<string>();
                Object.entries(latest.workTypeByEmployee as Record<string, 'FullDay' | 'HalfDay'>).forEach(([id, wt]) => {
                    if (wt === 'HalfDay') half.add(id);
                });
                setHalfDayEmpIds(half);
            } else {
                setHalfDayEmpIds(new Set());
            }
            if (latest.drumsWashedAtHome != null) {
                setDrumsWashedAtHome(String(latest.drumsWashedAtHome));
            } else {
                setDrumsWashedAtHome('');
            }
        } else {
            setWorkAssignments({});
            setCustomCategories(rememberedCustomCategories);
            setHalfDayEmpIds(new Set());
            setDrumsWashedAtHome('');
        }

        // Sand
        const sandTx = dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'Sand') as any[];
        const s1 = sandTx.find(t => t.sandMachineType === 'Old');
        const s2 = sandTx.find(t => t.sandMachineType === 'New');
        if (s1) {
            setSand1Morning(s1.sandMorning != null ? String(s1.sandMorning) : '');
            setSand1Afternoon(s1.sandAfternoon != null ? String(s1.sandAfternoon) : '');
            setSand1Operators(s1.sandOperators || []);
        } else {
            setSand1Morning('');
            setSand1Afternoon('');
            setSand1Operators([]);
        }
        if (s2) {
            setSand2Morning(s2.sandMorning != null ? String(s2.sandMorning) : '');
            setSand2Afternoon(s2.sandAfternoon != null ? String(s2.sandAfternoon) : '');
            setSand2Operators(s2.sandOperators || []);
        } else {
            setSand2Morning('');
            setSand2Afternoon('');
            setSand2Operators([]);
        }
        if (sandTx.length > 0) {
            const drums = Math.max(
                0,
                ...sandTx.map(t => (t.drumsObtained != null ? Number(t.drumsObtained) : 0))
            );
            setSandDrumsObtained(drums > 0 ? String(drums) : '');
            const first = sandTx[0] as any;
            setSandMorningStart(first.sandMorningStart || '');
            setSandAfternoonStart(first.sandAfternoonStart || '');
            setSandEveningEnd(first.sandEveningEnd || '');
        } else {
            setSandDrumsObtained('');
            setSandMorningStart('');
            setSandAfternoonStart('');
            setSandEveningEnd('');
        }

        // Fuel (prefill แยก: ซื้อเข้า / ใช้รายรถ)
        const fuelTx = dayTransactions
            .filter(t => t.category === 'Fuel')
            .sort((a, b) => a.id.localeCompare(b.id));
        const fuelInTx = fuelTx.filter(t => (t.fuelMovement || 'stock_in') === 'stock_in' && !t.vehicleId);
        const fuelOutTx = fuelTx.filter(t => (t.fuelMovement === 'stock_out') || !!t.vehicleId);
        if (fuelInTx.length > 0) {
            const latestFuelIn = fuelInTx[fuelInTx.length - 1] as any;
            setFuelAmount(latestFuelIn.amount != null ? String(latestFuelIn.amount) : '');
            setFuelLiters(latestFuelIn.quantity != null ? String(latestFuelIn.quantity) : '');
            setFuelUnit(latestFuelIn.unit === 'gallon' ? 'แกลลอน' : 'ลิตร');
            setFuelType(latestFuelIn.fuelType || 'Diesel');
            setFuelDetails(latestFuelIn.workDetails || '');
        } else {
            setFuelAmount('');
            setFuelLiters('');
            setFuelUnit('ลิตร');
            setFuelType('Diesel');
            setFuelDetails('');
        }
        if (fuelOutTx.length > 0) {
            const latestFuelOut = fuelOutTx[fuelOutTx.length - 1] as any;
            setFuelVehicle(latestFuelOut.vehicleId || '');
            setFuelVehicleLiters(latestFuelOut.quantity != null ? String(latestFuelOut.quantity) : '');
            setFuelVehicleType(latestFuelOut.fuelType || 'Diesel');
            const wd = String(latestFuelOut.workDetails || '').trim();
            setFuelVehicleDetails(/^\d{1,2}:\d{2}$/.test(wd) ? wd : '');
        } else {
            setFuelVehicle('');
            setFuelVehicleLiters('');
            setFuelVehicleType('Diesel');
            setFuelVehicleDetails('');
        }

        // Vehicle (latest simple entry) — ไม่ทับฟอร์มขณะกำลังแก้ไขรายการจากการ์ด
        if (!editingVehicleTxId) {
            const vehTx = dayTransactions
                .filter(t => t.category === 'Vehicle')
                .sort((a, b) => a.id.localeCompare(b.id));
            if (vehTx.length > 0) {
                const latestVeh = vehTx[vehTx.length - 1] as any;
                setVehCar(latestVeh.vehicleId || '');
                setVehDriver(latestVeh.driverId || '');
                setVehMachineWage(latestVeh.vehicleWage != null ? String(latestVeh.vehicleWage) : '');
                setVehWage(latestVeh.driverWage != null ? String(latestVeh.driverWage) : '');
                setVehDetails(latestVeh.workDetails || '');
                setVehWorkType(latestVeh.workType === 'HalfDay' ? 'HalfDay' : 'FullDay');
            } else {
                setVehCar('');
                setVehDriver('');
                setVehMachineWage('');
                setVehWage('');
                setVehDetails('');
                setVehWorkType('FullDay');
            }
        }
    }, [date, dayTransactions, rememberedCustomCategories, editingVehicleTxId]);

    const nextStep = async () => {
        // กันลืมกดบันทึก: ถ้ายังกด "ถัดไป" โดยไม่มีข้อมูลในแต่ละขั้น ให้เตือนก่อน
        const normDate = normalizeDate(date);
        const todaysTx = transactions.filter(t => normalizeDate(t.date) === normDate);

        // map step -> เงื่อนไขว่ามีข้อมูลแล้วหรือยัง (เฉพาะขั้นหลักที่ต้องมีการบันทึก)
        const stepNeedsData: Record<number, boolean> = {
            1: todaysTx.some(t => t.category === 'Labor'),
            2: todaysTx.some(t => t.category === 'Vehicle'),
            3: todaysTx.some(t => t.category === 'DailyLog' && t.subCategory === 'VehicleTrip'),
            4: todaysTx.some(t => t.category === 'DailyLog' && t.subCategory === 'Sand'),
            5: todaysTx.some(t => t.category === 'Fuel'),
            6: todaysTx.some(t => t.category === 'Income' && t.type === 'Income'),
            7: todaysTx.some(t => t.category === 'DailyLog' && t.subCategory === 'Event'),
        };

        if (stepNeedsData[step] === false) {
            const label = STEPS[step]?.label || '';
            const ok = await sessionConfirm(
                `ยังไม่มีการกดบันทึกในขั้น "${label}" สำหรับวันที่นี้\n\nหากต้องการไปขั้นถัดไปโดยไม่บันทึก ให้กด "ตกลง"`,
                { title: 'ไปขั้นถัดไปโดยไม่บันทึก?' }
            );
            if (!ok) return;
        }

        setStep(s => Math.min(s + 1, STEPS.length - 1));
    };
    const prevStep = () => setStep(s => Math.max(s - 1, 0));
    const handleStartRecord = () => {
        if (hasExistingWizardData) {
            setStep(resumeStep);
            return;
        }
        void nextStep();
    };
    const handleOpenLaborStep = () => {
        setLaborStatus('Work');
        setStep(1);
    };
    const handleCopyFromYesterday = async () => {
        const todayNorm = normalizeDate(date);
        const yesterday = new Date(`${todayNorm}T00:00:00`);
        yesterday.setDate(yesterday.getDate() - 1);
        const ymd = yesterday.toISOString().slice(0, 10);
        const fromYesterday = transactions.filter(t => normalizeDate(t.date) === ymd && t.category !== 'Payroll' && t.category !== 'PayrollUnlock');
        if (fromYesterday.length === 0) {
            await sessionAlert('ไม่พบข้อมูลเมื่อวานสำหรับคัดลอก');
            return;
        }
        const ok = await sessionConfirm(`พบข้อมูลเมื่อวาน ${fromYesterday.length} รายการ ต้องการคัดลอกมาวันนี้หรือไม่?`, { title: 'คัดลอกจากเมื่อวาน' });
        if (!ok) return;
        fromYesterday.slice(0, 50).forEach((tx, idx) => {
            onSaveTransaction({
                ...tx,
                id: `${Date.now()}_cpy_${idx}`,
                date: todayNorm,
            });
        });
        await sessionAlert(`คัดลอกสำเร็จ ${Math.min(fromYesterday.length, 50)} รายการ`);
    };
    useEffect(() => {
        if (!touchUI) return;
        const onKeyDown = (event: KeyboardEvent) => {
            const target = event.target as HTMLElement | null;
            if (!target) return;
            const tag = target.tagName.toLowerCase();
            const editable = target.isContentEditable || tag === 'textarea' || tag === 'select';
            if (editable) return;
            if (event.key === 'Enter' && !event.shiftKey) {
                const primary = document.querySelector<HTMLButtonElement>('[data-hotkey-primary="true"]');
                if (primary && !primary.disabled) {
                    event.preventDefault();
                    primary.click();
                }
            }
            if (event.key === 'Escape') {
                const cancel = document.querySelector<HTMLButtonElement>('[data-hotkey-cancel="true"]');
                if (cancel && !cancel.disabled) {
                    event.preventDefault();
                    cancel.click();
                }
            }
        };
        window.addEventListener('keydown', onKeyDown);
        return () => window.removeEventListener('keydown', onKeyDown);
    }, [touchUI]);
    useEffect(() => {
        setOtVisibleEmployeeCount(48);
        setPoolVisibleEmployeeCount(60);
    }, [debouncedLaborSearch, step, laborStatus]);

    const isWizardTx = (t: Transaction) =>
        t.category === 'Labor' ||
        t.category === 'Vehicle' ||
        t.category === 'Fuel' ||
        (t.category === 'DailyLog' && (t.subCategory === 'VehicleTrip' || t.subCategory === 'Sand' || t.subCategory === 'Event'));

    // ตั้งค่าเริ่มต้นช่วงวันที่รายงานจากข้อมูลที่มี (ถ้ายังไม่มีค่าใน state)
    useEffect(() => {
        if (reportStart && reportEnd) return;
        const wizardTx = transactions.filter(isWizardTx);
        if (wizardTx.length === 0) return;
        const dates = wizardTx.map(t => normalizeDate(t.date)).sort();
        const minDate = dates[0];
        const maxDate = dates[dates.length - 1];
        if (!reportStart) setReportStart(minDate);
        if (!reportEnd) setReportEnd(maxDate);
    }, [transactions, reportStart, reportEnd]);

    // รายงานสรุปข้อมูลที่บันทึกในแต่ละวัน (อิงช่วงวันที่ใน reportStart / reportEnd)
    const reportData = useMemo(() => {
        const fallback = getToday();
        let rangeStart = normalizeDate(reportStart || dateFilter?.start || fallback);
        let rangeEnd = normalizeDate(reportEnd || dateFilter?.end || fallback);
        if (rangeStart > rangeEnd) {
            const tmp = rangeStart;
            rangeStart = rangeEnd;
            rangeEnd = tmp;
        }

        const byDate: Record<string, Transaction[]> = {};

        transactions.filter(isWizardTx).forEach(t => {
            const d = normalizeDate(t.date);
            if (d < rangeStart || d > rangeEnd) return;
            if (!byDate[d]) byDate[d] = [];
            byDate[d].push(t);
        });

        return Object.entries(byDate).sort(([a], [b]) => b.localeCompare(a));
    }, [transactions, reportStart, reportEnd, dateFilter]);

    const formatReportDate = (d: string) =>
        new Date(d + 'T12:00:00').toLocaleDateString('th-TH', {
            weekday: 'long',
            day: 'numeric',
            month: 'long',
            year: 'numeric',
        });

    return (
        <div
            className={`animate-fade-in relative w-full max-w-full min-w-0 ${mobileShell ? 'min-h-0 bg-transparent p-0 sm:p-0' : 'min-h-screen min-h-[100dvh] bg-slate-50 dark:bg-transparent p-3 sm:p-4 lg:p-6'} ${isCompactDensity ? 'mobile-density-compact' : ''}`}
        >
            {/* Header + โหมด บันทึก | รายงาน — โหมดมือถือ: เฉพาะแถบขั้นตอน แตะง่าย */}
            {mobileShell ? (
                viewMode === 'record' && (
                    <div className="sticky top-0 z-10 mb-3 rounded-2xl border border-slate-200/90 bg-white/95 px-1.5 py-2 shadow-sm backdrop-blur-md md:mb-4 md:px-2 md:py-2.5 [@media(orientation:landscape)_and_(max-height:560px)]:mb-2 [@media(orientation:landscape)_and_(max-height:560px)]:py-1.5 dark:border-white/10 dark:bg-slate-900/95">
                        <div
                            ref={stepScrollerRef}
                            className="relative overflow-x-auto overscroll-x-contain hide-scrollbar touch-pan-x [-webkit-overflow-scrolling:touch] md:overflow-x-visible"
                        >
                            {canScrollStepLeft && (
                                <div
                                    className="pointer-events-none absolute bottom-0 left-0 top-0 w-7 rounded-l-xl bg-gradient-to-r from-white/95 to-transparent dark:from-slate-900/95"
                                    aria-hidden
                                />
                            )}
                            {canScrollStepRight && (
                                <div
                                    className="pointer-events-none absolute bottom-0 right-0 top-0 w-7 rounded-r-xl bg-gradient-to-l from-white/95 to-transparent dark:from-slate-900/95"
                                    aria-hidden
                                />
                            )}
                            <div className="flex w-max min-w-full gap-1 pb-0.5 snap-x snap-mandatory md:min-w-0 md:w-full md:flex-wrap md:justify-center md:gap-2 md:pb-0">
                            {STEPS.map((s, i) => (
                                <button
                                    type="button"
                                    key={s.id}
                                    data-step={i}
                                    onClick={() => setStep(i)}
                                    className={`flex min-h-[44px] shrink-0 snap-start items-center justify-center rounded-xl px-3.5 text-sm font-bold transition-all active:scale-[0.98] touch-manipulation md:min-h-[48px] md:px-4 md:text-base [@media(orientation:landscape)_and_(max-height:560px)]:min-h-[38px] [@media(orientation:landscape)_and_(max-height:560px)]:px-3 [@media(orientation:landscape)_and_(max-height:560px)]:text-xs ${
                                        step === i
                                            ? 'bg-indigo-600 text-white shadow-md'
                                            : i < step
                                              ? 'bg-emerald-100 text-emerald-800 dark:bg-emerald-500/25 dark:text-emerald-200'
                                              : 'bg-slate-100 text-slate-600 dark:bg-white/10 dark:text-slate-400'
                                    }`}
                                >
                                    {s.shortLabel}
                                </button>
                            ))}
                            </div>
                        </div>
                        {(canScrollStepLeft || canScrollStepRight) && (
                            <p className="mt-1 px-1 text-[10px] font-medium text-slate-400 dark:text-slate-500 md:hidden">ปัดซ้าย/ขวาเพื่อดูขั้นตอนทั้งหมด</p>
                        )}
                    </div>
                )
            ) : (
                <div className="mb-3 flex flex-col gap-3 sm:mb-6 sm:gap-4">
                    <div className="flex flex-col items-start justify-between gap-2 sm:flex-row sm:items-center sm:gap-3">
                        <div>
                            <p className="text-xs text-slate-500 dark:text-slate-400 sm:text-sm">
                                {viewMode === 'record' ? 'ระบบช่วยบันทึกข้อมูลแบบทีละขั้นตอน' : 'รายงานสรุปข้อมูลที่บันทึกในแต่ละวัน'}
                            </p>
                        </div>
                        <div className="flex w-full rounded-xl border border-slate-200 bg-white p-1 shadow-sm dark:border-white/10 dark:bg-white/[0.04] sm:w-auto">
                            <button
                                type="button"
                                onClick={() => setViewMode('record')}
                                className={`flex flex-1 items-center justify-center gap-2 rounded-lg font-medium transition-all touch-manipulation sm:flex-initial ${touchUI ? 'min-h-[48px] px-4 py-3 text-base' : 'px-4 py-2.5 text-sm sm:text-base'} ${viewMode === 'record' ? 'bg-indigo-600 text-white shadow' : 'text-slate-500 hover:bg-slate-100 dark:text-slate-400 dark:hover:bg-white/10'}`}
                            >
                                <ClipboardList size={16} />
                                บันทึก
                            </button>
                            <button
                                type="button"
                                onClick={() => setViewMode('report')}
                                className={`flex flex-1 items-center justify-center gap-2 rounded-lg font-medium transition-all touch-manipulation sm:flex-initial ${touchUI ? 'min-h-[48px] px-4 py-3 text-base' : 'px-4 py-2.5 text-sm sm:text-base'} ${viewMode === 'report' ? 'bg-indigo-600 text-white shadow' : 'text-slate-500 hover:bg-slate-100 dark:text-slate-400 dark:hover:bg-white/10'}`}
                            >
                                <FileText size={16} />
                                รายงาน
                            </button>
                        </div>
                    </div>
                    {viewMode === 'record' && (
                        <div className={`flex w-full overflow-x-auto pb-1 hide-scrollbar sm:w-auto ${touchUI ? 'gap-2' : 'gap-1.5 sm:gap-2'}`}>
                            {STEPS.map((s, i) => (
                                <button
                                    type="button"
                                    key={s.id}
                                    onClick={() => setStep(i)}
                                    className={`flex shrink-0 cursor-pointer items-center font-medium transition-colors touch-manipulation ${
                                        touchUI
                                            ? 'min-h-[44px] gap-2 rounded-xl px-3.5 py-2 text-sm sm:px-4 sm:text-base'
                                            : 'gap-1 rounded-full px-2 py-1.5 text-xs sm:gap-2 sm:px-3'
                                    } ${
                                        step === i
                                            ? 'bg-indigo-600 text-white'
                                            : i < step
                                              ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-500/20 dark:text-emerald-300'
                                              : 'bg-slate-200 text-slate-500 hover:bg-slate-300 dark:bg-white/10 dark:text-slate-400 dark:hover:bg-white/20'
                                    }`}
                                    title={`ไปที่ขั้น: ${s.label}`}
                                >
                                    <s.icon size={touchUI ? 16 : 12} />
                                    <span className={touchUI ? 'inline' : 'hidden sm:inline'}>{s.label}</span>
                                </button>
                            ))}
                        </div>
                    )}
                </div>
            )}

            {/* มุมมองรายงาน — บนมือถือ (mobileShell) ใช้เว็บปกติจอใหญ่เท่านั้น เพื่อไม่ให้คอลัมน์แคบเกินไป */}
            {viewMode === 'report' && !mobileShell && (
                <div className="space-y-6 animate-fade-in">
                    <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2 sm:gap-3">
                        <div className="flex flex-col sm:flex-row sm:items-center gap-2 sm:gap-3">
                            <p className="text-sm text-slate-500 dark:text-slate-400">
                                ช่วงวันที่
                            </p>
                            <div className="flex items-center gap-2 text-xs">
                                <input
                                    type="date"
                                    value={reportStart || ''}
                                    onChange={e => setReportStart(e.target.value)}
                                    className="border border-slate-200 dark:border-white/10 rounded-lg px-2 py-1.5 text-xs bg-white dark:bg-white/5 text-slate-700 dark:text-slate-100"
                                />
                                <span className="text-slate-400 dark:text-slate-500">ถึง</span>
                                <input
                                    type="date"
                                    value={reportEnd || ''}
                                    onChange={e => setReportEnd(e.target.value)}
                                    className="border border-slate-200 dark:border-white/10 rounded-lg px-2 py-1.5 text-xs bg-white dark:bg-white/5 text-slate-700 dark:text-slate-100"
                                />
                            </div>
                        </div>
                        <span className="text-xs font-medium text-slate-500 dark:text-slate-300 bg-slate-100 dark:bg-white/5 px-3 py-1 rounded-full">
                            {reportData.length} วันที่มีข้อมูล
                        </span>
                    </div>
                    <div className="space-y-4">
                        {reportData.length === 0 ? (
                            <Card className="p-12 text-center">
                                <FileText size={48} className="mx-auto text-slate-300 mb-3" />
                                <p className="text-slate-500 dark:text-slate-300 font-medium">ไม่มีข้อมูลบันทึกงานในช่วงนี้</p>
                                <p className="text-sm text-slate-400 dark:text-slate-500 mt-1">ลองเลือกช่วงวันที่อื่นหรือไปที่โหมด บันทึก เพื่อกรอกข้อมูล</p>
                            </Card>
                        ) : reportData.map(([dateStr, txs]) => {
                            const labor = txs.filter(t => t.category === 'Labor');
                            const vehicle = txs.filter(t => t.category === 'Vehicle');
                            const trips = txs.filter(t => t.category === 'DailyLog' && t.subCategory === 'VehicleTrip');
                            const sand = txs.filter(t => t.category === 'DailyLog' && t.subCategory === 'Sand');
                            const fuel = txs.filter(t => t.category === 'Fuel');
                            const income = txs.filter(t => t.category === 'Income' && t.type === 'Income');
                            const events = txs.filter(t => t.category === 'DailyLog' && t.subCategory === 'Event');
                            const laborSum = labor.reduce((s, t) => s + t.amount, 0);
                            const vehicleSum = vehicle.reduce((s, t) => s + t.amount, 0);
                            const tripsTotal = trips.reduce((s, t) => s + ((t as any).perCarTrips || (t as any).tripCount || 0), 0);
                            const tripsCubic = trips.reduce((s, t) => s + ((t as any).perCarCubic || (t as any).totalCubic || 0), 0);
                            const sandCubic = sand.reduce((s, t) => s + (t.sandMorning || 0) + (t.sandAfternoon || 0), 0);
                            const sandDrumsTotal = sand.length > 0
                                ? Math.max(0, ...sand.map(t => Number((t as any).drumsObtained || 0)))
                                : 0;
                            const sandHomeDrums = sand.length > 0
                                ? Math.max(0, ...sand.map(t => Number((t as any).drumsWashedAtHome || 0)))
                                : 0;
                            const laborAttendance = labor.filter(t => t.subCategory === 'Attendance') as any[];
                            const latestAttendance = laborAttendance.length > 0 ? laborAttendance[laborAttendance.length - 1] : null;
                            const homeDrums = Math.max(0, sandHomeDrums || Number(latestAttendance?.drumsWashedAtHome || 0));
                            const sandDrums = Math.max(0, sandDrumsTotal - homeDrums);
                            const fuelSum = fuel.reduce((s, t) => s + t.amount, 0);
                            const incomeSum = income.reduce((s, t) => s + t.amount, 0);
                            const workerIdSet = new Set<string>(labor.flatMap(t => t.employeeIds || []));
                            const workerCount = workerIdSet.size;
                            const workerIds = Array.from(workerIdSet);
                            const workerNames = workerIds.map(id => {
                                const emp = employees.find(e => e.id === id);
                                return emp?.nickname || emp?.name || id;
                            });
                            const washHomeDrumsReportAlert = getWashHomeDrumsMismatchMessage(txs);

                            // กลุ่มประเภทงานจาก Attendance (canvas) ถ้ามี
                            const attendance = laborAttendance;
                            let workGroups: { label: string; count: number }[] = [];
                            if (attendance.length > 0) {
                                const latest = attendance[attendance.length - 1] as any;
                                const wa: Record<string, string[]> | undefined = latest.workAssignments;
                                const customCategoryMap = new Map<string, string>(
                                    Array.isArray(latest.customWorkCategories)
                                        ? latest.customWorkCategories
                                            .filter((c: any) => c && typeof c.id === 'string' && typeof c.label === 'string')
                                            .map((c: any) => [c.id, c.label])
                                        : []
                                );
                                if (wa) {
                                    workGroups = Object.entries(wa)
                                        .map(([catId, empIds]) => {
                                            const def = DEFAULT_WORK_CATEGORIES.find(c => c.id === catId);
                                            return {
                                                label: def?.label || customCategoryMap.get(catId) || catId,
                                                count: (empIds || []).length,
                                            };
                                        })
                                        .filter(g => g.count > 0);
                                }
                            }

                            return (
                                <Card key={dateStr} className="overflow-hidden border border-slate-200 shadow-sm hover:shadow-md transition-shadow">
                                    <div className="bg-gradient-to-r from-slate-800 to-slate-700 px-5 py-4 text-white">
                                        <h3 className="font-bold text-lg">{formatReportDate(dateStr)}</h3>
                                        <p className="text-slate-300 text-sm mt-0.5">สรุปบันทึกงานประจำวัน</p>
                                    </div>
                                    {washHomeDrumsReportAlert && (
                                        <div className="border-b border-amber-200/60 bg-amber-50 px-4 py-3 dark:border-amber-500/25 dark:bg-amber-500/10">
                                            <p className="flex items-start gap-2 text-xs font-semibold text-amber-900 dark:text-amber-100">
                                                <AlertTriangle size={16} className="mt-0.5 shrink-0 text-amber-600 dark:text-amber-300" />
                                                <span><span className="font-bold">แจ้งเตือน:</span> {washHomeDrumsReportAlert}</span>
                                            </p>
                                        </div>
                                    )}
                                    <div className="grid grid-cols-1 gap-3 p-4 sm:grid-cols-2 sm:gap-4 sm:p-5 lg:grid-cols-3 xl:grid-cols-7">
                                        <div className="bg-emerald-50 dark:bg-emerald-500/10 rounded-xl p-4 border border-emerald-100 dark:border-emerald-500/30">
                                            <div className="flex items-center gap-2 text-emerald-700 dark:text-emerald-300 font-semibold text-sm mb-1"><Users size={16} /> ค่าแรง</div>
                                            <p className="text-lg font-bold text-emerald-800 dark:text-emerald-100">฿{laborSum.toLocaleString()}</p>
                                            <p className="text-xs text-emerald-600 dark:text-emerald-200 mt-0.5">{workerCount} คน • {labor.length} รายการ</p>
                                        </div>
                                        <div className="bg-amber-50 dark:bg-amber-500/10 rounded-xl p-4 border border-amber-100 dark:border-amber-500/30">
                                            <div className="flex items-center gap-2 text-amber-700 dark:text-amber-300 font-semibold text-sm mb-1"><Truck size={16} /> ใช้รถ</div>
                                            <p className="text-lg font-bold text-amber-800 dark:text-amber-100">฿{vehicleSum.toLocaleString()}</p>
                                            <p className="text-xs text-amber-600 dark:text-amber-200 mt-0.5">{vehicle.length} รายการ</p>
                                        </div>
                                        <div className="bg-blue-50 dark:bg-blue-500/10 rounded-xl p-4 border border-blue-100 dark:border-blue-500/30">
                                            <div className="flex items-center gap-2 text-blue-700 dark:text-blue-300 font-semibold text-sm mb-1"><Truck size={16} /> เที่ยวรถ</div>
                                            <p className="text-lg font-bold text-blue-800 dark:text-blue-100">{tripsTotal} เที่ยว</p>
                                            <p className="text-xs text-blue-600 dark:text-blue-200 mt-0.5">{tripsCubic} คิว • {trips.length} รายการ</p>
                                        </div>
                                        <div className="bg-cyan-50 dark:bg-cyan-500/10 rounded-xl p-4 border border-cyan-100 dark:border-cyan-500/30">
                                            <div className="flex items-center gap-2 text-cyan-700 dark:text-cyan-300 font-semibold text-sm mb-1"><Droplets size={16} /> ล้างทราย</div>
                                            <p className="text-lg font-bold text-cyan-800 dark:text-cyan-100">{sandCubic} คิว</p>
                                            <p className="text-xs text-cyan-600 dark:text-cyan-200 mt-0.5">
                                                {sandDrums > 0 && <>🪣 {sandDrums} ถังสุทธิ{homeDrums > 0 ? ` (หักบ้าน ${homeDrums})` : ''} • </>}
                                                {sand.length} รายการ
                                            </p>
                                        </div>
                                        <div className="bg-red-50 dark:bg-red-500/10 rounded-xl p-4 border border-red-100 dark:border-red-500/30">
                                            <div className="flex items-center gap-2 text-red-700 dark:text-red-300 font-semibold text-sm mb-1"><Fuel size={16} /> น้ำมัน</div>
                                            <p className="text-lg font-bold text-red-800 dark:text-red-100">฿{fuelSum.toLocaleString()}</p>
                                            <p className="text-xs text-red-600 dark:text-red-200 mt-0.5">{fuel.length} รายการ</p>
                                        </div>
                                        <div className="bg-lime-50 dark:bg-lime-500/10 rounded-xl p-4 border border-lime-100 dark:border-lime-500/30">
                                            <div className="flex items-center gap-2 text-lime-700 dark:text-lime-300 font-semibold text-sm mb-1"><Wallet size={16} /> รายรับ</div>
                                            <p className="text-lg font-bold text-lime-800 dark:text-lime-100">฿{incomeSum.toLocaleString()}</p>
                                            <p className="text-xs text-lime-600 dark:text-lime-200 mt-0.5">{income.length} รายการ</p>
                                        </div>
                                        <div className="bg-orange-50 dark:bg-orange-500/10 rounded-xl p-4 border border-orange-100 dark:border-orange-500/30">
                                            <div className="flex items-center gap-2 text-orange-700 dark:text-orange-300 font-semibold text-sm mb-1"><AlertTriangle size={16} /> เหตุการณ์</div>
                                            <p className="text-lg font-bold text-orange-800 dark:text-orange-100">{events.length} รายการ</p>
                                            {events.length > 0 && (
                                                <ul className="text-xs text-orange-600 mt-1 space-y-0.5 truncate max-h-12 overflow-hidden">
                                                    {events.slice(0, 2).map(t => <li key={t.id}>• {t.description}</li>)}
                                                    {events.length > 2 && <li>+ อีก {events.length - 2}</li>}
                                                </ul>
                                            )}
                                        </div>
                                    </div>
                                    <div className="px-5 pb-4 pt-0">
                                        <div className="flex flex-wrap gap-2 text-xs mb-2">
                                            <span className="bg-slate-100 dark:bg-white/5 text-slate-600 dark:text-slate-200 px-2 py-1 rounded">
                                                รวมค่าใช้จ่ายวันนี้: ฿{(laborSum + vehicleSum + fuelSum).toLocaleString()}
                                            </span>
                                            {workerCount > 0 && (
                                                <span className="bg-emerald-50 dark:bg-emerald-500/10 text-emerald-700 dark:text-emerald-200 px-2 py-1 rounded">
                                                    คนมาทำงาน: {workerCount} คน
                                                </span>
                                            )}
                                        </div>
                                        {workerCount > 0 && (
                                            <div className="mb-2">
                                                <p className="text-[11px] text-slate-500 dark:text-slate-400 mb-1">
                                                    รายชื่อคนที่มาทำงานวันนี้:
                                                </p>
                                                <div className="flex flex-wrap gap-1.5">
                                                    {workerNames.slice(0, 8).map((name, idx) => (
                                                        <span
                                                            key={idx}
                                                            className="px-2 py-0.5 rounded-full bg-slate-100 dark:bg-white/5 text-[11px] text-slate-700 dark:text-slate-200"
                                                        >
                                                            {name}
                                                        </span>
                                                    ))}
                                                    {workerNames.length > 8 && (
                                                        <span className="px-2 py-0.5 rounded-full bg-slate-50 dark:bg-white/5 text-[11px] text-slate-500 dark:text-slate-400">
                                                            + อีก {workerNames.length - 8} คน
                                                        </span>
                                                    )}
                                                </div>
                                            </div>
                                        )}
                                        {workGroups.length > 0 ? (
                                            <div>
                                                <p className="text-[11px] text-slate-500 dark:text-slate-400 mb-1">
                                                    แบ่งตามประเภทงาน:
                                                </p>
                                                <div className="flex flex-wrap gap-1.5">
                                                    {workGroups.map(g => (
                                                        <span
                                                            key={g.label}
                                                            className="px-2 py-0.5 rounded-full bg-slate-100 dark:bg-white/5 text-[11px] text-slate-700 dark:text-slate-200"
                                                        >
                                                            {g.label}: {g.count} คน
                                                        </span>
                                                    ))}
                                                </div>
                                            </div>
                                        ) : null}
                                    </div>
                                </Card>
                            );
                        })}
                    </div>
                </div>
            )}

            {viewMode === 'record' && (
            <div className={`grid w-full min-w-0 max-w-full grid-cols-1 gap-4 sm:gap-6 lg:gap-8 ${mobileShell ? '' : 'xl:grid-cols-12'}`}>
                {/* Left: Wizard Form — แยกแถบข้างเฉพาะจอ xl+ เพื่อไม่ให้คอลัมน์ขวาเหลือ ~195px */}
                <div className={`min-w-0 space-y-6 ${mobileShell ? '' : 'xl:col-span-8'}`}>
                    <Card className={`relative flex flex-col overflow-hidden ${mobileShell ? 'min-h-0 rounded-2xl border border-slate-200/80 p-4 shadow-sm dark:border-white/10 sm:p-4 md:p-5 lg:p-6' : 'min-h-[500px] p-6'}`}>
                        {viewMode === 'record' && (
                            <div className="mb-3 flex items-center justify-end">
                                <span
                                    role="status"
                                    aria-live="polite"
                                    aria-atomic="true"
                                    className={`rounded-full border px-2.5 py-1 text-[11px] font-semibold ${
                                        autosaveState === 'saving'
                                            ? 'border-blue-200 bg-blue-50 text-blue-700 dark:border-blue-500/30 dark:bg-blue-500/10 dark:text-blue-300'
                                            : autosaveState === 'saved'
                                              ? 'border-emerald-200 bg-emerald-50 text-emerald-700 dark:border-emerald-500/30 dark:bg-emerald-500/10 dark:text-emerald-300'
                                              : autosaveState === 'error'
                                                ? 'border-red-200 bg-red-50 text-red-700 dark:border-red-500/30 dark:bg-red-500/10 dark:text-red-300'
                                                : 'border-slate-200 bg-slate-50 text-slate-500 dark:border-white/15 dark:bg-white/5 dark:text-slate-300'
                                    }`}
                                >
                                    {autosaveState === 'saving'
                                        ? 'กำลังบันทึกแบบร่าง...'
                                        : autosaveState === 'saved'
                                          ? `บันทึกล่าสุด ${autosaveSavedAt ? new Date(autosaveSavedAt).toLocaleTimeString('th-TH', { hour: '2-digit', minute: '2-digit' }) : ''}`
                                          : autosaveState === 'error'
                                            ? `บันทึกแบบร่างไม่สำเร็จ (${autosaveErrorReason === 'quota_exceeded' ? 'พื้นที่เต็ม' : autosaveErrorReason === 'storage_unavailable' ? 'storage ใช้ไม่ได้' : 'ข้อผิดพลาดข้อมูล'})`
                                            : 'ยังไม่มีการแก้ไขล่าสุด'}
                                </span>
                            </div>
                        )}
                        {draftOffer && viewMode === 'record' && (
                            <div
                                className={`mb-4 rounded-2xl border p-3 text-sm shadow-sm ${
                                    draftOffer.hasConflict
                                        ? 'border-rose-200 bg-rose-50/90 text-rose-900 dark:border-rose-500/30 dark:bg-rose-500/10 dark:text-rose-100'
                                        : 'border-amber-200 bg-amber-50/90 text-amber-950 dark:border-amber-500/30 dark:bg-amber-500/10 dark:text-amber-50'
                                } ${
                                    mobileShell ? '' : 'mx-0'
                                }`}
                            >
                                <p className="font-bold">พบแบบร่างที่ยังไม่เสร็จ (ขั้น {STEPS[draftOffer.payload.step]?.shortLabel || draftOffer.payload.step})</p>
                                <p className="mt-1 text-xs opacity-90">
                                    บันทึกล่าสุด {new Date(draftOffer.savedAt).toLocaleString('th-TH', { hour: '2-digit', minute: '2-digit', day: 'numeric', month: 'short' })}
                                </p>
                                {draftOffer.hasConflict && (
                                    <p className="mt-1.5 text-xs font-semibold">
                                        มีข้อมูลรายการของวันนี้เปลี่ยนไปจากตอนที่บันทึกแบบร่าง (เดิม {draftOffer.conflictDraftTxCount} รายการ, ปัจจุบัน {draftOffer.conflictCurrentTxCount} รายการ) อาจเกิดการชนกันของข้อมูล
                                    </p>
                                )}
                                {draftOffer.hasConflict && (
                                    <div className="mt-2 grid grid-cols-2 gap-1.5 text-[11px] sm:grid-cols-4">
                                        {[
                                            ['labor', 'ค่าแรง'],
                                            ['vehicle', 'ใช้รถ'],
                                            ['trip', 'เที่ยวรถ'],
                                            ['sand', 'ล้างทราย'],
                                            ['fuel', 'น้ำมัน'],
                                            ['income', 'รายรับ'],
                                            ['event', 'เหตุการณ์'],
                                        ].map(([key, label]) => {
                                            const sectionKey = key as DraftMergeSection;
                                            return (
                                                <label key={key} className="flex items-center gap-1 rounded border border-rose-200/60 bg-white/60 px-2 py-1 dark:border-rose-500/25 dark:bg-rose-500/5">
                                                    <input
                                                        type="checkbox"
                                                        checked={draftMergeSections[sectionKey]}
                                                        onChange={(e) =>
                                                            setDraftMergeSections(prev => ({ ...prev, [sectionKey]: e.target.checked }))
                                                        }
                                                    />
                                                    <span>{label}</span>
                                                </label>
                                            );
                                        })}
                                    </div>
                                )}
                                <div className="mt-3 flex flex-wrap gap-2">
                                    <Button
                                        type="button"
                                        className="touch-manipulation"
                                        onClick={async () => {
                                            if (draftOffer.hasConflict) {
                                                const ok = await sessionConfirm('พบความต่างระหว่างแบบร่างกับข้อมูลล่าสุดของวันนี้ ต้องการกู้คืนทับค่าในฟอร์มต่อหรือไม่?', { title: 'ยืนยันกู้คืนแบบร่างที่มี conflict' });
                                                if (!ok) return;
                                            }
                                            const picked = ALL_DRAFT_MERGE_SECTIONS.filter(section => draftMergeSections[section]);
                                            if (picked.length === 0) {
                                                await sessionAlert('กรุณาเลือกอย่างน้อย 1 หมวดที่ต้องการกู้คืน');
                                                return;
                                            }
                                            applyWizardDraft(draftOffer.payload, picked);
                                            setDraftOffer(null);
                                            if (typeof sessionStorage !== 'undefined') {
                                                sessionStorage.removeItem(`cm_draft_dismiss_${normalizeDate(date)}`);
                                            }
                                        }}
                                    >
                                        กู้คืนแบบร่าง
                                    </Button>
                                    <Button
                                        type="button"
                                        variant="secondary"
                                        className="touch-manipulation"
                                        onClick={() => {
                                            clearWizardDraftForDate(normalizeDate(date));
                                            setDraftOffer(null);
                                            setAutosaveState('idle');
                                            setAutosaveSavedAt(null);
                                            setAutosaveErrorReason('none');
                                            if (typeof sessionStorage !== 'undefined') {
                                                sessionStorage.setItem(`cm_draft_dismiss_${normalizeDate(date)}`, '1');
                                            }
                                        }}
                                    >
                                        ไม่ใช้แบบร่าง
                                    </Button>
                                    <Button
                                        type="button"
                                        variant="ghost"
                                        className="touch-manipulation"
                                        onClick={async () => {
                                            const ok = await sessionConfirm('ล้างแบบร่างทั้งหมดทุกวันที่เคยบันทึกไว้?', { title: 'ล้างแบบร่างทั้งหมด' });
                                            if (!ok) return;
                                            clearAllWizardDrafts();
                                            setDraftOffer(null);
                                            setAutosaveState('idle');
                                            setAutosaveSavedAt(null);
                                            setAutosaveErrorReason('none');
                                        }}
                                    >
                                        ล้างแบบร่างทั้งหมด
                                    </Button>
                                </div>
                            </div>
                        )}

                        {/* Step 0: Date */}
                        {step === 0 && (
                            <div className="flex h-full flex-col items-center justify-center space-y-5 animate-slide-up [@media(orientation:landscape)_and_(max-height:560px)]:justify-start [@media(orientation:landscape)_and_(max-height:560px)]:space-y-3 [@media(orientation:landscape)_and_(max-height:560px)]:pt-1">
                                <div className="mb-1 flex h-14 w-14 items-center justify-center rounded-2xl bg-slate-100 text-slate-700 dark:bg-white/10 dark:text-slate-200">
                                    <Calendar size={32} />
                                </div>
                                <h3 className={`font-bold text-slate-800 dark:text-slate-100 ${mobileShell ? 'text-base' : 'text-xl'}`}>เลือกวันที่</h3>
                                <div className={mobileShell ? 'w-full' : 'w-full max-w-sm'}>
                                    <DatePicker label={mobileShell ? '' : 'วันที่'} value={date} onChange={setDate} touchFriendly={touchUI} />
                                </div>
                                <Button
                                    type="button"
                                    variant="secondary"
                                    onClick={() => void handleCopyFromYesterday()}
                                    className={mobileShell ? 'w-full min-h-[46px]' : ''}
                                >
                                    คัดลอกจากเมื่อวาน
                                </Button>
                                {!mobileShell && (
                                    <div className="max-w-md rounded-xl border border-orange-100 bg-orange-50 p-4 text-center text-sm text-orange-700 dark:border-orange-500/25 dark:bg-orange-500/10 dark:text-orange-200">
                                        💡 ระบบจะดึงข้อมูลเก่าของวันนี้มาแสดงให้ตรวจสอบด้วยครับ
                                    </div>
                                )}
                                {hasExistingWizardData && (
                                    <div className="w-full min-w-0 rounded-2xl border border-indigo-100 bg-gradient-to-br from-white to-indigo-50/60 p-3.5 text-xs text-slate-700 shadow-sm dark:border-indigo-500/20 dark:bg-gradient-to-br dark:from-white/[0.05] dark:to-indigo-500/[0.08] dark:text-slate-200">
                                        <div className="mb-2.5 flex items-center justify-between gap-2">
                                            <p className="break-words text-xs font-semibold text-slate-700 dark:text-slate-100">พบข้อมูลวันที่นี้แล้ว</p>
                                            <span className="rounded-full bg-indigo-100 px-2 py-0.5 text-[10px] font-bold text-indigo-700 dark:bg-indigo-500/20 dark:text-indigo-300">แก้ไขต่อได้</span>
                                        </div>
                                        <div className="grid grid-cols-2 gap-2 text-[11px] sm:grid-cols-3 md:grid-cols-4">
                                            <div className="min-w-0 rounded-lg border border-emerald-200/80 bg-emerald-50/80 px-2.5 py-2 text-center dark:border-emerald-500/25 dark:bg-emerald-500/10"><div className="font-semibold text-emerald-700 dark:text-emerald-300">ค่าแรง</div><div className="mt-0.5 text-base font-black text-emerald-800 dark:text-emerald-200">{dayStepStats.laborCount}</div></div>
                                            <div className="min-w-0 rounded-lg border border-amber-200/80 bg-amber-50/80 px-2.5 py-2 text-center dark:border-amber-500/25 dark:bg-amber-500/10"><div className="font-semibold text-amber-700 dark:text-amber-300">การใช้รถ</div><div className="mt-0.5 text-base font-black text-amber-800 dark:text-amber-200">{dayStepStats.vehicleCount}</div></div>
                                            <div className="min-w-0 rounded-lg border border-blue-200/80 bg-blue-50/80 px-2.5 py-2 text-center dark:border-blue-500/25 dark:bg-blue-500/10"><div className="font-semibold text-blue-700 dark:text-blue-300">เที่ยวรถ</div><div className="mt-0.5 text-base font-black text-blue-800 dark:text-blue-200">{dayStepStats.tripCount}</div></div>
                                            <div className="min-w-0 rounded-lg border border-cyan-200/80 bg-cyan-50/80 px-2.5 py-2 text-center dark:border-cyan-500/25 dark:bg-cyan-500/10"><div className="font-semibold text-cyan-700 dark:text-cyan-300">ทราย</div><div className="mt-0.5 text-base font-black text-cyan-800 dark:text-cyan-200">{dayStepStats.sandCount}</div></div>
                                            <div className="min-w-0 rounded-lg border border-rose-200/80 bg-rose-50/80 px-2.5 py-2 text-center dark:border-rose-500/25 dark:bg-rose-500/10"><div className="font-semibold text-rose-700 dark:text-rose-300">น้ำมัน</div><div className="mt-0.5 text-base font-black text-rose-800 dark:text-rose-200">{dayStepStats.fuelCount}</div></div>
                                            <div className="min-w-0 rounded-lg border border-lime-200/80 bg-lime-50/80 px-2.5 py-2 text-center dark:border-lime-500/25 dark:bg-lime-500/10"><div className="font-semibold text-lime-700 dark:text-lime-300">รายรับ</div><div className="mt-0.5 text-base font-black text-lime-800 dark:text-lime-200">{dayStepStats.incomeCount}</div></div>
                                            <div className="min-w-0 rounded-lg border border-orange-200/80 bg-orange-50/80 px-2.5 py-2 text-center dark:border-orange-500/25 dark:bg-orange-500/10"><div className="font-semibold text-orange-700 dark:text-orange-300">เหตุการณ์</div><div className="mt-0.5 text-base font-black text-orange-800 dark:text-orange-200">{dayStepStats.eventCount}</div></div>
                                        </div>
                                    </div>
                                )}
                                <Button onClick={handleStartRecord} className={`mt-6 w-full max-w-xs rounded-xl border border-slate-300 bg-slate-900 px-6 font-semibold text-white shadow-sm hover:bg-slate-800 [@media(orientation:landscape)_and_(max-height:560px)]:mt-3 sm:w-auto sm:max-w-none sm:px-8 dark:border-white/20 dark:bg-white dark:text-slate-900 dark:hover:bg-slate-100 touch-manipulation ${touchUI ? 'min-h-[52px] py-3.5 text-base' : 'py-3 text-sm sm:text-base'}`}>
                                    {hasExistingWizardData ? 'แก้ไขข้อมูลที่บันทึกแล้ว' : 'เริ่มบันทึก'} <ChevronRight className="ml-2" />
                                </Button>
                            </div>
                        )}

                        {/* Step 1: Labor - Canvas Style */}
                        {step === 1 && (
                            <div className="h-full flex flex-col animate-slide-up">
                                <div className="flex justify-between items-center mb-3">
                                    <h3 className="font-bold text-lg flex items-center gap-2 text-slate-800 dark:text-slate-100"><Users className="text-emerald-500 dark:text-emerald-400" /> บันทึกค่าแรง / OT</h3>
                                    <span className="text-xs text-slate-400 dark:text-slate-500">{new Date(date).toLocaleDateString('th-TH', { day: 'numeric', month: 'short', year: '2-digit' })}</span>
                                </div>
                                {mobileShell && (
                                    <div className="mb-3 w-full min-w-0 rounded-2xl border border-slate-200 bg-white/95 p-3 shadow-sm dark:border-white/10 dark:bg-white/[0.03]">
                                        <div className="mb-2 flex items-center justify-between gap-2">
                                            <p className="text-xs font-semibold text-slate-800 dark:text-slate-100">แคนวาสค่าแรงวันนี้</p>
                                            <span className="rounded-full border border-slate-200 bg-slate-50 px-2 py-0.5 text-[10px] font-semibold text-slate-600 dark:border-white/10 dark:bg-white/10 dark:text-slate-300">
                                                {mobileLaborCanvasPreview.reduce((acc, row) => acc + row.names.length, 0)} คน
                                            </span>
                                        </div>
                                        {mobileLaborCanvasPreview.length > 0 ? (
                                            <div className="space-y-2 md:grid md:grid-cols-2 md:gap-2 md:space-y-0 lg:grid-cols-3 [@media(orientation:landscape)_and_(max-height:560px)]:grid [@media(orientation:landscape)_and_(max-height:560px)]:grid-cols-2 [@media(orientation:landscape)_and_(max-height:560px)]:gap-2 [@media(orientation:landscape)_and_(max-height:560px)]:space-y-0">
                                                {mobileLaborCanvasPreview.map(row => (
                                                    <div key={row.catId} className="rounded-xl border border-slate-200/80 bg-slate-50/70 p-2.5 dark:border-white/10 dark:bg-white/5">
                                                        <p className="text-[11px] font-semibold text-slate-700 dark:text-slate-200">{row.label}</p>
                                                        <p className="mt-1 break-words text-[11px] text-slate-600 dark:text-slate-300">
                                                            {row.names.join(', ')}
                                                        </p>
                                                    </div>
                                                ))}
                                            </div>
                                        ) : (
                                            <p className="text-[11px] text-slate-500 dark:text-slate-400">ยังไม่มีการจัดคนลงกล่องงานสำหรับวันนี้</p>
                                        )}
                                        <button
                                            type="button"
                                            onClick={handleOpenLaborStep}
                                            className="mt-3 w-full rounded-xl border border-slate-300 bg-slate-900 px-4 py-2.5 text-xs font-semibold text-white shadow-sm transition hover:bg-slate-800 active:scale-[0.99] touch-manipulation dark:border-white/20 dark:bg-white dark:text-slate-900 dark:hover:bg-slate-100"
                                        >
                                            {hasLaborAttendanceToday ? 'แก้ไขค่าแรง' : 'เริ่มบันทึกค่าแรง'}
                                        </button>
                                    </div>
                                )}

                                <div className="mb-4 flex gap-3">
                                    <button type="button" onClick={() => setLaborStatus('Work')} className={`flex-1 touch-manipulation rounded-xl border text-base transition-all ${touchUI ? 'min-h-[52px] py-3.5' : 'py-3'} ${laborStatus === 'Work' ? 'bg-emerald-50 dark:bg-emerald-500/15 border-emerald-500 text-emerald-700 dark:text-emerald-300 font-bold' : 'bg-white dark:bg-white/5 border-slate-200 dark:border-white/10 text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-white/10'}`}>✅ มาทำงาน</button>
                                    <button type="button" onClick={() => setLaborStatus('OT')} className={`flex-1 touch-manipulation rounded-xl border text-base transition-all ${touchUI ? 'min-h-[52px] py-3.5' : 'py-3'} ${laborStatus === 'OT' ? 'bg-amber-50 dark:bg-amber-500/15 border-amber-500 text-amber-700 dark:text-amber-300 font-bold' : 'bg-white dark:bg-white/5 border-slate-200 dark:border-white/10 text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-white/10'}`}>🕒 OT</button>
                                </div>
                                {laborStatus === 'Work' && !mobileShell && (
                                    <p className="mb-2 text-xs text-slate-500 dark:text-slate-400">💡 มาทำงานปกติ = เต็มวัน (ไม่ต้องกด) — ถ้ามาครึ่งวันให้กดปุ่ม &quot;½ ครึ่งวัน&quot ที่ชื่อคนนั้น</p>
                                )}

                                {/* รายการบันทึกวันนี้ (ค่าแรง/OT) — เรียลไทม์ — ซ่อนในโหมดมือถือเพื่อลดความหนาแน่น */}
                                {step === 1 && !mobileShell && (
                                    <div className="mb-4 p-3 rounded-xl border border-emerald-200 dark:border-emerald-500/30 bg-emerald-50/80 dark:bg-emerald-500/10">
                                        <p className="text-xs font-bold text-emerald-800 dark:text-emerald-200 mb-2">📋 รายการบันทึกวันนี้ (อัปเดตทันที)</p>
                                        {dayTransactions.filter(t => t.category === 'Labor').length === 0 ? (
                                            <p className="text-sm text-slate-500 dark:text-slate-400 py-2">ยังไม่มีรายการค่าแรง/OT วันนี้ — เมื่อกดบันทึกจะแสดงที่นี่ทันที</p>
                                        ) : (
                                            <div className="space-y-1.5 max-h-32 overflow-y-auto">
                                                {dayTransactions.filter(t => t.category === 'Labor').map(t => (
                                                    <div key={t.id} className="flex justify-between items-center text-sm py-1.5 px-2 rounded-lg bg-white/80 dark:bg-white/5 border border-emerald-100 dark:border-emerald-500/20">
                                                        <span className="font-medium text-slate-700 dark:text-slate-200 truncate flex-1">{t.description}</span>
                                                        <span className="text-emerald-700 dark:text-emerald-300 font-bold shrink-0 ml-2">฿{t.amount?.toLocaleString() ?? 0}</span>
                                                    </div>
                                                ))}
                                            </div>
                                        )}
                                    </div>
                                )}

                                {/* === OT MODE: Clean form layout === */}
                                {laborStatus === 'OT' && (
                                    <div className="flex-1 flex flex-col">
                                        <div className="flex-1 bg-white dark:bg-white/[0.03] p-5 rounded-2xl border border-slate-200 dark:border-white/10 shadow-sm space-y-5">
                                            {/* Date */}
                                            <div>
                                                <label className="text-sm font-bold text-slate-700 dark:text-slate-200 mb-1.5 block">วันที่</label>
                                                <input type="date" value={date} readOnly
                                                    className="w-full px-4 py-3 border border-slate-300 dark:border-white/15 rounded-xl text-base text-slate-800 dark:text-slate-100 bg-slate-50 dark:bg-white/5" />
                                            </div>

                                            {/* Employee selector */}
                                            <div className="border border-slate-200 dark:border-white/10 rounded-xl p-4">
                                                <div className="flex justify-between items-center mb-3">
                                                    <span className="text-sm font-bold text-slate-700 dark:text-slate-200">เลือกพนักงาน ({selectedEmps.length})</span>
                                                    <input placeholder="ค้นหาชื่อ..." value={laborSearch} onChange={e => setLaborSearch(e.target.value)}
                                                        className="text-sm border border-slate-200 dark:border-white/15 rounded-lg px-3 py-1.5 w-32 bg-white dark:bg-white/5 text-slate-800 dark:text-slate-200 placeholder:text-slate-400" />
                                                </div>
                                                <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
                                                    {otVisibleEmployees.map(emp => {
                                                        const isSelected = selectedEmps.includes(emp.id);
                                                        const displayName = getEmployeeDisplayName(emp);
                                                        return (
                                                            <EmployeeSelectChip
                                                                key={emp.id}
                                                                touchUI={touchUI}
                                                                selected={isSelected}
                                                                onClick={() => setSelectedEmps(prev => prev.includes(emp.id) ? prev.filter(id => id !== emp.id) : [...prev, emp.id])}
                                                                label={`${displayName}${emp.name && displayName !== emp.name ? ` (${emp.name})` : ''}`}
                                                            />
                                                        );
                                                    })}
                                                </div>
                                                {filteredLaborEmployees.length > otVisibleEmployees.length && (
                                                    <button
                                                        type="button"
                                                        onClick={() => setOtVisibleEmployeeCount(prev => prev + 36)}
                                                        className="mt-2 w-full rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 text-xs font-semibold text-slate-700 hover:bg-slate-100"
                                                    >
                                                        แสดงพนักงานเพิ่ม ({otVisibleEmployees.length}/{filteredLaborEmployees.length})
                                                    </button>
                                                )}
                                            </div>

                                            {/* OT Rate */}
                                            <div>
                                                <label className="text-sm font-bold text-slate-700 dark:text-slate-200 mb-1.5 block">ค่า OT (บาท/คน/ชม.)</label>
                                                <NumberPickerInput
                                                    placeholder=""
                                                    value={otRate}
                                                    onChange={setOtRate}
                                                    listMin={0}
                                                    listMax={2000}
                                                    listStep={50}
                                                    scrollAnchor={100}
                                                    min={0}
                                                    className="w-full px-4 py-3.5 border border-slate-300 bg-white text-base text-slate-800 transition-colors focus:border-slate-500 focus:outline-none dark:border-white/15 dark:bg-white/5 dark:text-slate-100 dark:focus:border-slate-400"
                                                />
                                            </div>

                                            {/* OT Hours */}
                                            <div>
                                                <label className="text-sm font-bold text-slate-700 dark:text-slate-200 mb-1.5 block">จำนวนชั่วโมง OT</label>
                                                <NumberPickerInput
                                                    placeholder="เช่น 2.5"
                                                    value={otHours}
                                                    onChange={setOtHours}
                                                    listMin={0}
                                                    listMax={24}
                                                    listStep={0.5}
                                                    scrollAnchor={2}
                                                    min={0}
                                                    step={0.5}
                                                    className="w-full px-4 py-3 border border-slate-300 bg-white text-base text-slate-800 transition-colors focus:border-slate-500 focus:outline-none dark:border-white/15 dark:bg-white/5 dark:text-slate-100 dark:focus:border-slate-400"
                                                />
                                            </div>

                                            {/* OT Description */}
                                            <div>
                                                <label className="text-sm font-bold text-slate-700 dark:text-slate-200 mb-1.5 block">รายละเอียดงาน OT</label>
                                                <input type="text" placeholder="ทำอะไร..." value={otDesc} onChange={e => setOtDesc(e.target.value)}
                                                    className="w-full px-4 py-3 border border-slate-300 dark:border-white/15 rounded-xl text-base text-slate-800 dark:text-slate-100 bg-white dark:bg-white/5 focus:border-slate-500 dark:focus:border-slate-400 focus:outline-none transition-colors" />
                                                {mobileShell && otDescSuggestions.length > 0 && (
                                                    <div className="mt-2 flex gap-1.5 overflow-x-auto pb-1 hide-scrollbar md:flex-wrap md:gap-2 md:overflow-x-visible md:pb-0">
                                                        {otDescSuggestions.slice(0, 8).map(s => (
                                                            <button
                                                                key={s}
                                                                type="button"
                                                                onClick={() => setOtDesc(s)}
                                                                className="shrink-0 min-h-[36px] touch-manipulation rounded-full border border-slate-200 bg-slate-50 px-2.5 py-1.5 text-[11px] font-medium text-slate-600 md:min-h-[40px] md:px-3 md:py-2 md:text-xs"
                                                            >
                                                                {s}
                                                            </button>
                                                        ))}
                                                    </div>
                                                )}
                                            </div>

                                            {/* OT Summary */}
                                            {selectedEmps.length > 0 && Number(otRate) > 0 && Number(otHours) > 0 && (
                                                <div className="bg-amber-50 dark:bg-amber-500/10 p-3 rounded-xl border border-amber-200 dark:border-amber-500/25 text-center">
                                                    <span className="text-sm text-amber-800 dark:text-amber-200">รวม: <span className="font-bold text-lg">{(Number(otRate) * Number(otHours) * selectedEmps.length).toLocaleString()}</span> บาท</span>
                                                    <span className="text-xs text-amber-600 dark:text-amber-300/90 block">({selectedEmps.length} คน × {otRate} บาท × {otHours} ชม.)</span>
                                                </div>
                                            )}

                                            {/* Save */}
                                            <button onClick={async () => {
                                                if (selectedEmps.length === 0) {
                                                    await sessionAlert('กรุณาเลือกพนักงาน');
                                                    return;
                                                }
                                                if (!otRate) {
                                                    await sessionAlert('กรุณาระบุค่า OT');
                                                    return;
                                                }
                                                const existingLaborIds = dayTransactions
                                                    .filter(t => t.category === 'Labor' && (t.laborStatus === 'Work' || t.laborStatus === 'OT'))
                                                    .flatMap(t => t.employeeIds || []);
                                                const alreadyRecorded = selectedEmps.filter(id => existingLaborIds.includes(id));
                                                if (alreadyRecorded.length > 0) {
                                                    const names = alreadyRecorded.map(id => getEmployeeDisplayName(employees.find(e => e.id === id)) || id).join(', ');
                                                    await sessionAlert(
                                                        `ไม่สามารถบันทึกซ้ำได้ — พนักงานต่อไปนี้มีรายการค่าแรง/OT วันที่นี้แล้ว: ${names}\nกรุณาตรวจสอบที่เมนู "ค่าแรง/ลา" หรือลบรายการเดิมก่อน`
                                                    );
                                                    return;
                                                }
                                                const rate = Number(otRate) || 0;
                                                const hours = Number(otHours) || 0;
                                                const totalAmount = rate * hours * selectedEmps.length;
                                                const empNames = selectedEmps.map(id => employees.find(e => e.id === id)?.nickname || '').join(', ');
                                                onSaveTransaction({
                                                    id: Date.now().toString(), date, employeeIds: selectedEmps,
                                                    type: 'Expense', category: 'Labor', subCategory: 'OT', laborStatus: 'OT',
                                                    amount: totalAmount, otAmount: rate, otHours: hours, otDescription: otDesc,
                                                    description: `OT ${otDesc} (${otHours}ชม.) ${selectedEmps.length}คน [${empNames}]`
                                                } as Transaction);
                                                setSelectedEmps([]); setOtRate(''); setOtHours(''); setOtDesc(''); setLaborStatus('Work');
                                            }} className="w-full py-3.5 bg-slate-800 hover:bg-slate-900 text-white text-base font-bold rounded-xl transition-colors">
                                                บันทึก
                                            </button>
                                        </div>
                                        <div className={stepActionWrapClass}>
                                            <Button variant="secondary" onClick={prevStep} className={navBtnClass}>ย้อนกลับ</Button>
                                            <Button onClick={() => void nextStep()} className={navBtnClass}>ถัดไป <ChevronRight size={18} /></Button>
                                        </div>
                                    </div>
                                )}

                                {/* === WORK MODE: Canvas layout === */}
                                {laborStatus === 'Work' && (
                                    <>
                                        {/* Employee Pool - Draggable chips */}
                                        <div className="mb-3 rounded-2xl border border-slate-200 bg-white p-3 shadow-sm">
                                            <div className="mb-2.5 flex flex-wrap items-center justify-between gap-2">
                                                <span className="text-sm font-bold text-slate-600">👥 เลือกพนักงานเพื่อย้ายลงกล่องงาน</span>
                                                <div className="flex items-center gap-2">
                                                    <span className="text-xs font-semibold text-slate-500 bg-slate-100 px-2 py-1 rounded-lg">
                                                        {filteredLaborEmployees.length}/{employees.length} คน
                                                    </span>
                                                    <input placeholder="ค้นหา..." value={laborSearch} onChange={e => setLaborSearch(e.target.value)} className="text-sm border border-slate-200 rounded-lg px-3 py-1.5 w-36 bg-slate-50 focus:bg-white focus:outline-none focus:border-indigo-300" />
                                                </div>
                                            </div>
                                            <div className="grid max-h-[180px] grid-cols-2 gap-2 overflow-y-auto rounded-xl border border-slate-200 bg-slate-50 p-2.5 sm:grid-cols-3 sm:p-3 md:max-h-[240px] md:grid-cols-4 lg:grid-cols-5">
                                                {poolVisibleEmployees.map(emp => {
                                                    const isAssigned = Object.values(workAssignments).some(ids => ids.includes(emp.id));
                                                    const isSelected = selectedEmps.includes(emp.id);
                                                    const saved = dayTransactions.find(t => t.category === 'Labor' && t.employeeIds?.includes(emp.id));
                                                    const leaveRecord = transactions.find(t => t.category === 'Labor' && (t.laborStatus === 'Leave' || t.laborStatus === 'Sick' || t.laborStatus === 'Personal') && t.employeeIds?.includes(emp.id) && t.date <= date && (t.leaveDays ? new Date(new Date(t.date).getTime() + (t.leaveDays - 1) * 86400000).toISOString().split('T')[0] >= date : t.date === date));
                                                    const isAbsent = !isAssigned && !saved && !leaveRecord;
                                                    const displayName = getEmployeeDisplayName(emp);
                                                    return (
                                                        <div key={emp.id}
                                                            draggable onDragStart={() => setDragEmployee(emp.id)} onDragEnd={() => setDragEmployee(null)}
                                                            onClick={() => setSelectedEmps(prev => prev.includes(emp.id) ? prev.filter(id => id !== emp.id) : [...prev, emp.id])}
                                                            title={leaveRecord ? `ลา: ${new Date(leaveRecord.date).toLocaleDateString('th-TH')}${leaveRecord.leaveDays ? ` (${leaveRecord.leaveDays} วัน)` : ''} - ${leaveRecord.leaveReason || leaveRecord.laborStatus}` : isAbsent && saved === undefined ? '' : ''}
                                                            className={`rounded-xl font-semibold cursor-grab active:cursor-grabbing select-none transition-all text-center touch-manipulation ${touchUI ? 'min-h-[48px] px-3 py-3 text-base sm:text-lg' : 'px-2.5 py-2 text-xs sm:text-sm'}
                                                        ${leaveRecord ? 'bg-yellow-100 text-yellow-700 border-2 border-yellow-400 ring-1 ring-yellow-200' :
                                                                    isAssigned ? 'bg-emerald-100 text-emerald-600 border border-emerald-300 opacity-50' :
                                                                        isSelected ? 'bg-indigo-600 text-white shadow-md scale-105' :
                                                                            saved ? 'bg-emerald-50 text-emerald-700 border border-emerald-200' :
                                                                                'bg-white text-slate-600 border border-slate-200 hover:border-indigo-300 hover:shadow-sm'}`}
                                                        >
                                                            {displayName}{leaveRecord ? ' 🏖️ลา' : saved && !isAssigned ? ' ✅' : ''}
                                                        </div>
                                                    );
                                                })}
                                            </div>
                                            {filteredLaborEmployees.length > poolVisibleEmployees.length && (
                                                <button
                                                    type="button"
                                                    onClick={() => setPoolVisibleEmployeeCount(prev => prev + 40)}
                                                    className="mt-2 w-full rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 text-xs font-semibold text-slate-700 hover:bg-slate-100"
                                                >
                                                    แสดงรายการเพิ่ม ({poolVisibleEmployees.length}/{filteredLaborEmployees.length})
                                                </button>
                                            )}
                                            {selectedEmps.length > 0 && <p className="text-xs text-indigo-600 mt-1.5 font-medium">เลือก {selectedEmps.length} คน — กดปุ่ม "ย้าย" ในกล่องงานด้านล่าง</p>}
                                        </div>

                                        {/* Work Category Canvas Boxes */}
                                        <div className="flex-1 overflow-y-auto mb-3">
                                            <span className="text-sm font-bold text-slate-500 mb-2 block">📋 ประเภทงาน (ลากหรือกดย้ายพนักงานใส่)</span>
                                            <div className="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-4 md:gap-4">
                                                {[...DEFAULT_WORK_CATEGORIES, ...customCategories.map(c => ({ ...c, ...getCustomCategoryStyle(c.id) }))].map(cat => {
                                                    const assigned = workAssignments[cat.id] || [];
                                                    const isCustomCategory = !DEFAULT_WORK_CATEGORY_IDS.has(cat.id);
                                                    return (
                                                        <div key={cat.id}
                                                            onDragOver={e => e.preventDefault()}
                                                            onDrop={async e => {
                                                                e.preventDefault();
                                                                if (!dragEmployee) return;
                                                                const emp = employees.find(x => x.id === dragEmployee);
                                                                const needWage = emp && (emp.baseWage == null || emp.baseWage === 0) && ensureEmployeeWage;
                                                                if (needWage) {
                                                                    try {
                                                                        await ensureEmployeeWage(emp);
                                                                    } catch {
                                                                        setDragEmployee(null);
                                                                        return;
                                                                    }
                                                                }
                                                                setWorkAssignments(prev => {
                                                                    const u = { ...prev };
                                                                    Object.keys(u).forEach(k => { u[k] = u[k].filter(id => id !== dragEmployee); });
                                                                    u[cat.id] = [...(u[cat.id] || []), dragEmployee];
                                                                    return u;
                                                                });
                                                                setDragEmployee(null);
                                                            }}
                                                            className={`rounded-xl border-2 border-dashed transition-all p-3 ${touchUI ? 'min-h-[104px]' : 'min-h-[80px]'} ${cat.bgLight} ${dragEmployee ? 'border-indigo-400 bg-indigo-50/30' : ''}`}
                                                        >
                                                            <div className="mb-1.5 flex items-start justify-between gap-2">
                                                                <span
                                                                    className={`min-w-0 max-w-[75%] rounded-lg px-2 py-1 text-[10px] font-semibold leading-tight text-white sm:text-xs ${cat.color}`}
                                                                    title={cat.label}
                                                                >
                                                                    <span className="line-clamp-2 break-words">{cat.label}</span>
                                                                </span>
                                                                <div className="flex shrink-0 items-center gap-2">
                                                                    <span className="text-xs font-bold text-slate-400">{assigned.length} คน</span>
                                                                    {isCustomCategory && (
                                                                        <button
                                                                            type="button"
                                                                            onClick={() => {
                                                                                setCustomCategories(prev => prev.filter(c => c.id !== cat.id));
                                                                                setWorkAssignments(prev => {
                                                                                    const next = { ...prev };
                                                                                    delete next[cat.id];
                                                                                    return next;
                                                                                });
                                                                            }}
                                                                            className="text-[11px] px-2 py-0.5 rounded-md border border-rose-200 text-rose-600 bg-rose-50 hover:bg-rose-100"
                                                                            title="ลบกล่องประเภทงานนี้เฉพาะวันนี้"
                                                                        >
                                                                            ลบ
                                                                        </button>
                                                                    )}
                                                                </div>
                                                            </div>
                                                            <div className="flex flex-wrap gap-1.5">
                                                                {assigned.map(eid => {
                                                                    const emp = employees.find(e => e.id === eid);
                                                                    const isHalf = halfDayEmpIds.has(eid);
                                                                    return emp ? (
                                                                        <span key={eid} className={`flex items-center gap-1 rounded-lg border bg-white font-semibold ${touchUI ? 'min-h-[44px] px-2.5 py-2 text-sm' : 'px-2 py-1 text-xs'}`}>
                                                                            {getEmployeeDisplayName(emp)}
                                                                            <button type="button" onClick={(ev) => { ev.stopPropagation(); setHalfDayEmpIds(prev => { const n = new Set(prev); if (n.has(eid)) n.delete(eid); else n.add(eid); return n; }); }} className={`rounded font-bold touch-manipulation ${touchUI ? 'min-h-10 min-w-10 px-2 text-sm' : 'min-w-[1.5rem] px-1 py-0.5 text-[10px]'} ${isHalf ? 'bg-amber-100 text-amber-700 border border-amber-300' : 'bg-slate-100 text-slate-500 border border-slate-200 hover:bg-amber-50 hover:text-amber-600'}`} title={isHalf ? 'กดเพื่อเปลี่ยนเป็นเต็มวัน' : 'กดเพื่อกำหนดมาครึ่งวัน'}>½</button>
                                                                            <button type="button" onClick={() => setWorkAssignments(prev => ({ ...prev, [cat.id]: prev[cat.id].filter(id => id !== eid) }))} className={`text-red-400 hover:text-red-600 touch-manipulation ${touchUI ? 'flex min-h-10 min-w-10 items-center justify-center text-lg' : 'ml-0.5 text-base leading-none'}`}>×</button>
                                                                        </span>) : null;
                                                                })}
                                                                {assigned.length === 0 && <span className="text-xs text-slate-400 italic">ลากหรือย้ายคนมาวาง...</span>}
                                                            </div>
                                                            {selectedEmps.length > 0 && (
                                                                <button onClick={async () => {
                                                                    for (const id of selectedEmps) {
                                                                        const emp = employees.find(x => x.id === id);
                                                                        if (emp && (emp.baseWage == null || emp.baseWage === 0) && ensureEmployeeWage) {
                                                                            try { await ensureEmployeeWage(emp); } catch { return; }
                                                                        }
                                                                    }
                                                                    setWorkAssignments(prev => {
                                                                        const u = { ...prev };
                                                                        selectedEmps.forEach(id => { Object.keys(u).forEach(k => { u[k] = (u[k] || []).filter(eid => eid !== id); }); });
                                                                        u[cat.id] = [...(u[cat.id] || []), ...selectedEmps];
                                                                        return u;
                                                                    });
                                                                    setSelectedEmps([]);
                                                                }} className={`mt-1.5 w-full rounded-lg bg-indigo-100 font-bold text-indigo-700 hover:bg-indigo-200 touch-manipulation ${touchUI ? 'min-h-[44px] py-2.5 text-sm' : 'py-1.5 text-xs'}`}>
                                                                    ⬇️ ย้าย {selectedEmps.length} คน มาที่นี่
                                                                </button>
                                                            )}
                                                        </div>
                                                    );
                                                })}
                                            </div>
                                            <div className="flex gap-2 mt-3">
                                                <input value={newCategoryName} onChange={e => setNewCategoryName(e.target.value)} placeholder="เพิ่มประเภทงานใหม่..." className="flex-1 text-sm border rounded-xl px-3 py-2" />
                                                <button onClick={() => {
                                                    const label = newCategoryName.trim();
                                                    if (!label) return;
                                                    const target = normalizeCategoryLabel(label);
                                                    addOrSelectCustomCategory(label);

                                                    // Sync with Settings so added category appears in config screens too.
                                                    setSettings?.((prev: AppSettings) => {
                                                        const currentWorkCats = prev.appDefaults?.laborWorkCategories || [];
                                                        const hasWorkCat = currentWorkCats.some(c => normalizeCategoryLabel(c.label) === target);
                                                        const generatedId = makeStableCustomCategoryId(label);
                                                        const nextWorkCats = hasWorkCat ? currentWorkCats : [...currentWorkCats, { id: generatedId, label }];

                                                        const currentJobDescriptions = prev.jobDescriptions || [];
                                                        const hasJobDescription = currentJobDescriptions.some(d => normalizeCategoryLabel(d) === target);
                                                        const nextJobDescriptions = hasJobDescription ? currentJobDescriptions : [...currentJobDescriptions, label];

                                                        if (hasWorkCat && hasJobDescription) return prev;
                                                        return {
                                                            ...prev,
                                                            jobDescriptions: nextJobDescriptions,
                                                            appDefaults: {
                                                                ...(prev.appDefaults || {}),
                                                                laborWorkCategories: nextWorkCats,
                                                            },
                                                        };
                                                    });

                                                }} className="px-4 py-2 bg-purple-500 text-white text-sm rounded-xl hover:bg-purple-600 font-bold">+ เพิ่ม</button>
                                            </div>
                                            {settingJobDescriptionSuggestions.length > 0 && (
                                                <div className="mt-2">
                                                    <p className="text-xs font-medium text-slate-500 mb-1">ดึงจาก ตั้งค่า &gt; รายละเอียดงาน:</p>
                                                    <div className="flex flex-wrap gap-1.5">
                                                        {settingJobDescriptionSuggestions.slice(0, 12).map((label) => (
                                                            <button
                                                                key={label}
                                                                type="button"
                                                                onClick={() => addOrSelectCustomCategory(label)}
                                                                className="px-2 py-1 text-xs rounded-lg border border-violet-200 bg-violet-50 text-violet-700 hover:bg-violet-100"
                                                                title={`เพิ่มประเภทงาน: ${label}`}
                                                            >
                                                                + {label}
                                                            </button>
                                                        ))}
                                                    </div>
                                                </div>
                                            )}
                                        </div>

                                        {/* เมนูย่อย ล้างทรายที่บ้าน — เมื่อมีพนักงานในประเภทนี้ */}
                                        {(workAssignments['washHome']?.length ?? 0) > 0 && (() => {
                                            const sandTxToday = dayTransactions.filter((t: Transaction) => t.category === 'DailyLog' && t.subCategory === 'Sand');
                                            const totalDrumsFromSand = sandTxToday.length > 0 ? Math.max(0, ...sandTxToday.map((t: Transaction) => (t as any).drumsObtained ?? 0)) : 0;
                                            const homeDrums = Number(drumsWashedAtHome) || 0;
                                            const remainingDrums = Math.max(0, totalDrumsFromSand - homeDrums);
                                            return (
                                                <div className="mb-4 p-4 rounded-xl border-2 border-teal-200 bg-teal-50/80">
                                                    <h4 className="text-sm font-bold text-teal-800 mb-3 flex items-center gap-2">🏠 ล้างทรายที่บ้าน</h4>
                                                    <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-2">
                                                        <div>
                                                            <label className="text-xs font-medium text-teal-700 mb-1 block">จำนวนถังที่ล้างวันนี้ (ที่บ้าน)</label>
                                                            <input type="number" min="0" placeholder="0" value={drumsWashedAtHome} onChange={e => setDrumsWashedAtHome(e.target.value)}
                                                                className="w-full px-3 py-2 border border-teal-200 rounded-lg text-center font-semibold text-teal-800 bg-white focus:border-teal-500 focus:outline-none" />
                                                            <span className="text-xs text-teal-600 ml-1">ถัง</span>
                                                        </div>
                                                        <div className="flex flex-col justify-center p-2 bg-white rounded-lg border border-teal-100">
                                                            <span className="text-[10px] text-teal-600">จำนวนถังทั้งหมด</span>
                                                            <span className="text-lg font-bold text-teal-800">{(totalDrumsFromSand)}</span>
                                                            <span className="text-[10px] text-teal-500">ถัง (จากบันทึกการล้างทราย)</span>
                                                        </div>
                                                        <div className="flex flex-col justify-center p-2 bg-white rounded-lg border border-teal-100">
                                                            <span className="text-[10px] text-teal-600">จำนวนถังคงเหลือ</span>
                                                            <span className="text-lg font-bold text-teal-800">{remainingDrums}</span>
                                                            <span className="text-[10px] text-teal-500">ถัง</span>
                                                        </div>
                                                    </div>
                                                </div>
                                            );
                                        })()}

                                        <div className="pt-2 border-t space-y-2">
                                            <Button onClick={async () => {
                                                const allAssigned = Object.entries(workAssignments).flatMap(([, ids]) => ids);
                                                const driverWorkedToday = dayTransactions
                                                    .filter(t => t.category === 'Vehicle' && !!t.driverId)
                                                    .map(t => t.driverId as string);
                                                const allEmps = [...new Set([...allAssigned, ...driverWorkedToday])];
                                                if (allEmps.length === 0) {
                                                    await sessionAlert('กรุณาลากพนักงานใส่กล่องงานก่อน หรือมีรายการใช้รถที่ระบุคนขับในวันนี้');
                                                    return;
                                                }
                                                const existingLaborIds = dayTransactions
                                                    .filter(t => t.category === 'Labor' && (t.laborStatus === 'Work' || t.laborStatus === 'OT'))
                                                    .flatMap(t => t.employeeIds || []);
                                                const alreadyRecorded = allEmps.filter(id => existingLaborIds.includes(id));
                                                if (alreadyRecorded.length > 0) {
                                                    const names = alreadyRecorded.map(id => getEmployeeDisplayName(employees.find(e => e.id === id)) || id).join(', ');
                                                    await sessionAlert(
                                                        `ไม่สามารถบันทึกซ้ำได้ — พนักงานต่อไปนี้บันทึกค่าแรงวันที่นี้แล้ว: ${names}\nกรุณาตรวจสอบที่เมนู "ค่าแรง/ลา" หรือลบรายการเดิมก่อน`
                                                    );
                                                    return;
                                                }
                                                const base = { id: Date.now().toString(), date, employeeIds: allEmps };
                                                const allCats = [...DEFAULT_WORK_CATEGORIES, ...customCategories.map(c => ({ ...c, color: '', bgLight: '' }))];
                                                const desc = Object.entries(workAssignments).filter(([, ids]) => ids.length > 0).map(([catId, ids]) => {
                                                    const cat = allCats.find(c => c.id === catId); const names = ids.map(id => employees.find(e => e.id === id)?.nickname || '').join(',');
                                                    return `${cat?.label || catId}: ${names}`;
                                                }).join(' | ');
                                                const driverOnlyIds = driverWorkedToday.filter(id => !allAssigned.includes(id));
                                                const driverOnlyNames = [...new Set(driverOnlyIds)]
                                                    .map(id => getEmployeeDisplayName(employees.find(e => e.id === id)))
                                                    .filter(Boolean)
                                                    .join(', ');
                                                const workTypeByEmployee: Record<string, 'FullDay' | 'HalfDay'> = {};
                                                let total = 0;
                                                try {
                                                    for (const id of allEmps) {
                                                        const e = employees.find(x => x.id === id);
                                                        if (!e) continue;
                                                        const wage = ensureEmployeeWage ? await ensureEmployeeWage(e) : (e.baseWage ?? 0);
                                                        const wt = halfDayEmpIds.has(id) ? 'HalfDay' : 'FullDay';
                                                        workTypeByEmployee[id] = wt;
                                                        const daily = toDailyWage(e, wage);
                                                        total += wt === 'HalfDay' ? daily / 2 : daily;
                                                    }
                                                } catch {
                                                    return;
                                                }
                                                const halfCount = allEmps.filter(id => halfDayEmpIds.has(id)).length;
                                                const workLabel = halfCount === 0 ? 'เต็มวัน' : halfCount === allEmps.length ? 'ครึ่งวัน' : `เต็มวัน ${allEmps.length - halfCount} คน, ครึ่งวัน ${halfCount} คน`;
                                                const drumsHome = (workAssignments['washHome']?.length ?? 0) > 0 ? (Number(drumsWashedAtHome) || 0) : undefined;
                                                const t = {
                                                    ...base,
                                                    type: 'Expense',
                                                    category: 'Labor',
                                                    subCategory: 'Attendance',
                                                    laborStatus: 'Work',
                                                    workTypeByEmployee,
                                                    description: `ค่าแรง (${allEmps.length} คน) ${workLabel}${desc ? ` [${desc}]` : ''}${driverOnlyNames ? ` [คนขับจากงานใช้รถ: ${driverOnlyNames}]` : ''}`,
                                                    amount: total,
                                                    workAssignments: { ...workAssignments },
                                                    customWorkCategories: [...customCategories],
                                                    drumsWashedAtHome: drumsHome
                                                };
                                                onSaveTransaction(t as any); setSelectedEmps([]); setWorkAssignments({}); setHalfDayEmpIds(new Set()); if (drumsHome !== undefined) setDrumsWashedAtHome('');
                                            }} className="w-full bg-emerald-600 hover:bg-emerald-700 py-3 text-base focus-ring-strong" data-hotkey-primary="true">
                                                <CheckCircle2 size={18} className="mr-2" /> บันทึกค่าแรง ({[...new Set([
                                                    ...Object.values(workAssignments).flat(),
                                                    ...dayTransactions.filter(t => t.category === 'Vehicle' && !!t.driverId).map(t => t.driverId as string),
                                                ])].length} คน)
                                            </Button>
                                            <div className={stepActionWrapClass}>
                                                <Button variant="secondary" onClick={prevStep} className={navBtnClass}>ย้อนกลับ</Button>
                                                <Button onClick={() => void nextStep()} className={navBtnClass}>ถัดไป <ChevronRight size={18} /></Button>
                                            </div>
                                        </div>
                                    </>
                                )}
                            </div>
                        )}

                        {/* Step 2: Vehicle */}
                        {step === 2 && (
                            <div className="h-full flex flex-col animate-slide-up">
                                <h3 className="font-bold text-lg mb-4 flex items-center gap-2"><Truck className="text-amber-500" /> บันทึกการใช้รถ</h3>
                                <div className="mb-4 flex gap-2 overflow-x-auto pb-2">
                                    {dayTransactions.filter(t => t.category === 'Vehicle').map(t => (
                                        <div
                                            key={t.id}
                                            className={`min-w-[200px] max-w-[240px] shrink-0 relative rounded-lg border p-2 pr-9 text-xs transition-colors ${editingVehicleTxId === t.id ? 'border-amber-400 bg-amber-100/80 ring-1 ring-amber-300' : 'border-amber-100 bg-amber-50'}`}
                                        >
                                            <div className="absolute right-1 top-1 flex gap-0.5">
                                                <button
                                                    type="button"
                                                    title="แก้ไข"
                                                    onClick={() => loadVehicleForEdit(t)}
                                                    className="rounded-md p-1.5 text-amber-700 hover:bg-amber-200/80 active:bg-amber-300/80"
                                                >
                                                    <Pencil size={14} />
                                                </button>
                                                {onDeleteTransaction && (
                                                    <button
                                                        type="button"
                                                        title="ลบ"
                                                        onClick={async () => {
                                                            if (!(await sessionConfirm('ลบรายการรถนี้?', { title: 'ยืนยันการลบ' }))) return;
                                                            onDeleteTransaction(t.id);
                                                            if (editingVehicleTxId === t.id) {
                                                                setEditingVehicleTxId(null);
                                                                setVehCar('');
                                                                setVehDriver('');
                                                                setVehMachineWage('');
                                                                setVehWage('');
                                                                setVehDetails('');
                                                                setVehWorkType('FullDay');
                                                            }
                                                        }}
                                                        className="rounded-md p-1.5 text-amber-700 hover:bg-red-100 hover:text-red-600 active:bg-red-200"
                                                    >
                                                        <Trash2 size={14} />
                                                    </button>
                                                )}
                                            </div>
                                            <div className="font-bold text-amber-900 pr-1">{t.vehicleId}</div>
                                            <div className="text-amber-800/90 text-[10px] font-semibold">{(t as any).workType === 'HalfDay' ? 'ครึ่งวัน' : 'เต็มวัน'}</div>
                                            <div className="text-amber-700 line-clamp-3">{t.workDetails}</div>
                                            <div className="mt-1 text-[10px] font-medium text-amber-900/80">฿{(t.amount ?? 0).toLocaleString()}</div>
                                        </div>
                                    ))}
                                    {dayTransactions.filter(t => t.category === 'Vehicle').length === 0 && <span className="text-sm text-slate-400 italic">ยังไม่มีรายการรถวันนี้</span>}
                                </div>
                                <div className="space-y-4 bg-white p-4 rounded-xl border mb-4">
                                    {editingVehicleTxId && (
                                        <div className="flex items-center justify-between gap-2 rounded-lg border border-amber-200 bg-amber-50/80 px-3 py-2 text-xs text-amber-900">
                                            <span className="font-semibold">กำลังแก้ไขรายการรถ</span>
                                            <button
                                                type="button"
                                                data-hotkey-cancel="true"
                                                className="shrink-0 rounded-lg border border-amber-300 bg-white px-2 py-1 font-medium text-amber-800 hover:bg-amber-100"
                                                onClick={() => {
                                                    setEditingVehicleTxId(null);
                                                    setVehCar('');
                                                    setVehDriver('');
                                                    setVehMachineWage('');
                                                    setVehWage('');
                                                    setVehDetails('');
                                                    setVehWorkType('FullDay');
                                                }}
                                            >
                                                ยกเลิก
                                            </button>
                                        </div>
                                    )}
                                    <p className="text-xs text-slate-500">คนขับ: แสดงเฉพาะพนักงานที่มีตำแหน่ง &quot;คนขับรถ&quot; — เลือกแล้วเบี้ยเลี้ยงจะใช้ค่าแรงในวันนั้น</p>
                                    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 md:gap-5">
                                        <Select label="รถ/เครื่องจักร" value={vehCar} onChange={(e: any) => setVehCar(e.target.value)}><option value="">-- เลือกรถ --</option>{settings.cars.map(c => <option key={c}>{c}</option>)}</Select>
                                        <Select label="คนขับ" value={vehDriver} onChange={(e: any) => {
                                            const val = e.target.value;
                                            setVehDriver(val);
                                            void applyVehicleDriverAllowance(val, vehWorkType);
                                        }}>
                                            <option value="">-- เลือกคนขับ --</option>
                                            {driverEmployees.map(e => <option key={e.id} value={e.id}>{e.nickname || e.name || e.id}</option>)}
                                        </Select>
                                    </div>
                                    <div className="flex flex-col gap-2">
                                        <span className="text-sm font-medium text-slate-700 dark:text-slate-200">การทำงานของคนขับ</span>
                                        <div className="flex flex-wrap gap-2">
                                            <button
                                                type="button"
                                                onClick={() => {
                                                    setVehWorkType('FullDay');
                                                    void applyVehicleDriverAllowance(vehDriver, 'FullDay');
                                                }}
                                                className={`px-3 py-1.5 rounded-lg text-sm font-medium border transition-colors ${vehWorkType === 'FullDay' ? 'bg-emerald-600 text-white border-emerald-600' : 'bg-white dark:bg-white/5 text-slate-600 dark:text-slate-300 border-slate-200 dark:border-white/15 hover:border-emerald-300'}`}
                                            >
                                                เต็มวัน
                                            </button>
                                            <button
                                                type="button"
                                                onClick={() => {
                                                    setVehWorkType('HalfDay');
                                                    void applyVehicleDriverAllowance(vehDriver, 'HalfDay');
                                                }}
                                                className={`px-3 py-1.5 rounded-lg text-sm font-medium border transition-colors ${vehWorkType === 'HalfDay' ? 'bg-amber-500 text-white border-amber-500' : 'bg-white dark:bg-white/5 text-slate-600 dark:text-slate-300 border-slate-200 dark:border-white/15 hover:border-amber-300'}`}
                                            >
                                                ครึ่งวัน
                                            </button>
                                        </div>
                                        <p className="text-xs text-slate-500 dark:text-slate-400">ครึ่งวัน = เบี้ยเลี้ยงคนขับครึ่งหนึ่งของค่าแรงรายวัน (ค่าจ้างรถไม่เปลี่ยน)</p>
                                    </div>
                                    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 md:gap-5">
                                        <div className="space-y-2">
                                            <Input label="ค่าจ้างรถ (บาท)" type="number" value={vehMachineWage} onChange={(e: any) => setVehMachineWage(e.target.value)} />
                                            <div>
                                                <div className="flex flex-wrap gap-2">
                                                    {vehicleMachineWageTemplates.map(v => (
                                                        <button
                                                            key={`vmw-${v}`}
                                                            type="button"
                                                            onClick={() => setVehMachineWage(v)}
                                                            className="touch-manipulation rounded-lg border border-amber-200/90 bg-amber-50/90 px-3 py-2 text-sm font-bold text-amber-900 shadow-sm transition hover:bg-amber-100 dark:border-amber-500/35 dark:bg-amber-500/15 dark:text-amber-100 dark:hover:bg-amber-500/25"
                                                        >
                                                            {Number(v).toLocaleString()}
                                                        </button>
                                                    ))}
                                                </div>
                                            </div>
                                        </div>
                                        <div className="space-y-2">
                                            <Input label="เบี้ยเลี้ยงคนขับ (ใช้ค่าแรงในวันนั้น)" type="number" value={vehWage} onChange={(e: any) => setVehWage(e.target.value)} />
                                            <div>
                                                <div className="flex flex-wrap gap-2">
                                                    {vehicleDriverWageTemplates.map(v => (
                                                        <button
                                                            key={`vdw-${v}`}
                                                            type="button"
                                                            onClick={() => setVehWage(v)}
                                                            className="touch-manipulation rounded-lg border border-emerald-200/90 bg-emerald-50/90 px-3 py-2 text-sm font-bold text-emerald-900 shadow-sm transition hover:bg-emerald-100 dark:border-emerald-500/35 dark:bg-emerald-500/15 dark:text-emerald-100 dark:hover:bg-emerald-500/25"
                                                        >
                                                            {Number(v).toLocaleString()}
                                                        </button>
                                                    ))}
                                                </div>
                                            </div>
                                        </div>
                                    </div>
                                    <div className="flex flex-col gap-1">
                                        <label className="text-sm font-medium text-slate-700 dark:text-slate-200">รายละเอียดงาน</label>
                                        <textarea className="border border-slate-200 dark:border-white/15 rounded-xl p-2 text-sm bg-white dark:bg-white/5 text-slate-800 dark:text-slate-100 placeholder:text-slate-400" rows={2} value={vehDetails} onChange={e => setVehDetails(e.target.value)} placeholder="ขนดิน, ปรับพื้นที่..." />
                                        {mobileShell && vehicleDetailSuggestions.length > 0 && (
                                            <div className="mt-1.5 flex gap-1.5 overflow-x-auto pb-1 hide-scrollbar md:flex-wrap md:gap-2 md:overflow-x-visible md:pb-0">
                                                {vehicleDetailSuggestions.slice(0, 8).map(s => (
                                                    <button
                                                        key={s}
                                                        type="button"
                                                        onClick={() => setVehDetails(s)}
                                                        className="shrink-0 min-h-[36px] touch-manipulation rounded-full border border-slate-200 bg-slate-50 px-2.5 py-1.5 text-[11px] font-medium text-slate-600 md:min-h-[40px] md:px-3 md:py-2 md:text-xs"
                                                    >
                                                        {s}
                                                    </button>
                                                ))}
                                            </div>
                                        )}
                                    </div>
                                    <Button onClick={async () => {
                                        if (!vehCar || !vehDriver) {
                                            await sessionAlert('ข้อมูลไม่ครบ');
                                            return;
                                        }
                                        const vehicleWarnings: string[] = [];
                                        const duplicateVeh = dayTransactions.find(t =>
                                            t.category === 'Vehicle' &&
                                            t.id !== editingVehicleTxId &&
                                            t.vehicleId === vehCar &&
                                            t.driverId === vehDriver &&
                                            ((t.workType || 'FullDay') === vehWorkType)
                                        );
                                        if (duplicateVeh) vehicleWarnings.push(`มีรายการรถคันนี้กับคนขับนี้อยู่แล้วในวันนี้ (${vehCar})`);
                                        if ((Number(vehMachineWage) || 0) < 0 || (Number(vehWage) || 0) < 0) vehicleWarnings.push('ค่าจ้างรถหรือเบี้ยเลี้ยงเป็นค่าติดลบ');
                                        if ((Number(vehMachineWage) || 0) > 50000) vehicleWarnings.push('ค่าจ้างรถสูงกว่าปกติมาก');
                                        if (!(await shouldContinueWithWarning(vehicleWarnings, 'ตรวจพบรายการรถที่อาจไม่ถูกต้อง'))) return;
                                        const dayLabel = vehWorkType === 'HalfDay' ? 'ครึ่งวัน' : 'เต็มวัน';
                                        const id = editingVehicleTxId || Date.now().toString();
                                        onSaveTransaction({
                                            id, date, type: 'Expense', category: 'Vehicle',
                                            description: `รถ: ${vehCar} (${vehDetails}) [${dayLabel}]`, amount: Number(vehWage) + Number(vehMachineWage),
                                            vehicleId: vehCar, driverId: vehDriver, vehicleWage: Number(vehMachineWage), driverWage: Number(vehWage),
                                            workDetails: vehDetails, location: vehLocation, workType: vehWorkType
                                        } as Transaction);
                                        setEditingVehicleTxId(null);
                                        setVehCar(''); setVehDetails(''); setVehWage(''); setVehMachineWage(''); setVehWorkType('FullDay');
                                    }} className="w-full bg-amber-500 hover:bg-amber-600 focus-ring-strong" data-hotkey-primary="true">{editingVehicleTxId ? 'อัปเดตรายการรถ' : 'บันทึกรายการรถ'}</Button>
                                </div>
                                <div className={stepActionWrapClass}>
                                    <Button variant="secondary" onClick={prevStep} className={navBtnClass}>ย้อนกลับ</Button>
                                    <Button onClick={() => void nextStep()} className={navBtnClass}>ถัดไป <ChevronRight size={18} /></Button>
                                </div>
                            </div>
                        )}

                        {/* Step 3: Vehicle Trips - Canvas Style */}
                        {step === 3 && (
                            <div className="h-full flex flex-col animate-slide-up">
                                {/* Header with date and saved totals */}
                                <div className="flex flex-col gap-2 mb-4">
                                    <div className="flex justify-between items-center">
                                        <h3 className="font-bold text-lg flex items-center gap-2 text-slate-800 dark:text-slate-100"><Truck className="text-blue-500 dark:text-blue-400" /> บันทึกรถและจำนวนเที่ยวรถ</h3>
                                        {(() => {
                                            const savedTrips = dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'VehicleTrip');
                                            const savedTotalTrips = savedTrips.reduce((sum, t) => sum + ((t as any).perCarTrips || 0), 0);
                                            const savedTotalCubic = savedTrips.reduce((sum, t) => sum + ((t as any).perCarCubic || 0), 0);
                                            const displayTrips = totalTrips > 0 ? totalTrips : savedTotalTrips;
                                            const displayCubic = (() => {
                                                if (totalTrips <= 0) return savedTotalCubic;
                                                const activeCars = tripEntries.filter(e => e.vehicle);
                                                if (activeCars.length === 0) return 0;
                                                const tripsPerCar = Math.floor(totalTrips / activeCars.length);
                                                const remainder = totalTrips % activeCars.length;
                                                return activeCars.reduce((sum, entry, idx) => {
                                                    const carTrips = tripsPerCar + (idx < remainder ? 1 : 0);
                                                    const carCubicPerTrip = Number(entry.cubicPerTrip) || detectDefaultCubicPerTrip(entry.vehicle, 3);
                                                    return sum + (carTrips * carCubicPerTrip);
                                                }, 0);
                                            })();
                                            return (
                                                <div className="flex gap-2">
                                                    <div className={`${displayTrips > 0 ? 'bg-blue-600' : 'bg-slate-400'} text-white px-3 py-2 rounded-xl text-xs font-bold shadow-md`}>
                                                        {displayTrips} เที่ยว
                                                    </div>
                                                    <div className={`${displayCubic > 0 ? 'bg-emerald-600' : 'bg-slate-400'} text-white px-3 py-2 rounded-xl text-xs font-bold shadow-md`}>
                                                        {displayCubic} คิว
                                                    </div>
                                                </div>
                                            );
                                        })()}
                                    </div>
                                    <div className="text-sm text-slate-500 dark:text-slate-400 flex items-center gap-1.5">
                                        📅 วันที่: <span className="font-semibold text-indigo-600 dark:text-indigo-400">{new Date(date).toLocaleDateString('th-TH', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}</span>
                                    </div>
                                </div>

                                {/* Morning / Afternoon Trip Counts + Cubic per trip */}
                                <div className="bg-gradient-to-r from-amber-50 to-blue-50 dark:from-amber-500/10 dark:to-blue-500/10 p-4 rounded-xl border border-amber-100 dark:border-white/10 mb-4">
                                    <p className="text-sm font-bold text-slate-700 dark:text-slate-200 mb-1">จำนวนเที่ยวรวม</p>
                                    <p className="text-xs text-slate-500 dark:text-slate-400 mb-3">เว้นว่างได้ หากวันนี้ใช้รถขนงานอย่างอื่นและไม่มีการวิ่งเที่ยว</p>
                                    <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 md:gap-4">
                                        <div className="space-y-2">
                                            <label className="mb-1 block text-xs font-medium text-amber-700 dark:text-amber-300">☀️ ช่วงเช้า (เที่ยว)</label>
                                            <NumberPickerInput
                                                placeholder="0"
                                                value={tripMorning}
                                                onChange={setTripMorning}
                                                listMin={0}
                                                listMax={200}
                                                scrollAnchor={90}
                                                min={0}
                                                className="w-full px-3 py-2.5 border-2 border-amber-200 bg-white text-center text-lg font-bold text-amber-800 transition-colors focus:border-amber-400 focus:outline-none dark:border-amber-500/35 dark:bg-white/5 dark:text-amber-200"
                                            />
                                        </div>
                                        <div className="space-y-2">
                                            <label className="mb-1 block text-xs font-medium text-blue-700 dark:text-blue-300">🌙 ช่วงบ่าย (เที่ยว)</label>
                                            <NumberPickerInput
                                                placeholder="0"
                                                value={tripAfternoon}
                                                onChange={setTripAfternoon}
                                                listMin={0}
                                                listMax={200}
                                                scrollAnchor={90}
                                                min={0}
                                                className="w-full px-3 py-2.5 border-2 border-blue-200 bg-white text-center text-lg font-bold text-blue-800 transition-colors focus:border-blue-400 focus:outline-none dark:border-blue-500/35 dark:bg-white/5 dark:text-blue-200"
                                            />
                                        </div>
                                    </div>
                                    {totalTrips > 0 && (() => {
                                        const validCount = tripEntries.filter(e => e.vehicle).length || 1;
                                        const tripsPerCar = Math.floor(totalTrips / validCount);
                                        const remainder = totalTrips % validCount;
                                        // Calculate total cubic from each car's own cubic-per-trip setting
                                        let displayTotalCubic = 0;
                                        tripEntries.filter(e => e.vehicle).forEach((entry, idx) => {
                                            const carTrips = tripsPerCar + (idx < remainder ? 1 : 0);
                                            const carCubicPerTrip = Number(entry.cubicPerTrip) || detectDefaultCubicPerTrip(entry.vehicle, 3);
                                            displayTotalCubic += carTrips * carCubicPerTrip;
                                        });
                                        if (validCount <= 1) displayTotalCubic = totalTrips * (Number(tripEntries[0]?.cubicPerTrip) || detectDefaultCubicPerTrip(tripEntries[0]?.vehicle || '', 3));
                                        return (
                                            <div className="mt-3 p-3 bg-white/70 rounded-lg text-sm font-medium text-slate-600 space-y-1">
                                                <div className="text-center">
                                                    รวม <span className="font-bold text-blue-700">{totalTrips}</span> เที่ยว ÷ <span className="font-bold text-purple-700">{validCount}</span> คัน = <span className="font-bold text-indigo-700">{tripsPerCar}{remainder > 0 ? `~${tripsPerCar + 1}` : ''}</span> เที่ยว/คัน
                                                </div>
                                                <div className="text-center">
                                                    รวมทราย <span className="font-bold text-lg text-rose-600">{displayTotalCubic} คิว</span>
                                                    <span className="text-xs text-slate-400 ml-1">(คำนวณตามคิว/เที่ยวรายคัน)</span>
                                                </div>
                                            </div>
                                        );
                                    })()}
                                </div>

                                {/* Saved entries from today */}
                                {dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'VehicleTrip').length > 0 && (
                                    <div className="mb-4 flex gap-2 overflow-x-auto pb-2">
                                        {dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'VehicleTrip').map(t => (
                                            <div key={t.id} className="min-w-[200px] p-2.5 bg-emerald-50 border border-emerald-200 rounded-lg text-xs">
                                                <div className="font-bold text-emerald-900">✅ {t.vehicleId}</div>
                                                <div className="text-emerald-700 font-semibold">{(t as any).perCarTrips || (t as any).tripCount} เที่ยว • {(t as any).perCarCubic || (t as any).totalCubic || 0} คิว</div>
                                                <div className="text-emerald-600 mt-0.5">{t.workDetails || '-'}</div>
                                                <div className="text-emerald-500/70 mt-1 text-[10px]">📅 {new Date(t.date).toLocaleDateString('th-TH', { day: 'numeric', month: 'short', year: '2-digit' })}</div>
                                            </div>
                                        ))}
                                    </div>
                                )}

                                {/* Canvas: Vehicle Cards */}
                                <p className="text-sm font-medium text-slate-500 mb-2">เลือกรถและคนขับ ({tripEntries.length} คัน)</p>
                                <div className="flex-1 overflow-y-auto space-y-3 mb-4 pr-1">
                                    {tripEntries.map((entry, idx) => (
                                        <div key={entry.id} className="relative bg-white p-4 rounded-xl border-2 border-blue-100 hover:border-blue-300 shadow-sm hover:shadow-md transition-all">
                                            <div className="flex justify-between items-center mb-3">
                                                <span className="text-xs font-bold text-blue-500 bg-blue-50 px-2 py-1 rounded-lg">🚛 คันที่ {idx + 1}</span>
                                                {tripEntries.length > 1 && (
                                                    <button onClick={() => removeTripCard(entry.id)} className="p-1.5 text-slate-300 hover:text-red-500 hover:bg-red-50 rounded-lg transition-colors" title="ลบ">
                                                        <Trash2 size={14} />
                                                    </button>
                                                )}
                                            </div>
                                            <div className="mb-2 grid grid-cols-1 gap-3 sm:grid-cols-2 md:mb-3 md:gap-4">
                                                <Select label="รถ" value={entry.vehicle} onChange={(e: any) => {
                                                    const nextVehicle = e.target.value;
                                                    setTripEntries(prev => prev.map(item => {
                                                        if (item.id !== entry.id) return item;
                                                        const autoCubic = detectDefaultCubicPerTrip(nextVehicle, 3);
                                                        return {
                                                            ...item,
                                                            vehicle: nextVehicle,
                                                            cubicPerTrip: item.cubicPerTrip || String(autoCubic),
                                                        };
                                                    }));
                                                }}>
                                                    <option value="">-- เลือกรถ --</option>
                                                    {settings.cars.map(c => <option key={c}>{c}</option>)}
                                                </Select>
                                                <Select label="คนขับ" value={entry.driver} onChange={(e: any) => updateTripCard(entry.id, 'driver', e.target.value)}>
                                                    <option value="">-- เลือกคนขับ --</option>
                                                    {driverEmployees.map(e => <option key={e.id} value={e.id}>{e.nickname || e.name}</option>)}
                                                </Select>
                                            </div>
                                            <div className="mb-2 grid grid-cols-1 gap-3 sm:grid-cols-2 md:gap-4">
                                                <div className="space-y-2">
                                                    <NumberPickerInput
                                                        value={entry.cubicPerTrip}
                                                        onChange={(v) => updateTripCard(entry.id, 'cubicPerTrip', v)}
                                                        listMin={3}
                                                        listMax={8}
                                                        scrollAnchor={6}
                                                        min={0}
                                                        placeholder={String(detectDefaultCubicPerTrip(entry.vehicle, 3))}
                                                        className="w-full px-4 py-2.5 rounded-xl border border-slate-200 dark:border-white/20 focus:outline-none focus:ring-2 focus:ring-emerald-500/20 dark:focus:ring-amber-500/30 focus:border-emerald-500 dark:focus:border-amber-500/50 transition-all bg-white dark:bg-white/5 text-slate-800 dark:text-slate-100 placeholder:text-slate-400 dark:placeholder:text-slate-500"
                                                    />
                                                    <div className="flex flex-wrap gap-2">
                                                        {['3', '6'].map(v => (
                                                            <button
                                                                key={`${entry.id}-cubic-${v}`}
                                                                type="button"
                                                                onClick={() => updateTripCard(entry.id, 'cubicPerTrip', v)}
                                                                className="touch-manipulation rounded-lg border border-blue-200/90 bg-blue-50/80 px-3 py-2 text-xs font-bold text-blue-800 shadow-sm transition hover:bg-blue-100 dark:border-blue-500/35 dark:bg-blue-500/15 dark:text-blue-100 dark:hover:bg-blue-500/25"
                                                            >
                                                                {v}
                                                            </button>
                                                        ))}
                                                    </div>
                                                </div>
                                                <div className="rounded-xl border border-slate-200 bg-slate-50 p-2.5 text-xs text-slate-500 flex items-center">
                                                    ค่าแนะนำ: 6 ล้อ = 3, 10 ล้อ = 6 (แก้เองได้รายวัน)
                                                </div>
                                            </div>
                                            <Input label="รายละเอียดงาน" value={entry.work} onChange={(e: any) => updateTripCard(entry.id, 'work', e.target.value)} placeholder="ขนดิน, ขนทราย..." />
                                            {['ขนดิน', 'ขนหิน', 'ขนทราย', 'ซื้อของ'].length > 0 && (
                                                <div className="mt-1.5 flex gap-1.5 overflow-x-auto pb-1 hide-scrollbar md:flex-wrap md:gap-2 md:overflow-x-visible md:pb-0">
                                                    {['ขนดิน', 'ขนหิน', 'ขนทราย', 'ซื้อของ'].map(s => (
                                                        <button
                                                            key={`${entry.id}-${s}`}
                                                            type="button"
                                                            onClick={() => updateTripCard(entry.id, 'work', s)}
                                                            className="shrink-0 min-h-[36px] touch-manipulation rounded-full border border-slate-200 bg-slate-50 px-2.5 py-1.5 text-[11px] font-medium text-slate-600 md:min-h-[40px] md:px-3 md:py-2 md:text-xs"
                                                        >
                                                            {s}
                                                        </button>
                                                    ))}
                                                </div>
                                            )}
                                        </div>
                                    ))}

                                    <button onClick={addTripCard} className="w-full py-4 border-2 border-dashed border-slate-200 hover:border-blue-400 rounded-xl text-slate-400 hover:text-blue-500 flex items-center justify-center gap-2 transition-all hover:bg-blue-50/50">
                                        <Plus size={20} /> เพิ่มรถอีกคัน
                                    </button>
                                </div>

                                {/* Save all + navigation */}
                                <div className="pt-4 border-t space-y-3">
                                    <Button onClick={async () => {
                                        const valid = tripEntries.filter(e => e.vehicle);
                                        if (valid.length === 0) {
                                            await sessionAlert('กรุณาเลือกรถอย่างน้อย 1 คัน');
                                            return;
                                        }
                                        const tripWarnings: string[] = [];
                                        const duplicatedVehicleInForm = valid.length !== new Set(valid.map(v => v.vehicle)).size;
                                        if (duplicatedVehicleInForm) tripWarnings.push('มีการเลือกรถคันเดิมซ้ำในฟอร์มเดียวกัน');
                                        if (totalTrips <= 0) tripWarnings.push('จำนวนเที่ยวรวมเป็น 0');
                                        if (totalTrips > 300) tripWarnings.push('จำนวนเที่ยวรวมสูงกว่าปกติมาก');
                                        const hasExistingTripToday = dayTransactions.some(t => t.category === 'DailyLog' && t.subCategory === 'VehicleTrip');
                                        if (hasExistingTripToday) tripWarnings.push('วันนี้มีรายการเที่ยวรถอยู่แล้ว อาจเป็นการบันทึกซ้ำ');
                                        if (!(await shouldContinueWithWarning(tripWarnings, 'ตรวจพบรายการเที่ยวรถที่อาจซ้ำ/ผิดปกติ'))) return;
                                        const tripsPerCar = Math.floor(totalTrips / valid.length);
                                        const remainder = totalTrips % valid.length;
                                        valid.forEach((entry, idx) => {
                                            const driverName = employees.find(e => e.id === entry.driver)?.nickname || '';
                                            const carTrips = tripsPerCar + (idx < remainder ? 1 : 0);
                                            const carCubicPerTrip = Number(entry.cubicPerTrip) || detectDefaultCubicPerTrip(entry.vehicle, 3);
                                            const carCubic = carTrips * carCubicPerTrip;
                                            onSaveTransaction({
                                                id: Date.now().toString() + entry.id, date, type: 'Expense', category: 'DailyLog', subCategory: 'VehicleTrip',
                                                description: `${entry.vehicle}${driverName ? ` (${driverName})` : ''}: ${carTrips} เที่ยว × ${carCubicPerTrip} คิว = ${carCubic} คิว - ${entry.work}`, amount: 0,
                                                vehicleId: entry.vehicle, driverId: entry.driver, tripCount: totalTrips,
                                                tripMorning: Number(tripMorning) || 0, tripAfternoon: Number(tripAfternoon) || 0,
                                                cubicPerTrip: carCubicPerTrip, totalCubic: carCubic,
                                                perCarTrips: carTrips, perCarCubic: carCubic,
                                                workDetails: entry.work
                                            } as Transaction);
                                        });
                                        setTripEntries([{ id: Date.now().toString(), vehicle: '', driver: '', work: '', cubicPerTrip: '' }]);
                                        setTripMorning(''); setTripAfternoon('');
                                    }} className="w-full bg-blue-500 hover:bg-blue-600 py-3 text-base">
                                        <CheckCircle2 size={18} className="mr-2" /> บันทึกทั้งหมด ({tripEntries.filter(e => e.vehicle).length} คัน, {totalTrips} เที่ยวรวม)
                                    </Button>
                                    <div className={stepActionWrapClass}>
                                        <Button variant="secondary" onClick={prevStep} className={navBtnClass}>ย้อนกลับ</Button>
                                        <Button onClick={() => void nextStep()} className={navBtnClass}>ถัดไป <ChevronRight size={18} /></Button>
                                    </div>
                                </div>
                            </div>
                        )}

                        {/* Step 4: Sand Washing */}
                        {step === 4 && (
                            <div className="h-full flex flex-col animate-slide-up">
                                <div className="flex justify-between items-center mb-3">
                                    <h3 className="font-bold text-lg flex items-center gap-2"><Droplets className="text-cyan-500" /> บันทึกการล้างทราย</h3>
                                    <span className="text-xs text-slate-400">{new Date(date).toLocaleDateString('th-TH', { day: 'numeric', month: 'short', year: '2-digit' })}</span>
                                </div>

                                {/* Saved sand entries + จำนวนถังรวม 1 วัน (เช้า+บ่าย) */}
                                {(() => {
                                    const sandTxToday = dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'Sand');
                                    const totalDrumsDay = sandTxToday.length > 0
                                        ? Math.max(0, ...sandTxToday.map(t => (t as any).drumsObtained ?? 0))
                                        : (Number(sandDrumsObtained) || 0);
                                    const savedHomeDrumsFromSand = sandTxToday.length > 0
                                        ? Math.max(0, ...sandTxToday.map(t => Number((t as any).drumsWashedAtHome || 0)))
                                        : 0;
                                    const homeDrums = Math.max(0, Number(drumsWashedAtHome) || savedHomeDrumsFromSand || latestLaborDrumsWashedAtHome || 0);
                                    const netDrumsDay = Math.max(0, totalDrumsDay - homeDrums);
                                    const drumsDisplay = totalDrumsDay > 0 || homeDrums > 0;
                                    return (
                                        <>
                                            {sandTxToday.length > 0 && (
                                                <>
                                                    {drumsDisplay && (
                                                        <div className="mb-3 rounded-xl border border-slate-200 bg-white p-3 shadow-sm dark:border-white/10 dark:bg-white/[0.03]">
                                                            <div className="mb-2 flex items-center justify-between">
                                                                <span className="text-xs font-bold text-slate-600 dark:text-slate-300">🪣 สรุปจำนวนถังวันนี้</span>
                                                                <span className="text-xs text-slate-500 dark:text-slate-400">สุทธิหลังหักล้างที่บ้าน</span>
                                                            </div>
                                                            <div className="grid grid-cols-3 gap-2 text-center">
                                                                <div className="rounded-lg border border-emerald-200/80 bg-emerald-50/80 px-2 py-2 dark:border-emerald-500/25 dark:bg-emerald-500/10">
                                                                    <div className="text-[10px] font-semibold text-emerald-700 dark:text-emerald-300">ได้วันนี้</div>
                                                                    <div className="text-base font-black text-emerald-700 dark:text-emerald-300">{totalDrumsDay}</div>
                                                                </div>
                                                                <div className="rounded-lg border border-rose-200/80 bg-rose-50/80 px-2 py-2 dark:border-rose-500/25 dark:bg-rose-500/10">
                                                                    <div className="text-[10px] font-semibold text-rose-700 dark:text-rose-300">ล้างที่บ้าน</div>
                                                                    <div className="text-base font-black text-rose-700 dark:text-rose-300">{homeDrums}</div>
                                                                </div>
                                                                <div className="rounded-lg border border-amber-200/80 bg-amber-50/80 px-2 py-2 dark:border-amber-500/25 dark:bg-amber-500/10">
                                                                    <div className="text-[10px] font-semibold text-amber-700 dark:text-amber-300">คงเหลือสุทธิ</div>
                                                                    <div className="text-base font-black text-amber-700 dark:text-amber-300">{netDrumsDay}</div>
                                                                </div>
                                                            </div>
                                                        </div>
                                                    )}
                                                    <div className="mb-3 flex gap-2 overflow-x-auto pb-2">
                                                        {sandTxToday.map(t => {
                                                            const sandTotal = ((t as any).sandMorning || 0) + ((t as any).sandAfternoon || 0);
                                                            const drums = (t as any).drumsObtained ?? 0;
                                                            const isDrumsOnly = sandTotal === 0 && drums > 0;
                                                            return (
                                                            <div key={t.id} className="min-w-[190px] p-2.5 bg-white border border-slate-200 rounded-xl text-xs relative shadow-sm dark:bg-white/[0.03] dark:border-white/10">
                                                                <div className="font-bold text-slate-700 dark:text-slate-200">🌊 {t.description}</div>
                                                                {isDrumsOnly ? (
                                                                    <div className="text-teal-700 dark:text-teal-300 font-semibold mt-1">🪣 {drums} ถัง</div>
                                                                ) : (
                                                                    <div className="text-slate-600 dark:text-slate-300 font-semibold mt-1">เช้า {(t as any).sandMorning || 0} + บ่าย {(t as any).sandAfternoon || 0} = {sandTotal} คิว</div>
                                                                )}
                                                                {onDeleteTransaction && <button onClick={() => onDeleteTransaction(t.id)} className="absolute top-1.5 right-1.5 p-0.5 text-slate-300 hover:text-red-500"><Trash2 size={10} /></button>}
                                                            </div>
                                                        );})}
                                                    </div>
                                                </>
                                            )}
                                        </>
                                    );
                                })()}

                                <div className="flex-1 space-y-3 overflow-y-auto">
                                    {/* Machine 1 */}
                                    <div className="bg-gradient-to-r from-blue-50 to-cyan-50 p-4 rounded-xl border border-blue-200">
                                        <p className="text-sm font-bold text-blue-800 mb-2">🏭 เครื่องร่อน 1 (เก่า)</p>
                                        <div className="grid grid-cols-3 gap-3 mb-2">
                                            <div>
                                                <label className="text-xs font-medium text-amber-700 mb-1 block">☀️ เช้า (คิว)</label>
                                                <NumberPickerInput
                                                    placeholder="0"
                                                    value={sand1Morning}
                                                    onChange={setSand1Morning}
                                                    listMin={0}
                                                    listMax={150}
                                                    scrollAnchor={75}
                                                    min={0}
                                                    className="w-full px-3 py-2 border-2 border-amber-200 rounded-xl text-center text-lg font-bold text-amber-800 bg-white focus:border-amber-400 focus:outline-none"
                                                />
                                            </div>
                                            <div>
                                                <label className="text-xs font-medium text-blue-700 mb-1 block">🌙 บ่าย (คิว)</label>
                                                <NumberPickerInput
                                                    placeholder="0"
                                                    value={sand1Afternoon}
                                                    onChange={setSand1Afternoon}
                                                    listMin={0}
                                                    listMax={150}
                                                    scrollAnchor={75}
                                                    min={0}
                                                    className="w-full px-3 py-2 border-2 border-blue-200 rounded-xl text-center text-lg font-bold text-blue-800 bg-white focus:border-blue-400 focus:outline-none"
                                                />
                                            </div>
                                            <div className="flex flex-col items-center justify-center bg-white/70 rounded-xl border">
                                                <span className="text-[10px] text-slate-400">รวม</span>
                                                <span className="text-xl font-black text-blue-700">{sand1Total}</span>
                                                <span className="text-[10px] text-slate-400">คิว</span>
                                            </div>
                                        </div>
                                        <div>
                                            <label className="text-xs font-medium text-blue-700 mb-1 block">👷 พนักงานที่ล้าง</label>
                                            <div className="flex flex-wrap gap-1.5">
                                                {(workAssignments['wash1'] || []).length > 0 ? (workAssignments['wash1'] || []).map(eid => {
                                                    const emp = employees.find(e => e.id === eid);
                                                    return emp ? <span key={eid} className="px-2.5 py-1 rounded-lg text-xs font-medium bg-blue-500 text-white shadow-sm">{getEmployeeDisplayName(emp)}</span> : null;
                                                }) : <span className="text-xs text-slate-400 italic">ยังไม่มีข้อมูล (กรุณาลากพนักงานใส่กล่อง "ล้างทราย เครื่องร่อน 1" ในขั้นค่าแรง)</span>}
                                            </div>
                                        </div>
                                    </div>

                                    {/* Machine 2 */}
                                    <div className="bg-gradient-to-r from-cyan-50 to-teal-50 p-4 rounded-xl border border-cyan-200">
                                        <p className="text-sm font-bold text-cyan-800 mb-2">🏭 เครื่องร่อน 2 (ใหม่)</p>
                                        <div className="grid grid-cols-3 gap-3 mb-2">
                                            <div>
                                                <label className="text-xs font-medium text-amber-700 mb-1 block">☀️ เช้า (คิว)</label>
                                                <NumberPickerInput
                                                    placeholder="0"
                                                    value={sand2Morning}
                                                    onChange={setSand2Morning}
                                                    listMin={0}
                                                    listMax={150}
                                                    scrollAnchor={75}
                                                    min={0}
                                                    className="w-full px-3 py-2 border-2 border-amber-200 rounded-xl text-center text-lg font-bold text-amber-800 bg-white focus:border-amber-400 focus:outline-none"
                                                />
                                            </div>
                                            <div>
                                                <label className="text-xs font-medium text-blue-700 mb-1 block">🌙 บ่าย (คิว)</label>
                                                <NumberPickerInput
                                                    placeholder="0"
                                                    value={sand2Afternoon}
                                                    onChange={setSand2Afternoon}
                                                    listMin={0}
                                                    listMax={150}
                                                    scrollAnchor={75}
                                                    min={0}
                                                    className="w-full px-3 py-2 border-2 border-blue-200 rounded-xl text-center text-lg font-bold text-blue-800 bg-white focus:border-blue-400 focus:outline-none"
                                                />
                                            </div>
                                            <div className="flex flex-col items-center justify-center bg-white/70 rounded-xl border">
                                                <span className="text-[10px] text-slate-400">รวม</span>
                                                <span className="text-xl font-black text-cyan-700">{sand2Total}</span>
                                                <span className="text-[10px] text-slate-400">คิว</span>
                                            </div>
                                        </div>
                                        <div>
                                            <label className="text-xs font-medium text-cyan-700 mb-1 block">👷 พนักงานที่ล้าง</label>
                                            <div className="flex flex-wrap gap-1.5">
                                                {(workAssignments['wash2'] || []).length > 0 ? (workAssignments['wash2'] || []).map(eid => {
                                                    const emp = employees.find(e => e.id === eid);
                                                    return emp ? <span key={eid} className="px-2.5 py-1 rounded-lg text-xs font-medium bg-cyan-500 text-white shadow-sm">{getEmployeeDisplayName(emp)}</span> : null;
                                                }) : <span className="text-xs text-slate-400 italic">ยังไม่มีข้อมูล (กรุณาลากพนักงานใส่กล่อง "ล้างทราย เครื่องร่อน 2" ในขั้นค่าแรง)</span>}
                                            </div>
                                        </div>
                                    </div>

                                    {/* Grand total */}
                                    {sandGrandTotal > 0 && (
                                        <div className="bg-gradient-to-r from-emerald-100 to-teal-100 p-3 rounded-xl text-center border border-emerald-200">
                                            <span className="text-sm font-bold text-emerald-800">รวมล้างทรายทั้งหมด: </span>
                                            <span className="text-2xl font-black text-emerald-700">{sandGrandTotal}</span>
                                            <span className="text-sm text-emerald-600"> คิว/วัน</span>
                                            <div className="text-[10px] text-emerald-600 mt-1">เครื่อง 1: {sand1Total} คิว | เครื่อง 2: {sand2Total} คิว</div>
                                        </div>
                                    )}

                                    {/* เวลาเริ่มงาน / หยุดล้าง */}
                                    <div className="relative overflow-hidden rounded-2xl border border-cyan-200/80 bg-gradient-to-br from-cyan-50/90 via-white to-teal-50/80 p-5 shadow-sm">
                                        <div className="absolute top-0 right-0 w-24 h-24 bg-cyan-400/10 rounded-full -translate-y-1/2 translate-x-1/2" />
                                        <p className="text-xs font-bold uppercase tracking-wider text-cyan-700/80 mb-3 flex items-center gap-2">
                                            <span className="w-6 h-6 rounded-lg bg-cyan-500/20 flex items-center justify-center text-cyan-600 text-sm">🕐</span>
                                            เวลาเริ่มงาน / หยุดล้าง
                                        </p>
                                        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 relative">
                                            <div className="bg-white/80 rounded-xl border border-cyan-100 p-3 shadow-sm">
                                                <label className="text-[11px] font-semibold text-amber-700 mb-1.5 block">☀️ ช่วงเช้า เริ่มงาน (น.)</label>
                                                <input type="time" value={sandMorningStart} onChange={e => setSandMorningStart(e.target.value)}
                                                    className="w-full px-3 py-2.5 border border-amber-200/80 dark:border-amber-500/30 rounded-lg text-slate-800 dark:text-slate-100 bg-white dark:bg-white/5 text-sm font-medium focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20 outline-none transition-all" />
                                            </div>
                                            <div className="bg-white/80 rounded-xl border border-cyan-100 p-3 shadow-sm">
                                                <label className="text-[11px] font-semibold text-blue-700 mb-1.5 block">🌤️ ช่วงบ่าย เริ่มงาน (น.)</label>
                                                <input type="time" value={sandAfternoonStart} onChange={e => setSandAfternoonStart(e.target.value)}
                                                    className="w-full px-3 py-2.5 border border-blue-200/80 dark:border-blue-500/30 rounded-lg text-slate-800 dark:text-slate-100 bg-white dark:bg-white/5 text-sm font-medium focus:border-blue-400 focus:ring-2 focus:ring-blue-400/20 outline-none transition-all" />
                                            </div>
                                            <div className="bg-white/80 rounded-xl border border-teal-100 p-3 shadow-sm">
                                                <label className="text-[11px] font-semibold text-teal-700 mb-1.5 block">🌙 เย็น หยุดล้าง (กี่โมง)</label>
                                                <input type="time" value={sandEveningEnd} onChange={e => setSandEveningEnd(e.target.value)}
                                                    className="w-full px-3 py-2.5 border border-teal-200/80 dark:border-teal-500/30 rounded-lg text-slate-800 dark:text-slate-100 bg-white dark:bg-white/5 text-sm font-medium focus:border-teal-400 focus:ring-2 focus:ring-teal-400/20 outline-none transition-all" />
                                            </div>
                                        </div>
                                    </div>

                                    {/* จำนวนถังที่ได้วันนี้ */}
                                    <div className="rounded-2xl border border-slate-200 dark:border-white/10 bg-gradient-to-br from-slate-50 via-white to-slate-100/80 dark:from-white/[0.05] dark:via-white/[0.03] dark:to-white/[0.02] p-4 shadow-sm">
                                        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                                            <div className="rounded-xl border border-emerald-200 dark:border-emerald-500/30 bg-emerald-50/80 dark:bg-emerald-500/10 px-3 py-3">
                                                <label className="text-xs font-bold text-emerald-700 dark:text-emerald-300 mb-1.5 flex items-center gap-2">
                                                    <span className="w-6 h-6 rounded-lg bg-emerald-500/20 flex items-center justify-center">➕</span>
                                                    จำนวนถังที่ได้วันนี้
                                                </label>
                                                <div className="flex items-center gap-2">
                                                    <NumberPickerInput
                                                        min={0}
                                                        placeholder="0"
                                                        value={sandDrumsObtained}
                                                        onChange={setSandDrumsObtained}
                                                        listMin={0}
                                                        listMax={100}
                                                        scrollAnchor={40}
                                                        wrapperClassName="flex min-w-0 max-w-[10.5rem] flex-1 items-stretch gap-1"
                                                        className="w-24 min-w-0 flex-1 px-3 py-2 border-2 border-emerald-200 dark:border-emerald-500/35 rounded-xl text-center text-base font-bold text-emerald-800 dark:text-emerald-200 bg-white dark:bg-white/5 focus:border-emerald-500 focus:ring-2 focus:ring-emerald-500/20 outline-none transition-all"
                                                    />
                                                    <span className="shrink-0 text-sm font-medium text-emerald-700 dark:text-emerald-300">ถัง</span>
                                                </div>
                                            </div>
                                            <div className="rounded-xl border border-rose-200 dark:border-rose-500/30 bg-rose-50/80 dark:bg-rose-500/10 px-3 py-3">
                                                <label className="text-xs font-bold text-rose-700 dark:text-rose-300 mb-1.5 flex items-center gap-2">
                                                    <span className="w-6 h-6 rounded-lg bg-rose-500/20 flex items-center justify-center">➖</span>
                                                    จำนวนทรายที่ล้างที่บ้านวันนี้
                                                </label>
                                                <div className="flex items-center gap-2">
                                                    <NumberPickerInput
                                                        min={0}
                                                        placeholder="0"
                                                        value={drumsWashedAtHome}
                                                        onChange={setDrumsWashedAtHome}
                                                        listMin={0}
                                                        listMax={100}
                                                        scrollAnchor={40}
                                                        wrapperClassName="flex min-w-0 max-w-[10.5rem] flex-1 items-stretch gap-1"
                                                        className="w-24 min-w-0 flex-1 px-3 py-2 border-2 border-rose-200 dark:border-rose-500/35 rounded-xl text-center text-base font-bold text-rose-800 dark:text-rose-200 bg-white dark:bg-white/5 focus:border-rose-500 focus:ring-2 focus:ring-rose-500/20 outline-none transition-all"
                                                    />
                                                    <span className="shrink-0 text-sm font-medium text-rose-700 dark:text-rose-300">ถัง</span>
                                                </div>
                                            </div>
                                        </div>
                                        <div className="mt-3 grid grid-cols-1 sm:grid-cols-3 gap-2">
                                            <div className="rounded-xl border border-slate-200/80 dark:border-white/10 bg-white/80 dark:bg-white/[0.03] px-3 py-2">
                                                <p className="text-[10px] text-slate-500 dark:text-slate-400">จำนวนถังที่ได้วันนี้</p>
                                                <p className="text-lg font-black text-slate-700 dark:text-slate-100">{Number(sandDrumsObtained) || 0}</p>
                                            </div>
                                            <div className="rounded-xl border border-teal-200/80 dark:border-teal-500/30 bg-teal-50/70 dark:bg-teal-500/10 px-3 py-2">
                                                <p className="text-[10px] text-teal-700/90 dark:text-teal-300">ล้างที่บ้านวันนี้</p>
                                                <p className="text-lg font-black text-teal-700 dark:text-teal-300">{Number(drumsWashedAtHome) || 0}</p>
                                            </div>
                                            <div className="rounded-xl border border-emerald-200/80 dark:border-emerald-500/30 bg-emerald-50/70 dark:bg-emerald-500/10 px-3 py-2">
                                                <p className="text-[10px] text-emerald-700/90 dark:text-emerald-300">จำนวนถังคงเหลือ</p>
                                                <p className="text-lg font-black text-emerald-700 dark:text-emerald-300">{drumStockSummary.cumulativeRemaining}</p>
                                            </div>
                                        </div>
                                    </div>
                                </div>

                                <div className={mobileShell ? 'sticky bottom-[calc(0.4rem+env(safe-area-inset-bottom,0px))] z-[5] mt-2 space-y-2 rounded-2xl border border-slate-200/80 bg-white/95 p-2.5 shadow-sm backdrop-blur dark:border-white/10 dark:bg-slate-900/90' : 'pt-3 border-t space-y-2'}>
                                    <Button onClick={async () => {
                                        const drumsToday = Number(sandDrumsObtained) || 0;
                                        const drumsHomeToday = Number(drumsWashedAtHome) || 0;
                                        if (sandGrandTotal === 0 && drumsToday === 0) {
                                            await sessionAlert('กรุณาใส่จำนวนทรายที่ล้างได้หรือจำนวนถังที่ได้วันนี้');
                                            return;
                                        }
                                        const opNames1 = sand1Operators.map(id => employees.find(e => e.id === id)?.nickname || '').join(', ');
                                        const opNames2 = sand2Operators.map(id => employees.find(e => e.id === id)?.nickname || '').join(', ');
                                        const timePayload = {
                                            sandMorningStart: sandMorningStart || undefined,
                                            sandAfternoonStart: sandAfternoonStart || undefined,
                                            sandEveningEnd: sandEveningEnd || undefined
                                        };
                                        if (sand1Total > 0) {
                                            onSaveTransaction({
                                                id: Date.now().toString() + '_s1', date, type: 'Expense', category: 'DailyLog', subCategory: 'Sand',
                                                description: `ล้างทราย เครื่องร่อน 1 (เก่า)${opNames1 ? ` [${opNames1}]` : ''}`, amount: 0,
                                                sandMorning: Number(sand1Morning) || 0, sandAfternoon: Number(sand1Afternoon) || 0,
                                                sandOperators: sand1Operators, sandMachineType: 'Old', drumsObtained: drumsToday,
                                                drumsWashedAtHome: drumsHomeToday,
                                                ...timePayload
                                            } as Transaction);
                                        }
                                        if (sand2Total > 0) {
                                            onSaveTransaction({
                                                id: Date.now().toString() + '_s2', date, type: 'Expense', category: 'DailyLog', subCategory: 'Sand',
                                                description: `ล้างทราย เครื่องร่อน 2 (ใหม่)${opNames2 ? ` [${opNames2}]` : ''}`, amount: 0,
                                                sandMorning: Number(sand2Morning) || 0, sandAfternoon: Number(sand2Afternoon) || 0,
                                                sandOperators: sand2Operators, sandMachineType: 'New', drumsObtained: drumsToday,
                                                drumsWashedAtHome: drumsHomeToday,
                                                ...timePayload
                                            } as Transaction);
                                        }
                                        if (sandGrandTotal === 0 && drumsToday > 0) {
                                            onSaveTransaction({
                                                id: Date.now().toString() + '_drums', date, type: 'Expense', category: 'DailyLog', subCategory: 'Sand',
                                                description: 'จำนวนถังที่ได้วันนี้', amount: 0, drumsObtained: drumsToday, drumsWashedAtHome: drumsHomeToday,
                                                ...timePayload
                                            } as Transaction);
                                        }
                                        setSand1Morning(''); setSand1Afternoon(''); setSand2Morning(''); setSand2Afternoon('');
                                        setSand1Operators([]); setSand2Operators([]); setSandDrumsObtained('');
                                        setDrumsWashedAtHome('');
                                        setSandMorningStart(''); setSandAfternoonStart(''); setSandEveningEnd('');
                                    }} className="w-full bg-cyan-500 hover:bg-cyan-600 py-2.5 focus-ring-strong" data-hotkey-primary="true">
                                        <Droplets size={16} className="mr-1" /> บันทึกข้อมูลล้างทราย ({sandGrandTotal} คิว)
                                    </Button>
                                    <div className={stepActionWrapClass}>
                                        <Button variant="secondary" onClick={prevStep} className={navBtnClass}>ย้อนกลับ</Button>
                                        <Button onClick={() => void nextStep()} className={navBtnClass}>ถัดไป <ChevronRight size={18} /></Button>
                                    </div>
                                </div>
                            </div>
                        )}

                        {/* Step 5: Fuel */}
                        {step === 5 && (
                            <div className="h-full min-w-0 flex flex-col animate-slide-up overflow-x-hidden">
                                <h3 className="font-bold text-xl text-slate-800 dark:text-slate-100 mb-5">Fuel Entry</h3>

                                {/* Saved fuel entries */}
                                {dayTransactions.filter(t => t.category === 'Fuel').length > 0 && (
                                    <div className="mb-4 space-y-2">
                                        {(() => {
                                            const fuelInTx = dayTransactions.filter(t => t.category === 'Fuel' && (t.fuelMovement || 'stock_in') === 'stock_in' && !t.vehicleId);
                                            const fuelOutTx = dayTransactions.filter(t => t.category === 'Fuel' && ((t.fuelMovement === 'stock_out') || !!t.vehicleId));
                                            return (
                                                <>
                                                    <p className="text-sm font-semibold text-slate-500 dark:text-slate-400">รายการน้ำมันวันนี้ ({fuelInTx.length + fuelOutTx.length} รอบ)</p>
                                                    {fuelInTx.length > 0 && (
                                                        <>
                                                            <p className="text-xs font-bold text-red-700 dark:text-red-300">ซื้อน้ำมันเข้า ({fuelInTx.length} รอบ)</p>
                                                            <div className="flex gap-2 overflow-x-auto pb-2">
                                                                {fuelInTx.map(t => (
                                                                    <div key={t.id} className="min-w-[220px] p-3 bg-red-50 border border-red-100 rounded-xl text-xs relative">
                                                                        <div className="font-bold text-red-800">⛽ {(t as any).fuelType === 'Diesel' ? 'ดีเซล' : 'เบนซิน'}</div>
                                                                        <div className="text-red-700 mt-1 font-semibold">ซื้อเข้า <span className="font-bold">{(t.quantity || 0).toLocaleString()} {(t.unit === 'gallon' ? 'แกลลอน' : 'ลิตร')}</span></div>
                                                                        <div className="text-red-700 font-semibold">ราคา <span className="font-bold">{(t.amount || 0).toLocaleString()} บาท</span></div>
                                                                        {t.workDetails && <div className="text-red-600/70 mt-1">{t.workDetails}</div>}
                                                                        {onDeleteTransaction && <button onClick={() => onDeleteTransaction(t.id)} className="absolute top-2 right-2 p-1 text-red-300 hover:text-red-600"><Trash2 size={12} /></button>}
                                                                    </div>
                                                                ))}
                                                            </div>
                                                        </>
                                                    )}
                                                    {fuelOutTx.length > 0 && (
                                                        <>
                                                            <p className="text-xs font-bold text-indigo-700 dark:text-indigo-300">ใช้น้ำมันรายรถ ({fuelOutTx.length} รอบ)</p>
                                                            <div className="flex gap-2 overflow-x-auto pb-2">
                                                                {fuelOutTx.map(t => (
                                                                    <div key={t.id} className="min-w-[220px] p-3 bg-indigo-50 border border-indigo-100 rounded-xl text-xs relative">
                                                                        <div className="font-bold text-indigo-800">🚛 {t.vehicleId || '-'}</div>
                                                                        <div className="text-indigo-700 mt-1 font-semibold">{(t as any).fuelType === 'Diesel' ? 'ดีเซล' : 'เบนซิน'}: <span className="font-bold">{(t.quantity || 0).toLocaleString()} {(t.unit === 'gallon' ? 'แกลลอน' : 'ลิตร')}</span></div>
                                                                        {t.amount > 0 && <div className="text-indigo-700 font-semibold">คิดเป็นเงิน <span className="font-bold">{t.amount.toLocaleString()} บาท</span></div>}
                                                                        {t.workDetails && <div className="text-indigo-600/80 mt-1">{t.workDetails}</div>}
                                                                        {onDeleteTransaction && <button onClick={() => onDeleteTransaction(t.id)} className="absolute top-2 right-2 p-1 text-indigo-300 hover:text-indigo-600"><Trash2 size={12} /></button>}
                                                                    </div>
                                                                ))}
                                                            </div>
                                                        </>
                                                    )}
                                                </>
                                            );
                                        })()}
                                        {(() => {
                                            const fuelTx = dayTransactions.filter(t => t.category === 'Fuel');
                                            const totalBaht = fuelTx.reduce((s, t) => s + (t.amount || 0), 0);
                                            return <div className="bg-red-100/50 p-2 rounded-lg text-sm text-center text-red-800 font-medium">รวมวันนี้: <span className="font-bold">{totalBaht.toLocaleString()}</span> บาท</div>;
                                        })()}
                                    </div>
                                )}

                                {/* Clean fuel entry form */}
                                <div className="flex-1 min-w-0 overflow-hidden rounded-2xl border border-slate-200 bg-white p-4 shadow-sm space-y-5 dark:border-white/10 dark:bg-white/[0.03] sm:p-6">
                                    {/* Date */}
                                    <div>
                                        <label className="text-sm font-medium text-slate-600 dark:text-slate-300 mb-1.5 block">วันที่</label>
                                        <div className="w-full min-w-0 px-4 py-3 border border-slate-300 dark:border-white/15 rounded-xl text-base text-slate-800 dark:text-slate-100 bg-slate-50 dark:bg-white/5">
                                            {formatDateBE(date)}
                                        </div>
                                    </div>

                                    {/* Fuel Type - Radio style */}
                                    <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                                        <button onClick={() => setFuelType('Diesel')}
                                            type="button"
                                            className={`flex items-center gap-3 px-4 py-3 rounded-xl border-2 transition-all text-base font-medium ${fuelType === 'Diesel' ? 'border-slate-800 dark:border-slate-300 bg-white dark:bg-white/10 text-slate-800 dark:text-slate-100' : 'border-slate-200 dark:border-white/10 bg-white dark:bg-white/5 text-slate-600 dark:text-slate-300 hover:border-slate-300 dark:hover:border-white/20'}`}>
                                            <span className={`w-5 h-5 rounded-full border-2 flex items-center justify-center shrink-0 ${fuelType === 'Diesel' ? 'border-slate-800 dark:border-slate-300' : 'border-slate-300 dark:border-slate-500'}`}>
                                                {fuelType === 'Diesel' && <span className="w-3 h-3 rounded-full bg-slate-800 dark:bg-slate-200"></span>}
                                            </span>
                                            ดีเซล
                                        </button>
                                        <button onClick={() => setFuelType('Benzine')}
                                            type="button"
                                            className={`flex items-center gap-3 px-4 py-3 rounded-xl border-2 transition-all text-base font-medium ${fuelType === 'Benzine' ? 'border-slate-800 dark:border-slate-300 bg-white dark:bg-white/10 text-slate-800 dark:text-slate-100' : 'border-slate-200 dark:border-white/10 bg-white dark:bg-white/5 text-slate-600 dark:text-slate-300 hover:border-slate-300 dark:hover:border-white/20'}`}>
                                            <span className={`w-5 h-5 rounded-full border-2 flex items-center justify-center shrink-0 ${fuelType === 'Benzine' ? 'border-slate-800 dark:border-slate-300' : 'border-slate-300 dark:border-slate-500'}`}>
                                                {fuelType === 'Benzine' && <span className="w-3 h-3 rounded-full bg-slate-800 dark:bg-slate-200"></span>}
                                            </span>
                                            เบนซิน
                                        </button>
                                    </div>

                                    {/* Quantity + Unit */}
                                    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                                        <div className="min-w-0 space-y-2">
                                            <label className="mb-1.5 block text-sm font-medium text-slate-600 dark:text-slate-300">จำนวนลิตร</label>
                                            <NumberPickerInput
                                                placeholder=""
                                                value={fuelLiters}
                                                onChange={setFuelLiters}
                                                listMin={0}
                                                listMax={200}
                                                scrollAnchor={90}
                                                min={0}
                                                className="w-full min-w-0 px-4 py-3 border border-slate-300 bg-white text-base text-slate-800 transition-colors focus:border-slate-500 focus:outline-none dark:border-white/15 dark:bg-white/5 dark:text-slate-100 dark:focus:border-slate-400"
                                            />
                                            <div>
                                                {fuelPurchaseLitersTemplates.length > 0 && (
                                                    <div className="flex flex-wrap gap-2">
                                                        {fuelPurchaseLitersTemplates.map(v => (
                                                            <button
                                                                key={`fpl-${v}`}
                                                                type="button"
                                                                onClick={() => setFuelLiters(v)}
                                                                className="touch-manipulation rounded-full border border-slate-200 bg-slate-50 px-3 py-2 text-xs font-semibold text-slate-700 shadow-sm transition hover:bg-white dark:border-white/15 dark:bg-white/10 dark:text-slate-200 dark:hover:bg-white/15"
                                                            >
                                                                {Number(v).toLocaleString()} ลิตร
                                                            </button>
                                                        ))}
                                                    </div>
                                                )}
                                            </div>
                                        </div>
                                        <div className="min-w-0">
                                            <label className="text-sm font-medium text-slate-600 dark:text-slate-300 mb-1.5 block">หน่วย</label>
                                            <select value={fuelUnit} onChange={e => setFuelUnit(e.target.value)}
                                                className="w-full min-w-0 px-4 py-3 border border-slate-300 dark:border-white/15 rounded-xl text-base text-slate-800 dark:text-slate-100 bg-white dark:bg-white/5 focus:border-slate-500 dark:focus:border-slate-400 focus:outline-none transition-colors appearance-none">
                                                <option value="ลิตร">ลิตร</option>
                                                <option value="แกลลอน">แกลลอน</option>
                                            </select>
                                        </div>
                                    </div>

                                    {/* Price */}
                                    <div className="space-y-2">
                                        <label className="mb-1.5 block text-sm font-medium text-slate-600 dark:text-slate-300">ราคาซื้อน้ำมัน (บาท)</label>
                                        <input type="number" placeholder="" value={fuelAmount} onChange={e => setFuelAmount(e.target.value)}
                                            className="w-full px-4 py-4 border border-slate-300 dark:border-white/15 rounded-xl text-lg text-slate-800 dark:text-slate-100 bg-white dark:bg-white/5 focus:border-slate-500 dark:focus:border-slate-400 focus:outline-none transition-colors" />
                                        <div>
                                            {fuelPurchaseAmountTemplates.length > 0 && (
                                                <div className="flex flex-wrap gap-2">
                                                    {fuelPurchaseAmountTemplates.map(v => (
                                                        <button
                                                            key={`fpa-${v}`}
                                                            type="button"
                                                            onClick={() => setFuelAmount(v)}
                                                            className="touch-manipulation rounded-full border border-rose-200 bg-rose-50 px-3 py-2 text-xs font-bold text-rose-800 shadow-sm transition hover:bg-rose-100 dark:border-rose-500/35 dark:bg-rose-500/15 dark:text-rose-100 dark:hover:bg-rose-500/25"
                                                        >
                                                            ฿{Number(v).toLocaleString()}
                                                        </button>
                                                    ))}
                                                </div>
                                            )}
                                        </div>
                                    </div>

                                    {/* Details (optional) */}
                                    <div>
                                        <label className="text-sm font-medium text-slate-600 dark:text-slate-300 mb-1.5 block">รายละเอียดเพิ่มเติม <span className="text-slate-400 dark:text-slate-500 font-normal">(ไม่บังคับ)</span></label>
                                        <input type="text" placeholder="เช่น ซื้อที่ปั๊มหน้าแคมป์" value={fuelDetails} onChange={e => setFuelDetails(e.target.value)}
                                            className="w-full px-4 py-3 border border-slate-300 dark:border-white/15 rounded-xl text-base text-slate-800 dark:text-slate-100 bg-white dark:bg-white/5 focus:border-slate-500 dark:focus:border-slate-400 focus:outline-none transition-colors" />
                                        {fuelDetailsQuickChips.length > 0 && (
                                            <div className="mt-2">
                                                <div className="flex flex-wrap items-center gap-1.5 pt-0.5">
                                                    {fuelDetailsQuickChips.map(t => (
                                                        <button
                                                            key={`fdc-${t}`}
                                                            type="button"
                                                            onClick={() => setFuelDetails(t)}
                                                            className="inline-flex touch-manipulation items-center gap-1 rounded-full border border-emerald-200 bg-emerald-50 px-2.5 py-1.5 text-xs font-medium text-emerald-800 transition hover:bg-emerald-100 dark:border-emerald-500/35 dark:bg-emerald-500/15 dark:text-emerald-100 dark:hover:bg-emerald-500/25"
                                                        >
                                                            {t}
                                                        </button>
                                                    ))}
                                                </div>
                                            </div>
                                        )}
                                    </div>

                                    {/* Save button */}
                                    <button onClick={async () => {
                                        if (!fuelAmount) {
                                            await sessionAlert('กรุณาระบุราคาซื้อน้ำมัน');
                                            return;
                                        }
                                        const fuelWarnings: string[] = [];
                                        const liters = Number(fuelLiters) || 0;
                                        const amount = Number(fuelAmount) || 0;
                                        const duplicateFuelIn = dayTransactions.find(t =>
                                            t.category === 'Fuel' &&
                                            (t.fuelMovement || 'stock_in') === 'stock_in' &&
                                            t.fuelType === fuelType &&
                                            (Number(t.quantity) || 0) === liters &&
                                            (Number(t.amount) || 0) === amount
                                        );
                                        if (duplicateFuelIn) fuelWarnings.push('พบรายการซื้อน้ำมันค่าเดียวกันอยู่แล้วในวันนี้');
                                        if (liters <= 0) fuelWarnings.push('ปริมาณน้ำมันที่ซื้อควรมากกว่า 0');
                                        if (amount > 200000) fuelWarnings.push('ยอดซื้อน้ำมันสูงกว่าปกติมาก');
                                        if (!(await shouldContinueWithWarning(fuelWarnings, 'ตรวจพบรายการซื้อน้ำมันที่อาจซ้ำ/ผิดปกติ'))) return;
                                        const unitLabel = fuelUnit === 'แกลลอน' ? 'gallon' : 'L';
                                        onSaveTransaction({
                                            id: Date.now().toString(), date, type: 'Expense', category: 'Fuel',
                                            description: `ซื้อน้ำมัน ${fuelType === 'Diesel' ? 'ดีเซล' : 'เบนซิน'}: ${fuelLiters || 0} ${fuelUnit} ${fuelAmount} บาท${fuelDetails ? ` - ${fuelDetails}` : ''}`,
                                            amount: Number(fuelAmount),
                                            quantity: Number(fuelLiters), unit: unitLabel, fuelType,
                                            workDetails: fuelDetails,
                                            fuelMovement: 'stock_in'
                                        } as Transaction);
                                        setFuelAmount(''); setFuelLiters(''); setFuelDetails('');
                                    }} className="w-full py-3.5 bg-slate-800 hover:bg-slate-900 text-white text-base font-bold rounded-xl transition-colors focus-ring-strong" data-hotkey-primary="true">
                                        บันทึกซื้อน้ำมันเข้า
                                    </button>

                                    <div className="my-1 border-t border-slate-200 dark:border-white/10"></div>
                                    <h4 className="font-bold text-slate-800 dark:text-slate-100">บันทึกการใช้น้ำมันของรถแต่ละคัน</h4>
                                    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                                        <div className="min-w-0">
                                            <label className="text-sm font-medium text-slate-600 dark:text-slate-300 mb-1.5 block">เลือกรถ</label>
                                            <select
                                                value={fuelVehicle}
                                                onChange={e => setFuelVehicle(e.target.value)}
                                                className="w-full min-w-0 px-4 py-3 border border-slate-300 dark:border-white/15 rounded-xl text-base text-slate-800 dark:text-slate-100 bg-white dark:bg-white/5 focus:border-slate-500 dark:focus:border-slate-400 focus:outline-none transition-colors"
                                            >
                                                <option value="">-- เลือกรถ --</option>
                                                {settings.cars.map(car => <option key={car} value={car}>{car}</option>)}
                                            </select>
                                        </div>
                                        <div className="min-w-0">
                                            <label className="text-sm font-medium text-slate-600 dark:text-slate-300 mb-1.5 block">ชนิดน้ำมัน</label>
                                            <select
                                                value={fuelVehicleType}
                                                onChange={e => setFuelVehicleType(e.target.value as 'Diesel' | 'Benzine')}
                                                className="w-full min-w-0 px-4 py-3 border border-slate-300 dark:border-white/15 rounded-xl text-base text-slate-800 dark:text-slate-100 bg-white dark:bg-white/5 focus:border-slate-500 dark:focus:border-slate-400 focus:outline-none transition-colors"
                                            >
                                                <option value="Diesel">ดีเซล</option>
                                                <option value="Benzine">เบนซิน</option>
                                            </select>
                                        </div>
                                    </div>
                                    <div className="min-w-0 space-y-2">
                                        <label className="mb-1.5 block text-sm font-medium text-slate-600 dark:text-slate-300">ใช้น้ำมัน (ลิตร)</label>
                                        <NumberPickerInput
                                            placeholder=""
                                            value={fuelVehicleLiters}
                                            onChange={setFuelVehicleLiters}
                                            listMin={0}
                                            listMax={200}
                                            scrollAnchor={90}
                                            min={0}
                                            className="w-full min-w-0 px-4 py-3 border border-slate-300 bg-white text-base text-slate-800 transition-colors focus:border-slate-500 focus:outline-none dark:border-white/15 dark:bg-white/5 dark:text-slate-100 dark:focus:border-slate-400"
                                        />
                                        <div>
                                            {fuelVehicleLitersTemplates.length > 0 && (
                                                <div className="flex flex-wrap gap-2">
                                                    {fuelVehicleLitersTemplates.map(v => (
                                                        <button
                                                            key={`fvl-${v}`}
                                                            type="button"
                                                            onClick={() => setFuelVehicleLiters(v)}
                                                            className="touch-manipulation rounded-full border border-indigo-200 bg-indigo-50 px-3 py-2 text-xs font-bold text-indigo-800 shadow-sm transition hover:bg-indigo-100 dark:border-indigo-500/35 dark:bg-indigo-500/15 dark:text-indigo-100 dark:hover:bg-indigo-500/25"
                                                        >
                                                            {Number(v).toLocaleString()} ลิตร
                                                        </button>
                                                    ))}
                                                </div>
                                            )}
                                        </div>
                                    </div>
                                    <div>
                                        <label className="text-sm font-medium text-slate-600 dark:text-slate-300 mb-1.5 block">เวลาเติมน้ำมัน <span className="text-slate-400 font-normal">(ไม่บังคับ)</span></label>
                                        <input
                                            type="time"
                                            value={fuelVehicleDetails}
                                            onChange={e => setFuelVehicleDetails(e.target.value)}
                                            className="w-full px-4 py-3 border border-slate-300 dark:border-white/15 rounded-xl text-base text-slate-800 dark:text-slate-100 bg-white dark:bg-white/5 focus:border-slate-500 dark:focus:border-slate-400 focus:outline-none transition-colors"
                                        />
                                    </div>
                                    <button onClick={async () => {
                                        if (!fuelVehicle) {
                                            await sessionAlert('กรุณาเลือกรถ');
                                            return;
                                        }
                                        if (!fuelVehicleLiters || Number(fuelVehicleLiters) <= 0) {
                                            await sessionAlert('กรุณาระบุปริมาณน้ำมันที่ใช้');
                                            return;
                                        }
                                        const amount = 0;
                                        const liters = Number(fuelVehicleLiters) || 0;
                                        const fuelVehicleWarnings: string[] = [];
                                        const duplicateFuelOut = dayTransactions.find(t =>
                                            t.category === 'Fuel' &&
                                            (t.fuelMovement === 'stock_out' || !!t.vehicleId) &&
                                            t.vehicleId === fuelVehicle &&
                                            t.fuelType === fuelVehicleType &&
                                            (Number(t.quantity) || 0) === liters &&
                                            (Number(t.amount) || 0) === amount
                                        );
                                        if (duplicateFuelOut) fuelVehicleWarnings.push(`มีรายการใช้น้ำมันของรถ ${fuelVehicle} ค่าเดียวกันอยู่แล้ว`);
                                        if (liters > 5000) fuelVehicleWarnings.push('ปริมาณน้ำมันที่ใช้สูงกว่าปกติมาก');
                                        if (!(await shouldContinueWithWarning(fuelVehicleWarnings, 'ตรวจพบรายการใช้น้ำมันรายรถที่อาจซ้ำ/ผิดปกติ'))) return;
                                        const timePart = fuelVehicleDetails.trim() ? ` เวลา ${fuelVehicleDetails}` : '';
                                        onSaveTransaction({
                                            id: `fuel_car_${Date.now()}`,
                                            date,
                                            type: 'Expense',
                                            category: 'Fuel',
                                            subCategory: 'VehicleUsage',
                                            description: `ใช้น้ำมันรถ ${fuelVehicle}: ${Number(fuelVehicleLiters)} ลิตร (${fuelVehicleType === 'Diesel' ? 'ดีเซล' : 'เบนซิน'})${timePart}`,
                                            amount,
                                            quantity: Number(fuelVehicleLiters),
                                            unit: 'L',
                                            fuelType: fuelVehicleType,
                                            fuelMovement: 'stock_out',
                                            vehicleId: fuelVehicle,
                                            workDetails: fuelVehicleDetails.trim() || undefined
                                        } as Transaction);
                                        setFuelVehicleLiters('');
                                        setFuelVehicleDetails('');
                                    }} className="w-full py-3 bg-indigo-600 hover:bg-indigo-700 text-white text-base font-bold rounded-xl transition-colors">
                                        บันทึกการใช้น้ำมันรายรถ
                                    </button>
                                </div>

                                <div className={stepActionWrapClass}>
                                    <Button variant="secondary" onClick={prevStep} className={navBtnClass}>ย้อนกลับ</Button>
                                    <Button onClick={() => void nextStep()} className={navBtnClass}>ถัดไป <ChevronRight size={18} /></Button>
                                </div>
                            </div>
                        )}

                        {/* Step 6: Income */}
                        {step === 6 && (
                            <div className="h-full min-w-0 flex flex-col animate-slide-up overflow-x-hidden">
                                <h3 className="font-bold text-lg flex items-center gap-2 mb-3"><Wallet className="text-lime-600" /> บันทึกรายรับประจำวัน</h3>
                                {dayTransactions.filter(t => t.category === 'Income' && t.type === 'Income').length > 0 && (
                                    <div className="mb-3 flex gap-2 overflow-x-auto pb-2">
                                        {dayTransactions.filter(t => t.category === 'Income' && t.type === 'Income').map(t => (
                                            <div key={t.id} className="min-w-[220px] p-3 bg-lime-50 border border-lime-200 rounded-xl text-xs relative">
                                                <div className="font-bold text-lime-800">{t.description || 'รายรับ'}</div>
                                                <div className="text-lime-700 font-semibold mt-1">฿{(t.amount || 0).toLocaleString()}</div>
                                                {t.quantity != null && <div className="text-lime-600 mt-0.5">ปริมาณ: {t.quantity} {t.unit || ''}</div>}
                                                {onDeleteTransaction && <button onClick={() => onDeleteTransaction(t.id)} className="absolute top-2 right-2 p-0.5 text-lime-300 hover:text-red-500"><Trash2 size={10} /></button>}
                                            </div>
                                        ))}
                                    </div>
                                )}
                                <div className="flex-1 space-y-3">
                                    <div className="flex flex-col gap-1.5 w-full">
                                        <label className="text-sm font-medium text-slate-700">ประเภทรายรับ</label>
                                        <input
                                            type="text"
                                            value={incomeType}
                                            onChange={(e) => setIncomeType(e.target.value)}
                                            list="income-type-suggestions"
                                            placeholder="พิมพ์หรือเลือกจากตัวช่วยกรอก"
                                            className="w-full rounded-xl border border-slate-200 bg-white px-4 py-2.5 text-slate-800 transition-all focus:border-emerald-500 focus:outline-none focus:ring-2 focus:ring-emerald-500/20"
                                        />
                                        <datalist id="income-type-suggestions">
                                            {(settings.incomeTypes || []).map((t) => (
                                                <option key={t} value={t} />
                                            ))}
                                        </datalist>
                                        <div className="flex flex-wrap items-center gap-1.5 pt-1">
                                            {(settings.incomeTypes || []).map((t) => (
                                                <span
                                                    key={`quick-income-${t}`}
                                                    className="inline-flex items-center gap-1 rounded-full border border-emerald-200 bg-emerald-50 px-2.5 py-1 text-xs font-medium text-emerald-700"
                                                >
                                                    <button
                                                        type="button"
                                                        onClick={() => setIncomeType(t)}
                                                        className="hover:text-emerald-900"
                                                        title={`เลือก ${t}`}
                                                    >
                                                        {t}
                                                    </button>
                                                    <button
                                                        type="button"
                                                        onClick={() => handleRemoveIncomeType(t)}
                                                        className="rounded p-0.5 text-emerald-500 hover:bg-red-50 hover:text-red-500"
                                                        title={`ลบ ${t}`}
                                                    >
                                                        <Trash2 size={10} />
                                                    </button>
                                                </span>
                                            ))}
                                            {incomeTypeAddOpen ? (
                                                <span className="inline-flex min-w-0 max-w-full items-center gap-1 rounded-full border border-dashed border-lime-400 bg-white px-2 py-0.5 ps-2.5">
                                                    <input
                                                        ref={incomeAddInputRef}
                                                        value={newIncomeType}
                                                        onChange={(e) => setNewIncomeType(e.target.value)}
                                                        onKeyDown={(e) => {
                                                            if (e.key === 'Enter') {
                                                                e.preventDefault();
                                                                handleAddIncomeType();
                                                            }
                                                            if (e.key === 'Escape') {
                                                                e.preventDefault();
                                                                setNewIncomeType('');
                                                                setIncomeTypeAddOpen(false);
                                                            }
                                                        }}
                                                        onBlur={() => {
                                                            window.setTimeout(() => {
                                                                if (!newIncomeType.trim()) setIncomeTypeAddOpen(false);
                                                            }, 120);
                                                        }}
                                                        placeholder="ชื่อประเภทใหม่"
                                                        className="min-w-[6rem] max-w-[10rem] flex-1 border-0 bg-transparent py-1 text-xs text-slate-800 outline-none placeholder:text-slate-400"
                                                        autoFocus
                                                    />
                                                    <button
                                                        type="button"
                                                        onMouseDown={(e) => e.preventDefault()}
                                                        onClick={handleAddIncomeType}
                                                        className="shrink-0 rounded-full p-1 text-lime-600 hover:bg-lime-100"
                                                        title="เพิ่มประเภท"
                                                    >
                                                        <CheckCircle2 size={14} />
                                                    </button>
                                                    <button
                                                        type="button"
                                                        onMouseDown={(e) => e.preventDefault()}
                                                        onClick={() => {
                                                            setNewIncomeType('');
                                                            setIncomeTypeAddOpen(false);
                                                        }}
                                                        className="shrink-0 rounded-full p-1 text-slate-400 hover:bg-slate-100 hover:text-slate-600"
                                                        title="ยกเลิก"
                                                    >
                                                        <span className="text-xs leading-none">×</span>
                                                    </button>
                                                </span>
                                            ) : (
                                                <button
                                                    type="button"
                                                    onClick={() => {
                                                        setIncomeTypeAddOpen(true);
                                                        requestAnimationFrame(() => incomeAddInputRef.current?.focus());
                                                    }}
                                                    className="inline-flex items-center gap-0.5 rounded-full border border-dashed border-lime-400 bg-lime-50/80 px-2.5 py-1 text-xs font-semibold text-lime-700 hover:bg-lime-100"
                                                >
                                                    <Plus size={12} strokeWidth={2.5} />
                                                    เพิ่ม
                                                </button>
                                            )}
                                            {(settings.incomeTypes || []).length === 0 && !incomeTypeAddOpen && (
                                                <span className="text-[11px] text-slate-500">ยังไม่มีประเภทรายรับ — กด + เพิ่ม</span>
                                            )}
                                        </div>
                                    </div>
                                    <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                                        <Input label="ปริมาณ" type="number" value={incomeQty} onChange={(e: any) => handleIncomeCalc('qty', e.target.value)} />
                                        <Input label="ราคา/หน่วย" type="number" value={incomeUnitPrice} onChange={(e: any) => handleIncomeCalc('price', e.target.value)} />
                                        <Input label="รวม (บาท)" type="number" value={incomeTotal} onChange={(e: any) => handleIncomeCalc('total', e.target.value)} />
                                    </div>
                                    <Button onClick={async () => {
                                        if (!incomeType || !incomeTotal) {
                                            await sessionAlert('กรุณากรอกประเภทรายรับและยอดรวม');
                                            return;
                                        }
                                        onSaveTransaction({
                                            id: Date.now().toString(),
                                            date,
                                            type: 'Income',
                                            category: 'Income',
                                            description: incomeType,
                                            amount: Number(incomeTotal) || 0,
                                            quantity: incomeQty ? Number(incomeQty) : undefined,
                                            unitPrice: incomeUnitPrice ? Number(incomeUnitPrice) : undefined,
                                        } as Transaction);
                                        setIncomeType(''); setIncomeQty(''); setIncomeUnitPrice(''); setIncomeTotal('');
                                    }} className="w-full bg-lime-600 hover:bg-lime-700 py-2.5 focus-ring-strong" data-hotkey-primary="true">
                                        <Wallet size={16} className="mr-1" /> บันทึกรายรับ
                                    </Button>
                                </div>
                                <div className={stepActionWrapClass}>
                                    <Button variant="secondary" onClick={prevStep} className={navBtnClass}>ย้อนกลับ</Button>
                                    <Button onClick={() => void nextStep()} className={navBtnClass}>ถัดไป <ChevronRight size={18} /></Button>
                                </div>
                            </div>
                        )}

                        {/* Step 7: Important Events */}
                        {step === 7 && (
                            <div className="h-full flex flex-col animate-slide-up">
                                <div className="flex justify-between items-center mb-3">
                                    <h3 className="font-bold text-lg flex items-center gap-2"><AlertTriangle className="text-orange-500" /> เหตุการณ์สำคัญประจำวัน</h3>
                                    <span className="text-xs text-slate-400">{new Date(date).toLocaleDateString('th-TH', { day: 'numeric', month: 'short', year: '2-digit' })}</span>
                                </div>

                                {/* Saved events */}
                                {dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'Event').length > 0 && (
                                    <div className="mb-3 space-y-2">
                                        <p className="text-xs font-bold text-slate-500">📌 เหตุการณ์ที่บันทึกแล้ว</p>
                                        {dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'Event').map(t => (
                                            <div key={t.id} className={`p-3 rounded-xl border text-xs relative ${(t as any).eventPriority === 'urgent' ? 'bg-red-50 border-red-200' :
                                                (t as any).eventType === 'warning' ? 'bg-amber-50 border-amber-200' :
                                                    (t as any).eventType === 'success' ? 'bg-emerald-50 border-emerald-200' :
                                                    (t as any).eventType === 'problem' ? 'bg-red-50 border-red-200' :
                                                    (t as any).eventType === 'complaint' ? 'bg-orange-50 border-orange-200' :
                                                    (t as any).eventType === 'request' ? 'bg-violet-50 border-violet-200' :
                                                        'bg-blue-50 border-blue-200'
                                                }`}>
                                                <div className="flex items-center gap-2 mb-1">
                                                    <span className="text-sm">{(t as any).eventType === 'warning' ? '⚠️' : (t as any).eventType === 'success' ? '✅' : (t as any).eventType === 'problem' ? '🚨' : (t as any).eventType === 'complaint' ? '📢' : (t as any).eventType === 'request' ? '📋' : 'ℹ️'}</span>
                                                    <span className="font-bold">{t.description}</span>
                                                    {(t as any).eventPriority === 'urgent' && <span className="px-1.5 py-0.5 bg-red-500 text-white rounded-full text-[9px] font-bold">ด่วน!</span>}
                                                </div>
                                                {onDeleteTransaction && <button onClick={() => onDeleteTransaction(t.id)} className="absolute top-2 right-2 p-0.5 text-slate-300 hover:text-red-500"><Trash2 size={10} /></button>}
                                            </div>
                                        ))}
                                    </div>
                                )}

                                <div className="flex-1 space-y-3">
                                    {/* Event type selector */}
                                    <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-2">
                                        {[
                                            { v: 'info', l: 'ℹ️ ข้อมูล', c: 'border-blue-400 bg-blue-50' },
                                            { v: 'warning', l: '⚠️ เตือน', c: 'border-amber-400 bg-amber-50' },
                                            { v: 'problem', l: '🚨 ปัญหา', c: 'border-red-400 bg-red-50' },
                                            { v: 'success', l: '✅ สำเร็จ', c: 'border-emerald-400 bg-emerald-50' },
                                            { v: 'complaint', l: '📢 ข้อร้องเรียน', c: 'border-orange-400 bg-orange-50' },
                                            { v: 'request', l: '📋 ความต้องการ', c: 'border-violet-400 bg-violet-50' }
                                        ].map(opt => (
                                            <button key={opt.v} onClick={() => setEventType(opt.v)}
                                                className={`py-2 rounded-xl border-2 text-xs font-medium transition-all ${eventType === opt.v ? opt.c + ' font-bold shadow-sm' : 'border-slate-200 bg-white hover:bg-slate-50'}`}>
                                                {opt.l}
                                            </button>
                                        ))}
                                    </div>

                                    {/* Priority */}
                                    <div className="flex gap-3">
                                        <button onClick={() => setEventPriority('normal')} className={`flex-1 py-2 rounded-xl border text-xs transition-all ${eventPriority === 'normal' ? 'bg-slate-100 border-slate-400 font-bold' : 'bg-white'}`}>ปกติ</button>
                                        <button onClick={() => setEventPriority('urgent')} className={`flex-1 py-2 rounded-xl border text-xs transition-all ${eventPriority === 'urgent' ? 'bg-red-100 border-red-400 font-bold text-red-700' : 'bg-white'}`}>🔴 ด่วน!</button>
                                    </div>

                                    {/* Event description */}
                                    <div>
                                        <label className="text-xs font-medium text-slate-600 mb-1 block">📝 รายละเอียดเหตุการณ์</label>
                                        <textarea value={eventDesc} onChange={e => setEventDesc(e.target.value)}
                                            placeholder="เช่น ฝนตกหนักต้องหยุดงาน, เครื่องจักรเสีย, ทรายถูกส่งมาไม่ครบ, งานเสร็จเร็วกว่ากำหนด..."
                                            className="w-full px-3 py-3 border-2 border-slate-200 rounded-xl text-sm focus:border-orange-400 focus:outline-none transition-colors" rows={4} />
                                        {mobileShell && eventDescSuggestions.length > 0 && (
                                            <div className="mt-2 flex gap-1.5 overflow-x-auto pb-1 hide-scrollbar md:flex-wrap md:gap-2 md:overflow-x-visible md:pb-0">
                                                {eventDescSuggestions.slice(0, 8).map(s => (
                                                    <button
                                                        key={s}
                                                        type="button"
                                                        onClick={() => setEventDesc(s)}
                                                        className="shrink-0 min-h-[36px] touch-manipulation rounded-full border border-slate-200 bg-slate-50 px-2.5 py-1.5 text-[11px] font-medium text-slate-600 md:min-h-[40px] md:px-3 md:py-2 md:text-xs"
                                                    >
                                                        {s}
                                                    </button>
                                                ))}
                                            </div>
                                        )}
                                    </div>

                                    {/* Quick phrase chips */}
                                    <div>
                                        <div className="flex flex-wrap gap-1.5">
                                            {['ฝนตก หยุดงาน', 'เครื่องจักรเสีย', 'ทรายไม่ครบ', 'คนงานมาสาย', 'งานเสร็จตามแผน', 'ไฟฟ้าดับ', 'อุบัติเหตุเล็กน้อย'].map(tmpl => (
                                                <button key={tmpl} onClick={() => setEventDesc(prev => prev ? `${prev}, ${tmpl}` : tmpl)}
                                                    className="px-2 py-1 bg-slate-100 hover:bg-orange-100 text-xs rounded-lg text-slate-600 hover:text-orange-700 transition-colors border border-transparent hover:border-orange-200">
                                                    {tmpl}
                                                </button>
                                            ))}
                                        </div>
                                    </div>
                                </div>

                                <div className={mobileShell ? 'sticky bottom-[calc(0.4rem+env(safe-area-inset-bottom,0px))] z-[5] mt-2 space-y-2 rounded-2xl border border-slate-200/80 bg-white/95 p-2.5 shadow-sm backdrop-blur dark:border-white/10 dark:bg-slate-900/90' : 'pt-3 border-t space-y-2'}>
                                    <Button onClick={async () => {
                                        if (!eventDesc.trim()) {
                                            await sessionAlert('กรุณาระบุรายละเอียดเหตุการณ์');
                                            return;
                                        }
                                        onSaveTransaction({
                                            id: Date.now().toString(), date, type: 'Expense', category: 'DailyLog', subCategory: 'Event',
                                            description: eventDesc.trim(), amount: 0,
                                            eventType, eventPriority
                                        } as Transaction);
                                        setEventDesc(''); setEventType('info'); setEventPriority('normal');
                                    }} className="w-full bg-orange-500 hover:bg-orange-600 py-2.5 focus-ring-strong" data-hotkey-primary="true">
                                        <AlertTriangle size={16} className="mr-1" /> บันทึกเหตุการณ์
                                    </Button>
                                    <div className={stepActionWrapClass}>
                                        <Button variant="secondary" onClick={prevStep} className={navBtnClass}>ย้อนกลับ</Button>
                                        <Button onClick={() => void nextStep()} className={navBtnClass}>ถัดไป <ChevronRight size={18} /></Button>
                                    </div>
                                </div>
                            </div>
                        )}

                        {/* Step 7: Summary */}
                        {step === 8 && (
                            <div className="h-full flex flex-col animate-slide-up text-center">
                                <div className={`flex flex-col items-center justify-center ${mobileShell ? 'mb-4' : 'mb-6'}`}>
                                    <FileText size={mobileShell ? 40 : 48} className="mb-3 text-emerald-400" />
                                    <h3 className={`font-bold text-slate-800 dark:text-slate-100 ${mobileShell ? 'text-xl' : 'text-2xl'} mb-1`}>เรียบร้อย</h3>
                                    {!mobileShell && (
                                        <p className="text-slate-500">สรุปข้อมูลที่คุณบันทึกในวันนี้ ({new Date(date).toLocaleDateString('th-TH')})</p>
                                    )}
                                </div>

                                <div className={`grid w-full grid-cols-3 gap-2 sm:grid-cols-7 sm:gap-3 ${mobileShell ? 'mb-4' : 'mb-6'}`}>
                                    <div className="bg-emerald-50 p-2 sm:p-3 rounded-xl border border-emerald-100 text-center">
                                        <div className="text-lg sm:text-2xl font-bold text-emerald-600">{dayTransactions.filter(t => t.category === 'Labor').length}</div>
                                        <div className="text-[10px] sm:text-xs text-emerald-800">ค่าแรง</div>
                                    </div>
                                    <div className="bg-amber-50 p-2 sm:p-3 rounded-xl border border-amber-100 text-center">
                                        <div className="text-lg sm:text-2xl font-bold text-amber-600">{dayTransactions.filter(t => t.category === 'Vehicle').length}</div>
                                        <div className="text-[10px] sm:text-xs text-amber-800">การใช้รถ</div>
                                    </div>
                                    <div className="bg-blue-50 p-2 sm:p-3 rounded-xl border border-blue-100 text-center">
                                        <div className="text-lg sm:text-2xl font-bold text-blue-600">{dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'VehicleTrip').length}</div>
                                        <div className="text-[10px] sm:text-xs text-blue-800">เที่ยวรถ</div>
                                    </div>
                                    <div className="bg-cyan-50 p-2 sm:p-3 rounded-xl border border-cyan-100 text-center">
                                        <div className="text-lg sm:text-2xl font-bold text-cyan-600">{dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'Sand').length}</div>
                                        <div className="text-[10px] sm:text-xs text-cyan-800">ล้างทราย</div>
                                    </div>
                                    <div className="bg-red-50 p-2 sm:p-3 rounded-xl border border-red-100 text-center">
                                        <div className="text-lg sm:text-2xl font-bold text-red-600">{dayTransactions.filter(t => t.category === 'Fuel').length}</div>
                                        <div className="text-[10px] sm:text-xs text-red-800">น้ำมัน</div>
                                    </div>
                                    <div className="bg-lime-50 p-2 sm:p-3 rounded-xl border border-lime-100 text-center">
                                        <div className="text-lg sm:text-2xl font-bold text-lime-600">{dayTransactions.filter(t => t.category === 'Income' && t.type === 'Income').length}</div>
                                        <div className="text-[10px] sm:text-xs text-lime-800">รายรับ</div>
                                    </div>
                                    <div className="bg-orange-50 p-2 sm:p-3 rounded-xl border border-orange-100 text-center">
                                        <div className="text-lg sm:text-2xl font-bold text-orange-600">{dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'Event').length}</div>
                                        <div className="text-[10px] sm:text-xs text-orange-800">เหตุการณ์</div>
                                    </div>
                                </div>

                                {/* Missing category warnings to help user remember what is not recorded yet */}
                                {(() => {
                                    const hasLabor = dayTransactions.some(t => t.category === 'Labor');
                                    const hasVehicle = dayTransactions.some(t => t.category === 'Vehicle');
                                    const hasTrips = dayTransactions.some(t => t.category === 'DailyLog' && t.subCategory === 'VehicleTrip');
                                    const hasSand = dayTransactions.some(t => t.category === 'DailyLog' && t.subCategory === 'Sand');
                                    const hasFuel = dayTransactions.some(t => t.category === 'Fuel');
                                    const hasIncome = dayTransactions.some(t => t.category === 'Income' && t.type === 'Income');
                                    const hasEvent = dayTransactions.some(t => t.category === 'DailyLog' && t.subCategory === 'Event');
                                    const missing: string[] = [];
                                    if (!hasLabor) missing.push('ค่าแรง');
                                    if (!hasVehicle) missing.push('การใช้รถ');
                                    if (!hasTrips) missing.push('เที่ยวรถ');
                                    if (!hasSand) missing.push('ล้างทราย');
                                    if (!hasFuel) missing.push('น้ำมัน');
                                    if (!hasIncome) missing.push('รายรับ');
                                    if (!hasEvent) missing.push('เหตุการณ์');
                                    if (missing.length === 0) return null;
                                    if (mobileShell) {
                                        return (
                                            <div className="mb-4 inline-flex items-center gap-2 rounded-2xl bg-amber-100 px-3 py-2 text-xs font-bold text-amber-900 dark:bg-amber-500/20 dark:text-amber-200">
                                                <AlertTriangle size={14} className="shrink-0" />
                                                ยังว่าง {missing.length} หัวข้อ
                                            </div>
                                        );
                                    }
                                    return (
                                        <div className="mb-6 inline-flex items-center gap-2 rounded-full border border-amber-200 bg-amber-50 px-4 py-2 text-xs text-amber-700">
                                            <AlertTriangle size={14} className="shrink-0" />
                                            <span>วันนี้ยังไม่มีข้อมูล: {missing.join(' • ')}</span>
                                        </div>
                                    );
                                })()}

                                {washHomeDrumsAlertMessage && (
                                    <div className={`w-full text-left ${mobileShell ? 'mb-4' : 'mb-6'}`}>
                                        <div className="rounded-xl border border-amber-200 bg-amber-50 px-3 py-2.5 dark:border-amber-500/35 dark:bg-amber-500/15">
                                            <p className="flex items-center gap-2 text-xs font-bold text-amber-900 dark:text-amber-100">
                                                <AlertTriangle size={16} className="shrink-0 text-amber-600 dark:text-amber-300" />
                                                แจ้งเตือน
                                            </p>
                                            <p className="mt-1.5 pl-0.5 text-xs font-medium leading-relaxed text-amber-900/95 dark:text-amber-100/95 sm:text-sm">
                                                {washHomeDrumsAlertMessage}
                                            </p>
                                        </div>
                                    </div>
                                )}

                                {!mobileShell && (
                                <>
                                {/* Detailed list of today's records */}
                                <div className="flex-1 w-full bg-slate-50/50 dark:bg-white/[0.02] rounded-xl border border-slate-200 dark:border-white/10 overflow-hidden flex flex-col mb-4">
                                    <div className="bg-slate-100 dark:bg-white/5 px-4 py-2 border-b border-slate-200 dark:border-white/10 text-left">
                                        <p className="font-bold text-slate-700 dark:text-slate-200 text-sm">รายการที่บันทึกแล้ววันนี้</p>
                                    </div>
                                    <div className="overflow-y-auto max-h-[250px] p-2 space-y-2 text-left">
                                        {dayTransactions.length === 0 ? (
                                            <p className="text-center text-slate-400 dark:text-slate-500 py-4 text-sm">ไม่มีรายการบันทึกในวันนี้</p>
                                        ) : (
                                            dayTransactions.map(t => {
                                                const driverName = t.driverId ? (employees.find(e => e.id === t.driverId)?.nickname || employees.find(e => e.id === t.driverId)?.name || '') : '';
                                                const vehDay = (t as any).workType === 'HalfDay' ? 'ครึ่งวัน' : 'เต็มวัน';
                                                const vehicleDesc = t.category === 'Vehicle'
                                                    ? `รถ: ${t.vehicleId || '-'}${driverName ? ` (คนขับ: ${driverName})` : ''} · ${vehDay}${t.workDetails ? ` — ${t.workDetails}` : ''}`
                                                    : t.description;
                                                const displayDescription = t.category === 'Vehicle' ? vehicleDesc : t.description;
                                                const isExpanded = expandedRecordId === t.id;
                                                return (
                                                <div
                                                    key={t.id}
                                                    className="bg-white dark:bg-white/[0.04] p-3 rounded-lg border border-slate-200 dark:border-white/10 text-sm flex justify-between items-center hover:bg-slate-50 dark:hover:bg-white/[0.06] cursor-pointer"
                                                    title={displayDescription}
                                                    onClick={() => setExpandedRecordId(prev => prev === t.id ? null : t.id)}
                                                >
                                                    <div className="flex-1">
                                                        <div className="flex items-center gap-2 mb-1">
                                                            {t.category === 'Labor' && <span className="bg-emerald-100 text-emerald-700 text-[10px] px-1.5 py-0.5 rounded font-bold">ค่าแรง</span>}
                                                            {t.category === 'Vehicle' && <span className="bg-amber-100 text-amber-700 text-[10px] px-1.5 py-0.5 rounded font-bold">ใช้รถ</span>}
                                                            {t.category === 'Fuel' && <span className="bg-red-100 text-red-700 text-[10px] px-1.5 py-0.5 rounded font-bold">น้ำมัน</span>}
                                                            {t.category === 'DailyLog' && t.subCategory === 'VehicleTrip' && <span className="bg-blue-100 text-blue-700 text-[10px] px-1.5 py-0.5 rounded font-bold">เที่ยวรถ</span>}
                                                            {t.category === 'DailyLog' && t.subCategory === 'Sand' && <span className="bg-cyan-100 text-cyan-700 text-[10px] px-1.5 py-0.5 rounded font-bold">ทราย</span>}
                                                            {t.category === 'DailyLog' && t.subCategory === 'Event' && <span className="bg-orange-100 text-orange-700 text-[10px] px-1.5 py-0.5 rounded font-bold">เหตุการณ์</span>}
                                                            <span className="font-medium text-slate-700 dark:text-slate-200">{displayDescription}</span>
                                                        </div>
                                                        <div className="text-xs text-slate-500 dark:text-slate-400">
                                                            {t.category === 'Fuel' && <span className="mr-3">{(t.fuelMovement === 'stock_out' || t.vehicleId) ? 'มูลค่าน้ำมันที่ใช้' : 'ค่าน้ำมันที่ซื้อ'}: ฿{t.amount?.toLocaleString()} บาท</span>}
                                                            {t.amount > 0 && t.category !== 'Fuel' && <span className="mr-3">ยอดเงิน: ฿{t.amount.toLocaleString()}</span>}
                                                            {((t as any).perCarTrips || (t as any).tripCount) && <span className="mr-3">จำนวน: {(t as any).perCarTrips || (t as any).tripCount} เที่ยว</span>}
                                                            {((t as any).perCarCubic || (t as any).totalCubic) && <span className="mr-3">ปริมาณ: {(t as any).perCarCubic || (t as any).totalCubic} คิว</span>}
                                                            {(t as any).quantity && <span className="mr-3">ปริมาณ: {(t as any).quantity} {(t as any).unit === 'gallon' ? 'แกลลอน' : 'ลิตร'}</span>}
                                                        </div>
                                                        {isExpanded && (
                                                            <div className="mt-2 p-2 rounded-md bg-slate-50 dark:bg-white/[0.03] border border-slate-200/70 dark:border-white/10 text-xs text-slate-600 dark:text-slate-300 space-y-1">
                                                                {t.category === 'Vehicle' && (
                                                                    <>
                                                                        <div>รถ: {t.vehicleId || '-'}</div>
                                                                        <div>คนขับ: {driverName || '-'}</div>
                                                                        <div>การทำงาน: {(t as any).workType === 'HalfDay' ? 'ครึ่งวัน' : 'เต็มวัน'}</div>
                                                                        <div>รายละเอียดงาน: {t.workDetails || '-'}</div>
                                                                    </>
                                                                )}
                                                                <div>คำอธิบาย: {t.description || '-'}</div>
                                                                <div>วันที่: {formatDateBE(t.date)}</div>
                                                            </div>
                                                        )}
                                                    </div>
                                                    {onDeleteTransaction && (
                                                        <button onClick={(ev) => { ev.stopPropagation(); onDeleteTransaction(t.id); }} className="p-2 text-slate-400 hover:text-red-500 hover:bg-red-50 rounded-lg transition-colors" title="ลบรายการ">
                                                            <Trash2 size={16} />
                                                        </button>
                                                    )}
                                                </div>
                                            )})
                                        )}
                                    </div>
                                </div>
                                </>
                                )}

                                {mobileShell && (
                                    <p className="mb-4 text-center text-sm font-medium text-slate-500 dark:text-slate-400">
                                        รวม {dayTransactions.length} รายการ · ดูรายละเอียดได้ที่แท็บ &quot;รายการ&quot;
                                    </p>
                                )}

                                <Button
                                    onClick={() => {
                                        clearWizardDraftForDate(normalizeDate(date));
                                        setDraftOffer(null);
                                        setAutosaveState('idle');
                                        setAutosaveSavedAt(null);
                                        setAutosaveErrorReason('none');
                                        if (typeof sessionStorage !== 'undefined') {
                                            sessionStorage.removeItem(`cm_draft_dismiss_${normalizeDate(date)}`);
                                        }
                                        setStep(0);
                                    }}
                                    className={`mx-auto mt-auto w-full px-8 sm:w-auto ${mobileShell ? 'min-h-[52px] text-base font-bold' : ''}`}
                                >
                                    {mobileShell ? 'เลือกวันใหม่' : 'เสร็จสิ้น / เริ่มบันทึกวันอื่น'}
                                </Button>
                            </div>
                        )}
                    </Card>
                </div>

                {!mobileShell && (
                <div className="xl:col-span-4 flex min-w-0 w-full flex-col gap-4">
                    {/* Right: Daily Dashboard — กว้างเต็มแถวจนถึง xl; จาก xl เป็นคอลัมน์ข้าง (~≥320px) */}
                    {/* สรุปด่วน: การ์ดแนวตั้ง อ่านง่าย; จอเล็ก 2×2 / แถบข้าง xl สแต็ก 1 คอลัมน์ */}
                    <div className="rounded-2xl border border-slate-200 bg-white p-3.5 shadow-sm dark:border-white/10 dark:bg-slate-950/40">
                        <div className="mb-3 rounded-xl border border-slate-200/80 bg-slate-50/80 px-3 py-2 dark:border-white/10 dark:bg-white/[0.03]">
                            <p className="text-[10px] font-bold uppercase tracking-[0.14em] text-slate-500 dark:text-slate-400">สรุปวันนี้</p>
                            <p className="mt-0.5 text-xs text-slate-500 dark:text-slate-400">
                                {new Date(date + 'T12:00:00').toLocaleDateString('th-TH', { day: 'numeric', month: 'short', year: 'numeric' })}
                            </p>
                        </div>
                        <div className="rounded-xl border border-slate-200/90 bg-gradient-to-b from-slate-50/90 to-white p-2.5 shadow-inner dark:border-white/10 dark:from-white/[0.04] dark:to-white/[0.02] [contain:layout]">
                            <div className="grid grid-cols-2 gap-2 sm:gap-2.5">
                                {[
                                    {
                                        label: 'คนงาน',
                                        unit: 'คน',
                                        display: String(atAGlanceStats.laborCount),
                                        Icon: Users,
                                        cell: 'bg-emerald-500/[0.08] dark:bg-emerald-500/10 border-emerald-200/70 dark:border-emerald-500/20',
                                        iconWrap: 'bg-emerald-500/20 text-emerald-700 dark:text-emerald-300',
                                        labelClass: 'text-emerald-900/80 dark:text-emerald-200',
                                        valueClass: 'text-emerald-800 dark:text-emerald-200',
                                    },
                                    {
                                        label: 'ทรายล้าง',
                                        unit: 'คิว',
                                        display: atAGlanceStats.sandCubic.toLocaleString(),
                                        Icon: Droplets,
                                        cell: 'bg-cyan-500/[0.08] dark:bg-cyan-500/10 border-cyan-200/70 dark:border-cyan-500/20',
                                        iconWrap: 'bg-cyan-500/20 text-cyan-700 dark:text-cyan-300',
                                        labelClass: 'text-cyan-900/80 dark:text-cyan-200',
                                        valueClass: 'text-cyan-800 dark:text-cyan-200',
                                    },
                                    {
                                        label: 'รถ / รายวัน',
                                        unit: 'รายการ',
                                        display: String(atAGlanceStats.vehicleOrDailyCount),
                                        Icon: Truck,
                                        cell: 'bg-orange-500/[0.08] dark:bg-orange-500/10 border-orange-200/70 dark:border-orange-500/20',
                                        iconWrap: 'bg-orange-500/20 text-orange-800 dark:text-orange-300',
                                        labelClass: 'text-orange-900/85 dark:text-orange-200',
                                        valueClass: 'text-orange-800 dark:text-orange-200',
                                    },
                                    {
                                        label: 'น้ำมัน',
                                        unit: 'บาท',
                                        display: atAGlanceStats.fuelBaht.toLocaleString(),
                                        Icon: Fuel,
                                        cell: 'bg-rose-500/[0.08] dark:bg-rose-500/10 border-rose-200/70 dark:border-rose-500/20',
                                        iconWrap: 'bg-rose-500/20 text-rose-700 dark:text-rose-300',
                                        labelClass: 'text-rose-900/85 dark:text-rose-200',
                                        valueClass: 'text-rose-800 dark:text-rose-200',
                                        prefix: '฿',
                                    },
                                ].map((item) => {
                                    const GlanceIcon = item.Icon;
                                    return (
                                        <div
                                            key={item.label}
                                            className={`flex min-w-0 items-center gap-2 rounded-lg border px-2 py-2 sm:px-2.5 sm:py-2.5 ${item.cell}`}
                                        >
                                            <div
                                                className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-md ${item.iconWrap}`}
                                                aria-hidden
                                            >
                                                <GlanceIcon className="h-[15px] w-[15px]" strokeWidth={2.25} />
                                            </div>
                                            <div className="min-w-0 flex-1">
                                                <p className={`truncate text-[10px] font-bold leading-tight ${item.labelClass}`} title={item.label}>
                                                    {item.label}
                                                </p>
                                                <p className={`mt-0.5 flex flex-wrap items-baseline gap-x-1 leading-none ${item.valueClass}`}>
                                                    <span className="text-lg font-black tabular-nums tracking-tight sm:text-xl">
                                                        {'prefix' in item && item.prefix ? <span className="font-black">{item.prefix}</span> : null}
                                                        {item.display}
                                                    </span>
                                                    <span className={`text-[9px] font-semibold opacity-85 ${item.labelClass}`}>{item.unit}</span>
                                                </p>
                                            </div>
                                        </div>
                                    );
                                })}
                            </div>
                        </div>
                    </div>

                    <Card className="flex-1 flex flex-col min-h-[min(400px,70vh)] xl:min-h-[400px] bg-white dark:bg-[#0f111a]/80 backdrop-blur-xl border-slate-200 dark:border-white/10 shadow-xl relative overflow-hidden">
                        <div className="p-3 sm:p-4 border-b border-slate-100 dark:border-white/5 flex flex-col gap-2 sm:flex-row sm:flex-wrap sm:items-center sm:justify-between bg-slate-50/50 dark:bg-white/[0.02]">
                            <div className="min-w-0">
                                <h3 className="font-bold text-sm sm:text-base text-slate-800 dark:text-white flex flex-wrap items-center gap-x-2 gap-y-1">
                                    <span className="inline-flex items-center gap-1.5 shrink-0">
                                        <FileText size={16} className="text-indigo-500 shrink-0" />
                                        <span>รายการบันทึกวันนี้</span>
                                    </span>
                                    <span className="text-xs font-normal text-slate-500 dark:text-slate-400 block w-full sm:w-auto sm:inline sm:pl-0">
                                        {date
                                            ? `(${new Date(date + 'T12:00:00').toLocaleDateString('th-TH', { day: 'numeric', month: 'short', year: 'numeric' })})`
                                            : '(—)'}
                                    </span>
                                </h3>
                            </div>
                            <span className="text-xs font-bold bg-indigo-100 dark:bg-indigo-500/20 text-indigo-700 dark:text-indigo-400 px-2.5 py-1 rounded-full shrink-0 self-start sm:self-center">
                                {dayTransactions.length} รายการ
                            </span>
                            {duplicateTxMeta.count > 0 && (
                                <span className="text-xs font-bold bg-rose-100 dark:bg-rose-500/20 text-rose-700 dark:text-rose-300 px-2.5 py-1 rounded-full shrink-0 self-start sm:self-center">
                                    ซ้ำ {duplicateTxMeta.count} รายการ
                                </span>
                            )}
                        </div>

                        <div className="flex-1 overflow-y-auto p-3 sm:p-4 space-y-3">
                            {dayTransactions.length === 0 ? (
                                <div className="h-full flex flex-col items-center justify-center text-slate-500 dark:text-slate-300">
                                    <FileText size={48} className="mb-3 text-slate-300 dark:text-slate-500" />
                                    <p className="font-medium">ยังไม่มีรายการบันทึก</p>
                                </div>
                            ) : (
                                dayTransactions.map(t => {
                                    const isDuplicate = duplicateTxMeta.duplicateIds.has(t.id);
                                    return (
                                    <div key={t.id} className={`p-3 bg-white dark:bg-white/[0.03] rounded-xl border hover:shadow-md transition-all group relative ${isDuplicate ? 'border-rose-200 dark:border-rose-500/30 bg-rose-50/40 dark:bg-rose-500/10' : 'border-slate-100 dark:border-white/5 hover:border-indigo-300 dark:hover:border-indigo-500/50'}`}>
                                        <div className="flex justify-between items-start mb-1.5">
                                            <span className={`text-[9px] sm:text-[10px] uppercase font-bold px-1.5 py-0.5 rounded tracking-wide ${t.category === 'Labor' ? 'bg-emerald-100 dark:bg-emerald-500/20 text-emerald-700 dark:text-emerald-400' :
                                                t.category === 'Vehicle' ? 'bg-amber-100 dark:bg-amber-500/20 text-amber-700 dark:text-amber-400' :
                                                    t.category === 'Income' ? 'bg-lime-100 dark:bg-lime-500/20 text-lime-700 dark:text-lime-400' :
                                                    t.category === 'Fuel' ? 'bg-red-100 dark:bg-rose-500/20 text-red-700 dark:text-rose-400' :
                                                        t.category === 'DailyLog' ? 'bg-blue-100 dark:bg-blue-500/20 text-blue-700 dark:text-blue-400' :
                                                            'bg-slate-100 dark:bg-white/10 text-slate-600 dark:text-slate-400'
                                                }`}>{t.category}</span>
                                            <div className="flex items-center gap-2">
                                                {isDuplicate && <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-rose-100 dark:bg-rose-500/20 text-rose-700 dark:text-rose-300">อาจซ้ำ</span>}
                                                {t.amount > 0 && <span className="font-bold text-sm text-slate-800 dark:text-white text-right">฿{t.amount.toLocaleString()}</span>}
                                            </div>
                                        </div>
                                        <p className="text-xs font-medium text-slate-700 dark:text-slate-300 mb-1 leading-snug">{t.description}</p>

                                        <div className="flex flex-wrap gap-2 text-[10px] text-slate-500 dark:text-slate-400 mt-2 bg-slate-50 dark:bg-white/[0.02] p-1.5 rounded-lg border border-slate-100 dark:border-white/5">
                                            {t.otHours && <span className="flex items-center gap-1"><span className="w-1.5 h-1.5 rounded-full bg-amber-500"></span>OT: {t.otHours} ชม.</span>}
                                            {t.workDetails && <span className="flex items-center gap-1"><span className="w-1.5 h-1.5 rounded-full bg-indigo-500"></span>งานรถ: {t.workDetails}</span>}
                                            {t.machineHours && <span className="flex items-center gap-1"><span className="w-1.5 h-1.5 rounded-full bg-orange-500"></span>ชม.: {t.machineHours}</span>}
                                            {t.category === 'Fuel' && t.amount != null && <span className="flex items-center gap-1"><span className="w-1.5 h-1.5 rounded-full bg-red-500"></span>{(t.fuelMovement === 'stock_out' || t.vehicleId) ? 'มูลค่าน้ำมันที่ใช้' : 'ค่าน้ำมัน'}: ฿{t.amount.toLocaleString()}</span>}
                                            {t.quantity != null && <span className="flex items-center gap-1"><span className="w-1.5 h-1.5 rounded-full bg-cyan-500"></span>จำนวน: {t.quantity} {(t.unit === 'gallon' ? 'แกลลอน' : 'ลิตร')}</span>}
                                            {(!t.otHours && !t.workDetails && !t.machineHours && (t.category !== 'Fuel' || t.amount == null) && !t.quantity) && <span>วันที่: {formatDateBE(t.date)}</span>}
                                        </div>

                                        {/* Simple Delete Button */}
                                        {onDeleteTransaction && (
                                            <button onClick={() => onDeleteTransaction(t.id)} className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 p-1.5 bg-red-100 hover:bg-red-500 text-red-600 hover:text-white rounded-lg transition-all" title="ลบรายการ">
                                                <Trash2 size={12} />
                                            </button>
                                        )}
                                    </div>
                                )})
                            )}
                        </div>

                        {/* Daily Total Expense Summary Footer */}
                        <div className="p-3 sm:p-4 bg-slate-50/80 dark:bg-black/20 border-t border-slate-100 dark:border-white/5 flex flex-col gap-2 sm:flex-row sm:justify-between sm:items-center backdrop-blur-md">
                            <div className="min-w-0">
                                <span className="text-xs font-bold text-slate-500 dark:text-slate-400 block mb-0.5">รวมค่าใช้จ่ายวันนี้</span>
                                <span className="text-[10px] text-slate-400 dark:text-slate-500 leading-snug">ค่าแรง, รถ, น้ำมัน ฯลฯ</span>
                            </div>
                            <span className="text-xl sm:text-2xl font-black text-rose-600 dark:text-rose-400 tracking-tight tabular-nums shrink-0 self-end sm:self-auto">
                                ฿{dayTransactions.filter(t => t.type === 'Expense').reduce((s, t) => s + t.amount, 0).toLocaleString()}
                            </span>
                        </div>
                    </Card>
                </div>
                )}
            </div>
            )}
        </div>
    );
};

export default DailyStepRecorder;
