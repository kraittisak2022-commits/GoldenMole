import { memo, useState, useMemo, useEffect, useCallback, useRef } from 'react';
import { Calendar, Users, Truck, Fuel, CheckCircle2, ChevronRight, ChevronDown, FileText, Plus, Trash2, Droplets, AlertTriangle, ClipboardList, Pencil, Wallet, Sun, Sunset, Moon, LayoutGrid, Search, GripVertical } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import DatePicker from '../../components/ui/DatePicker';
import NumberPickerInput from '../../components/ui/NumberPickerInput';
import Select from '../../components/ui/Select';
import { getToday, formatDateBE, normalizeDate, formatDisplayNumber } from '../../utils';
import { driverOptionLabel, getVehicleDefaultDriverId } from '../../utils/vehicleDefaultDriverUtils';
import { toDailyWage } from '../../utils/laborWage';
import { Employee, Transaction, AppSettings, WorkType } from '../../types';
import { useSessionDialog } from '../../context/useSessionDialog';
import {
    computeDayWizardStepStats,
    computeSandDrumStockSummary,
    countsAsWizardSandWashRecord,
    countsAsWizardVehicleUsageRecord,
    getTransactionRecencyScore,
    classifyLaborEmployeePool,
    LABOR_POOL_FIXED_CANVAS_IDS,
    mergeLaborCanvasAssignments,
    pickLatestByDayOrder,
    persistedSandHomeDrums,
    sumWizardDailySpend,
    transactionCountsAsVehicleTripMenu,
    vehicleTripDrumCarOptions,
} from './dailyStepRecorderUtils';

import {
    parseSignatureNote,
    formatSignatureDateTime,
    signatureSourceLabel,
} from '../../utils/signatureNote';
import { SignatureAttachmentPreview } from '../../components/SignatureAttachmentPreview';
import { visibleIncomeTypes } from '../../utils/incomeTypes';

const normalizeTimeInputValue = (raw?: string | null) => {
    const value = String(raw || '').trim();
    if (!value) return '';
    const normalized = value.replace(/\./g, ':');
    const m = normalized.match(/^(\d{1,2}):(\d{1,2})$/);
    if (!m) return '';
    const hh = Number(m[1]);
    const mm = Number(m[2]);
    if (!Number.isFinite(hh) || !Number.isFinite(mm)) return '';
    if (hh < 0 || hh > 23 || mm < 0 || mm > 59) return '';
    return `${String(hh).padStart(2, '0')}:${String(mm).padStart(2, '0')}`;
};

interface DailyStepRecorderProps {
    employees: Employee[];
    settings: AppSettings;
    transactions: Transaction[];
    /** วันที่ที่ต้องการให้เปิดหน้า Daily Wizard ทันที (จากเมนูตรวจสอบ) */
    initialDate?: string;
    /** step ที่ต้องการเปิดทันที (จากเมนูตรวจสอบ) */
    initialStep?: number;
    dateFilter?: { start: string; end: string };
    /** คืน false เมื่อผู้ใช้ยกเลิกลายเซ็น / ไม่มีสิทธิ์บันทึก — ให้ผู้เรียก await แล้วไม่รีเซ็ตฟอร์ม */
    onSaveTransaction: (t: Transaction) => void | Promise<boolean | void>;
    onDeleteTransaction?: (id: string) => void;
    /** ลบถาวรจาก Supabase (ใช้ในแท็บรายงาน — ไม่ซ่อนรายการ) */
    onPermanentDeleteTransaction?: (id: string) => void | Promise<void>;
    ensureEmployeeWage?: (emp: Employee) => Promise<number>;
    setSettings?: (updater: AppSettings | ((prev: AppSettings) => AppSettings)) => void;
    /** โหมดเว็บมือถือ: ลดรายละเอียด ซ่อนคอลัมน์สรุปขวาและแท็บรายงาน */
    mobileShell?: boolean;
    /** โหมดสัมผัสสำหรับแท็บเล็ต/ไฮบริด */
    touchLayout?: boolean;
    /** ความหนาแน่นหน้าจอสำหรับ mobile shell */
    densityMode?: 'comfortable' | 'compact';
    /** โหมด Quick Input แบบ Android — แสดงเฉพาะขั้นเดียว */
    singleStepMode?: number;
    /** ซ่อนมุมมองรายงาน (ใช้กับ singleStepMode) */
    hideReportMode?: boolean;
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
            className={`rounded-xl text-left font-medium transition-all border-2 touch-manipulation ${touchUI ? 'min-h-[52px] px-3 py-3 text-base' : 'min-h-[46px] px-3 py-2.5 text-[15px]'} ${selected ? 'border-slate-800 dark:border-slate-300 bg-slate-50 dark:bg-white/10 text-slate-800 dark:text-slate-100' : 'border-slate-200 dark:border-white/10 bg-white dark:bg-white/5 text-slate-500 dark:text-slate-400 hover:border-slate-300 dark:hover:border-white/20'}`}
        >
            {label}
        </button>
    );
});

type LaborEmployeeBucket = 'all' | 'sifter' | 'excavatorMac' | 'nightWatch' | 'generalLabor';

type LaborCanvasCategoryDef = {
    id: string;
    label: string;
    shortTitle: string;
    color: string;
    bgLight: string;
    accent: string;
};

const LABOR_POOL_BUCKET_ICON: Record<LaborEmployeeBucket, typeof Droplets> = {
    all: LayoutGrid,
    sifter: Droplets,
    excavatorMac: Truck,
    nightWatch: Moon,
    generalLabor: Users,
};

const LaborCanvasBucketCard = memo(function LaborCanvasBucketCard({
    cat,
    assigned,
    expanded,
    touchUI,
    dragActive,
    selectedCount,
    employees,
    halfDayEmpIds,
    onToggleExpanded,
    onDropEmployee,
    onRemoveEmployee,
    onToggleHalfDay,
    onMovePickedHere,
    onDragStartEmployee,
}: {
    cat: LaborCanvasCategoryDef;
    assigned: string[];
    expanded: boolean;
    touchUI: boolean;
    dragActive: boolean;
    selectedCount: number;
    employees: Employee[];
    halfDayEmpIds: Set<string>;
    onToggleExpanded: () => void;
    onDropEmployee: (empId: string) => void;
    onRemoveEmployee: (empId: string) => void;
    onToggleHalfDay: (empId: string) => void;
    onMovePickedHere: () => void;
    onDragStartEmployee: (empId: string | null) => void;
}) {
    const showMembers = expanded || assigned.length > 0;
    return (
        <div
            onDragOver={e => e.preventDefault()}
            onDrop={e => {
                e.preventDefault();
                const empId = e.dataTransfer.getData('text/plain');
                if (empId) onDropEmployee(empId);
            }}
            className={`overflow-hidden rounded-xl border bg-white shadow-sm transition-all ${dragActive ? 'border-indigo-400 ring-2 ring-indigo-200/50' : 'border-slate-200/90 hover:border-slate-300'}`}
        >
            <div className="h-0.5" style={{ backgroundColor: cat.accent }} />
            <div className="p-2.5">
                <button
                    type="button"
                    onClick={onToggleExpanded}
                    className="flex w-full items-center gap-2.5 text-left touch-manipulation"
                >
                    <span
                        className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg text-xs font-black text-white"
                        style={{ backgroundColor: cat.accent }}
                    >
                        {assigned.length}
                    </span>
                    <span className="min-w-0 flex-1">
                        <span className="block truncate text-base font-bold text-slate-800" title={cat.label}>
                            {cat.shortTitle}
                        </span>
                        <span className="block text-xs font-medium text-slate-500">
                            {assigned.length > 0 ? `${assigned.length} คนในกล่อง` : 'ว่าง — ลากคนมาวาง'}
                        </span>
                    </span>
                    <ChevronDown
                        size={20}
                        className={`shrink-0 text-slate-400 transition-transform ${showMembers ? 'rotate-180' : ''}`}
                    />
                </button>
                {showMembers && (
                    <div className="mt-2 flex flex-wrap gap-1 border-t border-slate-100 pt-2">
                        {assigned.map(eid => {
                            const emp = employees.find(e => e.id === eid);
                            if (!emp) return null;
                            const isHalf = halfDayEmpIds.has(eid);
                            return (
                                <span
                                    key={eid}
                                    draggable
                                    onDragStart={e => {
                                        e.dataTransfer.setData('text/plain', eid);
                                        e.dataTransfer.effectAllowed = 'move';
                                        onDragStartEmployee(eid);
                                    }}
                                    onDragEnd={() => onDragStartEmployee(null)}
                                    className={`flex max-w-full cursor-grab items-center gap-1 rounded-md border border-slate-200 bg-slate-50 font-medium active:cursor-grabbing ${touchUI ? 'min-h-[38px] px-2.5 py-1.5 text-sm' : 'min-h-[32px] px-2 py-1 text-xs leading-snug'}`}
                                >
                                    <span className="truncate">{getEmployeeDisplayName(emp)}</span>
                                    <button
                                        type="button"
                                        onClick={ev => {
                                            ev.stopPropagation();
                                            onToggleHalfDay(eid);
                                        }}
                                        className={`shrink-0 rounded font-bold touch-manipulation ${touchUI ? 'min-h-8 min-w-8 px-1 text-xs' : 'min-h-6 min-w-6 px-0.5 text-[11px]'} ${isHalf ? 'bg-amber-100 text-amber-700 border border-amber-300' : 'bg-white text-slate-500 border border-slate-200'}`}
                                        title={isHalf ? 'กดเพื่อเปลี่ยนเป็นเต็มวัน' : 'กดเพื่อกำหนดมาครึ่งวัน'}
                                    >
                                        ½
                                    </button>
                                    <button
                                        type="button"
                                        onClick={() => onRemoveEmployee(eid)}
                                        className={`shrink-0 text-red-400 hover:text-red-600 touch-manipulation ${touchUI ? 'flex min-h-7 min-w-7 items-center justify-center text-sm' : 'text-sm leading-none'}`}
                                    >
                                        ×
                                    </button>
                                </span>
                            );
                        })}
                        {assigned.length === 0 && (
                            <span className="text-xs italic text-slate-400">ลากหรือกดย้ายคนมาวาง...</span>
                        )}
                    </div>
                )}
                {selectedCount > 0 && (
                    <button
                        type="button"
                        onClick={onMovePickedHere}
                        className={`mt-2 w-full rounded-lg border border-indigo-300 bg-indigo-50 font-bold text-indigo-800 hover:bg-indigo-100 touch-manipulation ${touchUI ? 'min-h-[44px] py-2.5 text-base' : 'min-h-[36px] py-2 text-sm'}`}
                    >
                        ย้ายมาที่นี่ ({selectedCount})
                    </button>
                )}
            </div>
        </div>
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

// Default work categories for labor canvas (fixed set — ไม่มีกล่องอื่นนอกจากรายการนี้)
const DEFAULT_WORK_CATEGORIES = [
    { id: 'wash1', label: 'ล้างทราย เครื่องร่อน 1 (เก่า)', shortTitle: 'เครื่องร่อน 1 (เก่า)', color: 'bg-blue-500', bgLight: 'bg-blue-50 border-blue-200', accent: '#4A90E2' },
    { id: 'wash2', label: 'ล้างทราย เครื่องร่อน 2 (ใหม่)', shortTitle: 'เครื่องร่อน 2 (ใหม่)', color: 'bg-cyan-500', bgLight: 'bg-cyan-50 border-cyan-200', accent: '#24A7B8' },
    { id: 'washHome', label: 'ล้างทรายที่บ้าน', shortTitle: 'ล้างทรายที่บ้าน', color: 'bg-teal-500', bgLight: 'bg-teal-50 border-teal-200', accent: '#2CB67D' },
    { id: 'pierWatch', label: 'เฝ้าท่าทราย', shortTitle: 'เฝ้าท่าทราย', color: 'bg-pink-500', bgLight: 'bg-pink-50 border-pink-200', accent: '#E64A9E' },
    { id: 'nightShift', label: 'เวร/เฝ้ากลางคืน', shortTitle: 'เวร/เฝ้ากลางคืน', color: 'bg-indigo-600', bgLight: 'bg-indigo-50 border-indigo-200', accent: '#7B5AE6' },
    { id: 'digHaul', label: 'ขุดขน', shortTitle: 'ขุดขน', color: 'bg-orange-600', bgLight: 'bg-orange-50 border-orange-200', accent: '#7962E6' },
    { id: 'generalWork', label: 'งานทั่วไป', shortTitle: 'งานทั่วไป', color: 'bg-slate-600', bgLight: 'bg-slate-50 border-slate-200', accent: '#5F6AD8' },
];
const FIXED_LABOR_CANVAS_CATEGORIES = DEFAULT_WORK_CATEGORIES.filter(c => c.id !== 'generalWork');
const DEFAULT_WORK_CATEGORY_IDS = new Set(DEFAULT_WORK_CATEGORIES.map(c => c.id));
const GENERAL_WORK_PREFIX = 'general:';
type GeneralSubJob = { id: string; title: string };
const newGeneralSubJobId = () => Date.now().toString(36);
const generalSubJobAssignmentKey = (subId: string) => `${GENERAL_WORK_PREFIX}${subId}`;
const isGeneralAssignmentKey = (key: string) =>
    key === 'generalWork' || key === 'general' || key.startsWith(GENERAL_WORK_PREFIX);

const buildGeneralSubJobsFromAssignments = (
    wa: Record<string, string[]>,
    customCategories?: Array<{ id?: string; label?: string }>,
    legacyNote?: string
): GeneralSubJob[] => {
    const labelByKey: Record<string, string> = {};
    for (const row of customCategories || []) {
        const id = String(row.id || '').trim();
        const label = String(row.label || '').trim();
        if (id && label) labelByKey[id] = label;
    }
    const buckets: Array<{ key: string; ids: string[] }> = [];
    for (const [key, ids] of Object.entries(wa)) {
        const list = (ids || []).map(id => String(id).trim()).filter(Boolean);
        if (list.length === 0) continue;
        if (isGeneralAssignmentKey(key) || !DEFAULT_WORK_CATEGORY_IDS.has(key)) {
            buckets.push({ key, ids: list });
        }
    }
    if (buckets.length === 0) {
        return [{ id: newGeneralSubJobId(), title: String(legacyNote || '').trim() }];
    }
    return buckets.map(bucket => {
        if (bucket.key.startsWith(GENERAL_WORK_PREFIX)) {
            return {
                id: bucket.key.slice(GENERAL_WORK_PREFIX.length),
                title:
                    labelByKey[bucket.key] ||
                    (bucket.key === 'generalWork' || bucket.key === 'general'
                        ? String(legacyNote || '').trim()
                        : ''),
            };
        }
        return {
            id: newGeneralSubJobId(),
            title:
                labelByKey[bucket.key] ||
                (bucket.key === 'generalWork' || bucket.key === 'general'
                    ? String(legacyNote || '').trim()
                    : ''),
        };
    });
};

const remapGeneralWorkAssignments = (
    wa: Record<string, string[]>,
    subJobs: GeneralSubJob[]
): Record<string, string[]> => {
    const out: Record<string, string[]> = {};
    const pushUnique = (key: string, ids: string[]) => {
        const list = (ids || []).map(id => String(id).trim()).filter(Boolean);
        if (list.length === 0) return;
        if (!out[key]) out[key] = [];
        const seen = new Set(out[key]);
        for (const id of list) {
            if (!seen.has(id)) {
                seen.add(id);
                out[key].push(id);
            }
        }
    };
    for (const [k, ids] of Object.entries(wa)) {
        if (!isGeneralAssignmentKey(k) && DEFAULT_WORK_CATEGORY_IDS.has(k)) {
            pushUnique(k, ids);
        }
    }
    const generalBuckets = Object.entries(wa).filter(
        ([k, ids]) =>
            (isGeneralAssignmentKey(k) || !DEFAULT_WORK_CATEGORY_IDS.has(k)) &&
            Array.isArray(ids) &&
            ids.length > 0
    );
    generalBuckets.forEach(([, ids], index) => {
        const job = subJobs[index] || subJobs[subJobs.length - 1];
        if (!job) return;
        pushUnique(generalSubJobAssignmentKey(job.id), ids);
    });
    return out;
};

/** รวมคีย์ประเภทงานเก่า/กำหนดเอง — คงกล่อง general:… แยกตามชื่องาน */
const mergeUnknownLaborCanvasAssignments = (raw: Record<string, string[]> | undefined | null): Record<string, string[]> =>
    mergeLaborCanvasAssignments(sanitizeWorkAssignments(raw));
const normalizeCategoryLabel = (label: string) => label.trim().replace(/\s+/g, ' ').toLowerCase();
const HIDDEN_WORK_CATEGORY_IDS = new Set(['other']);
const HIDDEN_WORK_CATEGORY_LABELS = new Set(['ทำอื่นๆ'].map(normalizeCategoryLabel));
const isGeneratedCategoryId = (value: string) => /^c_\d+$/.test((value || '').trim());
const isCfgLikeCategoryId = (value: string) => /^cfg[_-]/i.test((value || '').trim());
const isCfgLikeToken = (value: string) => /^cfg(?:[_-]|[a-z0-9]{4,})/i.test((value || '').trim());
const isGeneratedCategoryLabel = (value: string) => isGeneratedCategoryId(value);
const isSystemCategoryLabel = (value: string) =>
    isGeneratedCategoryLabel(value) || isCfgLikeToken(value);
const sanitizeWorkAssignments = (raw: Record<string, string[]> | undefined | null) => {
    if (!raw || typeof raw !== 'object') return {};
    return Object.fromEntries(
        Object.entries(raw).filter(([catId]) => !HIDDEN_WORK_CATEGORY_IDS.has(catId))
    );
};

/** คีย์งานที่บ้าน (รวมรูปแบบเก่าจากมือถือหลายกล่อง) */
const HOME_WASH_ASSIGNMENT_KEYS = ['washHome', 'wash_home', 'wash_yard_house', 'sift_home'] as const;

function countWashHomeAssignedWorkers(wa: Record<string, string[] | undefined>): number {
    const ids = new Set<string>();
    for (const k of HOME_WASH_ASSIGNMENT_KEYS) {
        const list = wa[k];
        if (!Array.isArray(list)) continue;
        for (const id of list) {
            const s = String(id || '').trim();
            if (s) ids.add(s);
        }
    }
    return ids.size;
}

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

const LABOR_EMPLOYEE_BUCKET_LABEL: Record<LaborEmployeeBucket, string> = {
    all: 'พนักงานทั้งหมด',
    sifter: 'พนักงานร่อนทราย',
    excavatorMac: 'คนขับรถแม็คโคร',
    nightWatch: 'เฝ้ากลางคืน',
    generalLabor: 'พนักงานทั่วไป',
};
const LABOR_EMPLOYEE_BUCKET_HINT: Record<LaborEmployeeBucket, string> = {
    all: 'เลือกลงกล่องงานได้ทุกประเภท',
    sifter: 'ตำแหน่งมีคำว่า «ร่อน»',
    excavatorMac: 'ตำแหน่ง «คนขับรถแม็คโคร» เท่านั้น',
    nightWatch: 'ตำแหน่งเวร/เฝ้ากลางคืน',
    generalLabor: 'เฉพาะตำแหน่งพนักงานทั่วไป',
};
const LABOR_EMPLOYEE_BUCKET_ORDER: LaborEmployeeBucket[] = ['all', 'sifter', 'excavatorMac', 'nightWatch', 'generalLabor'];
const detectDefaultCubicPerTrip = (vehicleName: string, fallback: number) => {
    const name = (vehicleName || '').toLowerCase().replace(/\s+/g, '');
    if (name.includes('10ล้อ') || name.includes('สิบล้อ')) return 6;
    if (name.includes('6ล้อ') || name.includes('หกล้อ')) return 3;
    return fallback;
};

type WizardTripEntry = {
    id: string;
    vehicle: string;
    driver: string;
    work: string;
    cubicPerTrip: string;
    billingMode: 'PerTrip' | 'LumpSum';
    lumpSumCubic: string;
};

const emptyWizardTripEntry = (): WizardTripEntry => ({
    id: `${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
    vehicle: '',
    driver: '',
    work: '',
    cubicPerTrip: '',
    billingMode: 'PerTrip',
    lumpSumCubic: '',
});

/** คิวรวมจากฟอร์ม: แยกคิดเป็นเที่ยว (ใช้เที่ยวรวม ÷ รถที่โหมดเที่ยว) + รวมจากเหมา */
const computeWizardTripFormCubic = (
    tripEntries: WizardTripEntry[],
    tripMorning: string,
    tripAfternoon: string,
): number => {
    const totalTrips = (Number(tripMorning) || 0) + (Number(tripAfternoon) || 0);
    const active = tripEntries.filter(e => e.vehicle);
    let lumpSum = 0;
    const perTripCars: WizardTripEntry[] = [];
    active.forEach(e => {
        if (e.billingMode === 'LumpSum') lumpSum += Number(e.lumpSumCubic) || 0;
        else perTripCars.push(e);
    });
    if (perTripCars.length === 0 || totalTrips <= 0) return lumpSum;
    const tripsPerCar = Math.floor(totalTrips / perTripCars.length);
    const remainder = totalTrips % perTripCars.length;
    let perTripCubic = 0;
    perTripCars.forEach((entry, idx) => {
        const carTrips = tripsPerCar + (idx < remainder ? 1 : 0);
        const carCubicPerTrip = Number(entry.cubicPerTrip) || detectDefaultCubicPerTrip(entry.vehicle, 3);
        perTripCubic += carTrips * carCubicPerTrip;
    });
    return lumpSum + perTripCubic;
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
        const n = countWashHomeAssignedWorkers(wa);
        washHomeWorkers = Math.max(washHomeWorkers, n);
    }
    const sand = txs.filter(t => t.category === 'DailyLog' && t.subCategory === 'Sand');
    const fromSand = persistedSandHomeDrums(sand);
    const fromLabor = labor.length > 0 ? Math.max(0, ...labor.map(t => Number((t as any).drumsWashedAtHome || 0))) : 0;
    const homeDrums = Math.max(fromSand, fromLabor);
    if (washHomeWorkers >= 1 && homeDrums <= 0) {
        return `มีพนักงานในประเภทงาน "ล้างทรายที่บ้าน" (ข้อมูลเก่า) ${washHomeWorkers} คน แต่ยังไม่ระบุจำนวนถังที่ล้างที่บ้านวันนี้ — กรุณาตรวจสอบและกรอกในขั้นล้างทราย`;
    }
    return null;
}

const DailyStepRecorder = ({ employees, settings, transactions, initialDate, initialStep, dateFilter, onSaveTransaction, onDeleteTransaction, onPermanentDeleteTransaction, ensureEmployeeWage, setSettings, mobileShell = false, touchLayout = false, densityMode = 'comfortable', singleStepMode, hideReportMode = false }: DailyStepRecorderProps) => {
    const { alert: sessionAlert, confirm: sessionConfirm } = useSessionDialog();
    const isTouchLayout = useMediaQuery('(max-width: 1023px)');
    /** จอสัมผัส / มือถือ: ปุ่มและช่องกดใหญ่ขึ้น */
    const touchUI = mobileShell || touchLayout || isTouchLayout;
    const isSingleStepMode = typeof singleStepMode === 'number';
    const isCompactDensity = mobileShell && densityMode === 'compact';
    const navBtnClass = touchUI ? 'min-h-[48px] px-5 text-base font-semibold touch-manipulation focus-ring-strong' : 'focus-ring-strong';
    const stepActionWrapClass = isSingleStepMode
        ? 'hidden'
        : mobileShell
        ? 'sticky bottom-[calc(0.4rem+env(safe-area-inset-bottom,0px))] z-[5] mt-auto flex justify-between gap-3 rounded-2xl border border-slate-200/80 bg-white/95 p-2.5 shadow-sm backdrop-blur dark:border-white/10 dark:bg-slate-900/90'
        : 'mt-auto flex justify-between gap-3 pt-3';
    const [step, setStep] = useState(0);
    const [date, setDate] = useState(() => normalizeDate(initialDate) || getToday());
    const [viewMode, setViewMode] = useState<'record' | 'report'>('record');

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
    useEffect(() => {
        if (!isSingleStepMode) return;
        const bounded = Math.max(0, Math.min(singleStepMode, STEPS.length - 1));
        setStep(bounded);
    }, [isSingleStepMode, singleStepMode]);
    // ช่วงวันที่สำหรับรายงาน (ใช้ dateFilter เป็นค่าเริ่มต้นถ้ามี)
    const [reportStart, setReportStart] = useState<string>(dateFilter?.start || '');
    const [reportEnd, setReportEnd] = useState<string>(dateFilter?.end || '');

    // Derived: Transactions for the selected date (normalize date so DB ISO string matches YYYY-MM-DD)
    const dayTransactions = useMemo(() => {
        const norm = normalizeDate(date);
        return transactions.filter(t => normalizeDate(t.date) === norm);
    }, [transactions, date]);
    /** สรุปข้อมูล Sand ที่บันทึกแล้ว — ใช้แทน dayTransactions ใน effect เพื่อไม่รีเซ็ตฟอร์มเมื่อ parent ส่ง array reference ใหม่โดยเนื้อหาเดิม */
    const sandPersistedPrefillSignature = useMemo(() => {
        const sandTx = dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'Sand') as any[];
        if (sandTx.length === 0) return '';
        return sandTx
            .map((t) =>
                [
                    t.id,
                    String(t.sandMachineType ?? ''),
                    String(t.sandMorning ?? ''),
                    String(t.sandAfternoon ?? ''),
                    JSON.stringify(t.sandOperators || []),
                    String(t.drumsObtained ?? ''),
                    String((t as any).drumsWashedAtHome ?? ''),
                    String(t.sandMorningStart ?? ''),
                    String(t.sandAfternoonStart ?? ''),
                    String(t.sandEveningEnd ?? ''),
                    String(t.sandBatchId ?? ''),
                ].join(':')
            )
            .sort()
            .join('|');
    }, [dayTransactions]);
    /** สรุป Labor Attendance (canvas) ที่บันทึกแล้ว — กันไม่ให้รีเซ็ต workAssignments เมื่อ transactions reference เปลี่ยน */
    const laborCanvasPersistedPrefillSignature = useMemo(() => {
        const laborAttendance = dayTransactions.filter(
            (t) => t.category === 'Labor' && t.subCategory === 'Attendance' && t.laborStatus === 'Work'
        );
        if (laborAttendance.length === 0) return '';
        const latest = pickLatestByDayOrder(laborAttendance as any[], dayTransactions) as any;
        if (!latest?.id) return '';
        const wa =
            latest.workAssignments && typeof latest.workAssignments === 'object'
                ? mergeUnknownLaborCanvasAssignments(latest.workAssignments as Record<string, string[]>)
                : ({} as Record<string, string[]>);
        const waSig = Object.keys(wa)
            .sort()
            .map((k) => `${k}:${(wa[k] || []).slice().sort().join(',')}`)
            .join(';');
        const wte = (latest.workTypeByEmployee || {}) as Record<string, string>;
        const halfSig = Object.keys(wte)
            .sort()
            .filter((id) => wte[id] === 'HalfDay')
            .join(',');
        return [
            String(latest.id),
            waSig,
            String(latest.laborGeneralWorkNotes ?? '').trim(),
            halfSig,
            String(latest.drumsWashedAtHome ?? ''),
        ].join('#');
    }, [dayTransactions]);
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
    const eventDescSuggestions = useMemo(() => {
        const fromHistory = transactions
            .filter(t => t.category === 'DailyLog' && t.subCategory === 'Event')
            .map(t => t.description);
        return buildSmartSuggestions(fromHistory, 10);
    }, [transactions]);
    const dayStepStats = useMemo(
        () => computeDayWizardStepStats(dayTransactions),
        [dayTransactions],
    );
    const hasExistingWizardData = useMemo(() => Object.values(dayStepStats).some(count => count > 0), [dayStepStats]);
    const latestLaborAttendance = useMemo(() => {
        const laborAttendance = dayTransactions
            .filter(t => t.category === 'Labor' && t.subCategory === 'Attendance') as any[];
        return pickLatestByDayOrder(laborAttendance, dayTransactions);
    }, [dayTransactions]);
    const resumeStep = useMemo(() => {
        if (dayStepStats.eventCount > 0) return 7;
        if (dayStepStats.incomeCount > 0) return 6;
        if (dayStepStats.fuelCount > 0) return 5;
        if (dayStepStats.sandWashCount > 0) return 4;
        if (dayStepStats.tripCount > 0) return 3;
        if (dayStepStats.vehicleUsageCount > 0) return 2;
        if (dayStepStats.laborCount > 0) return 1;
        return 1;
    }, [dayStepStats]);
    const mobileLaborCanvasPreview = useMemo(() => {
        const assignments = mergeUnknownLaborCanvasAssignments(latestLaborAttendance?.workAssignments as Record<string, string[]> | undefined);
        if (Object.keys(assignments).length === 0) return [];
        const knownLabels = new Map<string, string>();
        DEFAULT_WORK_CATEGORIES.forEach(c => knownLabels.set(c.id, c.label));
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
    }, [latestLaborAttendance, employees]);
    const hasLaborAttendanceToday = dayTransactions.some(t => t.category === 'Labor' && t.subCategory === 'Attendance');
    /** สรุปวันนี้ (คอลัมน์ขวา) — คำนวณครั้งเดียว */
    const atAGlanceStats = useMemo(() => {
        const wizard = computeDayWizardStepStats(dayTransactions);
        const laborCount = dayTransactions
            .filter(t => t.category === 'Labor' && t.laborStatus === 'Work')
            .reduce((acc, t) => acc + (t.employeeIds?.length || 0), 0);
        const fuelBaht = dayTransactions.filter(t => t.category === 'Fuel').reduce((acc, t) => acc + (t.amount || 0), 0);
        return {
            laborCount,
            sandCubic: wizard.sandWashCubic,
            sandWashCount: wizard.sandWashCount,
            vehicleTripCount: wizard.tripCount,
            vehicleUsageCount: wizard.vehicleUsageCount,
            fuelBaht,
        };
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
            String((t as any).tripBillingMode || ''),
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
    const duplicateLaborAttendanceMeta = useMemo(() => {
        const byDate = new Map<string, Transaction[]>();
        transactions
            .filter(t => t.category === 'Labor' && t.subCategory === 'Attendance' && t.laborStatus === 'Work')
            .forEach((t) => {
                const key = normalizeDate(t.date);
                const prev = byDate.get(key) || [];
                prev.push(t);
                byDate.set(key, prev);
            });
        const duplicateGroups: Array<{ date: string; items: Transaction[] }> = [];
        let duplicateRecordCount = 0;
        byDate.forEach((items, date) => {
            if (items.length > 1) {
                duplicateGroups.push({ date, items });
                duplicateRecordCount += items.length;
            }
        });
        return {
            duplicateGroups,
            duplicateDateCount: duplicateGroups.length,
            duplicateRecordCount,
        };
    }, [transactions]);
    const handleMergeDuplicateLaborAttendance = useCallback(async () => {
        if (!setSettings) {
            await sessionAlert('ไม่สามารถรวมรายการได้ในโหมดนี้');
            return;
        }
        if (duplicateLaborAttendanceMeta.duplicateDateCount === 0) {
            await sessionAlert('ไม่พบรายการ LABOR ที่ซ้ำในวันเดียวกัน');
            return;
        }
        const hideIds = duplicateLaborAttendanceMeta.duplicateGroups.flatMap(({ items }) => {
            const sorted = [...items].sort((a, b) => {
                const d = normalizeDate(a.date).localeCompare(normalizeDate(b.date));
                if (d !== 0) return d;
                return String(a.id).localeCompare(String(b.id));
            });
            return sorted.slice(0, -1).map(t => t.id);
        });
        if (hideIds.length === 0) {
            await sessionAlert('ไม่พบรายการที่ต้องรวมเพิ่มเติม');
            return;
        }
        const shouldProceed = await sessionConfirm(
            `พบ LABOR ซ้ำ ${duplicateLaborAttendanceMeta.duplicateDateCount} วัน (${duplicateLaborAttendanceMeta.duplicateRecordCount} รายการ)\nระบบจะเก็บเฉพาะรายการล่าสุดของแต่ละวัน และซ่อนรายการเก่า ${hideIds.length} รายการ\n\nต้องการดำเนินการต่อหรือไม่?`,
            { title: 'รวมรายการ LABOR ซ้ำย้อนหลัง' }
        );
        if (!shouldProceed) return;
        setSettings(prev => ({
            ...prev,
            appDefaults: {
                ...(prev.appDefaults || {}),
                hiddenTransactionIds: Array.from(new Set([...(prev.appDefaults?.hiddenTransactionIds || []), ...hideIds])),
            },
        }));
        await sessionAlert(`รวมรายการ LABOR ซ้ำเรียบร้อยแล้ว\nซ่อนรายการเก่า ${hideIds.length} รายการ`);
    }, [duplicateLaborAttendanceMeta.duplicateDateCount, duplicateLaborAttendanceMeta.duplicateGroups, duplicateLaborAttendanceMeta.duplicateRecordCount, sessionAlert, sessionConfirm, setSettings]);
    const shouldContinueWithWarning = useCallback(
        async (messages: string[], title = 'พบข้อมูลที่อาจซ้ำหรือผิดปกติ') => {
            if (messages.length === 0) return true;
            const text = `- ${messages.join('\n- ')}\n\nต้องการบันทึกต่อหรือไม่?`;
            return sessionConfirm(text, { title });
        },
        [sessionConfirm]
    );
    const hasSemanticNearDuplicate = useCallback((candidate: Transaction, options?: { ignoreId?: string }) => {
        const candidateDesc = String(candidate.description || '').trim().toLowerCase();
        const candidateEmp = new Set(candidate.employeeIds || []);
        return dayTransactions.some((existing) => {
            if (options?.ignoreId && existing.id === options.ignoreId) return false;
            if (existing.id === candidate.id) return false;
            if (existing.category !== candidate.category) return false;
            if ((existing.subCategory || '') !== (candidate.subCategory || '')) return false;
            const sameDate = normalizeDate(existing.date) === normalizeDate(candidate.date);
            if (!sameDate) return false;
            const existingDesc = String(existing.description || '').trim().toLowerCase();
            const sameAmount = Math.abs(Number(existing.amount || 0) - Number(candidate.amount || 0)) <= 1;
            const descLooksClose = candidateDesc === existingDesc || (candidateDesc.length > 8 && existingDesc.includes(candidateDesc.slice(0, 8)));
            const existingEmp = new Set(existing.employeeIds || []);
            const overlap = Array.from(candidateEmp).filter(id => existingEmp.has(id)).length;
            return (sameAmount && descLooksClose) || overlap >= Math.max(1, Math.floor(candidateEmp.size * 0.7));
        });
    }, [dayTransactions]);

    const getEmpPositions = (e: Employee) => e.positions ?? (e.position ? [e.position] : []);
    const driverEmployees = useMemo(() => employees.filter(e => getEmpPositions(e).includes('คนขับรถ')), [employees]);

    const defaultVehicleMachineWage = useMemo(
        () => String(settings.appDefaults?.vehicleDefaultMachineWage ?? 4500),
        [settings.appDefaults?.vehicleDefaultMachineWage]
    );
    const vehicleMachineWageTemplates = [defaultVehicleMachineWage];
    // Labor State
    const [laborSearch, setLaborSearch] = useState('');
    const debouncedLaborSearch = useDebouncedValue(laborSearch, 220);
    const [laborEmployeeBucket, setLaborEmployeeBucket] = useState<LaborEmployeeBucket>('all');
    const [laborGeneralWorkNotes, setLaborGeneralWorkNotes] = useState('');
    const [generalSubJobs, setGeneralSubJobs] = useState<GeneralSubJob[]>([{ id: 'default', title: '' }]);
    const [otVisibleEmployeeCount, setOtVisibleEmployeeCount] = useState(48);
    const [selectedEmps, setSelectedEmps] = useState<string[]>([]);
    const [laborStatus, setLaborStatus] = useState<'Work' | 'OT' | 'Leave'>('Work');
    /** รายคน: เฉพาะคนที่มาครึ่งวัน (ไม่มีในนี้ = เต็มวันปกติ) */
    const [halfDayEmpIds, setHalfDayEmpIds] = useState<Set<string>>(new Set());
    /** จำนวนถังล้างที่บ้าน (ซิงก์จากขั้นล้างทราย / พรีฟิลจากข้อมูลวันนี้) */
    const [drumsWashedAtHome, setDrumsWashedAtHome] = useState('');
    const [otHours, setOtHours] = useState('');
    const [otDesc, setOtDesc] = useState('');
    const [otRate, setOtRate] = useState('');
    // Canvas-style work category assignments: { categoryId: employeeId[] }
    const [workAssignments, setWorkAssignments] = useState<Record<string, string[]>>({});
    const normalizedWorkAssignments = useMemo(
        () => mergeUnknownLaborCanvasAssignments(workAssignments),
        [workAssignments]
    );
    const [dragEmployee, setDragEmployee] = useState<string | null>(null);
    const [laborBucketExpanded, setLaborBucketExpanded] = useState<Record<string, boolean>>({});
    const laborBucketCounts = useMemo(() => {
        const counts: Record<LaborEmployeeBucket, number> = { all: 0, sifter: 0, excavatorMac: 0, nightWatch: 0, generalLabor: 0 };
        for (const e of employees) {
            if (e.inactive) continue;
            counts.all += 1;
            const bucket = classifyLaborEmployeePool(e);
            if (bucket) counts[bucket] += 1;
        }
        return counts;
    }, [employees]);
    const filteredLaborEmployees = useMemo(
        () =>
            employees.filter(e => {
                if (e.inactive) return false;
                if (!isEmployeeMatchedBySearch(e, debouncedLaborSearch)) return false;
                if (laborEmployeeBucket === 'all') return true;
                return classifyLaborEmployeePool(e) === laborEmployeeBucket;
            }),
        [employees, laborEmployeeBucket, debouncedLaborSearch]
    );
    const otVisibleEmployees = useMemo(
        () => filteredLaborEmployees.slice(0, otVisibleEmployeeCount),
        [filteredLaborEmployees, otVisibleEmployeeCount]
    );
    const laborAssignedEmpIds = useMemo(
        () => new Set(Object.values(workAssignments).flatMap(ids => (Array.isArray(ids) ? ids : []))),
        [workAssignments]
    );
    const poolVisibleEmployees = useMemo(
        () =>
            filteredLaborEmployees
                .filter(e => !laborAssignedEmpIds.has(e.id))
                .slice()
                .sort((a, b) =>
                    getEmployeeDisplayName(a).localeCompare(getEmployeeDisplayName(b), 'th')
                ),
        [filteredLaborEmployees, laborAssignedEmpIds]
    );
    const laborFixedCanvasCategories = useMemo(() => {
        if (laborEmployeeBucket === 'all') return FIXED_LABOR_CANVAS_CATEGORIES;
        const ids = new Set(LABOR_POOL_FIXED_CANVAS_IDS[laborEmployeeBucket]);
        return FIXED_LABOR_CANVAS_CATEGORIES.filter((c) => ids.has(c.id));
    }, [laborEmployeeBucket]);
    const assignEmployeesToLaborBucket = useCallback(
        async (bucketId: string, empIds: string[]) => {
            const ids = [...new Set(empIds.map(id => String(id).trim()).filter(Boolean))];
            if (ids.length === 0) return;
            for (const id of ids) {
                const emp = employees.find(x => x.id === id);
                if (emp && (emp.baseWage == null || emp.baseWage === 0) && ensureEmployeeWage) {
                    try {
                        await ensureEmployeeWage(emp);
                    } catch {
                        return;
                    }
                }
            }
            setWorkAssignments(prev => {
                const u = { ...prev };
                for (const empId of ids) {
                    Object.keys(u).forEach(k => {
                        u[k] = (u[k] || []).filter(eid => eid !== empId);
                    });
                }
                const bucket = [...(u[bucketId] || [])];
                for (const empId of ids) {
                    if (!bucket.includes(empId)) bucket.push(empId);
                }
                u[bucketId] = bucket;
                return u;
            });
            setLaborBucketExpanded(prev => ({ ...prev, [bucketId]: true }));
            setDragEmployee(null);
            setSelectedEmps(prev => prev.filter(id => !ids.includes(id)));
        },
        [employees, ensureEmployeeWage]
    );
    const removeEmployeeFromLaborBucket = useCallback((bucketId: string, empId: string) => {
        setWorkAssignments(prev => {
            const nextList = (prev[bucketId] || []).filter(id => id !== empId);
            if (nextList.length === 0) {
                setLaborBucketExpanded(exp => ({ ...exp, [bucketId]: false }));
            }
            return { ...prev, [bucketId]: nextList };
        });
    }, []);
    const latestLaborDrumsWashedAtHome = useMemo(() => {
        if (!latestLaborAttendance) return 0;
        return Number((latestLaborAttendance as any).drumsWashedAtHome || 0);
    }, [latestLaborAttendance]);
    const totalAssignedWorkers = useMemo(
        () => Object.values(workAssignments).reduce((sum, ids) => sum + (Array.isArray(ids) ? ids.length : 0), 0),
        [workAssignments]
    );
    const validationChecklist = useMemo(() => {
        const items: Array<{ level: 'warning' | 'info'; message: string; fix: string }> = [];
        if (step === 1 && laborStatus === 'Work') {
            if (totalAssignedWorkers === 0) {
                items.push({ level: 'warning', message: 'ยังไม่ได้จัดคนลงกล่องงาน', fix: 'เลือกพนักงานแล้วกดย้ายลงประเภทงานอย่างน้อย 1 กล่อง' });
            }
        }
        if (step === 1 && laborStatus === 'OT') {
            if (selectedEmps.length === 0) items.push({ level: 'warning', message: 'ยังไม่ได้เลือกคนทำ OT', fix: 'เลือกพนักงานอย่างน้อย 1 คน' });
            if (selectedEmps.length > 0 && !otDesc.trim()) items.push({ level: 'warning', message: 'OT ยังไม่ระบุเหตุผลงาน', fix: 'กรอกรายละเอียดงาน OT สั้นๆ เช่น ล้างทรายรอบเย็น' });
            if ((Number(otHours) || 0) <= 0) items.push({ level: 'info', message: 'OT ชั่วโมงยังว่าง', fix: 'ใส่จำนวนชั่วโมงเพื่อคำนวณยอดถูกต้อง' });
        }
        return items;
    }, [step, laborStatus, totalAssignedWorkers, workAssignments, selectedEmps.length, otDesc, otHours]);
    const sortedDayTransactions = useMemo(() => {
        return [...dayTransactions].sort((a, b) => {
            const scoreA = getTransactionRecencyScore(a, dayTransactions, dayTransactions.findIndex(x => x.id === a.id));
            const scoreB = getTransactionRecencyScore(b, dayTransactions, dayTransactions.findIndex(x => x.id === b.id));
            if (scoreA !== scoreB) return scoreB - scoreA;
            return String(b.id).localeCompare(String(a.id));
        });
    }, [dayTransactions]);
    const timelineStatusById = useMemo(() => {
        const latestByGroup = new Map<string, string>();
        for (const tx of sortedDayTransactions) {
            const key = `${tx.category}|${tx.subCategory || '-'}|${String(tx.description || '').trim().slice(0, 40)}`;
            if (!latestByGroup.has(key)) latestByGroup.set(key, tx.id);
        }
        const out = new Map<string, 'latest' | 'edited' | 'final'>();
        for (const tx of sortedDayTransactions) {
            const key = `${tx.category}|${tx.subCategory || '-'}|${String(tx.description || '').trim().slice(0, 40)}`;
            if (latestByGroup.get(key) === tx.id) {
                out.set(tx.id, 'latest');
            } else {
                out.set(tx.id, 'edited');
            }
        }
        return out;
    }, [sortedDayTransactions]);
    const smartWorkTemplates = useMemo(() => {
        const selectedWeekday = new Date(`${normalizeDate(date)}T12:00:00`).getDay();
        const pool = transactions.filter(
            t => t.category === 'Labor' &&
                t.subCategory === 'Attendance' &&
                t.laborStatus === 'Work' &&
                t.workAssignments &&
                new Date(`${normalizeDate(t.date)}T12:00:00`).getDay() === selectedWeekday
        ) as any[];
        const freq = new Map<string, { count: number; workAssignments: Record<string, string[]>; label: string }>();
        for (const tx of pool) {
            const wa = mergeUnknownLaborCanvasAssignments(sanitizeWorkAssignments(tx.workAssignments));
            const key = JSON.stringify(Object.entries(wa).sort(([a], [b]) => a.localeCompare(b)));
            const current = freq.get(key) || {
                count: 0,
                workAssignments: wa,
                label: Object.entries(wa).filter(([, ids]) => ids.length > 0).map(([k, ids]) => `${k}:${ids.length}`).join(' • '),
            };
            current.count += 1;
            freq.set(key, current);
        }
        return Array.from(freq.values())
            .filter(x => x.count >= 2 && Object.values(x.workAssignments).some(ids => ids.length > 0))
            .sort((a, b) => b.count - a.count)
            .slice(0, 3);
    }, [transactions, date]);
    const [laborStepHistory, setLaborStepHistory] = useState<Array<{
        selectedEmps: string[];
        workAssignments: Record<string, string[]>;
        halfDayEmpIds: string[];
        laborStatus: 'Work' | 'OT' | 'Leave';
        otHours: string;
        otDesc: string;
        otRate: string;
        drumsWashedAtHome: string;
    }>>([]);
    const laborHistoryFingerprintRef = useRef('');
    useEffect(() => {
        if (step !== 1) return;
        const snapshot = {
            selectedEmps: [...selectedEmps],
            workAssignments: { ...workAssignments },
            halfDayEmpIds: Array.from(halfDayEmpIds),
            laborStatus,
            otHours,
            otDesc,
            otRate,
            drumsWashedAtHome,
        };
        const fingerprint = JSON.stringify(snapshot);
        if (laborHistoryFingerprintRef.current === fingerprint) return;
        laborHistoryFingerprintRef.current = fingerprint;
        setLaborStepHistory(prev => [...prev.slice(-11), snapshot]);
    }, [step, selectedEmps, workAssignments, halfDayEmpIds, laborStatus, otHours, otDesc, otRate, drumsWashedAtHome]);
    const restoreLaborStepHistory = () => {
        if (laborStepHistory.length < 2) return;
        const nextHistory = laborStepHistory.slice(0, -1);
        const previous = nextHistory[nextHistory.length - 1];
        laborHistoryFingerprintRef.current = JSON.stringify(previous);
        setLaborStepHistory(nextHistory);
        setSelectedEmps(previous.selectedEmps);
        setWorkAssignments(previous.workAssignments);
        setHalfDayEmpIds(new Set(previous.halfDayEmpIds));
        setLaborStatus(previous.laborStatus);
        setOtHours(previous.otHours);
        setOtDesc(previous.otDesc);
        setOtRate(previous.otRate);
        setDrumsWashedAtHome(previous.drumsWashedAtHome);
    };

    // Vehicle State
    const [vehCar, setVehCar] = useState('');
    const [vehDriver, setVehDriver] = useState('');
    const [vehWage, setVehWage] = useState('');
    const [vehMachineWage, setVehMachineWage] = useState(defaultVehicleMachineWage);
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
        setVehMachineWage(t.vehicleWage != null ? String(t.vehicleWage) : defaultVehicleMachineWage);
        setVehWage(t.driverWage != null ? String(t.driverWage) : '');
        setVehDetails(t.workDetails || '');
        setVehWorkType(x.workType === 'HalfDay' ? 'HalfDay' : 'FullDay');
    }, [defaultVehicleMachineWage]);

    useEffect(() => {
        setEditingVehicleTxId(null);
    }, [date]);

    // Daily Log State (Vehicle Trips - Multi-card Canvas)
    const [tripEntries, setTripEntries] = useState<WizardTripEntry[]>([emptyWizardTripEntry()]);
    const [tripMorning, setTripMorning] = useState('');
    const [tripAfternoon, setTripAfternoon] = useState('');
    const totalTrips = (Number(tripMorning) || 0) + (Number(tripAfternoon) || 0);
    const addTripCard = () => setTripEntries(prev => [...prev, emptyWizardTripEntry()]);
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
    const [sandBatchId, setSandBatchId] = useState('');
    const [sandMorningStart, setSandMorningStart] = useState('');
    const [sandAfternoonStart, setSandAfternoonStart] = useState('');
    const [sandEveningEnd, setSandEveningEnd] = useState('');
    const drumStockSummary = useMemo(
        () =>
            computeSandDrumStockSummary(
                normalizeDate(date),
                transactions,
                { sandDrumsObtained, drumsWashedAtHome },
            ),
        [transactions, date, sandDrumsObtained, drumsWashedAtHome],
    );
    const sand1Total = (Number(sand1Morning) || 0) + (Number(sand1Afternoon) || 0);
    const sand2Total = (Number(sand2Morning) || 0) + (Number(sand2Afternoon) || 0);
    const sandGrandTotal = sand1Total + sand2Total;
    // Sand drum stock (ได้ − ล้างที่บ้าน) สะสมแบบต่อเนื่อง — ไม่ใช้รอบตัดอัตโนมัติ

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
    const [incomePartyName, setIncomePartyName] = useState('');
    const [incomePartyAddress, setIncomePartyAddress] = useState('');
    const [incomePartyDetail, setIncomePartyDetail] = useState('');
    const [incomeQty, setIncomeQty] = useState('');
    const [incomeUnitPrice, setIncomeUnitPrice] = useState('');
    const [incomeTotal, setIncomeTotal] = useState('');
    const [newIncomeType, setNewIncomeType] = useState('');
    const [incomeTypeAddOpen, setIncomeTypeAddOpen] = useState(false);
    const [incomePaymentStatus, setIncomePaymentStatus] = useState<'Paid' | 'Unpaid'>('Paid');
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
        if (label === 'ขายแร่') {
            void sessionAlert('ประเภท "ขายแร่" ไม่ใช้ในระบบแล้ว');
            return;
        }
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
    const [rightSummaryCompact, setRightSummaryCompact] = useState(false);
    useEffect(() => {
        try {
            localStorage.removeItem('cm_daily_wizard_draft_v2');
        } catch {
            /* ignore */
        }
    }, []);
    useEffect(() => {
        if (!vehMachineWage) setVehMachineWage(defaultVehicleMachineWage);
    }, [defaultVehicleMachineWage, vehMachineWage]);

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
                setVehMachineWage(latestVeh.vehicleWage != null ? String(latestVeh.vehicleWage) : defaultVehicleMachineWage);
                setVehWage(latestVeh.driverWage != null ? String(latestVeh.driverWage) : '');
                setVehDetails(latestVeh.workDetails || '');
                setVehWorkType(latestVeh.workType === 'HalfDay' ? 'HalfDay' : 'FullDay');
            } else {
                setVehCar('');
                setVehDriver('');
                setVehMachineWage(defaultVehicleMachineWage);
                setVehWage('');
                setVehDetails('');
                setVehWorkType('FullDay');
            }
        }
    }, [date, dayTransactions, editingVehicleTxId]);

    // Prefill canvas ค่าแรงจาก Attendance ที่บันทึกแล้ว — แยกจาก effect หลักเพื่อไม่รีเซ็ตเมื่อ parent ส่ง transactions array ใหม่โดยเนื้อหาเดิม
    useEffect(() => {
        const laborAttendance = dayTransactions.filter(
            (t) => t.category === 'Labor' && t.subCategory === 'Attendance' && t.laborStatus === 'Work'
        );
        if (laborAttendance.length > 0) {
            const latest = pickLatestByDayOrder(laborAttendance as any[], dayTransactions) as any;
            if (!latest) return;
            const mergedWa =
                latest.workAssignments && typeof latest.workAssignments === 'object'
                    ? mergeUnknownLaborCanvasAssignments(latest.workAssignments as Record<string, string[]>)
                    : ({} as Record<string, string[]>);
            const legacyNote = String(latest.laborGeneralWorkNotes || '').trim();
            const customCats = Array.isArray((latest as any).customWorkCategories)
                ? ((latest as any).customWorkCategories as Array<{ id?: string; label?: string }>)
                : [];
            const subJobs = buildGeneralSubJobsFromAssignments(mergedWa, customCats, legacyNote);
            setGeneralSubJobs(subJobs);
            const remappedWa = remapGeneralWorkAssignments(mergedWa, subJobs);
            const hasAssignedWorkers = Object.values(remappedWa).some(ids => Array.isArray(ids) && ids.length > 0);
            setWorkAssignments(hasAssignedWorkers ? remappedWa : {});
            setLaborGeneralWorkNotes(legacyNote);
            if (latest.workTypeByEmployee) {
                const half = new Set<string>();
                Object.entries(latest.workTypeByEmployee as Record<string, 'FullDay' | 'HalfDay'>).forEach(([id, wt]) => {
                    if (wt === 'HalfDay') half.add(id);
                });
                setHalfDayEmpIds(half);
            } else {
                setHalfDayEmpIds(new Set());
            }
        } else {
            setWorkAssignments({});
            setLaborGeneralWorkNotes('');
            setGeneralSubJobs([{ id: newGeneralSubJobId(), title: '' }]);
            setHalfDayEmpIds(new Set());
        }
    }, [date, laborCanvasPersistedPrefillSignature]);

    // Prefill ฟอร์มล้างทรายจากรายการที่บันทึกแล้ว — ใช้ signature แทน dayTransactions เพื่อไม่รีเซ็ตเมื่อ parent ส่ง transactions array ใหม่ (reference) โดยเนื้อหาเดิม
    useEffect(() => {
        const laborWorkHome = dayTransactions.filter(
            (t) => t.category === 'Labor' && t.subCategory === 'Attendance' && t.laborStatus === 'Work'
        );
        let homeFromLabor = 0;
        if (laborWorkHome.length > 0) {
            const latestLab = pickLatestByDayOrder(laborWorkHome as any[], dayTransactions) as any;
            homeFromLabor = Number(latestLab?.drumsWashedAtHome || 0);
        }

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
            setSandDrumsObtained(sandTx.length > 0 ? String(drums) : drums > 0 ? String(drums) : '');
            const txWithTime = sandTx.find((t: any) =>
                !!(t.sandMorningStart || t.sandAfternoonStart || t.sandEveningEnd)
            ) as any;
            const first = (txWithTime || sandTx[0]) as any;
            setSandMorningStart(normalizeTimeInputValue(first.sandMorningStart));
            setSandAfternoonStart(normalizeTimeInputValue(first.sandAfternoonStart));
            setSandEveningEnd(normalizeTimeInputValue(first.sandEveningEnd));
            setSandBatchId(String(first.sandBatchId || `BATCH-${normalizeDate(date).replace(/-/g, '')}`));
        } else {
            setSandDrumsObtained('');
            setSandMorningStart('');
            setSandAfternoonStart('');
            setSandEveningEnd('');
            setSandBatchId(`BATCH-${normalizeDate(date).replace(/-/g, '')}`);
        }

        const homeFromSand = persistedSandHomeDrums(sandTx as Transaction[]);
        const mergedHomeDrums = Math.max(homeFromLabor, homeFromSand);
        setDrumsWashedAtHome(
            sandTx.length > 0 || homeFromLabor > 0 ? String(mergedHomeDrums) : mergedHomeDrums > 0 ? String(mergedHomeDrums) : '',
        );
    }, [date, sandPersistedPrefillSignature, laborCanvasPersistedPrefillSignature]);

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

        if (isSingleStepMode) return;
        setStep(s => Math.min(s + 1, STEPS.length - 1));
    };
    const prevStep = () => {
        if (isSingleStepMode) return;
        setStep(s => Math.max(s - 1, 0));
    };
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
        const slice = fromYesterday.slice(0, 50);
        for (let idx = 0; idx < slice.length; idx += 1) {
            const tx = slice[idx];
            const r = await Promise.resolve(
                onSaveTransaction({
                    ...tx,
                    id: `${Date.now()}_cpy_${idx}`,
                    date: todayNorm,
                })
            );
            if (r === false) break;
        }
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

    const handleReportPermanentDelete = useCallback(
        async (t: Transaction) => {
            if (!onPermanentDeleteTransaction) return;
            const label = [t.category, t.subCategory].filter(Boolean).join(' · ');
            const detail = String(t.description || '').trim() || '(ไม่มีรายละเอียด)';
            const ok = await sessionConfirm(
                `ลบรายการนี้ออกจากฐานข้อมูลถาวร ไม่สามารถกู้คืนได้\n\n${label}\n${detail}`,
                { title: 'ลบจากฐานข้อมูล' }
            );
            if (!ok) return;
            await onPermanentDeleteTransaction(t.id);
        },
        [onPermanentDeleteTransaction, sessionConfirm]
    );

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
            {mobileShell && !(isSingleStepMode && hideReportMode) ? (
                <div className="sticky top-0 z-10 mb-3 space-y-2 rounded-2xl border border-slate-200/90 bg-white/95 p-2 shadow-sm backdrop-blur-md dark:border-white/10 dark:bg-slate-900/95">
                    {!hideReportMode && (
                    <div className="flex w-full rounded-xl border border-slate-200 bg-white p-1 shadow-sm dark:border-white/10 dark:bg-white/[0.04]">
                        <button
                            type="button"
                            onClick={() => setViewMode('record')}
                            className={`flex flex-1 items-center justify-center gap-2 rounded-lg font-semibold transition-all touch-manipulation min-h-[44px] px-3 text-sm ${viewMode === 'record' ? 'bg-indigo-600 text-white shadow' : 'text-slate-500 dark:text-slate-400'}`}
                        >
                            <ClipboardList size={16} />
                            บันทึก
                        </button>
                        <button
                            type="button"
                            onClick={() => setViewMode('report')}
                            className={`flex flex-1 items-center justify-center gap-2 rounded-lg font-semibold transition-all touch-manipulation min-h-[44px] px-3 text-sm ${viewMode === 'report' ? 'bg-indigo-600 text-white shadow' : 'text-slate-500 dark:text-slate-400'}`}
                        >
                            <FileText size={16} />
                            รายงาน
                        </button>
                    </div>
                    )}
                    {viewMode === 'record' && !isSingleStepMode && (
                    <div className="px-0.5 pb-0.5">
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
                    )}
                </div>
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

            {/* มุมมองรายงาน — รวมมือถือ/Android (mobileShell) */}
            {viewMode === 'report' && (
                <div className={`space-y-6 animate-fade-in ${mobileShell ? 'px-0.5' : ''}`}>
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
                            const vehicle = txs.filter(countsAsWizardVehicleUsageRecord);
                            const trips = txs.filter(transactionCountsAsVehicleTripMenu);
                            const sand = txs.filter(countsAsWizardSandWashRecord);
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
                            const sandHomeDrums = persistedSandHomeDrums(sand);
                            const laborAttendance = labor.filter(t => t.subCategory === 'Attendance') as any[];
                            const latestAttendance = pickLatestByDayOrder(laborAttendance, txs);
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
                                const latest = pickLatestByDayOrder(attendance as any[], txs) as any;
                                    if (latest) {
                                        const waRaw: Record<string, string[]> | undefined = latest.workAssignments;
                                        if (waRaw) {
                                            const mergedWa = mergeUnknownLaborCanvasAssignments(waRaw);
                                            workGroups = Object.entries(mergedWa)
                                                .map(([catId, empIds]) => ({
                                                    label: DEFAULT_WORK_CATEGORIES.find(c => c.id === catId)?.label || catId,
                                                    count: (empIds || []).length,
                                                }))
                                                .filter(g => g.count > 0);
                                        }
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
                                        <div className="rounded-xl border border-emerald-100 bg-emerald-50 p-3.5 dark:border-emerald-500/30 dark:bg-emerald-500/10">
                                            <div className="mb-1 flex items-center gap-1.5 text-xs font-medium text-emerald-700 dark:text-emerald-300"><Users size={14} /> ค่าแรง</div>
                                            <p className="text-base font-semibold text-emerald-800 dark:text-emerald-100">฿{formatDisplayNumber(laborSum)}</p>
                                            <p className="mt-0.5 text-[11px] font-normal text-emerald-600 dark:text-emerald-200">{workerCount} คน • {labor.length} รายการ</p>
                                        </div>
                                        <div className="rounded-xl border border-amber-100 bg-amber-50 p-3.5 dark:border-amber-500/30 dark:bg-amber-500/10">
                                            <div className="mb-1 flex items-center gap-1.5 text-xs font-medium text-amber-700 dark:text-amber-300"><Truck size={14} /> ใช้รถ</div>
                                            <p className="text-base font-semibold text-amber-800 dark:text-amber-100">฿{formatDisplayNumber(vehicleSum)}</p>
                                            <p className="mt-0.5 text-[11px] font-normal text-amber-600 dark:text-amber-200">{vehicle.length} รายการ</p>
                                        </div>
                                        <div className="rounded-xl border border-amber-100 bg-amber-50/90 p-3.5 dark:border-amber-500/25 dark:bg-amber-950/30">
                                            <div className="mb-1 flex items-center gap-1.5 text-xs font-medium text-amber-800 dark:text-amber-200"><Truck size={14} /> เที่ยวรถ</div>
                                            <p className="text-base font-semibold text-amber-900 dark:text-amber-100">{tripsTotal} เที่ยว</p>
                                            <p className="mt-0.5 text-[11px] font-normal text-amber-800/90 dark:text-amber-300/90">{tripsCubic} คิว • {trips.length} รายการ</p>
                                        </div>
                                        <div className="rounded-xl border border-cyan-100 bg-cyan-50 p-3.5 dark:border-cyan-500/30 dark:bg-cyan-500/10">
                                            <div className="mb-1 flex items-center gap-1.5 text-xs font-medium text-cyan-700 dark:text-cyan-300"><Droplets size={14} /> ล้างทราย</div>
                                            <p className="text-base font-semibold text-cyan-800 dark:text-cyan-100">{sandCubic} คิว</p>
                                            <p className="mt-0.5 text-[11px] font-normal text-cyan-600 dark:text-cyan-200">
                                                {sandDrums > 0 && <>🪣 {sandDrums} ถังสุทธิ{homeDrums > 0 ? ` (หักบ้าน ${homeDrums})` : ''} • </>}
                                                {sand.length} รายการ
                                            </p>
                                        </div>
                                        <div className="rounded-xl border border-red-100 bg-red-50 p-3.5 dark:border-red-500/30 dark:bg-red-500/10">
                                            <div className="mb-1 flex items-center gap-1.5 text-xs font-medium text-red-700 dark:text-red-300"><Fuel size={14} /> น้ำมัน</div>
                                            <p className="text-base font-semibold text-red-800 dark:text-red-100">฿{formatDisplayNumber(fuelSum)}</p>
                                            <p className="mt-0.5 text-[11px] font-normal text-red-600 dark:text-red-200">{fuel.length} รายการ</p>
                                        </div>
                                        <div className="rounded-xl border border-lime-100 bg-lime-50 p-3.5 dark:border-lime-500/30 dark:bg-lime-500/10">
                                            <div className="mb-1 flex items-center gap-1.5 text-xs font-medium text-lime-700 dark:text-lime-300"><Wallet size={14} /> รายรับ</div>
                                            <p className="text-base font-semibold text-lime-800 dark:text-lime-100">฿{formatDisplayNumber(incomeSum)}</p>
                                            <p className="mt-0.5 text-[11px] font-normal text-lime-600 dark:text-lime-200">{income.length} รายการ</p>
                                        </div>
                                        <div className="rounded-xl border border-orange-100 bg-orange-50 p-3.5 dark:border-orange-500/30 dark:bg-orange-500/10">
                                            <div className="mb-1 flex items-center gap-1.5 text-xs font-medium text-orange-700 dark:text-orange-300"><AlertTriangle size={14} /> เหตุการณ์</div>
                                            <p className="text-base font-semibold text-orange-800 dark:text-orange-100">{events.length} รายการ</p>
                                            {events.length > 0 && (
                                                <ul className="mt-1 max-h-12 space-y-0.5 overflow-hidden truncate text-[11px] font-normal text-orange-600">
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
                                        {onPermanentDeleteTransaction && txs.length > 0 && (
                                            <div className="mt-4 border-t border-slate-200 pt-4 dark:border-white/10">
                                                <p className="mb-2 text-[11px] font-semibold text-slate-600 dark:text-slate-300">
                                                    รายการทั้งหมด ({txs.length}) — ลบถาวรจากฐานข้อมูล
                                                </p>
                                                <ul className="space-y-2">
                                                    {txs.map(t => {
                                                        const label = [t.category, t.subCategory].filter(Boolean).join(' · ');
                                                        const detail = String(t.description || '').trim() || '(ไม่มีรายละเอียด)';
                                                        const amountStr =
                                                            t.amount != null && t.amount !== 0
                                                                ? `฿${formatDisplayNumber(t.amount)}`
                                                                : '';
                                                        return (
                                                            <li
                                                                key={t.id}
                                                                className="flex items-start justify-between gap-2 rounded-xl border border-slate-200 bg-slate-50/80 px-3 py-2.5 dark:border-white/10 dark:bg-white/[0.04]"
                                                            >
                                                                <div className="min-w-0 flex-1">
                                                                    <p className="text-xs font-semibold text-slate-800 dark:text-slate-100">{label}</p>
                                                                    <p className="mt-0.5 truncate text-[11px] text-slate-600 dark:text-slate-300">{detail}</p>
                                                                    {amountStr && (
                                                                        <p className="mt-0.5 text-[11px] font-medium text-slate-500 dark:text-slate-400">{amountStr}</p>
                                                                    )}
                                                                </div>
                                                                <button
                                                                    type="button"
                                                                    onClick={() => void handleReportPermanentDelete(t)}
                                                                    className="flex shrink-0 items-center gap-1 rounded-lg border border-red-200 bg-red-50 px-2.5 py-2 text-xs font-semibold text-red-700 touch-manipulation min-h-[44px] dark:border-red-500/30 dark:bg-red-500/10 dark:text-red-200"
                                                                    aria-label={`ลบถาวร ${label}`}
                                                                >
                                                                    <Trash2 size={16} />
                                                                    ลบ
                                                                </button>
                                                            </li>
                                                        );
                                                    })}
                                                </ul>
                                            </div>
                                        )}
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
                <div className={`min-w-0 space-y-6 ${mobileShell ? '' : step === 1 ? 'xl:col-span-12' : 'xl:col-span-8'}`}>
                    <Card className={`relative flex min-h-0 flex-col overflow-hidden ${mobileShell ? 'min-h-0 rounded-2xl border border-slate-200/80 p-4 shadow-sm dark:border-white/10 sm:p-4 md:p-5 lg:p-6' : 'min-h-[560px] p-6'}`}>
                        {viewMode === 'record' && validationChecklist.length > 0 && (
                            <div className="mb-4 rounded-2xl border border-amber-200 bg-amber-50/90 p-3 dark:border-amber-500/25 dark:bg-amber-500/10">
                                <p className="mb-2 text-xs font-bold text-amber-800 dark:text-amber-200">Checklist ก่อนบันทึก</p>
                                <ul className="space-y-1.5 text-xs">
                                    {validationChecklist.map((item, idx) => (
                                        <li key={`${item.message}_${idx}`} className="rounded-lg border border-amber-200/70 bg-white/70 px-2 py-1.5 text-amber-900 dark:border-amber-500/20 dark:bg-white/5 dark:text-amber-100">
                                            <span className="font-semibold">{item.level === 'warning' ? 'เตือน' : 'แนะนำ'}:</span> {item.message}
                                            <span className="block text-[11px] opacity-90">วิธีแก้: {item.fix}</span>
                                        </li>
                                    ))}
                                </ul>
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
                                            <div className="min-w-0 rounded-lg border border-amber-200/80 bg-amber-50/80 px-2.5 py-2 text-center dark:border-amber-500/25 dark:bg-amber-500/10"><div className="font-semibold text-amber-700 dark:text-amber-300">การใช้รถ</div><div className="mt-0.5 text-base font-black text-amber-800 dark:text-amber-200">{dayStepStats.vehicleUsageCount}</div></div>
                                            <div className="min-w-0 rounded-lg border border-amber-200/80 bg-amber-50/80 px-2.5 py-2 text-center dark:border-amber-500/25 dark:bg-amber-950/30"><div className="font-semibold text-amber-800 dark:text-amber-200">เที่ยวรถ</div><div className="mt-0.5 text-base font-black text-amber-900 dark:text-amber-100">{dayStepStats.tripCount}</div></div>
                                            <div className="min-w-0 rounded-lg border border-cyan-200/80 bg-cyan-50/80 px-2.5 py-2 text-center dark:border-cyan-500/25 dark:bg-cyan-500/10"><div className="font-semibold text-cyan-700 dark:text-cyan-300">ล้างทราย</div><div className="mt-0.5 text-base font-black text-cyan-800 dark:text-cyan-200">{dayStepStats.sandWashCount}</div></div>
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
                            <div className="flex min-h-0 flex-1 flex-col animate-slide-up">
                                <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
                                    <div>
                                        <h3 className="flex items-center gap-2 text-lg font-bold text-slate-800 dark:text-slate-100">
                                            <Users className="text-emerald-500 dark:text-emerald-400" /> บันทึกค่าแรง / OT
                                        </h3>
                                        <p className="mt-0.5 text-xs text-slate-500 dark:text-slate-400">
                                            {new Date(date).toLocaleDateString('th-TH', { weekday: 'short', day: 'numeric', month: 'short', year: '2-digit' })}
                                        </p>
                                    </div>
                                    {laborStatus === 'Work' && !mobileShell && (
                                        <div className="flex flex-wrap gap-2 text-[11px] font-semibold">
                                            <span className="rounded-full border border-indigo-200 bg-indigo-50 px-2.5 py-1 text-indigo-800">
                                                เลือก {selectedEmps.length}
                                            </span>
                                            <span className="rounded-full border border-emerald-200 bg-emerald-50 px-2.5 py-1 text-emerald-800">
                                                จัดแล้ว {laborAssignedEmpIds.size}
                                            </span>
                                            <span className="rounded-full border border-slate-200 bg-slate-50 px-2.5 py-1 text-slate-600">
                                                ในรายชื่อ {poolVisibleEmployees.length}
                                            </span>
                                        </div>
                                    )}
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

                                <div className="mb-4 inline-flex w-full max-w-md rounded-xl border border-slate-200 bg-slate-100/80 p-1 dark:border-white/10 dark:bg-white/5">
                                    <button
                                        type="button"
                                        onClick={() => setLaborStatus('Work')}
                                        className={`flex-1 touch-manipulation rounded-lg px-3 text-sm font-bold transition-all ${touchUI ? 'min-h-[44px] py-2.5' : 'py-2'} ${laborStatus === 'Work' ? 'bg-white text-emerald-700 shadow-sm dark:bg-white/10 dark:text-emerald-300' : 'text-slate-600 dark:text-slate-400'}`}
                                    >
                                        มาทำงาน
                                    </button>
                                    <button
                                        type="button"
                                        onClick={() => setLaborStatus('OT')}
                                        className={`flex-1 touch-manipulation rounded-lg px-3 text-sm font-bold transition-all ${touchUI ? 'min-h-[44px] py-2.5' : 'py-2'} ${laborStatus === 'OT' ? 'bg-white text-amber-700 shadow-sm dark:bg-white/10 dark:text-amber-300' : 'text-slate-600 dark:text-slate-400'}`}
                                    >
                                        OT
                                    </button>
                                </div>
                                {laborStatus === 'Work' && !mobileShell && (
                                    <p className="mb-3 text-[11px] leading-relaxed text-slate-500 dark:text-slate-400">
                                        เต็มวัน = ไม่ต้องกด ½ · เลือกหลายคนแล้วลากหรือกด «ย้ายมาที่นี่» ในกล่องงาน
                                    </p>
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
                                                <div className="max-h-[min(52vh,520px)] min-h-0 overflow-y-auto overscroll-y-contain rounded-lg border border-slate-100 bg-slate-50/50 p-2 [-webkit-overflow-scrolling:touch]">
                                                <div className="grid grid-cols-2 gap-2.5 sm:grid-cols-3 md:grid-cols-3 lg:grid-cols-4">
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
                                                const existingDailyLaborTx = pickLatestByDayOrder(
                                                    dayTransactions.filter(tx =>
                                                        tx.category === 'Labor' &&
                                                        tx.subCategory === 'Attendance' &&
                                                        tx.laborStatus === 'Work'
                                                    ),
                                                    dayTransactions
                                                );
                                                const existingLaborIds = dayTransactions
                                                    .filter(t =>
                                                        t.category === 'Labor' &&
                                                        (t.laborStatus === 'Work' || t.laborStatus === 'OT') &&
                                                        t.id !== existingDailyLaborTx?.id
                                                    )
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
                                                const candidateOtTx = {
                                                    id: Date.now().toString(),
                                                    date,
                                                    employeeIds: selectedEmps,
                                                    type: 'Expense',
                                                    category: 'Labor',
                                                    subCategory: 'OT',
                                                    laborStatus: 'OT',
                                                    amount: totalAmount,
                                                    otAmount: rate,
                                                    otHours: hours,
                                                    otDescription: otDesc,
                                                    description: `OT ${otDesc} (${otHours}ชม.) ${selectedEmps.length}คน [${empNames}]`,
                                                } as Transaction;
                                                if (hasSemanticNearDuplicate(candidateOtTx)) {
                                                    const proceed = await shouldContinueWithWarning(
                                                        ['พบรายการ OT ที่ข้อมูลใกล้เคียงในวันเดียวกัน'],
                                                        'ตรวจพบรายการ OT ใกล้เคียง'
                                                    );
                                                    if (!proceed) return;
                                                }
                                                const otSaved = await Promise.resolve(
                                                    onSaveTransaction({
                                                        ...candidateOtTx,
                                                    } as Transaction)
                                                );
                                                if (otSaved === false) return;
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
                                        <div className="mb-3 flex flex-wrap items-center justify-between gap-2 rounded-xl border border-slate-200/80 bg-white px-3 py-2 shadow-sm dark:border-white/10 dark:bg-white/[0.02]">
                                            <div className="flex min-w-0 flex-1 flex-wrap gap-1.5">
                                                {smartWorkTemplates.map((tpl, idx) => (
                                                    <button
                                                        key={`${tpl.label}_${idx}`}
                                                        type="button"
                                                        onClick={() => setWorkAssignments(tpl.workAssignments)}
                                                        className="rounded-lg border border-indigo-200/80 bg-indigo-50 px-2 py-1 text-[10px] font-semibold text-indigo-700 hover:bg-indigo-100 dark:border-indigo-500/30 dark:bg-indigo-500/10 dark:text-indigo-200"
                                                        title="ใช้ template การจัดงานเดิมทั้งชุด"
                                                    >
                                                        เทมเพลต #{idx + 1} · {tpl.count}x
                                                    </button>
                                                ))}
                                            </div>
                                            <button
                                                type="button"
                                                onClick={restoreLaborStepHistory}
                                                disabled={laborStepHistory.length < 2}
                                                className="shrink-0 rounded-lg border border-slate-200 bg-slate-50 px-2.5 py-1 text-[10px] font-semibold text-slate-700 hover:bg-slate-100 disabled:cursor-not-allowed disabled:opacity-40 dark:border-white/15 dark:bg-white/5 dark:text-slate-300"
                                            >
                                                ย้อนกลับ ({Math.max(0, laborStepHistory.length - 1)})
                                            </button>
                                        </div>
                                        {/* Labor drag board */}
                                        <div className="mb-3 min-h-0 flex-1 overflow-hidden rounded-2xl border border-slate-200/90 bg-gradient-to-br from-slate-50 to-slate-100/80 p-2.5 shadow-sm dark:border-white/10 dark:from-white/[0.02] dark:to-white/[0.04] sm:p-3">
                                            <div
                                                className={
                                                    !isTouchLayout
                                                        ? 'grid h-[min(64vh,720px)] max-h-[min(82vh,860px)] min-h-[420px] grid-cols-[minmax(300px,38%)_minmax(0,1fr)] gap-3'
                                                        : 'flex max-h-[min(88vh,820px)] min-h-0 flex-col gap-3'
                                                }
                                            >
                                                <div
                                                    className={
                                                        !isTouchLayout
                                                            ? 'flex min-h-0 flex-col overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm'
                                                            : 'flex max-h-[min(48vh,520px)] min-h-0 flex-col overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm'
                                                    }
                                                >
                                                    <div className="shrink-0 space-y-2.5 border-b border-slate-100 p-3">
                                                        <div className="flex items-center justify-between gap-2">
                                                            <p className="text-base font-extrabold text-slate-800">เลือกพนักงาน</p>
                                                            <span className="rounded-full bg-indigo-100 px-2.5 py-0.5 text-xs font-bold text-indigo-800">
                                                                {selectedEmps.length} เลือก
                                                            </span>
                                                        </div>
                                                        <div
                                                            className={
                                                                !isTouchLayout
                                                                    ? 'flex gap-1.5 overflow-x-auto pb-0.5 [-webkit-overflow-scrolling:touch]'
                                                                    : 'max-h-[min(28vh,240px)] space-y-1 overflow-y-auto pr-0.5'
                                                            }
                                                            role="tablist"
                                                            aria-label="กลุ่มพนักงาน"
                                                        >
                                                            {LABOR_EMPLOYEE_BUCKET_ORDER.map(b => {
                                                                const Icon = LABOR_POOL_BUCKET_ICON[b];
                                                                const selected = laborEmployeeBucket === b;
                                                                return (
                                                                    <button
                                                                        key={b}
                                                                        type="button"
                                                                        role="tab"
                                                                        aria-selected={selected}
                                                                        onClick={() => setLaborEmployeeBucket(b)}
                                                                        className={
                                                                            !isTouchLayout
                                                                                ? `flex shrink-0 items-center gap-2 rounded-full border px-3 py-2 text-left transition-colors touch-manipulation ${
                                                                                      selected
                                                                                          ? 'border-[#1565C0] bg-[#E8F1FF] text-[#0D47A1]'
                                                                                          : 'border-slate-200 bg-white text-slate-700 hover:border-indigo-200'
                                                                                  }`
                                                                                : `flex w-full items-center gap-2.5 rounded-lg border px-3 py-2.5 text-left touch-manipulation ${
                                                                                      selected
                                                                                          ? 'border-[#1565C0] bg-[#E8F1FF]'
                                                                                          : 'border-slate-200 bg-slate-50'
                                                                                  }`
                                                                        }
                                                                    >
                                                                        <Icon size={!isTouchLayout ? 18 : 22} className="shrink-0" />
                                                                        <span className={`font-bold ${!isTouchLayout ? 'text-sm whitespace-nowrap' : 'text-base'}`}>
                                                                            {LABOR_EMPLOYEE_BUCKET_LABEL[b]}
                                                                        </span>
                                                                        <span className={`rounded-full px-2 font-bold ${!isTouchLayout ? 'text-xs' : 'text-sm'} ${selected ? 'bg-[#1565C0] text-white' : 'bg-slate-200 text-slate-600'}`}>
                                                                            {laborBucketCounts[b]}
                                                                        </span>
                                                                    </button>
                                                                );
                                                            })}
                                                        </div>
                                                        {!isTouchLayout && (
                                                            <p className="text-xs font-medium text-slate-500">
                                                                {LABOR_EMPLOYEE_BUCKET_HINT[laborEmployeeBucket]}
                                                            </p>
                                                        )}
                                                        <div className="relative">
                                                            <Search size={18} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
                                                            <input
                                                                placeholder="ค้นหาชื่อ..."
                                                                value={laborSearch}
                                                                onChange={e => setLaborSearch(e.target.value)}
                                                                className="w-full rounded-lg border border-slate-200 bg-slate-50 py-2.5 pl-9 pr-3 text-base text-slate-800 placeholder:text-slate-400 focus:border-indigo-400 focus:bg-white focus:outline-none focus:ring-1 focus:ring-indigo-200"
                                                            />
                                                        </div>
                                                    </div>
                                                    <div className="min-h-0 flex-1 overflow-y-auto overscroll-y-contain p-2.5 sm:p-3 [-webkit-overflow-scrolling:touch]">
                                                        <div className="grid grid-cols-2 gap-2.5 content-start lg:grid-cols-2 xl:grid-cols-2">
                                                            {poolVisibleEmployees.map(emp => {
                                                                const isSelected = selectedEmps.includes(emp.id);
                                                                const saved = dayTransactions.find(
                                                                    t => t.category === 'Labor' && t.employeeIds?.includes(emp.id)
                                                                );
                                                                const leaveRecord = transactions.find(
                                                                    t =>
                                                                        t.category === 'Labor' &&
                                                                        (t.laborStatus === 'Leave' ||
                                                                            t.laborStatus === 'Sick' ||
                                                                            t.laborStatus === 'Personal') &&
                                                                        t.employeeIds?.includes(emp.id) &&
                                                                        t.date <= date &&
                                                                        (t.leaveDays
                                                                            ? new Date(
                                                                                  new Date(t.date).getTime() +
                                                                                      (t.leaveDays - 1) * 86400000
                                                                              )
                                                                                  .toISOString()
                                                                                  .split('T')[0] >= date
                                                                            : t.date === date)
                                                                );
                                                                const displayName = getEmployeeDisplayName(emp);
                                                                return (
                                                                    <div
                                                                        key={emp.id}
                                                                        draggable
                                                                        onDragStart={() => setDragEmployee(emp.id)}
                                                                        onDragEnd={() => setDragEmployee(null)}
                                                                        onClick={() =>
                                                                            setSelectedEmps(prev =>
                                                                                prev.includes(emp.id)
                                                                                    ? prev.filter(id => id !== emp.id)
                                                                                    : [...prev, emp.id]
                                                                            )
                                                                        }
                                                                        title={
                                                                            leaveRecord
                                                                                ? `ลา: ${new Date(leaveRecord.date).toLocaleDateString('th-TH')}${leaveRecord.leaveDays ? ` (${leaveRecord.leaveDays} วัน)` : ''} - ${leaveRecord.leaveReason || leaveRecord.laborStatus}`
                                                                                : undefined
                                                                        }
                                                                        className={`flex w-full items-center justify-center gap-1.5 rounded-xl border font-semibold cursor-grab active:cursor-grabbing select-none transition-all text-center touch-manipulation ${touchUI ? 'min-h-[56px] px-2.5 py-3 text-base' : 'min-h-[50px] px-2.5 py-3 text-base leading-snug'}
                                                                            ${
                                                                                leaveRecord
                                                                                    ? 'border-amber-300 bg-amber-50 text-amber-900'
                                                                                    : isSelected
                                                                                      ? 'border-indigo-600 bg-indigo-600 text-white shadow-md ring-2 ring-indigo-200'
                                                                                      : saved
                                                                                        ? 'border-emerald-200 bg-emerald-50/90 text-emerald-800'
                                                                                        : 'border-slate-200 bg-white text-slate-700 hover:border-indigo-300 hover:bg-indigo-50/40'
                                                                            }`}
                                                                    >
                                                                        <GripVertical size={14} className={`shrink-0 opacity-40 ${isSelected ? 'text-white' : ''}`} />
                                                                        <span className="truncate">{displayName}</span>
                                                                        {leaveRecord ? <span className="shrink-0 text-sm">🏖️</span> : saved ? <span className="shrink-0 text-sm">✓</span> : null}
                                                                    </div>
                                                                );
                                                            })}
                                                            {poolVisibleEmployees.length === 0 && (
                                                                <div className="col-span-2 w-full rounded-lg border border-dashed border-slate-300 bg-white/80 p-5 text-center text-base text-slate-500">
                                                                    {laborSearch.trim()
                                                                        ? 'ไม่มีพนักงานในกลุ่มนี้ที่ตรงคำค้นหา'
                                                                        : laborAssignedEmpIds.size > 0
                                                                          ? 'ไม่มีพนักงานในกลุ่มนี้ (หรือจัดลงกล่องงานหมดแล้ว)'
                                                                          : 'ไม่มีพนักงานในกลุ่มนี้'}
                                                                    {laborSearch.trim() && (
                                                                        <button
                                                                            type="button"
                                                                            onClick={() => setLaborSearch('')}
                                                                            className="mt-2 block w-full rounded-md border border-slate-300 bg-white px-2 py-1.5 text-sm font-semibold text-slate-700 hover:bg-slate-50"
                                                                        >
                                                                            ล้างคำค้น
                                                                        </button>
                                                                    )}
                                                                </div>
                                                            )}
                                                        </div>
                                                    </div>
                                                </div>
                                                <div className="flex min-h-0 flex-1 flex-col overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm">
                                                    <div className="sticky top-0 z-[1] shrink-0 border-b border-slate-100 bg-white/95 px-3 py-2.5 backdrop-blur-sm">
                                                        <p className="text-base font-extrabold text-slate-800">กล่องงาน</p>
                                                        <p className="text-xs font-medium text-slate-500">
                                                            ลากจากรายชื่อ{!isTouchLayout ? 'ซ้าย' : 'บน'} หรือกด «ย้ายมาที่นี่»
                                                        </p>
                                                    </div>
                                                    <div className="min-h-0 flex-1 overflow-y-auto overscroll-y-contain p-2.5 sm:p-3 [-webkit-overflow-scrolling:touch]">
                                                    {laborFixedCanvasCategories.length > 0 && (
                                                        <>
                                                            <p className="mb-2 text-sm font-bold text-slate-600">
                                                                ประเภทงาน
                                                            </p>
                                                            <div className="grid grid-cols-1 gap-2.5 sm:grid-cols-2 xl:grid-cols-2 2xl:grid-cols-3">
                                                                {laborFixedCanvasCategories.map(cat => {
                                                                    const assigned = workAssignments[cat.id] || [];
                                                                    const expanded =
                                                                        laborBucketExpanded[cat.id] ?? assigned.length > 0;
                                                                    return (
                                                                        <LaborCanvasBucketCard
                                                                            key={cat.id}
                                                                            cat={cat}
                                                                            assigned={assigned}
                                                                            expanded={expanded}
                                                                            touchUI={touchUI}
                                                                            dragActive={dragEmployee !== null}
                                                                            selectedCount={selectedEmps.length}
                                                                            employees={employees}
                                                                            halfDayEmpIds={halfDayEmpIds}
                                                                            onToggleExpanded={() =>
                                                                                setLaborBucketExpanded(prev => ({
                                                                                    ...prev,
                                                                                    [cat.id]: !expanded,
                                                                                }))
                                                                            }
                                                                            onDropEmployee={empId =>
                                                                                void assignEmployeesToLaborBucket(cat.id, [empId])
                                                                            }
                                                                            onRemoveEmployee={empId =>
                                                                                removeEmployeeFromLaborBucket(cat.id, empId)
                                                                            }
                                                                            onToggleHalfDay={eid =>
                                                                                setHalfDayEmpIds(prev => {
                                                                                    const n = new Set(prev);
                                                                                    if (n.has(eid)) n.delete(eid);
                                                                                    else n.add(eid);
                                                                                    return n;
                                                                                })
                                                                            }
                                                                            onMovePickedHere={() =>
                                                                                void assignEmployeesToLaborBucket(cat.id, selectedEmps)
                                                                            }
                                                                            onDragStartEmployee={id => setDragEmployee(id)}
                                                                        />
                                                                    );
                                                                })}
                                                            </div>
                                                        </>
                                                    )}
                                                    {(laborEmployeeBucket === 'generalLabor' || laborEmployeeBucket === 'all') && (
                                                        <div className="mt-4 rounded-xl border border-slate-200 bg-slate-50/90 p-3">
                                                            <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
                                                                <span className="text-base font-bold text-slate-700">งานทั่วไป (ชื่องาน)</span>
                                                                <button
                                                                    type="button"
                                                                    onClick={() => {
                                                                        const id = newGeneralSubJobId();
                                                                        setGeneralSubJobs(prev => [...prev, { id, title: '' }]);
                                                                        setWorkAssignments(prev => ({
                                                                            ...prev,
                                                                            [generalSubJobAssignmentKey(id)]:
                                                                                prev[generalSubJobAssignmentKey(id)] || [],
                                                                        }));
                                                                    }}
                                                                    className="rounded-lg bg-slate-200 px-3 py-1.5 text-sm font-bold text-slate-700 hover:bg-slate-300 touch-manipulation"
                                                                >
                                                                    + เพิ่มงาน
                                                                </button>
                                                            </div>
                                                            <p className="mb-2 text-xs text-slate-500">
                                                                แยกหลายงานได้ — ลากพนักงานลงแต่ละกล่อง
                                                            </p>
                                                            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                                                                {generalSubJobs.map(job => {
                                                                    const bucketId = generalSubJobAssignmentKey(job.id);
                                                                    const assigned = workAssignments[bucketId] || [];
                                                                    const generalBase = DEFAULT_WORK_CATEGORIES.find(
                                                                        c => c.id === 'generalWork'
                                                                    )!;
                                                                    const displayTitle = job.title.trim() || 'งานทั่วไป';
                                                                    const cat: LaborCanvasCategoryDef = {
                                                                        id: bucketId,
                                                                        label: displayTitle,
                                                                        shortTitle:
                                                                            displayTitle.length > 28
                                                                                ? `${displayTitle.slice(0, 28)}…`
                                                                                : displayTitle,
                                                                        color: generalBase.color,
                                                                        bgLight: generalBase.bgLight,
                                                                        accent: generalBase.accent,
                                                                    };
                                                                    const expanded =
                                                                        laborBucketExpanded[bucketId] ?? assigned.length > 0;
                                                                    return (
                                                                        <div key={job.id} className="space-y-1.5">
                                                                            <div className="flex items-center gap-1">
                                                                                <input
                                                                                    type="text"
                                                                                    value={job.title}
                                                                                    onChange={e =>
                                                                                        setGeneralSubJobs(prev =>
                                                                                            prev.map(row =>
                                                                                                row.id === job.id
                                                                                                    ? { ...row, title: e.target.value }
                                                                                                    : row
                                                                                            )
                                                                                        )
                                                                                    }
                                                                                    placeholder="ชื่องาน เช่น ทำรั้วสแสลม"
                                                                                    className="w-full rounded-lg border border-slate-200 bg-white px-2.5 py-2 text-sm text-slate-800 placeholder:text-slate-400 focus:border-indigo-400 focus:outline-none focus:ring-1 focus:ring-indigo-200"
                                                                                />
                                                                                {generalSubJobs.length > 1 && (
                                                                                    <button
                                                                                        type="button"
                                                                                        title="ลบงานนี้"
                                                                                        onClick={() => {
                                                                                            setGeneralSubJobs(prev =>
                                                                                                prev.filter(row => row.id !== job.id)
                                                                                            );
                                                                                            setWorkAssignments(prev => {
                                                                                                const u = { ...prev };
                                                                                                delete u[bucketId];
                                                                                                return u;
                                                                                            });
                                                                                        }}
                                                                                        className="shrink-0 rounded-lg px-2 py-1 text-slate-400 hover:bg-red-50 hover:text-red-600 touch-manipulation"
                                                                                    >
                                                                                        ×
                                                                                    </button>
                                                                                )}
                                                                            </div>
                                                                            <LaborCanvasBucketCard
                                                                                cat={cat}
                                                                                assigned={assigned}
                                                                                expanded={expanded}
                                                                                touchUI={touchUI}
                                                                                dragActive={dragEmployee !== null}
                                                                                selectedCount={selectedEmps.length}
                                                                                employees={employees}
                                                                                halfDayEmpIds={halfDayEmpIds}
                                                                                onToggleExpanded={() =>
                                                                                    setLaborBucketExpanded(prev => ({
                                                                                        ...prev,
                                                                                        [bucketId]: !expanded,
                                                                                    }))
                                                                                }
                                                                                onDropEmployee={empId =>
                                                                                    void assignEmployeesToLaborBucket(bucketId, [empId])
                                                                                }
                                                                                onRemoveEmployee={empId =>
                                                                                    removeEmployeeFromLaborBucket(bucketId, empId)
                                                                                }
                                                                                onToggleHalfDay={eid =>
                                                                                    setHalfDayEmpIds(prev => {
                                                                                        const n = new Set(prev);
                                                                                        if (n.has(eid)) n.delete(eid);
                                                                                        else n.add(eid);
                                                                                        return n;
                                                                                    })
                                                                                }
                                                                                onMovePickedHere={() =>
                                                                                    void assignEmployeesToLaborBucket(bucketId, selectedEmps)
                                                                                }
                                                                                onDragStartEmployee={id => setDragEmployee(id)}
                                                                            />
                                                                        </div>
                                                                    );
                                                                })}
                                                            </div>
                                                        </div>
                                                    )}
                                                    <div
                                                        className={`mt-3 flex items-center justify-center gap-2 rounded-xl border px-3 py-3 text-center text-sm font-bold ${
                                                            laborAssignedEmpIds.size > 0
                                                                ? 'border-emerald-200 bg-emerald-50 text-emerald-900'
                                                                : 'border-dashed border-slate-200 bg-slate-50 text-slate-500'
                                                        }`}
                                                    >
                                                        <Users size={16} className="shrink-0" />
                                                        {laborAssignedEmpIds.size > 0
                                                            ? `จัดลงงานแล้ว ${laborAssignedEmpIds.size} คน`
                                                            : 'ยังไม่มีคนในกล่องงาน'}
                                                    </div>
                                                    </div>
                                                </div>
                                            </div>
                                        </div>
                                        <div className="pt-2 border-t space-y-2">
                                            <Button onClick={async () => {
                                                for (const job of generalSubJobs) {
                                                    const key = generalSubJobAssignmentKey(job.id);
                                                    const count = (workAssignments[key] || []).length;
                                                    if (count > 0 && !job.title.trim()) {
                                                        await sessionAlert('กรุณาระบุชื่องานสำหรับงานทั่วไปที่มีพนักงาน');
                                                        return;
                                                    }
                                                }
                                                const fixedWa = Object.fromEntries(
                                                    Object.entries(workAssignments).filter(
                                                        ([k]) =>
                                                            DEFAULT_WORK_CATEGORY_IDS.has(k) &&
                                                            k !== 'generalWork'
                                                    )
                                                );
                                                const generalWa = Object.fromEntries(
                                                    generalSubJobs
                                                        .map(job => {
                                                            const key = generalSubJobAssignmentKey(job.id);
                                                            const ids = workAssignments[key] || [];
                                                            return ids.length > 0 ? [key, ids] : null;
                                                        })
                                                        .filter(Boolean) as Array<[string, string[]]>
                                                );
                                                const normalizedWa = mergeUnknownLaborCanvasAssignments({
                                                    ...fixedWa,
                                                    ...generalWa,
                                                });
                                                const allAssigned = Object.entries(normalizedWa).flatMap(([, ids]) => ids);
                                                const driverWorkedToday = dayTransactions
                                                    .filter(t => t.category === 'Vehicle' && !!t.driverId)
                                                    .map(t => t.driverId as string);
                                                const allEmps = [...new Set([...allAssigned, ...driverWorkedToday])];
                                                if (allEmps.length === 0) {
                                                    await sessionAlert('กรุณาลากพนักงานใส่กล่องงานก่อน หรือมีรายการใช้รถที่ระบุคนขับในวันนี้');
                                                    return;
                                                }
                                                const existingDailyLaborTx = dayTransactions.find(tx =>
                                                    tx.category === 'Labor' &&
                                                    tx.subCategory === 'Attendance' &&
                                                    tx.laborStatus === 'Work'
                                                );
                                                const existingLaborIds = dayTransactions
                                                    .filter(t =>
                                                        t.category === 'Labor' &&
                                                        (t.laborStatus === 'Work' || t.laborStatus === 'OT') &&
                                                        t.id !== existingDailyLaborTx?.id
                                                    )
                                                    .flatMap(t => t.employeeIds || []);
                                                const alreadyRecorded = allEmps.filter(id => existingLaborIds.includes(id));
                                                if (alreadyRecorded.length > 0) {
                                                    const names = alreadyRecorded.map(id => getEmployeeDisplayName(employees.find(e => e.id === id)) || id).join(', ');
                                                    await sessionAlert(
                                                        `ไม่สามารถบันทึกซ้ำได้ — พนักงานต่อไปนี้บันทึกค่าแรงวันที่นี้แล้ว: ${names}\nกรุณาตรวจสอบที่เมนู "ค่าแรง/ลา" หรือลบรายการเดิมก่อน`
                                                    );
                                                    return;
                                                }
                                                // Upsert daily labor record: update existing attendance card instead of creating duplicates.
                                                const base = {
                                                    id: existingDailyLaborTx?.id || Date.now().toString(),
                                                    date,
                                                    employeeIds: allEmps,
                                                    createdAt: existingDailyLaborTx?.createdAt || new Date().toISOString(),
                                                };
                                                const genNote =
                                                    generalSubJobs
                                                        .filter(
                                                            job =>
                                                                (workAssignments[generalSubJobAssignmentKey(job.id)] || [])
                                                                    .length > 0
                                                        )
                                                        .map(job => job.title.trim())
                                                        .filter(Boolean)
                                                        .join(', ') || laborGeneralWorkNotes.trim();
                                                const desc = Object.entries(normalizedWa)
                                                    .filter(([, ids]) => ids.length > 0)
                                                    .map(([catId, ids]) => {
                                                        const cat = DEFAULT_WORK_CATEGORIES.find(c => c.id === catId);
                                                        let baseLabel = cat?.label || catId;
                                                        if (catId.startsWith(GENERAL_WORK_PREFIX)) {
                                                            const subId = catId.slice(GENERAL_WORK_PREFIX.length);
                                                            const job = generalSubJobs.find(j => j.id === subId);
                                                            baseLabel = job?.title.trim() || 'งานทั่วไป';
                                                        } else if (catId === 'generalWork' && genNote) {
                                                            baseLabel = `${baseLabel} (${genNote})`;
                                                        }
                                                        const names = ids
                                                            .map(
                                                                id =>
                                                                    employees.find(e => e.id === id)?.nickname || ''
                                                            )
                                                            .join(',');
                                                        return `${baseLabel}: ${names}`;
                                                    })
                                                    .join(' | ');
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
                                                const homeDraft = String(drumsWashedAtHome).trim();
                                                let drumsHome: number | undefined;
                                                if (homeDraft === '') drumsHome = undefined;
                                                else drumsHome = Math.max(0, Number(homeDraft) || 0);
                                                const t = {
                                                    ...base,
                                                    type: 'Expense',
                                                    category: 'Labor',
                                                    subCategory: 'Attendance',
                                                    laborStatus: 'Work',
                                                    workTypeByEmployee,
                                                    description: `ค่าแรง (${allEmps.length} คน) ${workLabel}${desc ? ` [${desc}]` : ''}${driverOnlyNames ? ` [คนขับจากงานใช้รถ: ${driverOnlyNames}]` : ''}`,
                                                    amount: total,
                                                    workAssignments: { ...normalizedWa },
                                                    customWorkCategories: [
                                                        ...FIXED_LABOR_CANVAS_CATEGORIES.map(c => ({
                                                            id: c.id,
                                                            label: c.label,
                                                        })),
                                                        ...generalSubJobs
                                                            .filter(
                                                                job =>
                                                                    (workAssignments[
                                                                        generalSubJobAssignmentKey(job.id)
                                                                    ] || []).length > 0
                                                            )
                                                            .map(job => ({
                                                                id: generalSubJobAssignmentKey(job.id),
                                                                label: job.title.trim() || 'งานทั่วไป',
                                                            })),
                                                    ],
                                                    ...(drumsHome !== undefined ? { drumsWashedAtHome: drumsHome } : {}),
                                                };
                                                if (hasSemanticNearDuplicate(t as Transaction, { ignoreId: existingDailyLaborTx?.id })) {
                                                    const proceed = await shouldContinueWithWarning(
                                                        ['พบรายการค่าแรง Attendance ที่ข้อมูลใกล้เคียงในวันเดียวกัน'],
                                                        'ตรวจพบรายการค่าแรงใกล้เคียง'
                                                    );
                                                    if (!proceed) return;
                                                }
                                                const laborSaved = await Promise.resolve(onSaveTransaction(t as any));
                                                if (laborSaved === false) return;
                                                setSelectedEmps([]);
                                                setWorkAssignments({});
                                                setLaborGeneralWorkNotes('');
                                                setGeneralSubJobs([{ id: newGeneralSubJobId(), title: '' }]);
                                                setHalfDayEmpIds(new Set());
                                                if (drumsHome !== undefined) setDrumsWashedAtHome('');
                                            }} className="w-full bg-emerald-600 hover:bg-emerald-700 py-3 text-base focus-ring-strong" data-hotkey-primary="true">
                                                <CheckCircle2 size={18} className="mr-2" /> {(dayTransactions.some(tx => tx.category === 'Labor' && tx.subCategory === 'Attendance' && tx.laborStatus === 'Work') ? 'อัปเดตค่าแรง' : 'บันทึกค่าแรง')} ({[...new Set([
                                                    ...Object.values(normalizedWorkAssignments).flat(),
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
                                    {dayTransactions.filter(t => t.category === 'Vehicle').map(t => {
                                        const mobileSignature = parseSignatureNote(t.note);
                                        return (
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
                                                                    setVehMachineWage(defaultVehicleMachineWage);
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
                                                <div className="text-amber-800/90 text-[10px] font-semibold">{(t as any).workType === 'HalfDay' ? 'ครึ่งวัน' : (t as any).workType === 'Hourly' ? 'รายชั่วโมง' : 'เต็มวัน'}</div>
                                                <div className="text-amber-700 line-clamp-3">{t.workDetails}</div>
                                                <div className="mt-1 text-[10px] font-medium text-amber-900/80">฿{(t.amount ?? 0).toLocaleString()}</div>
                                                {mobileSignature && (
                                                    <div className="mt-1 rounded-md border border-amber-200/90 bg-amber-50/95 px-1.5 py-1 text-[10px] font-medium text-amber-900 dark:border-amber-500/35 dark:bg-amber-950/50 dark:text-amber-100">
                                                        ✍️ {signatureSourceLabel(mobileSignature)} {mobileSignature.signedBy ? `โดย ${mobileSignature.signedBy}` : ''}
                                                        {mobileSignature.signedAt ? ` • ${formatSignatureDateTime(mobileSignature.signedAt)}` : ''}
                                                    </div>
                                                )}
                                                {mobileSignature && <SignatureAttachmentPreview meta={mobileSignature} />}
                                            </div>
                                        );
                                    })}
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
                                                    setVehMachineWage(defaultVehicleMachineWage);
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
                                        <Select label="รถ/เครื่องจักร" value={vehCar} onChange={(e: any) => {
                                            const nextCar = e.target.value;
                                            setVehCar(nextCar);
                                            const defaultDriverId = getVehicleDefaultDriverId(nextCar, settings);
                                            if (defaultDriverId) {
                                                setVehDriver(defaultDriverId);
                                                void applyVehicleDriverAllowance(defaultDriverId, vehWorkType);
                                            }
                                        }}><option value="">-- เลือกรถ --</option>{settings.cars.map(c => <option key={c}>{c}</option>)}</Select>
                                        <Select label="คนขับ" value={vehDriver} onChange={(e: any) => {
                                            const val = e.target.value;
                                            setVehDriver(val);
                                            void applyVehicleDriverAllowance(val, vehWorkType);
                                        }}>
                                            <option value="">-- เลือกคนขับ --</option>
                                            {driverEmployees.map(e => (
                                                <option key={e.id} value={e.id}>
                                                    {driverOptionLabel(e, getVehicleDefaultDriverId(vehCar, settings))}
                                                </option>
                                            ))}
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
                                                className={`px-3 py-1.5 rounded-lg text-sm font-medium border transition-colors ${vehWorkType === 'FullDay' ? 'bg-amber-700 text-white border-amber-700' : 'bg-white dark:bg-white/5 text-slate-600 dark:text-slate-300 border-slate-200 dark:border-white/15 hover:border-amber-300'}`}
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
                                            <div />
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
                                        const vehSaved = await Promise.resolve(
                                            onSaveTransaction({
                                                id, date, type: 'Expense', category: 'Vehicle',
                                                description: `รถ: ${vehCar} (${vehDetails}) [${dayLabel}]`, amount: Number(vehWage) + Number(vehMachineWage),
                                                vehicleId: vehCar, driverId: vehDriver, vehicleWage: Number(vehMachineWage), driverWage: Number(vehWage),
                                                workDetails: vehDetails, location: vehLocation, workType: vehWorkType
                                            } as Transaction)
                                        );
                                        if (vehSaved === false) return;
                                        setEditingVehicleTxId(null);
                                        setVehCar(''); setVehDetails(''); setVehWage(''); setVehMachineWage(defaultVehicleMachineWage); setVehWorkType('FullDay');
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
                                        <h3 className="font-bold text-lg flex items-center gap-2 text-slate-800 dark:text-slate-100"><Truck className="text-amber-600 dark:text-amber-400" /> บันทึกรถและจำนวนเที่ยวรถ</h3>
                                        {(() => {
                                            const savedTrips = dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'VehicleTrip');
                                            const savedTotalTrips = savedTrips.reduce((sum, t) => sum + ((t as any).perCarTrips || 0), 0);
                                            const savedTotalCubic = savedTrips.reduce((sum, t) => sum + ((t as any).perCarCubic || 0), 0);
                                            const displayTrips = totalTrips > 0 ? totalTrips : savedTotalTrips;
                                            const draftCubic = computeWizardTripFormCubic(tripEntries, tripMorning, tripAfternoon);
                                            const displayCubic = draftCubic > 0 || totalTrips > 0 ? draftCubic : savedTotalCubic;
                                            return (
                                                <div className="flex gap-2">
                                                    <div className={`${displayTrips > 0 ? 'bg-amber-700' : 'bg-slate-400'} text-white px-3 py-2 rounded-xl text-xs font-bold shadow-md`}>
                                                        {displayTrips} เที่ยว
                                                    </div>
                                                    <div className={`${displayCubic > 0 ? 'bg-amber-600' : 'bg-slate-400'} text-white px-3 py-2 rounded-xl text-xs font-bold shadow-md`}>
                                                        {displayCubic} คิว
                                                    </div>
                                                </div>
                                            );
                                        })()}
                                    </div>
                                    <div className="text-sm text-slate-500 dark:text-slate-400 flex items-center gap-1.5">
                                        📅 วันที่: <span className="font-semibold text-amber-900 dark:text-amber-200">{new Date(date).toLocaleDateString('th-TH', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}</span>
                                    </div>
                                </div>

                                {/* Morning / Afternoon Trip Counts + Cubic per trip */}
                                <div className="rounded-xl border border-amber-100/90 bg-gradient-to-br from-amber-50/90 via-white to-stone-50/80 p-4 dark:border-white/10 dark:from-amber-950/30 dark:via-white/[0.03] dark:to-stone-950/20 mb-4">
                                    <p className="text-sm font-bold text-slate-700 dark:text-slate-200 mb-1">จำนวนเที่ยวรวม</p>
                                    <p className="text-xs text-slate-500 dark:text-slate-400 mb-3">เว้นว่างได้ หากวันนี้ใช้รถขนงานอย่างอื่นและไม่มีการวิ่งเที่ยว</p>
                                    <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 md:gap-4">
                                        <div className="space-y-2">
                                            <label className="mb-1 block text-xs font-medium text-amber-800 dark:text-amber-200">☀️ ช่วงเช้า (เที่ยว)</label>
                                            <NumberPickerInput
                                                placeholder="0"
                                                value={tripMorning}
                                                onChange={setTripMorning}
                                                listMin={0}
                                                listMax={200}
                                                scrollAnchor={90}
                                                min={0}
                                                className="w-full px-3 py-2.5 border-2 border-amber-300/90 bg-white text-center text-lg font-bold text-amber-900 transition-colors focus:border-amber-500 focus:outline-none dark:border-amber-500/40 dark:bg-white/5 dark:text-amber-100"
                                            />
                                        </div>
                                        <div className="space-y-2">
                                            <label className="mb-1 block text-xs font-medium text-amber-700/90 dark:text-amber-300/90">🌙 ช่วงบ่าย (เที่ยว)</label>
                                            <NumberPickerInput
                                                placeholder="0"
                                                value={tripAfternoon}
                                                onChange={setTripAfternoon}
                                                listMin={0}
                                                listMax={200}
                                                scrollAnchor={90}
                                                min={0}
                                                className="w-full px-3 py-2.5 border-2 border-amber-200 bg-white text-center text-lg font-bold text-amber-900 transition-colors focus:border-amber-400 focus:outline-none dark:border-amber-500/30 dark:bg-white/5 dark:text-amber-100"
                                            />
                                        </div>
                                    </div>
                                    {(() => {
                                        const withVeh = tripEntries.filter(e => e.vehicle);
                                        const perTripCars = withVeh.filter(e => e.billingMode !== 'LumpSum');
                                        const lumpTotal = withVeh
                                            .filter(e => e.billingMode === 'LumpSum')
                                            .reduce((s, e) => s + (Number(e.lumpSumCubic) || 0), 0);
                                        if (totalTrips <= 0 && lumpTotal <= 0) return null;
                                        let displayTotalCubic = lumpTotal;
                                        let tripsPerCar = 0;
                                        let remainder = 0;
                                        const validCount = perTripCars.length;
                                        if (perTripCars.length > 0 && totalTrips > 0) {
                                            tripsPerCar = Math.floor(totalTrips / perTripCars.length);
                                            remainder = totalTrips % perTripCars.length;
                                            perTripCars.forEach((entry, idx) => {
                                                const carTrips = tripsPerCar + (idx < remainder ? 1 : 0);
                                                const carCubicPerTrip = Number(entry.cubicPerTrip) || detectDefaultCubicPerTrip(entry.vehicle, 3);
                                                displayTotalCubic += carTrips * carCubicPerTrip;
                                            });
                                        }
                                        if (validCount <= 0) {
                                            return (
                                                <div className="mt-3 p-3 bg-white/80 dark:bg-white/[0.04] rounded-lg text-sm font-medium text-slate-600 dark:text-slate-300 space-y-1 border border-amber-100/80 dark:border-white/10">
                                                    <div className="text-center">
                                                        รวมทราย <span className="font-bold text-lg text-amber-800 dark:text-amber-200">{displayTotalCubic} คิว</span>
                                                        <span className="text-xs text-slate-400 ml-1">(เหมา)</span>
                                                    </div>
                                                </div>
                                            );
                                        }
                                        if (totalTrips <= 0) {
                                            return (
                                                <div className="mt-3 p-3 bg-white/80 dark:bg-white/[0.04] rounded-lg text-sm font-medium text-slate-600 dark:text-slate-300 space-y-1 border border-amber-100/80 dark:border-white/10">
                                                    <div className="text-center text-xs text-slate-500 dark:text-slate-400">ระบุเที่ยวรวมด้านบนเพื่อคำนวณคิวแบบคิดเป็นเที่ยว</div>
                                                    <div className="text-center">
                                                        รวมทราย <span className="font-bold text-lg text-amber-800 dark:text-amber-200">{displayTotalCubic} คิว</span>
                                                        <span className="text-xs text-slate-400 ml-1">(เหมาเท่านั้นจนกว่าจะมีเที่ยวรวม)</span>
                                                    </div>
                                                </div>
                                            );
                                        }
                                        return (
                                            <div className="mt-3 p-3 bg-white/80 dark:bg-white/[0.04] rounded-lg text-sm font-medium text-slate-600 dark:text-slate-300 space-y-1 border border-amber-100/80 dark:border-white/10">
                                                <div className="text-center">
                                                    รวม <span className="font-bold text-amber-800 dark:text-amber-200">{totalTrips}</span> เที่ยว ÷ <span className="font-bold text-amber-900 dark:text-amber-100">{validCount}</span> คัน = <span className="font-bold text-amber-700 dark:text-amber-300">{tripsPerCar}{remainder > 0 ? `~${tripsPerCar + 1}` : ''}</span> เที่ยว/คัน
                                                </div>
                                                <div className="text-center">
                                                    รวมทราย <span className="font-bold text-lg text-amber-800 dark:text-amber-200">{displayTotalCubic} คิว</span>
                                                    <span className="text-xs text-slate-400 ml-1">(คิดเป็นเที่ยว + เหมา)</span>
                                                </div>
                                            </div>
                                        );
                                    })()}
                                </div>

                                {/* Saved entries from today */}
                                {dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'VehicleTrip').length > 0 && (
                                    <div className="mb-4 flex gap-2 overflow-x-auto pb-2">
                                        {dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'VehicleTrip').map(t => {
                                            const mobileSignature = parseSignatureNote(t.note);
                                            return (
                                                <div key={t.id} className="min-w-[200px] p-2.5 bg-amber-50/90 border border-amber-200/90 rounded-lg text-xs dark:bg-amber-950/25 dark:border-amber-500/25">
                                                    <div className="font-bold text-amber-950 dark:text-amber-100">✅ {t.vehicleId}</div>
                                                    <div className="text-amber-900/95 dark:text-amber-200 font-semibold">
                                                        {(t as any).tripBillingMode === 'LumpSum' ? (
                                                            <>เหมา {(t as any).perCarCubic ?? (t as any).totalCubic ?? 0} คิว</>
                                                        ) : (
                                                            <>{(t as any).perCarTrips || (t as any).tripCount} เที่ยว • {(t as any).perCarCubic ?? (t as any).totalCubic ?? 0} คิว</>
                                                        )}
                                                    </div>
                                                    <div className="text-amber-800/90 dark:text-amber-300/90 mt-0.5">{t.workDetails || '-'}</div>
                                                    <div className="text-amber-700/70 dark:text-amber-400/80 mt-1 text-[10px]">📅 {new Date(t.date).toLocaleDateString('th-TH', { day: 'numeric', month: 'short', year: '2-digit' })}</div>
                                                    {mobileSignature && (
                                                        <div className="mt-1 rounded-md border border-amber-200/90 bg-amber-50/95 px-1.5 py-1 text-[10px] font-medium text-amber-900 dark:border-amber-500/35 dark:bg-amber-950/50 dark:text-amber-100">
                                                            ✍️ {signatureSourceLabel(mobileSignature)} {mobileSignature.signedBy ? `โดย ${mobileSignature.signedBy}` : ''}
                                                            {mobileSignature.signedAt ? ` • ${formatSignatureDateTime(mobileSignature.signedAt)}` : ''}
                                                        </div>
                                                    )}
                                                    {mobileSignature && <SignatureAttachmentPreview meta={mobileSignature} />}
                                                </div>
                                            );
                                        })}
                                    </div>
                                )}

                                {/* Canvas: Vehicle Cards */}
                                <p className="text-sm font-medium text-slate-500 mb-2">เลือกรถและคนขับ ({tripEntries.length} คัน)</p>
                                <div className="flex-1 overflow-y-auto space-y-3 mb-4 pr-1">
                                    {tripEntries.map((entry, idx) => (
                                        <div key={entry.id} className="relative bg-white dark:bg-white/[0.03] p-4 rounded-xl border-2 border-amber-100 shadow-sm transition-all hover:border-amber-300/90 dark:border-amber-500/20 dark:hover:border-amber-500/40">
                                            <div className="flex justify-between items-center mb-3">
                                                <span className="text-xs font-bold text-amber-800 bg-amber-50 dark:text-amber-100 dark:bg-amber-950/40 px-2 py-1 rounded-lg border border-amber-200/80 dark:border-amber-500/25">🚛 คันที่ {idx + 1}</span>
                                                {tripEntries.length > 1 && (
                                                    <button onClick={() => removeTripCard(entry.id)} className="p-1.5 text-slate-300 hover:text-red-500 hover:bg-red-50 rounded-lg transition-colors" title="ลบ">
                                                        <Trash2 size={14} />
                                                    </button>
                                                )}
                                            </div>
                                            <div className="mb-2 grid grid-cols-1 gap-3 sm:grid-cols-2 md:mb-3 md:gap-4">
                                                <Select label="รถ" value={entry.vehicle} onChange={(e: any) => {
                                                    const nextVehicle = e.target.value;
                                                    const defaultDriverId = getVehicleDefaultDriverId(nextVehicle, settings);
                                                    setTripEntries(prev => prev.map(item => {
                                                        if (item.id !== entry.id) return item;
                                                        const autoCubic = detectDefaultCubicPerTrip(nextVehicle, 3);
                                                        return {
                                                            ...item,
                                                            vehicle: nextVehicle,
                                                            driver: defaultDriverId || item.driver,
                                                            cubicPerTrip: item.cubicPerTrip || String(autoCubic),
                                                        };
                                                    }));
                                                }}>
                                                    <option value="">-- เลือกรถ --</option>
                                                    {vehicleTripDrumCarOptions(settings.cars, entry.vehicle).map(c => <option key={c}>{c}</option>)}
                                                </Select>
                                                <Select label="คนขับ" value={entry.driver} onChange={(e: any) => updateTripCard(entry.id, 'driver', e.target.value)}>
                                                    <option value="">-- เลือกคนขับ --</option>
                                                    {driverEmployees.map((e) => {
                                                        const defaultId = getVehicleDefaultDriverId(entry.vehicle, settings);
                                                        return (
                                                            <option key={e.id} value={e.id}>
                                                                {driverOptionLabel(e, defaultId)}
                                                            </option>
                                                        );
                                                    })}
                                                </Select>
                                            </div>
                                            <div className="mb-2 flex flex-wrap gap-2">
                                                <button
                                                    type="button"
                                                    onClick={() => updateTripCard(entry.id, 'billingMode', 'PerTrip')}
                                                    className={`touch-manipulation rounded-xl border-2 px-3 py-2 text-xs font-bold transition ${entry.billingMode === 'PerTrip' ? 'border-amber-500 bg-amber-50 text-amber-950 dark:border-amber-400 dark:bg-amber-950/40 dark:text-amber-100' : 'border-slate-200 bg-white text-slate-600 dark:border-white/15 dark:bg-white/5 dark:text-slate-300'}`}
                                                >
                                                    คิดเป็นเที่ยว
                                                </button>
                                                <button
                                                    type="button"
                                                    onClick={() => updateTripCard(entry.id, 'billingMode', 'LumpSum')}
                                                    className={`touch-manipulation rounded-xl border-2 px-3 py-2 text-xs font-bold transition ${entry.billingMode === 'LumpSum' ? 'border-amber-500 bg-amber-50 text-amber-950 dark:border-amber-400 dark:bg-amber-950/40 dark:text-amber-100' : 'border-slate-200 bg-white text-slate-600 dark:border-white/15 dark:bg-white/5 dark:text-slate-300'}`}
                                                >
                                                    เหมา
                                                </button>
                                            </div>
                                            {entry.billingMode === 'LumpSum' ? (
                                                <div className="mb-2 space-y-2">
                                                    <label className="mb-1 block text-xs font-medium text-amber-900 dark:text-amber-200">รวมคิว (เหมา)</label>
                                                    <NumberPickerInput
                                                        value={entry.lumpSumCubic}
                                                        onChange={(v) => updateTripCard(entry.id, 'lumpSumCubic', v)}
                                                        listMin={1}
                                                        listMax={200}
                                                        scrollAnchor={30}
                                                        min={0}
                                                        placeholder="0"
                                                        className="w-full px-4 py-2.5 rounded-xl border border-amber-200 dark:border-amber-500/30 bg-white dark:bg-white/5 text-center text-lg font-bold text-amber-900 dark:text-amber-100"
                                                    />
                                                </div>
                                            ) : (
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
                                                        className="w-full px-4 py-2.5 rounded-xl border border-slate-200 dark:border-white/20 focus:outline-none focus:ring-2 focus:ring-amber-500/25 dark:focus:ring-amber-500/20 focus:border-amber-500 dark:focus:border-amber-500/50 transition-all bg-white dark:bg-white/5 text-slate-800 dark:text-slate-100 placeholder:text-slate-400 dark:placeholder:text-slate-500"
                                                    />
                                                    <div className="flex flex-wrap gap-2">
                                                        {['3', '6'].map(v => (
                                                            <button
                                                                key={`${entry.id}-cubic-${v}`}
                                                                type="button"
                                                                onClick={() => updateTripCard(entry.id, 'cubicPerTrip', v)}
                                                                className="touch-manipulation rounded-lg border border-amber-200/90 bg-amber-50/90 px-3 py-2 text-xs font-bold text-amber-900 shadow-sm transition hover:bg-amber-100 dark:border-amber-500/35 dark:bg-amber-500/15 dark:text-amber-100 dark:hover:bg-amber-500/25"
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
                                            )}
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

                                    <button onClick={addTripCard} className="w-full py-4 border-2 border-dashed border-slate-200 dark:border-white/15 hover:border-amber-400 rounded-xl text-slate-400 hover:text-amber-700 dark:hover:text-amber-300 flex items-center justify-center gap-2 transition-all hover:bg-amber-50/60 dark:hover:bg-amber-950/20">
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
                                        const lumpEntries = valid.filter(e => e.billingMode === 'LumpSum');
                                        const perTripEntries = valid.filter(e => e.billingMode !== 'LumpSum');
                                        for (const e of lumpEntries) {
                                            if ((Number(e.lumpSumCubic) || 0) <= 0) {
                                                await sessionAlert('กรุณาระบุรวมคิว (เหมา) ให้มากกว่า 0 สำหรับทุกคันที่เลือกเหมา');
                                                return;
                                            }
                                        }
                                        if (perTripEntries.length > 0 && totalTrips <= 0) {
                                            await sessionAlert('มีรถที่โหมดคิดเป็นเที่ยว — กรุณาระบุเที่ยวรวม (เช้า + บ่าย)');
                                            return;
                                        }
                                        const tripWarnings: string[] = [];
                                        const duplicatedVehicleInForm = valid.length !== new Set(valid.map(v => v.vehicle)).size;
                                        if (duplicatedVehicleInForm) tripWarnings.push('มีการเลือกรถคันเดิมซ้ำในฟอร์มเดียวกัน');
                                        if (perTripEntries.length > 0 && totalTrips > 300) tripWarnings.push('จำนวนเที่ยวรวมสูงกว่าปกติมาก');
                                        const hasExistingTripToday = dayTransactions.some(t => t.category === 'DailyLog' && t.subCategory === 'VehicleTrip');
                                        if (hasExistingTripToday) tripWarnings.push('วันนี้มีรายการเที่ยวรถอยู่แล้ว อาจเป็นการบันทึกซ้ำ');
                                        if (!(await shouldContinueWithWarning(tripWarnings, 'ตรวจพบรายการเที่ยวรถที่อาจซ้ำ/ผิดปกติ'))) return;
                                        const nPer = perTripEntries.length;
                                        const tripsPerCar = nPer > 0 ? Math.floor(totalTrips / nPer) : 0;
                                        const remainder = nPer > 0 ? totalTrips % nPer : 0;
                                        for (const entry of lumpEntries) {
                                            const driverName = employees.find(e => e.id === entry.driver)?.nickname || employees.find(e => e.id === entry.driver)?.name || '';
                                            const cubic = Number(entry.lumpSumCubic) || 0;
                                            const ok = await Promise.resolve(
                                                onSaveTransaction({
                                                    id: Date.now().toString() + entry.id, date, type: 'Expense', category: 'DailyLog', subCategory: 'VehicleTrip',
                                                    description: `${entry.vehicle}${driverName ? ` (${driverName})` : ''}: เหมา ${cubic} คิว - ${entry.work}`, amount: 0,
                                                    vehicleId: entry.vehicle, driverId: entry.driver, tripBillingMode: 'LumpSum',
                                                    tripCount: 0, tripMorning: 0, tripAfternoon: 0, cubicPerTrip: 0, totalCubic: cubic,
                                                    perCarTrips: 0, perCarCubic: cubic,
                                                    workDetails: entry.work
                                                } as Transaction)
                                            );
                                            if (ok === false) return;
                                        }
                                        for (let idx = 0; idx < perTripEntries.length; idx += 1) {
                                            const entry = perTripEntries[idx];
                                            const driverName = employees.find(e => e.id === entry.driver)?.nickname || '';
                                            const carTrips = tripsPerCar + (idx < remainder ? 1 : 0);
                                            const carCubicPerTrip = Number(entry.cubicPerTrip) || detectDefaultCubicPerTrip(entry.vehicle, 3);
                                            const carCubic = carTrips * carCubicPerTrip;
                                            const ok = await Promise.resolve(
                                                onSaveTransaction({
                                                    id: Date.now().toString() + entry.id, date, type: 'Expense', category: 'DailyLog', subCategory: 'VehicleTrip',
                                                    description: `${entry.vehicle}${driverName ? ` (${driverName})` : ''}: ${carTrips} เที่ยว × ${carCubicPerTrip} คิว = ${carCubic} คิว - ${entry.work}`, amount: 0,
                                                    vehicleId: entry.vehicle, driverId: entry.driver, tripBillingMode: 'PerTrip', tripCount: totalTrips,
                                                    tripMorning: Number(tripMorning) || 0, tripAfternoon: Number(tripAfternoon) || 0,
                                                    cubicPerTrip: carCubicPerTrip, totalCubic: carCubic,
                                                    perCarTrips: carTrips, perCarCubic: carCubic,
                                                    workDetails: entry.work
                                                } as Transaction)
                                            );
                                            if (ok === false) return;
                                        }
                                        setTripEntries([emptyWizardTripEntry()]);
                                        setTripMorning(''); setTripAfternoon('');
                                    }} className="w-full bg-amber-600 hover:bg-amber-700 py-3 text-base">
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
                                    const savedHomeDrumsFromSand =
                                        sandTxToday.length > 0 ? persistedSandHomeDrums(sandTxToday) : 0;
                                    const homeField = String(drumsWashedAtHome).trim();
                                    const homeDrums =
                                        homeField === ''
                                            ? Math.max(0, savedHomeDrumsFromSand || latestLaborDrumsWashedAtHome || 0)
                                            : Math.max(0, Number(homeField) || 0);
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
                                                            const mobileSignature = parseSignatureNote(t.note);
                                                            return (
                                                            <div key={t.id} className="min-w-[190px] p-2.5 bg-white border border-slate-200 rounded-xl text-xs relative shadow-sm dark:bg-white/[0.03] dark:border-white/10">
                                                                <div className="font-bold text-slate-700 dark:text-slate-200">🌊 {t.description}</div>
                                                                {isDrumsOnly ? (
                                                                    <div className="text-teal-700 dark:text-teal-300 font-semibold mt-1">🪣 {drums} ถัง</div>
                                                                ) : (
                                                                    <div className="text-slate-600 dark:text-slate-300 font-semibold mt-1">เช้า {(t as any).sandMorning || 0} + บ่าย {(t as any).sandAfternoon || 0} = {sandTotal} คิว</div>
                                                                )}
                                                                {mobileSignature && (
                                                                    <div className="mt-1 rounded-md border border-cyan-200 bg-cyan-50 px-1.5 py-1 text-[10px] font-medium text-cyan-700 dark:border-cyan-500/30 dark:bg-cyan-500/10 dark:text-cyan-200">
                                                                        ✍️ เซ็นจาก {signatureSourceLabel(mobileSignature)} {mobileSignature.signedBy ? `โดย ${mobileSignature.signedBy}` : ''}
                                                                        {mobileSignature.signedAt ? ` • ${formatSignatureDateTime(mobileSignature.signedAt)}` : ''}
                                                                    </div>
                                                                )}
                                                                {mobileSignature && <SignatureAttachmentPreview meta={mobileSignature} />}
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
                                    {/* ร่อนทราย — เลย์เอาต์เดียวกับแอป Android: ช่วงเช้า/บ่าย แถวละ 2 เครื่อง (ซ้าย=ใหม่ ขวา=เก่า) */}
                                    <p className="px-0.5 text-[13px] leading-snug text-slate-600 dark:text-slate-400">
                                        บันทึกทีละส่วนได้ เช่น กรอกคิวเช้าก่อน แล้วกลับมาเพิ่มคิวบ่ายภายหลัง
                                    </p>

                                    <div className="rounded-[14px] border border-slate-200 bg-slate-50/90 p-3 shadow-sm dark:border-white/10 dark:bg-white/[0.04]">
                                        <div className="mb-3 flex items-center gap-2">
                                            <Sun className="h-[18px] w-[18px] shrink-0 text-sky-500" aria-hidden />
                                            <span className="text-[15.5px] font-bold text-slate-800 dark:text-slate-100">ช่วงเช้า</span>
                                        </div>
                                        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 sm:gap-2.5">
                                            <div className="rounded-[14px] border border-cyan-200/90 bg-cyan-50/80 p-2.5 dark:border-cyan-500/30 dark:bg-cyan-500/10">
                                                <p className="mb-2 text-xs font-bold text-cyan-900 dark:text-cyan-100">เครื่องร่อน (ใหม่)</p>
                                                <label className="mb-1 block text-[11px] font-semibold text-slate-600 dark:text-slate-400">คิว</label>
                                                <NumberPickerInput
                                                    placeholder="0"
                                                    value={sand2Morning}
                                                    onChange={setSand2Morning}
                                                    listMin={0}
                                                    listMax={150}
                                                    scrollAnchor={75}
                                                    min={0}
                                                    className="w-full rounded-xl border-2 border-cyan-200/90 bg-white px-3 py-2 text-center text-lg font-bold text-cyan-900 focus:border-cyan-400 focus:outline-none dark:border-cyan-500/35 dark:bg-white/5 dark:text-cyan-100"
                                                />
                                                <p className="mb-1 mt-2 text-[11.5px] font-semibold text-slate-600 dark:text-slate-400">พนักงานล้าง</p>
                                                <div className="flex flex-wrap gap-1.5">
                                                    {(workAssignments['wash2'] || []).length > 0 ? (workAssignments['wash2'] || []).map(eid => {
                                                        const emp = employees.find(e => e.id === eid);
                                                        return emp ? <span key={eid} className="rounded-lg bg-cyan-500 px-2.5 py-1 text-xs font-medium text-white shadow-sm">{getEmployeeDisplayName(emp)}</span> : null;
                                                    }) : <span className="text-xs italic text-slate-400">ลากพนักงานใส่กล่อง &quot;ล้างทราย เครื่องร่อน 2 (ใหม่)&quot; ในขั้นค่าแรง</span>}
                                                </div>
                                            </div>
                                            <div className="rounded-[14px] border border-blue-200/90 bg-blue-50/80 p-2.5 dark:border-blue-500/30 dark:bg-blue-500/10">
                                                <p className="mb-2 text-xs font-bold text-blue-900 dark:text-blue-100">เครื่องร่อน (เก่า)</p>
                                                <label className="mb-1 block text-[11px] font-semibold text-slate-600 dark:text-slate-400">คิว</label>
                                                <NumberPickerInput
                                                    placeholder="0"
                                                    value={sand1Morning}
                                                    onChange={setSand1Morning}
                                                    listMin={0}
                                                    listMax={150}
                                                    scrollAnchor={75}
                                                    min={0}
                                                    className="w-full rounded-xl border-2 border-blue-200/90 bg-white px-3 py-2 text-center text-lg font-bold text-blue-900 focus:border-blue-400 focus:outline-none dark:border-blue-500/35 dark:bg-white/5 dark:text-blue-100"
                                                />
                                                <p className="mb-1 mt-2 text-[11.5px] font-semibold text-slate-600 dark:text-slate-400">พนักงานล้าง</p>
                                                <div className="flex flex-wrap gap-1.5">
                                                    {(workAssignments['wash1'] || []).length > 0 ? (workAssignments['wash1'] || []).map(eid => {
                                                        const emp = employees.find(e => e.id === eid);
                                                        return emp ? <span key={eid} className="rounded-lg bg-blue-500 px-2.5 py-1 text-xs font-medium text-white shadow-sm">{getEmployeeDisplayName(emp)}</span> : null;
                                                    }) : <span className="text-xs italic text-slate-400">ลากพนักงานใส่กล่อง &quot;ล้างทราย เครื่องร่อน 1 (เก่า)&quot; ในขั้นค่าแรง</span>}
                                                </div>
                                            </div>
                                        </div>
                                    </div>

                                    <div className="rounded-[14px] border border-slate-200 bg-slate-50/90 p-3 shadow-sm dark:border-white/10 dark:bg-white/[0.04]">
                                        <div className="mb-3 flex items-center gap-2">
                                            <Sunset className="h-[18px] w-[18px] shrink-0 text-teal-500" aria-hidden />
                                            <span className="text-[15.5px] font-bold text-slate-800 dark:text-slate-100">ช่วงบ่าย</span>
                                        </div>
                                        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 sm:gap-2.5">
                                            <div className="rounded-[14px] border border-cyan-200/90 bg-cyan-50/80 p-2.5 dark:border-cyan-500/30 dark:bg-cyan-500/10">
                                                <p className="mb-2 text-xs font-bold text-cyan-900 dark:text-cyan-100">เครื่องร่อน (ใหม่)</p>
                                                <label className="mb-1 block text-[11px] font-semibold text-slate-600 dark:text-slate-400">คิว</label>
                                                <NumberPickerInput
                                                    placeholder="0"
                                                    value={sand2Afternoon}
                                                    onChange={setSand2Afternoon}
                                                    listMin={0}
                                                    listMax={150}
                                                    scrollAnchor={75}
                                                    min={0}
                                                    className="w-full rounded-xl border-2 border-cyan-200/90 bg-white px-3 py-2 text-center text-lg font-bold text-cyan-900 focus:border-cyan-400 focus:outline-none dark:border-cyan-500/35 dark:bg-white/5 dark:text-cyan-100"
                                                />
                                                <p className="mb-1 mt-2 text-[11.5px] font-semibold text-slate-600 dark:text-slate-400">พนักงานล้าง</p>
                                                <div className="flex flex-wrap gap-1.5">
                                                    {(workAssignments['wash2'] || []).length > 0 ? (workAssignments['wash2'] || []).map(eid => {
                                                        const emp = employees.find(e => e.id === eid);
                                                        return emp ? <span key={`pm2-${eid}`} className="rounded-lg bg-cyan-500 px-2.5 py-1 text-xs font-medium text-white shadow-sm">{getEmployeeDisplayName(emp)}</span> : null;
                                                    }) : <span className="text-xs italic text-slate-400">ลากพนักงานใส่กล่อง &quot;ล้างทราย เครื่องร่อน 2 (ใหม่)&quot; ในขั้นค่าแรง</span>}
                                                </div>
                                            </div>
                                            <div className="rounded-[14px] border border-blue-200/90 bg-blue-50/80 p-2.5 dark:border-blue-500/30 dark:bg-blue-500/10">
                                                <p className="mb-2 text-xs font-bold text-blue-900 dark:text-blue-100">เครื่องร่อน (เก่า)</p>
                                                <label className="mb-1 block text-[11px] font-semibold text-slate-600 dark:text-slate-400">คิว</label>
                                                <NumberPickerInput
                                                    placeholder="0"
                                                    value={sand1Afternoon}
                                                    onChange={setSand1Afternoon}
                                                    listMin={0}
                                                    listMax={150}
                                                    scrollAnchor={75}
                                                    min={0}
                                                    className="w-full rounded-xl border-2 border-blue-200/90 bg-white px-3 py-2 text-center text-lg font-bold text-blue-900 focus:border-blue-400 focus:outline-none dark:border-blue-500/35 dark:bg-white/5 dark:text-blue-100"
                                                />
                                                <p className="mb-1 mt-2 text-[11.5px] font-semibold text-slate-600 dark:text-slate-400">พนักงานล้าง</p>
                                                <div className="flex flex-wrap gap-1.5">
                                                    {(workAssignments['wash1'] || []).length > 0 ? (workAssignments['wash1'] || []).map(eid => {
                                                        const emp = employees.find(e => e.id === eid);
                                                        return emp ? <span key={`pm1-${eid}`} className="rounded-lg bg-blue-500 px-2.5 py-1 text-xs font-medium text-white shadow-sm">{getEmployeeDisplayName(emp)}</span> : null;
                                                    }) : <span className="text-xs italic text-slate-400">ลากพนักงานใส่กล่อง &quot;ล้างทราย เครื่องร่อน 1 (เก่า)&quot; ในขั้นค่าแรง</span>}
                                                </div>
                                            </div>
                                        </div>
                                    </div>

                                    {/* Grand total */}
                                    {sandGrandTotal > 0 && (
                                        <div className="rounded-xl border border-emerald-200 bg-gradient-to-r from-emerald-100 to-teal-100 p-3 text-center">
                                            <span className="text-sm font-bold text-emerald-800">รวมล้างทรายทั้งหมด: </span>
                                            <span className="text-2xl font-black text-emerald-700">{sandGrandTotal}</span>
                                            <span className="text-sm text-emerald-600"> คิว/วัน</span>
                                            <div className="mt-1 text-[10px] text-emerald-600">เครื่อง (เก่า): {sand1Total} คิว | เครื่อง (ใหม่): {sand2Total} คิว</div>
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
                                        <div className="mt-3 grid grid-cols-2 sm:grid-cols-4 gap-2">
                                            <div className="rounded-xl border border-slate-200/80 dark:border-white/10 bg-white/80 dark:bg-white/[0.03] px-3 py-2">
                                                <p className="text-[10px] text-slate-500 dark:text-slate-400">จำนวนถังที่ได้วันนี้</p>
                                                <p className="text-lg font-black text-slate-700 dark:text-slate-100">{drumStockSummary.todayObtained}</p>
                                            </div>
                                            <div className="rounded-xl border border-teal-200/80 dark:border-teal-500/30 bg-teal-50/70 dark:bg-teal-500/10 px-3 py-2">
                                                <p className="text-[10px] text-teal-700/90 dark:text-teal-300">ล้างที่บ้านวันนี้</p>
                                                <p className="text-lg font-black text-teal-700 dark:text-teal-300">{drumStockSummary.todayHome}</p>
                                            </div>
                                            <div className="rounded-xl border border-amber-200/80 dark:border-amber-500/30 bg-amber-50/70 dark:bg-amber-500/10 px-3 py-2">
                                                <p className="text-[10px] text-amber-800/90 dark:text-amber-200">คงเหลือก่อนวันนี้</p>
                                                <p className="text-lg font-black text-amber-800 dark:text-amber-100">{drumStockSummary.cumulativeBeforeToday}</p>
                                            </div>
                                            <div className="rounded-xl border border-emerald-200/80 dark:border-emerald-500/30 bg-emerald-50/70 dark:bg-emerald-500/10 px-3 py-2">
                                                <p className="text-[10px] text-emerald-700/90 dark:text-emerald-300">คงเหลือหลังล้างวันนี้</p>
                                                <p className="text-lg font-black text-emerald-700 dark:text-emerald-300">{drumStockSummary.cumulativeRemaining}</p>
                                            </div>
                                        </div>
                                        <div className="mt-3 rounded-xl border border-cyan-200/70 dark:border-cyan-500/30 bg-cyan-50/60 dark:bg-cyan-500/10 p-3">
                                            <p className="text-xs font-bold text-cyan-800 dark:text-cyan-200 mb-2">Lot/Batch ต้นทาง</p>
                                            <label className="block text-[11px] text-cyan-700 dark:text-cyan-300">
                                                รหัสล็อตทรายวันนี้
                                                <input
                                                    type="text"
                                                    value={sandBatchId}
                                                    onChange={e => setSandBatchId(e.target.value)}
                                                    className="mt-1 w-full max-w-md rounded-lg border border-cyan-200 dark:border-cyan-500/35 bg-white dark:bg-white/5 px-2 py-1.5 text-[11px]"
                                                />
                                            </label>
                                        </div>
                                    </div>
                                </div>

                                <div className={mobileShell ? 'sticky bottom-[calc(0.4rem+env(safe-area-inset-bottom,0px))] z-[5] mt-2 space-y-2 rounded-2xl border border-slate-200/80 bg-white/95 p-2.5 shadow-sm backdrop-blur dark:border-white/10 dark:bg-slate-900/90' : 'pt-3 border-t space-y-2'}>
                                    <Button onClick={async () => {
                                        const drumsToday = Number(sandDrumsObtained) || 0;
                                        const homeDraft = String(drumsWashedAtHome).trim();
                                        const drumsHomeToday =
                                            homeDraft === '' ? 0 : Math.max(0, Number(homeDraft) || 0);
                                        if (sandGrandTotal === 0 && drumsToday === 0) {
                                            await sessionAlert('กรุณาใส่จำนวนทรายที่ล้างได้หรือจำนวนถังที่ได้วันนี้');
                                            return;
                                        }
                                        const batchIdFinal = (sandBatchId || `BATCH-${normalizeDate(date).replace(/-/g, '')}`).trim();
                                        if (drumsToday > 0 && !batchIdFinal) {
                                            await sessionAlert('กรุณาระบุรหัสล็อตทรายก่อนบันทึก');
                                            return;
                                        }
                                        const sandSnap = dayTransactions.filter(
                                            t => t.category === 'DailyLog' && t.subCategory === 'Sand'
                                        ) as any[];
                                        const existingS1 = pickLatestByDayOrder(
                                            sandSnap.filter((t: any) => t.sandMachineType === 'Old'),
                                            dayTransactions
                                        );
                                        const existingS2 = pickLatestByDayOrder(
                                            sandSnap.filter((t: any) => t.sandMachineType === 'New'),
                                            dayTransactions
                                        );
                                        const drumsOnlyPool = sandSnap.filter((t: any) => {
                                            if (t.sandMachineType === 'Old' || t.sandMachineType === 'New') return false;
                                            return (Number(t.sandMorning || 0) + Number(t.sandAfternoon || 0)) === 0;
                                        });
                                        const existingDrumsOnly = pickLatestByDayOrder(
                                            drumsOnlyPool as Transaction[],
                                            dayTransactions
                                        );
                                        const ts = Date.now().toString();
                                        const idSand1 = sand1Total > 0 ? (existingS1?.id ?? `${ts}_s1`) : '';
                                        const idSand2 = sand2Total > 0 ? (existingS2?.id ?? `${ts}_s2`) : '';
                                        const idSandDrumsOnly =
                                            sandGrandTotal === 0 && drumsToday > 0 ? (existingDrumsOnly?.id ?? `${ts}_drums`) : '';

                                        const opNames1 = sand1Operators.map(id => employees.find(e => e.id === id)?.nickname || '').join(', ');
                                        const opNames2 = sand2Operators.map(id => employees.find(e => e.id === id)?.nickname || '').join(', ');
                                        const timePayload = {
                                            sandMorningStart: sandMorningStart || undefined,
                                            sandAfternoonStart: sandAfternoonStart || undefined,
                                            sandEveningEnd: sandEveningEnd || undefined
                                        };
                                        if (sand1Total > 0) {
                                            const ok = await Promise.resolve(
                                                onSaveTransaction({
                                                    id: idSand1, date, type: 'Expense', category: 'DailyLog', subCategory: 'Sand',
                                                    description: `ล้างทราย เครื่องร่อน 1 (เก่า)${opNames1 ? ` [${opNames1}]` : ''}`, amount: 0,
                                                    sandMorning: Number(sand1Morning) || 0, sandAfternoon: Number(sand1Afternoon) || 0,
                                                    sandOperators: sand1Operators, sandMachineType: 'Old', drumsObtained: drumsToday,
                                                    drumsWashedAtHome: drumsHomeToday,
                                                    sandBatchId: batchIdFinal || undefined,
                                                    sandHomeBatchUsages: [],
                                                    ...timePayload
                                                } as Transaction)
                                            );
                                            if (ok === false) return;
                                        }
                                        if (sand2Total > 0) {
                                            const ok = await Promise.resolve(
                                                onSaveTransaction({
                                                    id: idSand2, date, type: 'Expense', category: 'DailyLog', subCategory: 'Sand',
                                                    description: `ล้างทราย เครื่องร่อน 2 (ใหม่)${opNames2 ? ` [${opNames2}]` : ''}`, amount: 0,
                                                    sandMorning: Number(sand2Morning) || 0, sandAfternoon: Number(sand2Afternoon) || 0,
                                                    sandOperators: sand2Operators, sandMachineType: 'New', drumsObtained: drumsToday,
                                                    drumsWashedAtHome: drumsHomeToday,
                                                    sandBatchId: batchIdFinal || undefined,
                                                    sandHomeBatchUsages: [],
                                                    ...timePayload
                                                } as Transaction)
                                            );
                                            if (ok === false) return;
                                        }
                                        if (sandGrandTotal === 0 && drumsToday > 0) {
                                            const ok = await Promise.resolve(
                                                onSaveTransaction({
                                                    id: idSandDrumsOnly, date, type: 'Expense', category: 'DailyLog', subCategory: 'Sand',
                                                    description: 'จำนวนถังที่ได้วันนี้', amount: 0, drumsObtained: drumsToday, drumsWashedAtHome: drumsHomeToday,
                                                    sandBatchId: batchIdFinal || undefined,
                                                    sandHomeBatchUsages: [],
                                                    ...timePayload
                                                } as Transaction)
                                            );
                                            if (ok === false) return;
                                        }
                                        if (homeDraft !== '') {
                                            const laborWork = dayTransactions.filter(
                                                t =>
                                                    t.category === 'Labor' &&
                                                    t.subCategory === 'Attendance' &&
                                                    t.laborStatus === 'Work'
                                            );
                                            const laborLatest = pickLatestByDayOrder(laborWork as any[], dayTransactions);
                                            if (laborLatest?.id) {
                                                const okLabor = await Promise.resolve(
                                                    onSaveTransaction({
                                                        ...(laborLatest as any),
                                                        drumsWashedAtHome: drumsHomeToday
                                                    } as Transaction)
                                                );
                                                if (okLabor === false) {
                                                    await sessionAlert(
                                                        'บันทึกล้างทรายแล้ว แต่ซิงก์จำนวนถังล้างที่บ้านไปยังบันทึกค่าแรงไม่สำเร็จ — กรุณาเปิดขั้นค่าแรงแล้วบันทึกอีกครั้ง'
                                                    );
                                                }
                                            }
                                        }
                                        if (onDeleteTransaction) {
                                            const normD = normalizeDate(date);
                                            for (const t of sandSnap) {
                                                if (normalizeDate(t.date) !== normD) continue;
                                                const mt = (t as any).sandMachineType;
                                                if (sand1Total > 0 && mt === 'Old' && t.id !== idSand1) {
                                                    onDeleteTransaction(t.id);
                                                }
                                                if (sand2Total > 0 && mt === 'New' && t.id !== idSand2) {
                                                    onDeleteTransaction(t.id);
                                                }
                                            }
                                            if (sand1Total > 0 || sand2Total > 0) {
                                                for (const t of sandSnap) {
                                                    if (normalizeDate(t.date) !== normD) continue;
                                                    const tx = t as any;
                                                    if (tx.sandMachineType === 'Old' || tx.sandMachineType === 'New') continue;
                                                    if (Number(tx.sandMorning || 0) + Number(tx.sandAfternoon || 0) !== 0) continue;
                                                    onDeleteTransaction(t.id);
                                                }
                                            }
                                            if (sandGrandTotal === 0 && drumsToday > 0 && idSandDrumsOnly) {
                                                for (const t of sandSnap) {
                                                    if (normalizeDate(t.date) !== normD) continue;
                                                    const tx = t as any;
                                                    if (tx.sandMachineType === 'Old' || tx.sandMachineType === 'New') continue;
                                                    if (Number(tx.sandMorning || 0) + Number(tx.sandAfternoon || 0) !== 0) continue;
                                                    if (t.id !== idSandDrumsOnly) onDeleteTransaction(t.id);
                                                }
                                            }
                                        }
                                        setSand1Morning(''); setSand1Afternoon(''); setSand2Morning(''); setSand2Afternoon('');
                                        setSand1Operators([]); setSand2Operators([]); setSandDrumsObtained('');
                                        setSandBatchId(`BATCH-${normalizeDate(date).replace(/-/g, '')}`);
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
                                                                        {(() => {
                                                                            const mobileSignature = parseSignatureNote(t.note);
                                                                            if (!mobileSignature) return null;
                                                                            return (
                                                                                <>
                                                                                    <div className="mb-1 rounded-md border border-cyan-200 bg-cyan-50 px-1.5 py-1 text-[10px] font-medium text-cyan-700">
                                                                                        ✍️ {signatureSourceLabel(mobileSignature)} {mobileSignature.signedBy ? `โดย ${mobileSignature.signedBy}` : ''}
                                                                                        {mobileSignature.signedAt ? ` • ${formatSignatureDateTime(mobileSignature.signedAt)}` : ''}
                                                                                    </div>
                                                                                    <SignatureAttachmentPreview meta={mobileSignature} />
                                                                                </>
                                                                            );
                                                                        })()}
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
                                                                        {(() => {
                                                                            const mobileSignature = parseSignatureNote(t.note);
                                                                            if (!mobileSignature) return null;
                                                                            return (
                                                                                <>
                                                                                    <div className="mb-1 rounded-md border border-cyan-200 bg-cyan-50 px-1.5 py-1 text-[10px] font-medium text-cyan-700">
                                                                                        ✍️ {signatureSourceLabel(mobileSignature)} {mobileSignature.signedBy ? `โดย ${mobileSignature.signedBy}` : ''}
                                                                                        {mobileSignature.signedAt ? ` • ${formatSignatureDateTime(mobileSignature.signedAt)}` : ''}
                                                                                    </div>
                                                                                    <SignatureAttachmentPreview meta={mobileSignature} />
                                                                                </>
                                                                            );
                                                                        })()}
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
                                            <div />
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
                                            onWheel={e => e.preventDefault()}
                                            className="w-full px-4 py-4 border border-slate-300 dark:border-white/15 rounded-xl text-lg text-slate-800 dark:text-slate-100 bg-white dark:bg-white/5 focus:border-slate-500 dark:focus:border-slate-400 focus:outline-none transition-colors" />
                                        <div />
                                    </div>

                                    {/* Details (optional) */}
                                    <div>
                                        <label className="text-sm font-medium text-slate-600 dark:text-slate-300 mb-1.5 block">รายละเอียดเพิ่มเติม <span className="text-slate-400 dark:text-slate-500 font-normal">(ไม่บังคับ)</span></label>
                                        <input type="text" placeholder="เช่น ซื้อที่ปั๊มหน้าแคมป์" value={fuelDetails} onChange={e => setFuelDetails(e.target.value)}
                                            className="w-full px-4 py-3 border border-slate-300 dark:border-white/15 rounded-xl text-base text-slate-800 dark:text-slate-100 bg-white dark:bg-white/5 focus:border-slate-500 dark:focus:border-slate-400 focus:outline-none transition-colors" />
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
                                        const okIn = await Promise.resolve(
                                            onSaveTransaction({
                                                id: Date.now().toString(), date, type: 'Expense', category: 'Fuel',
                                                description: `ซื้อน้ำมัน ${fuelType === 'Diesel' ? 'ดีเซล' : 'เบนซิน'}: ${fuelLiters || 0} ${fuelUnit} ${fuelAmount} บาท${fuelDetails ? ` - ${fuelDetails}` : ''}`,
                                                amount: Number(fuelAmount),
                                                quantity: Number(fuelLiters), unit: unitLabel, fuelType,
                                                workDetails: fuelDetails,
                                                fuelMovement: 'stock_in'
                                            } as Transaction)
                                        );
                                        if (okIn === false) return;
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
                                        <div />
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
                                        const okOut = await Promise.resolve(
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
                                            } as Transaction)
                                        );
                                        if (okOut === false) return;
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
                                                {(() => {
                                                    const mobileSignature = parseSignatureNote(t.note);
                                                    if (!mobileSignature) return null;
                                                    return (
                                                        <>
                                                            <div className="mb-1 rounded-md border border-cyan-200 bg-cyan-50 px-1.5 py-1 text-[10px] font-medium text-cyan-700">
                                                                ✍️ {signatureSourceLabel(mobileSignature)} {mobileSignature.signedBy ? `โดย ${mobileSignature.signedBy}` : ''}
                                                                {mobileSignature.signedAt ? ` • ${formatSignatureDateTime(mobileSignature.signedAt)}` : ''}
                                                            </div>
                                                            <SignatureAttachmentPreview meta={mobileSignature} />
                                                        </>
                                                    );
                                                })()}
                                                <div className="font-bold text-lime-800">{t.description || 'รายรับ'}</div>
                                                <div className="text-lime-700 font-semibold mt-1">฿{(t.amount || 0).toLocaleString()}</div>
                                                {(t as any).incomePaymentStatus === 'Unpaid' ? (
                                                    <div className="mt-1 inline-flex rounded-md border border-amber-300 bg-amber-50 px-2 py-0.5 text-[10px] font-bold text-amber-900 dark:border-amber-600/50 dark:bg-amber-950/40 dark:text-amber-100">ยังไม่ได้จ่ายเงิน</div>
                                                ) : (
                                                    <div className="mt-1 inline-flex rounded-md border border-emerald-300 bg-emerald-50 px-2 py-0.5 text-[10px] font-bold text-emerald-900 dark:border-emerald-600/50 dark:bg-emerald-950/40 dark:text-emerald-100">จ่ายเงินแล้ว</div>
                                                )}
                                                {t.quantity != null && <div className="text-lime-600 mt-0.5">ปริมาณ: {t.quantity} {t.unit || ''}</div>}
                                                {(t as any).projectId ? <div className="text-lime-700/90 mt-0.5">ชื่อ: {(t as any).projectId}</div> : null}
                                                {t.location ? <div className="text-lime-700/90 mt-0.5 line-clamp-2">ที่อยู่: {t.location}</div> : null}
                                                {t.workDetails ? <div className="text-lime-600/90 mt-0.5 line-clamp-2">{t.workDetails}</div> : null}
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
                                            {visibleIncomeTypes(settings.incomeTypes).map((t) => (
                                                <option key={t} value={t} />
                                            ))}
                                        </datalist>
                                        <div className="flex flex-wrap items-center gap-1.5 pt-1">
                                            {visibleIncomeTypes(settings.incomeTypes).map((t) => (
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
                                            {visibleIncomeTypes(settings.incomeTypes).length === 0 && !incomeTypeAddOpen && (
                                                <span className="text-[11px] text-slate-500">ยังไม่มีประเภทรายรับ — กด + เพิ่ม</span>
                                            )}
                                        </div>
                                    </div>
                                    <Input label="ชื่อ" value={incomePartyName} onChange={(e: any) => setIncomePartyName(e.target.value)} />
                                    <Input label="ที่อยู่" value={incomePartyAddress} onChange={(e: any) => setIncomePartyAddress(e.target.value)} />
                                    <Input label="รายละเอียด (ไม่บังคับ)" value={incomePartyDetail} onChange={(e: any) => setIncomePartyDetail(e.target.value)} />
                                    <div className="rounded-xl border border-lime-200/80 bg-lime-50/60 dark:border-lime-500/25 dark:bg-lime-950/20 p-3 space-y-2">
                                        <p className="text-sm font-semibold text-slate-700 dark:text-slate-200">สถานะรับเงิน</p>
                                        <div className="flex flex-wrap gap-2">
                                            <button
                                                type="button"
                                                onClick={() => setIncomePaymentStatus('Unpaid')}
                                                className={`touch-manipulation rounded-xl border-2 px-3 py-2 text-xs font-bold transition ${incomePaymentStatus === 'Unpaid' ? 'border-amber-500 bg-amber-50 text-amber-950 dark:border-amber-400 dark:bg-amber-950/40 dark:text-amber-100' : 'border-slate-200 bg-white text-slate-600 dark:border-white/15 dark:bg-white/5 dark:text-slate-300'}`}
                                            >
                                                ยังไม่ได้จ่ายเงิน
                                            </button>
                                            <button
                                                type="button"
                                                onClick={() => setIncomePaymentStatus('Paid')}
                                                className={`touch-manipulation rounded-xl border-2 px-3 py-2 text-xs font-bold transition ${incomePaymentStatus === 'Paid' ? 'border-emerald-500 bg-emerald-50 text-emerald-950 dark:border-emerald-400 dark:bg-emerald-950/40 dark:text-emerald-100' : 'border-slate-200 bg-white text-slate-600 dark:border-white/15 dark:bg-white/5 dark:text-slate-300'}`}
                                            >
                                                จ่ายเงินแล้ว
                                            </button>
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
                                        const okInc = await Promise.resolve(
                                            onSaveTransaction({
                                                id: Date.now().toString(),
                                                date,
                                                type: 'Income',
                                                category: 'Income',
                                                description: incomeType,
                                                amount: Number(incomeTotal) || 0,
                                                quantity: incomeQty ? Number(incomeQty) : undefined,
                                                unitPrice: incomeUnitPrice ? Number(incomeUnitPrice) : undefined,
                                                projectId: incomePartyName.trim() || undefined,
                                                location: incomePartyAddress.trim() || undefined,
                                                workDetails: incomePartyDetail.trim() || undefined,
                                                incomePaymentStatus: incomePaymentStatus === 'Unpaid' ? 'Unpaid' : 'Paid',
                                            } as Transaction)
                                        );
                                        if (okInc === false) return;
                                        setIncomeType('');
                                        setIncomePartyName('');
                                        setIncomePartyAddress('');
                                        setIncomePartyDetail('');
                                        setIncomeQty('');
                                        setIncomeUnitPrice('');
                                        setIncomeTotal('');
                                        setIncomePaymentStatus('Paid');
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
                                        const okEv = await Promise.resolve(
                                            onSaveTransaction({
                                                id: Date.now().toString(), date, type: 'Expense', category: 'DailyLog', subCategory: 'Event',
                                                description: eventDesc.trim(), amount: 0,
                                                eventType, eventPriority
                                            } as Transaction)
                                        );
                                        if (okEv === false) return;
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
                                        <div className="text-lg sm:text-2xl font-bold text-amber-600">{dayStepStats.vehicleUsageCount}</div>
                                        <div className="text-[10px] sm:text-xs text-amber-800">การใช้รถ</div>
                                    </div>
                                    <div className="bg-blue-50 p-2 sm:p-3 rounded-xl border border-blue-100 text-center">
                                        <div className="text-lg sm:text-2xl font-bold text-blue-600">{dayStepStats.tripCount}</div>
                                        <div className="text-[10px] sm:text-xs text-blue-800">เที่ยวรถ</div>
                                    </div>
                                    <div className="bg-cyan-50 p-2 sm:p-3 rounded-xl border border-cyan-100 text-center">
                                        <div className="text-lg sm:text-2xl font-bold text-cyan-600">{dayStepStats.sandWashCount}</div>
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
                                    const hasVehicle = dayTransactions.some(countsAsWizardVehicleUsageRecord);
                                    const hasTrips = dayTransactions.some(transactionCountsAsVehicleTripMenu);
                                    const hasSand = dayTransactions.some(countsAsWizardSandWashRecord);
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
                                            sortedDayTransactions.map(t => {
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
                                    onClick={() => setStep(0)}
                                    className={`mx-auto mt-auto w-full px-8 sm:w-auto ${mobileShell ? 'min-h-[52px] text-base font-bold' : ''}`}
                                >
                                    {mobileShell ? 'เลือกวันใหม่' : 'เสร็จสิ้น / เริ่มบันทึกวันอื่น'}
                                </Button>
                            </div>
                        )}
                    </Card>
                </div>

                {!mobileShell && step === 0 && (
                <div className="xl:col-span-4 flex min-w-0 w-full flex-col gap-4">
                    {/* Right: สรุปวันนี้ — เฉพาะขั้น «วันที่ทำงาน» */}
                    {/* สรุปด่วน: การ์ดแนวตั้ง อ่านง่าย; จอเล็ก 2×2 / แถบข้าง xl สแต็ก 1 คอลัมน์ */}
                    <div className="rounded-2xl border border-slate-200 bg-white p-3.5 shadow-sm dark:border-white/10 dark:bg-slate-950/40">
                        <div className="mb-3 flex items-start justify-between gap-3 rounded-xl border border-slate-200/80 bg-slate-50/80 px-3 py-2 dark:border-white/10 dark:bg-white/[0.03]">
                            <div>
                                <p className="text-[10px] font-bold uppercase tracking-[0.14em] text-slate-500 dark:text-slate-400">สรุปวันนี้</p>
                                <p className="mt-0.5 text-xs text-slate-500 dark:text-slate-400">
                                    {new Date(date + 'T12:00:00').toLocaleDateString('th-TH', { day: 'numeric', month: 'short', year: 'numeric' })}
                                </p>
                            </div>
                            <button
                                type="button"
                                onClick={() => setRightSummaryCompact(prev => !prev)}
                                className="shrink-0 rounded-lg border border-slate-300 bg-white px-2 py-1 text-[11px] font-semibold text-slate-700 hover:bg-slate-50 dark:border-white/20 dark:bg-white/[0.06] dark:text-slate-200"
                            >
                                {rightSummaryCompact ? 'ขยาย' : 'ย่อ'}
                            </button>
                        </div>
                        <div className="rounded-xl border border-slate-200/90 bg-gradient-to-b from-slate-50/90 to-white p-2.5 shadow-inner dark:border-white/10 dark:from-white/[0.04] dark:to-white/[0.02] [contain:layout]">
                            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2 sm:gap-2.5">
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
                                        label: 'ล้างทราย',
                                        unit: 'คิว',
                                        display: formatDisplayNumber(atAGlanceStats.sandCubic),
                                        Icon: Droplets,
                                        cell: 'bg-cyan-500/[0.08] dark:bg-cyan-500/10 border-cyan-200/70 dark:border-cyan-500/20',
                                        iconWrap: 'bg-cyan-500/20 text-cyan-700 dark:text-cyan-300',
                                        labelClass: 'text-cyan-900/80 dark:text-cyan-200',
                                        valueClass: 'text-cyan-800 dark:text-cyan-200',
                                    },
                                    {
                                        label: 'เที่ยวรถ',
                                        unit: 'รายการ',
                                        display: String(atAGlanceStats.vehicleTripCount),
                                        Icon: Truck,
                                        cell: 'bg-orange-500/[0.08] dark:bg-orange-500/10 border-orange-200/70 dark:border-orange-500/20',
                                        iconWrap: 'bg-orange-500/20 text-orange-800 dark:text-orange-300',
                                        labelClass: 'text-orange-900/85 dark:text-orange-200',
                                        valueClass: 'text-orange-800 dark:text-orange-200',
                                    },
                                    {
                                        label: 'น้ำมัน',
                                        unit: 'บาท',
                                        display: formatDisplayNumber(atAGlanceStats.fuelBaht),
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
                                            className={`flex min-w-0 items-center gap-1.5 rounded-lg border px-2 py-1.5 sm:gap-2 sm:px-2.5 sm:py-2 ${item.cell}`}
                                        >
                                            {!rightSummaryCompact && (
                                                <div
                                                    className={`flex h-7 w-7 shrink-0 items-center justify-center rounded-md ${item.iconWrap}`}
                                                    aria-hidden
                                                >
                                                    <GlanceIcon className="h-[14px] w-[14px]" strokeWidth={2.1} />
                                                </div>
                                            )}
                                            <div className="min-w-0 flex-1">
                                                <p className={`truncate text-[10px] font-bold leading-tight ${item.labelClass}`} title={item.label}>
                                                    {item.label}
                                                </p>
                                                <p className={`mt-0.5 leading-tight ${item.valueClass}`}>
                                                    <span
                                                        className="block max-w-full text-sm font-bold tabular-nums tracking-tight sm:text-base"
                                                        title={`${'prefix' in item && item.prefix ? item.prefix : ''}${item.display} ${item.unit}`}
                                                    >
                                                        {'prefix' in item && item.prefix ? <span className="font-bold">{item.prefix}</span> : null}
                                                        {item.display}
                                                    </span>
                                                    {!rightSummaryCompact && <span className={`block text-[9px] font-medium opacity-80 ${item.labelClass}`}>{item.unit}</span>}
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
                            {setSettings && duplicateLaborAttendanceMeta.duplicateDateCount > 0 && (
                                <button
                                    type="button"
                                    onClick={() => void handleMergeDuplicateLaborAttendance()}
                                    className="text-xs font-bold bg-amber-100 dark:bg-amber-500/20 text-amber-700 dark:text-amber-300 px-2.5 py-1 rounded-full shrink-0 self-start sm:self-center hover:bg-amber-200 dark:hover:bg-amber-500/30 transition-colors"
                                    title="รวมรายการ LABOR ซ้ำของวันเดียวกัน และซ่อนรายการเก่า"
                                >
                                    รวม LABOR ซ้ำ ({duplicateLaborAttendanceMeta.duplicateDateCount} วัน)
                                </button>
                            )}
                        </div>

                        <div className="flex-1 overflow-y-auto p-3 sm:p-4 space-y-3">
                            {sortedDayTransactions.length > 0 && (
                                <div className="rounded-xl border border-slate-200 bg-slate-50/80 p-2.5 dark:border-white/10 dark:bg-white/[0.03]">
                                    <p className="mb-2 text-[11px] font-semibold text-slate-600 dark:text-slate-300">Timeline วันนี้ (ตามเวลา createdAt)</p>
                                    <div className="flex flex-wrap gap-1.5">
                                        {sortedDayTransactions.slice(0, 8).map((t) => {
                                            const timeLabel = t.createdAt
                                                ? new Date(t.createdAt).toLocaleTimeString('th-TH', { hour: '2-digit', minute: '2-digit' })
                                                : '--:--';
                                            const status = timelineStatusById.get(t.id) || 'final';
                                            return (
                                                <span
                                                    key={`tl_${t.id}`}
                                                    className={`rounded-full px-2 py-0.5 text-[10px] font-semibold ${
                                                        status === 'latest'
                                                            ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-500/20 dark:text-emerald-300'
                                                            : status === 'edited'
                                                                ? 'bg-amber-100 text-amber-700 dark:bg-amber-500/20 dark:text-amber-300'
                                                                : 'bg-slate-100 text-slate-600 dark:bg-white/10 dark:text-slate-300'
                                                    }`}
                                                    title={`${t.category} • ${t.description}`}
                                                >
                                                    {timeLabel} · {status === 'latest' ? 'ล่าสุด' : status === 'edited' ? 'แก้ไขก่อนหน้า' : 'บันทึกแล้ว'}
                                                </span>
                                            );
                                        })}
                                    </div>
                                </div>
                            )}
                            {dayTransactions.length === 0 ? (
                                <div className="h-full flex flex-col items-center justify-center text-slate-500 dark:text-slate-300">
                                    <FileText size={48} className="mb-3 text-slate-300 dark:text-slate-500" />
                                    <p className="font-medium">ยังไม่มีรายการบันทึก</p>
                                </div>
                            ) : (
                                sortedDayTransactions.map(t => {
                                    const isDuplicate = duplicateTxMeta.duplicateIds.has(t.id);
                                    const timelineStatus = timelineStatusById.get(t.id) || 'final';
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
                                                <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${
                                                    timelineStatus === 'latest'
                                                        ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-500/20 dark:text-emerald-300'
                                                        : timelineStatus === 'edited'
                                                            ? 'bg-amber-100 text-amber-700 dark:bg-amber-500/20 dark:text-amber-300'
                                                            : 'bg-slate-100 text-slate-600 dark:bg-white/10 dark:text-slate-300'
                                                }`}>
                                                    {timelineStatus === 'latest' ? 'ล่าสุด' : timelineStatus === 'edited' ? 'แก้ไขก่อนหน้า' : 'บันทึกแล้ว'}
                                                </span>
                                                {isDuplicate && <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-rose-100 dark:bg-rose-500/20 text-rose-700 dark:text-rose-300">อาจซ้ำ</span>}
                                                {t.amount > 0 && <span className="font-bold text-sm text-slate-800 dark:text-white text-right">฿{t.amount.toLocaleString()}</span>}
                                            </div>
                                        </div>
                                        <p className="text-xs font-medium text-slate-700 dark:text-slate-300 mb-1 leading-snug">{t.description}</p>

                                        <div className="flex flex-wrap gap-2 text-[10px] text-slate-500 dark:text-slate-400 mt-2 bg-slate-50 dark:bg-white/[0.02] p-1.5 rounded-lg border border-slate-100 dark:border-white/5">
                                            {t.createdAt && <span className="flex items-center gap-1"><span className="w-1.5 h-1.5 rounded-full bg-slate-400"></span>เวลา: {new Date(t.createdAt).toLocaleTimeString('th-TH', { hour: '2-digit', minute: '2-digit' })}</span>}
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
                                ฿{sumWizardDailySpend(dayTransactions, employees).toLocaleString()}
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
