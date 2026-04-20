import { useState, useMemo, useEffect, useCallback } from 'react';
import { Calendar, Users, Truck, Fuel, CheckCircle2, ChevronRight, FileText, Plus, Trash2, Droplets, AlertTriangle, ClipboardList, Pencil } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import DatePicker from '../../components/ui/DatePicker';
import Select from '../../components/ui/Select';
import { getToday, formatDateBE, normalizeDate } from '../../utils';
import { Employee, Transaction, AppSettings, WorkType } from '../../types';

interface DailyStepRecorderProps {
    employees: Employee[];
    settings: AppSettings;
    transactions: Transaction[];
    dateFilter?: { start: string; end: string };
    onSaveTransaction: (t: Transaction) => void;
    onDeleteTransaction?: (id: string) => void;
    ensureEmployeeWage?: (emp: Employee) => Promise<number>;
    /** โหมดเว็บมือถือ: ลดรายละเอียด ซ่อนคอลัมน์สรุปขวาและแท็บรายงาน */
    mobileShell?: boolean;
}

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

const STEPS = [
    { id: 0, label: 'วันที่ทำงาน', shortLabel: 'วันที่', icon: Calendar },
    { id: 1, label: 'ค่าแรง', shortLabel: 'ค่าแรง', icon: Users },
    { id: 2, label: 'การใช้รถ', shortLabel: 'ใช้รถ', icon: Truck },
    { id: 3, label: 'เที่ยวรถ', shortLabel: 'เที่ยว', icon: Truck },
    { id: 4, label: 'ล้างทราย', shortLabel: 'ทราย', icon: Droplets },
    { id: 5, label: 'น้ำมัน', shortLabel: 'น้ำมัน', icon: Fuel },
    { id: 6, label: 'เหตุการณ์', shortLabel: 'เหตุการณ์', icon: AlertTriangle },
    { id: 7, label: 'ตรวจสอบ', shortLabel: 'สรุป', icon: CheckCircle2 }
];

// Default work categories for labor canvas
const DEFAULT_WORK_CATEGORIES = [
    { id: 'wash1', label: 'ล้างทราย เครื่องร่อน 1 (เก่า)', color: 'bg-blue-500', bgLight: 'bg-blue-50 border-blue-200' },
    { id: 'wash2', label: 'ล้างทราย เครื่องร่อน 2 (ใหม่)', color: 'bg-cyan-500', bgLight: 'bg-cyan-50 border-cyan-200' },
    { id: 'washHome', label: 'ล้างทรายที่บ้าน', color: 'bg-teal-500', bgLight: 'bg-teal-50 border-teal-200' },
    { id: 'other', label: 'ทำอื่นๆ', color: 'bg-slate-500', bgLight: 'bg-slate-50 border-slate-200' },
];
const DEFAULT_WORK_CATEGORY_IDS = new Set(DEFAULT_WORK_CATEGORIES.map(c => c.id));
const detectDefaultCubicPerTrip = (vehicleName: string, fallback: number) => {
    const name = (vehicleName || '').toLowerCase().replace(/\s+/g, '');
    if (name.includes('10ล้อ') || name.includes('สิบล้อ')) return 6;
    if (name.includes('6ล้อ') || name.includes('หกล้อ')) return 3;
    return fallback;
};
const isMonthlyEmployee = (emp?: Employee) => {
    if (!emp?.type) return false;
    const normalized = String(emp.type).trim().toLowerCase();
    return normalized === 'monthly' || normalized === 'รายเดือน';
};
const toDailyWage = (emp: Employee, wage: number) => (isMonthlyEmployee(emp) ? wage / 30 : wage);

const DailyStepRecorder = ({ employees, settings, transactions, dateFilter, onSaveTransaction, onDeleteTransaction, ensureEmployeeWage, mobileShell = false }: DailyStepRecorderProps) => {
    const isTouchLayout = useMediaQuery('(max-width: 1023px)');
    const [step, setStep] = useState(0);
    const [date, setDate] = useState(getToday());
    const [viewMode, setViewMode] = useState<'record' | 'report'>('record');

    useEffect(() => {
        if (mobileShell) setViewMode('record');
    }, [mobileShell]);
    // ช่วงวันที่สำหรับรายงาน (ใช้ dateFilter เป็นค่าเริ่มต้นถ้ามี)
    const [reportStart, setReportStart] = useState<string>(dateFilter?.start || '');
    const [reportEnd, setReportEnd] = useState<string>(dateFilter?.end || '');

    // Derived: Transactions for the selected date (normalize date so DB ISO string matches YYYY-MM-DD)
    const dayTransactions = useMemo(() => {
        const norm = normalizeDate(date);
        return transactions.filter(t => normalizeDate(t.date) === norm);
    }, [transactions, date]);
    const dayStepStats = useMemo(() => {
        const laborCount = dayTransactions.filter(t => t.category === 'Labor').length;
        const vehicleCount = dayTransactions.filter(t => t.category === 'Vehicle').length;
        const tripCount = dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'VehicleTrip').length;
        const sandCount = dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'Sand').length;
        const fuelCount = dayTransactions.filter(t => t.category === 'Fuel').length;
        const eventCount = dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'Event').length;
        return { laborCount, vehicleCount, tripCount, sandCount, fuelCount, eventCount };
    }, [dayTransactions]);
    const hasExistingWizardData = useMemo(() => Object.values(dayStepStats).some(count => count > 0), [dayStepStats]);
    const resumeStep = useMemo(() => {
        if (dayStepStats.eventCount > 0) return 6;
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
        const configuredCategories = settings.appDefaults?.laborWorkCategories || [];
        configuredCategories
            .filter((c: any) => c && typeof c.id === 'string' && typeof c.label === 'string')
            .forEach((c: any) => {
                if (!DEFAULT_WORK_CATEGORY_IDS.has(c.id) && !customById.has(c.id)) {
                    customById.set(c.id, { id: c.id, label: c.label });
                }
            });
        const laborAttendance = transactions.filter(t => t.category === 'Labor' && t.subCategory === 'Attendance') as any[];
        laborAttendance.forEach((tx) => {
            if (Array.isArray(tx.customWorkCategories)) {
                tx.customWorkCategories
                    .filter((c: any) => c && typeof c.id === 'string' && typeof c.label === 'string')
                    .forEach((c: any) => {
                        if (!customById.has(c.id)) customById.set(c.id, { id: c.id, label: c.label });
                    });
            }
            if (tx.workAssignments && typeof tx.workAssignments === 'object') {
                Object.keys(tx.workAssignments)
                    .filter(catId => !DEFAULT_WORK_CATEGORY_IDS.has(catId))
                    .forEach((catId) => {
                        if (!customById.has(catId)) customById.set(catId, { id: catId, label: catId });
                    });
            }
        });
        return Array.from(customById.values());
    }, [transactions, settings.appDefaults?.laborWorkCategories]);

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

    const getEmpPositions = (e: Employee) => e.positions ?? (e.position ? [e.position] : []);
    const driverEmployees = useMemo(() => employees.filter(e => getEmpPositions(e).includes('คนขับรถ')), [employees]);

    // Labor State
    const [laborSearch, setLaborSearch] = useState('');
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
    const [customCategories, setCustomCategories] = useState<Array<{ id: string; label: string }>>([]);
    const [newCategoryName, setNewCategoryName] = useState('');
    const [dragEmployee, setDragEmployee] = useState<string | null>(null);

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
    const [cubicPerTrip, setCubicPerTrip] = useState('3');
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
    const sand1Total = (Number(sand1Morning) || 0) + (Number(sand1Afternoon) || 0);
    const sand2Total = (Number(sand2Morning) || 0) + (Number(sand2Afternoon) || 0);
    const sandGrandTotal = sand1Total + sand2Total;

    // Fuel State
    const [fuelAmount, setFuelAmount] = useState('');
    const [fuelLiters, setFuelLiters] = useState('');
    const [fuelType, setFuelType] = useState<any>('Diesel');
    const [fuelUnit, setFuelUnit] = useState('ลิตร');
    const [fuelDetails, setFuelDetails] = useState('');

    // Events State
    const [eventDesc, setEventDesc] = useState('');
    const [eventType, setEventType] = useState('info');
    const [eventPriority, setEventPriority] = useState('normal');
    const [expandedRecordId, setExpandedRecordId] = useState<string | null>(null);

    // Prefill form state เมื่อเลือกวันที่ที่เคยบันทึกแล้ว
    useEffect(() => {
        // Labor Attendance (canvas)
        const laborAttendance = dayTransactions
            .filter(t => t.category === 'Labor' && t.subCategory === 'Attendance')
            .sort((a, b) => a.id.localeCompare(b.id));
        if (laborAttendance.length > 0) {
            const latest = laborAttendance[laborAttendance.length - 1] as any;
            if (latest.workAssignments) {
                setWorkAssignments(latest.workAssignments);
            } else {
                setWorkAssignments({});
            }
            if (Array.isArray(latest.customWorkCategories)) {
                setCustomCategories(
                    latest.customWorkCategories.filter((c: any) =>
                        c && typeof c.id === 'string' && typeof c.label === 'string'
                    )
                );
            } else if (latest.workAssignments) {
                const recoveredCustom = Object.keys(latest.workAssignments)
                    .filter(catId => !DEFAULT_WORK_CATEGORY_IDS.has(catId))
                    .map(catId => ({ id: catId, label: catId }));
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

        // Fuel (latest of the day)
        const fuelTx = dayTransactions
            .filter(t => t.category === 'Fuel')
            .sort((a, b) => a.id.localeCompare(b.id));
        if (fuelTx.length > 0) {
            const latestFuel = fuelTx[fuelTx.length - 1] as any;
            setFuelAmount(latestFuel.amount != null ? String(latestFuel.amount) : '');
            setFuelLiters(latestFuel.quantity != null ? String(latestFuel.quantity) : '');
            setFuelUnit(latestFuel.unit === 'gallon' ? 'แกลลอน' : 'ลิตร');
            setFuelType(latestFuel.fuelType || 'Diesel');
            setFuelDetails(latestFuel.workDetails || '');
        } else {
            setFuelAmount('');
            setFuelLiters('');
            setFuelUnit('ลิตร');
            setFuelType('Diesel');
            setFuelDetails('');
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

    const nextStep = () => {
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
            6: todaysTx.some(t => t.category === 'DailyLog' && t.subCategory === 'Event'),
        };

        if (stepNeedsData[step] === false) {
            const label = STEPS[step]?.label || '';
            if (!window.confirm(`ยังไม่มีการกดบันทึกในขั้น \"${label}\" สำหรับวันที่นี้\n\nหากต้องการไปขั้นถัดไปโดยไม่บันทึก ให้กด \"ตกลง\"`)) {
                return;
            }
        }

        setStep(s => Math.min(s + 1, STEPS.length - 1));
    };
    const prevStep = () => setStep(s => Math.max(s - 1, 0));
    const handleStartRecord = () => {
        if (hasExistingWizardData) {
            setStep(resumeStep);
            return;
        }
        nextStep();
    };

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
            className={`animate-fade-in relative w-full max-w-full min-w-0 ${mobileShell ? 'min-h-0 bg-transparent p-0 sm:p-0' : 'min-h-screen min-h-[100dvh] bg-slate-50 dark:bg-transparent p-3 sm:p-4 lg:p-6'}`}
        >
            {/* Header + โหมด บันทึก | รายงาน — โหมดมือถือ: เฉพาะแถบขั้นตอน แตะง่าย */}
            {mobileShell ? (
                viewMode === 'record' && (
                    <div className="sticky top-0 z-10 mb-3 rounded-2xl border border-slate-200/90 bg-white/95 px-1.5 py-2 shadow-sm backdrop-blur-md dark:border-white/10 dark:bg-slate-900/95">
                        <div className="flex gap-1 overflow-x-auto pb-0.5 hide-scrollbar">
                            {STEPS.map((s, i) => (
                                <button
                                    type="button"
                                    key={s.id}
                                    onClick={() => setStep(i)}
                                    className={`flex min-h-[44px] shrink-0 items-center justify-center rounded-xl px-3.5 text-sm font-bold transition-all active:scale-[0.98] touch-manipulation ${
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
                )
            ) : (
                <div className="mb-3 flex flex-col gap-3 sm:mb-6 sm:gap-4">
                    <div className="flex flex-col items-start justify-between gap-2 sm:flex-row sm:items-center sm:gap-3">
                        <div>
                            <h2 className="text-lg font-bold text-slate-800 dark:text-slate-100 sm:text-2xl">บันทึกงานประจำวัน (Daily Wizard)</h2>
                            <p className="text-xs text-slate-500 dark:text-slate-400 sm:text-sm">
                                {viewMode === 'record' ? 'ระบบช่วยบันทึกข้อมูลแบบทีละขั้นตอน' : 'รายงานสรุปข้อมูลที่บันทึกในแต่ละวัน'}
                            </p>
                        </div>
                        <div className="flex w-full rounded-xl border border-slate-200 bg-white p-1 shadow-sm dark:border-white/10 dark:bg-white/[0.04] sm:w-auto">
                            <button
                                type="button"
                                onClick={() => setViewMode('record')}
                                className={`flex flex-1 items-center justify-center gap-2 rounded-lg px-4 py-2.5 text-sm font-medium transition-all sm:flex-initial sm:text-base ${viewMode === 'record' ? 'bg-indigo-600 text-white shadow' : 'text-slate-500 hover:bg-slate-100 dark:text-slate-400 dark:hover:bg-white/10'}`}
                            >
                                <ClipboardList size={16} />
                                บันทึก
                            </button>
                            <button
                                type="button"
                                onClick={() => setViewMode('report')}
                                className={`flex flex-1 items-center justify-center gap-2 rounded-lg px-4 py-2.5 text-sm font-medium transition-all sm:flex-initial sm:text-base ${viewMode === 'report' ? 'bg-indigo-600 text-white shadow' : 'text-slate-500 hover:bg-slate-100 dark:text-slate-400 dark:hover:bg-white/10'}`}
                            >
                                <FileText size={16} />
                                รายงาน
                            </button>
                        </div>
                    </div>
                    {viewMode === 'record' && (
                        <div className="flex w-full gap-1.5 overflow-x-auto pb-1 hide-scrollbar sm:gap-2 sm:w-auto">
                            {STEPS.map((s, i) => (
                                <button
                                    type="button"
                                    key={s.id}
                                    onClick={() => setStep(i)}
                                    className={`flex shrink-0 cursor-pointer items-center gap-1 rounded-full px-2 py-1.5 text-xs font-medium transition-colors sm:gap-2 sm:px-3 ${
                                        step === i
                                            ? 'bg-indigo-600 text-white'
                                            : i < step
                                              ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-500/20 dark:text-emerald-300'
                                              : 'bg-slate-200 text-slate-500 hover:bg-slate-300 dark:bg-white/10 dark:text-slate-400 dark:hover:bg-white/20'
                                    }`}
                                    title={`ไปที่ขั้น: ${s.label}`}
                                >
                                    <s.icon size={12} />
                                    <span className="hidden sm:inline">{s.label}</span>
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
                            const events = txs.filter(t => t.category === 'DailyLog' && t.subCategory === 'Event');
                            const laborSum = labor.reduce((s, t) => s + t.amount, 0);
                            const vehicleSum = vehicle.reduce((s, t) => s + t.amount, 0);
                            const tripsTotal = trips.reduce((s, t) => s + ((t as any).perCarTrips || (t as any).tripCount || 0), 0);
                            const tripsCubic = trips.reduce((s, t) => s + ((t as any).perCarCubic || (t as any).totalCubic || 0), 0);
                            const sandCubic = sand.reduce((s, t) => s + (t.sandMorning || 0) + (t.sandAfternoon || 0), 0);
                            const sandDrums = sand.reduce((s, t) => s + ((t as any).drumsObtained || 0), 0);
                            const fuelSum = fuel.reduce((s, t) => s + t.amount, 0);
                            const workerIdSet = new Set<string>(labor.flatMap(t => t.employeeIds || []));
                            const workerCount = workerIdSet.size;
                            const workerIds = Array.from(workerIdSet);
                            const workerNames = workerIds.map(id => {
                                const emp = employees.find(e => e.id === id);
                                return emp?.nickname || emp?.name || id;
                            });

                            // กลุ่มประเภทงานจาก Attendance (canvas) ถ้ามี
                            const attendance = labor.filter(t => t.subCategory === 'Attendance') as any[];
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
                                    <div className="grid grid-cols-1 gap-3 p-4 sm:grid-cols-2 sm:gap-4 sm:p-5 lg:grid-cols-3 xl:grid-cols-6">
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
                                                {sandDrums > 0 && <>🪣 {sandDrums} ถัง • </>}
                                                {sand.length} รายการ
                                            </p>
                                        </div>
                                        <div className="bg-red-50 dark:bg-red-500/10 rounded-xl p-4 border border-red-100 dark:border-red-500/30">
                                            <div className="flex items-center gap-2 text-red-700 dark:text-red-300 font-semibold text-sm mb-1"><Fuel size={16} /> น้ำมัน</div>
                                            <p className="text-lg font-bold text-red-800 dark:text-red-100">฿{fuelSum.toLocaleString()}</p>
                                            <p className="text-xs text-red-600 dark:text-red-200 mt-0.5">{fuel.length} รายการ</p>
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
                    <Card className={`relative flex flex-col overflow-hidden ${mobileShell ? 'min-h-0 rounded-2xl border border-slate-200/80 p-4 shadow-sm dark:border-white/10 sm:p-4' : 'min-h-[500px] p-6'}`}>

                        {/* Step 0: Date */}
                        {step === 0 && (
                            <div className="flex flex-col items-center justify-center h-full space-y-6 animate-slide-up">
                                <div className="w-16 h-16 bg-indigo-100 dark:bg-indigo-500/20 rounded-full flex items-center justify-center text-indigo-600 dark:text-indigo-300 mb-2">
                                    <Calendar size={32} />
                                </div>
                                <h3 className={`font-bold text-slate-800 dark:text-slate-100 ${mobileShell ? 'text-lg' : 'text-xl'}`}>เลือกวันที่</h3>
                                <div className={mobileShell ? 'w-full' : 'w-full max-w-sm'}>
                                    <DatePicker label={mobileShell ? '' : 'วันที่'} value={date} onChange={setDate} />
                                </div>
                                {!mobileShell && (
                                    <div className="max-w-md rounded-xl border border-orange-100 bg-orange-50 p-4 text-center text-sm text-orange-700 dark:border-orange-500/25 dark:bg-orange-500/10 dark:text-orange-200">
                                        💡 ระบบจะดึงข้อมูลเก่าของวันนี้มาแสดงให้ตรวจสอบด้วยครับ
                                    </div>
                                )}
                                {hasExistingWizardData && (
                                    <div className="w-full rounded-2xl border border-emerald-200 bg-emerald-50/90 p-3 text-sm text-emerald-800 dark:border-emerald-500/40 dark:bg-emerald-500/15 dark:text-emerald-200">
                                        <p className="mb-2 font-bold">พบข้อมูลวันที่นี้แล้ว สามารถกดเพื่อเข้าไปแก้ไขต่อได้</p>
                                        <div className="grid grid-cols-3 gap-2 text-[11px]">
                                            <div className="rounded-lg bg-white/90 px-2 py-1.5 text-center dark:bg-white/10">ค่าแรง {dayStepStats.laborCount}</div>
                                            <div className="rounded-lg bg-white/90 px-2 py-1.5 text-center dark:bg-white/10">การใช้รถ {dayStepStats.vehicleCount}</div>
                                            <div className="rounded-lg bg-white/90 px-2 py-1.5 text-center dark:bg-white/10">เที่ยวรถ {dayStepStats.tripCount}</div>
                                            <div className="rounded-lg bg-white/90 px-2 py-1.5 text-center dark:bg-white/10">ทราย {dayStepStats.sandCount}</div>
                                            <div className="rounded-lg bg-white/90 px-2 py-1.5 text-center dark:bg-white/10">น้ำมัน {dayStepStats.fuelCount}</div>
                                            <div className="rounded-lg bg-white/90 px-2 py-1.5 text-center dark:bg-white/10">เหตุการณ์ {dayStepStats.eventCount}</div>
                                        </div>
                                    </div>
                                )}
                                <Button onClick={handleStartRecord} className="mt-8 px-8 py-3 text-lg shadow-lg shadow-indigo-200">
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

                                <div className="flex gap-3 mb-4">
                                    <button onClick={() => setLaborStatus('Work')} className={`flex-1 py-3 rounded-xl border text-base transition-all ${laborStatus === 'Work' ? 'bg-emerald-50 dark:bg-emerald-500/15 border-emerald-500 text-emerald-700 dark:text-emerald-300 font-bold' : 'bg-white dark:bg-white/5 border-slate-200 dark:border-white/10 text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-white/10'}`}>✅ มาทำงาน</button>
                                    <button onClick={() => setLaborStatus('OT')} className={`flex-1 py-3 rounded-xl border text-base transition-all ${laborStatus === 'OT' ? 'bg-amber-50 dark:bg-amber-500/15 border-amber-500 text-amber-700 dark:text-amber-300 font-bold' : 'bg-white dark:bg-white/5 border-slate-200 dark:border-white/10 text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-white/10'}`}>🕒 OT</button>
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
                                                <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
                                                    {employees.filter(e => e.name.includes(laborSearch) || e.nickname.includes(laborSearch)).map(emp => {
                                                        const isSelected = selectedEmps.includes(emp.id);
                                                        return (
                                                            <button key={emp.id}
                                                                onClick={() => setSelectedEmps(prev => prev.includes(emp.id) ? prev.filter(id => id !== emp.id) : [...prev, emp.id])}
                                                                className={`px-3 py-2.5 rounded-xl text-sm text-left font-medium transition-all border-2 ${isSelected ? 'border-slate-800 dark:border-slate-300 bg-slate-50 dark:bg-white/10 text-slate-800 dark:text-slate-100' : 'border-slate-200 dark:border-white/10 bg-white dark:bg-white/5 text-slate-500 dark:text-slate-400 hover:border-slate-300 dark:hover:border-white/20'}`}>
                                                                {emp.nickname} ({emp.name})
                                                            </button>
                                                        );
                                                    })}
                                                </div>
                                            </div>

                                            {/* OT Rate */}
                                            <div>
                                                <label className="text-sm font-bold text-slate-700 dark:text-slate-200 mb-1.5 block">ค่า OT (บาท/คน/ชม.)</label>
                                                <input type="number" placeholder="" value={otRate} onChange={e => setOtRate(e.target.value)}
                                                    className="w-full px-4 py-3.5 border border-slate-300 dark:border-white/15 rounded-xl text-base text-slate-800 dark:text-slate-100 bg-white dark:bg-white/5 focus:border-slate-500 dark:focus:border-slate-400 focus:outline-none transition-colors" />
                                            </div>

                                            {/* OT Hours */}
                                            <div>
                                                <label className="text-sm font-bold text-slate-700 dark:text-slate-200 mb-1.5 block">จำนวนชั่วโมง OT</label>
                                                <input type="number" placeholder="เช่น 2.5" value={otHours} onChange={e => setOtHours(e.target.value)}
                                                    className="w-full px-4 py-3 border border-slate-300 dark:border-white/15 rounded-xl text-base text-slate-800 dark:text-slate-100 bg-white dark:bg-white/5 focus:border-slate-500 dark:focus:border-slate-400 focus:outline-none transition-colors" />
                                            </div>

                                            {/* OT Description */}
                                            <div>
                                                <label className="text-sm font-bold text-slate-700 dark:text-slate-200 mb-1.5 block">รายละเอียดงาน OT</label>
                                                <input type="text" placeholder="ทำอะไร..." value={otDesc} onChange={e => setOtDesc(e.target.value)}
                                                    className="w-full px-4 py-3 border border-slate-300 dark:border-white/15 rounded-xl text-base text-slate-800 dark:text-slate-100 bg-white dark:bg-white/5 focus:border-slate-500 dark:focus:border-slate-400 focus:outline-none transition-colors" />
                                            </div>

                                            {/* OT Summary */}
                                            {selectedEmps.length > 0 && Number(otRate) > 0 && Number(otHours) > 0 && (
                                                <div className="bg-amber-50 dark:bg-amber-500/10 p-3 rounded-xl border border-amber-200 dark:border-amber-500/25 text-center">
                                                    <span className="text-sm text-amber-800 dark:text-amber-200">รวม: <span className="font-bold text-lg">{(Number(otRate) * Number(otHours) * selectedEmps.length).toLocaleString()}</span> บาท</span>
                                                    <span className="text-xs text-amber-600 dark:text-amber-300/90 block">({selectedEmps.length} คน × {otRate} บาท × {otHours} ชม.)</span>
                                                </div>
                                            )}

                                            {/* Save */}
                                            <button onClick={() => {
                                                if (selectedEmps.length === 0) return alert('กรุณาเลือกพนักงาน');
                                                if (!otRate) return alert('กรุณาระบุค่า OT');
                                                const existingLaborIds = dayTransactions
                                                    .filter(t => t.category === 'Labor' && (t.laborStatus === 'Work' || t.laborStatus === 'OT'))
                                                    .flatMap(t => t.employeeIds || []);
                                                const alreadyRecorded = selectedEmps.filter(id => existingLaborIds.includes(id));
                                                if (alreadyRecorded.length > 0) {
                                                    const names = alreadyRecorded.map(id => employees.find(e => e.id === id)?.nickname || id).join(', ');
                                                    return alert(`ไม่สามารถบันทึกซ้ำได้ — พนักงานต่อไปนี้มีรายการค่าแรง/OT วันที่นี้แล้ว: ${names}\nกรุณาตรวจสอบที่เมนู "ค่าแรง/ลา" หรือลบรายการเดิมก่อน`);
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
                                        <div className="mt-auto pt-3 flex justify-between">
                                            <Button variant="secondary" onClick={prevStep}>ย้อนกลับ</Button>
                                            <Button onClick={nextStep}>ถัดไป <ChevronRight size={18} /></Button>
                                        </div>
                                    </div>
                                )}

                                {/* === WORK MODE: Canvas layout === */}
                                {laborStatus === 'Work' && (
                                    <>
                                        {/* Employee Pool - Draggable chips */}
                                        <div className="mb-3">
                                            <div className="flex justify-between items-center mb-2">
                                                <span className="text-sm font-bold text-slate-500">👥 พนักงาน — คลิกเลือกแล้วกดย้ายใส่กล่องงาน</span>
                                                <input placeholder="ค้นหา..." value={laborSearch} onChange={e => setLaborSearch(e.target.value)} className="text-sm border rounded-lg px-3 py-1.5 w-32" />
                                            </div>
                                            <div className="flex flex-wrap gap-2 bg-slate-50 p-3 rounded-xl border max-h-[120px] overflow-y-auto">
                                                {employees.filter(e => e.name.includes(laborSearch) || e.nickname.includes(laborSearch)).map(emp => {
                                                    const isAssigned = Object.values(workAssignments).some(ids => ids.includes(emp.id));
                                                    const isSelected = selectedEmps.includes(emp.id);
                                                    const saved = dayTransactions.find(t => t.category === 'Labor' && t.employeeIds?.includes(emp.id));
                                                    const leaveRecord = transactions.find(t => t.category === 'Labor' && (t.laborStatus === 'Leave' || t.laborStatus === 'Sick' || t.laborStatus === 'Personal') && t.employeeIds?.includes(emp.id) && t.date <= date && (t.leaveDays ? new Date(new Date(t.date).getTime() + (t.leaveDays - 1) * 86400000).toISOString().split('T')[0] >= date : t.date === date));
                                                    const isAbsent = !isAssigned && !saved && !leaveRecord;
                                                    return (
                                                        <div key={emp.id}
                                                            draggable onDragStart={() => setDragEmployee(emp.id)} onDragEnd={() => setDragEmployee(null)}
                                                            onClick={() => setSelectedEmps(prev => prev.includes(emp.id) ? prev.filter(id => id !== emp.id) : [...prev, emp.id])}
                                                            title={leaveRecord ? `ลา: ${new Date(leaveRecord.date).toLocaleDateString('th-TH')}${leaveRecord.leaveDays ? ` (${leaveRecord.leaveDays} วัน)` : ''} - ${leaveRecord.leaveReason || leaveRecord.laborStatus}` : isAbsent && saved === undefined ? '' : ''}
                                                            className={`px-3 py-2 rounded-xl text-sm font-semibold cursor-grab active:cursor-grabbing select-none transition-all
                                                        ${leaveRecord ? 'bg-yellow-100 text-yellow-700 border-2 border-yellow-400 ring-1 ring-yellow-200' :
                                                                    isAssigned ? 'bg-emerald-100 text-emerald-600 border border-emerald-300 opacity-50' :
                                                                        isSelected ? 'bg-indigo-600 text-white shadow-md scale-105' :
                                                                            saved ? 'bg-emerald-50 text-emerald-700 border border-emerald-200' :
                                                                                'bg-white text-slate-600 border border-slate-200 hover:border-indigo-300 hover:shadow-sm'}`}
                                                        >
                                                            {emp.nickname}{leaveRecord ? ' 🏖️ลา' : saved && !isAssigned ? ' ✅' : ''}
                                                        </div>
                                                    );
                                                })}
                                            </div>
                                            {selectedEmps.length > 0 && <p className="text-xs text-indigo-600 mt-1.5 font-medium">เลือก {selectedEmps.length} คน — กดปุ่ม "ย้าย" ในกล่องงานด้านล่าง</p>}
                                        </div>

                                        {/* Work Category Canvas Boxes */}
                                        <div className="flex-1 overflow-y-auto mb-3">
                                            <span className="text-sm font-bold text-slate-500 mb-2 block">📋 ประเภทงาน (ลากหรือกดย้ายพนักงานใส่)</span>
                                            <div className="grid grid-cols-2 gap-3">
                                                {[...DEFAULT_WORK_CATEGORIES, ...customCategories.map(c => ({ ...c, color: 'bg-purple-500', bgLight: 'bg-purple-50 border-purple-200' }))].map(cat => {
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
                                                            className={`p-3 rounded-xl border-2 border-dashed min-h-[80px] transition-all ${cat.bgLight} ${dragEmployee ? 'border-indigo-400 bg-indigo-50/30' : ''}`}
                                                        >
                                                            <div className="flex justify-between items-center mb-1.5">
                                                                <span className={`text-xs font-bold text-white px-2 py-1 rounded-full ${cat.color}`}>{cat.label}</span>
                                                                <div className="flex items-center gap-2">
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
                                                                        <span key={eid} className="px-2 py-1 bg-white rounded-lg text-xs font-semibold border flex items-center gap-1">
                                                                            {emp.nickname}
                                                                            <button type="button" onClick={(ev) => { ev.stopPropagation(); setHalfDayEmpIds(prev => { const n = new Set(prev); if (n.has(eid)) n.delete(eid); else n.add(eid); return n; }); }} className={`min-w-[1.5rem] px-1 py-0.5 rounded text-[10px] font-bold ${isHalf ? 'bg-amber-100 text-amber-700 border border-amber-300' : 'bg-slate-100 text-slate-500 border border-slate-200 hover:bg-amber-50 hover:text-amber-600'}`} title={isHalf ? 'กดเพื่อเปลี่ยนเป็นเต็มวัน' : 'กดเพื่อกำหนดมาครึ่งวัน'}>½</button>
                                                                            <button type="button" onClick={() => setWorkAssignments(prev => ({ ...prev, [cat.id]: prev[cat.id].filter(id => id !== eid) }))} className="text-red-400 hover:text-red-600 ml-0.5 text-base leading-none">×</button>
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
                                                                }} className="mt-1.5 w-full py-1.5 text-xs bg-indigo-100 text-indigo-700 rounded-lg hover:bg-indigo-200 font-bold">
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
                                                    setCustomCategories(prev => {
                                                        const exists = prev.some(c => c.label.trim() === label);
                                                        if (exists) return prev;
                                                        return [...prev, { id: `c_${Date.now()}`, label }];
                                                    });
                                                    setNewCategoryName('');
                                                }} className="px-4 py-2 bg-purple-500 text-white text-sm rounded-xl hover:bg-purple-600 font-bold">+ เพิ่ม</button>
                                            </div>
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
                                                const allEmps = [...new Set([...allAssigned, ...selectedEmps])];
                                                if (allEmps.length === 0) return alert('เลือกหรือลากพนักงานใส่กล่องงานก่อนครับ');
                                                const existingLaborIds = dayTransactions
                                                    .filter(t => t.category === 'Labor' && (t.laborStatus === 'Work' || t.laborStatus === 'OT'))
                                                    .flatMap(t => t.employeeIds || []);
                                                const alreadyRecorded = allEmps.filter(id => existingLaborIds.includes(id));
                                                if (alreadyRecorded.length > 0) {
                                                    const names = alreadyRecorded.map(id => employees.find(e => e.id === id)?.nickname || id).join(', ');
                                                    return alert(`ไม่สามารถบันทึกซ้ำได้ — พนักงานต่อไปนี้บันทึกค่าแรงวันที่นี้แล้ว: ${names}\nกรุณาตรวจสอบที่เมนู "ค่าแรง/ลา" หรือลบรายการเดิมก่อน`);
                                                }
                                                const base = { id: Date.now().toString(), date, employeeIds: allEmps };
                                                const allCats = [...DEFAULT_WORK_CATEGORIES, ...customCategories.map(c => ({ ...c, color: '', bgLight: '' }))];
                                                const desc = Object.entries(workAssignments).filter(([, ids]) => ids.length > 0).map(([catId, ids]) => {
                                                    const cat = allCats.find(c => c.id === catId); const names = ids.map(id => employees.find(e => e.id === id)?.nickname || '').join(',');
                                                    return `${cat?.label || catId}: ${names}`;
                                                }).join(' | ');
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
                                                    description: `ค่าแรง (${allEmps.length} คน) ${workLabel}${desc ? ` [${desc}]` : ''}`,
                                                    amount: total,
                                                    workAssignments: { ...workAssignments },
                                                    customWorkCategories: [...customCategories],
                                                    drumsWashedAtHome: drumsHome
                                                };
                                                onSaveTransaction(t as any); setSelectedEmps([]); setWorkAssignments({}); setHalfDayEmpIds(new Set()); if (drumsHome !== undefined) setDrumsWashedAtHome('');
                                            }} className="w-full bg-emerald-600 hover:bg-emerald-700 py-3 text-base">
                                                <CheckCircle2 size={18} className="mr-2" /> บันทึกค่าแรง ({Object.values(workAssignments).flat().length + selectedEmps.length} คน)
                                            </Button>
                                            <div className="flex justify-between">
                                                <Button variant="secondary" onClick={prevStep}>ย้อนกลับ</Button>
                                                <Button onClick={nextStep}>ถัดไป <ChevronRight size={18} /></Button>
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
                                                        onClick={() => {
                                                            if (!window.confirm('ลบรายการรถนี้?')) return;
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
                                    <div className="grid grid-cols-2 gap-4">
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
                                    <div className="grid grid-cols-2 gap-4">
                                        <Input label="ค่าจ้างรถ (บาท)" type="number" value={vehMachineWage} onChange={(e: any) => setVehMachineWage(e.target.value)} />
                                        <Input label="เบี้ยเลี้ยงคนขับ (ใช้ค่าแรงในวันนั้น)" type="number" value={vehWage} onChange={(e: any) => setVehWage(e.target.value)} />
                                    </div>
                                    <div className="flex flex-col gap-1">
                                        <label className="text-sm font-medium text-slate-700 dark:text-slate-200">รายละเอียดงาน</label>
                                        <textarea className="border border-slate-200 dark:border-white/15 rounded-xl p-2 text-sm bg-white dark:bg-white/5 text-slate-800 dark:text-slate-100 placeholder:text-slate-400" rows={2} value={vehDetails} onChange={e => setVehDetails(e.target.value)} placeholder="ขนดิน, ปรับพื้นที่..." />
                                    </div>
                                    <Button onClick={() => {
                                        if (!vehCar || !vehDriver) return alert('ข้อมูลไม่ครบ');
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
                                    }} className="w-full bg-amber-500 hover:bg-amber-600">{editingVehicleTxId ? 'อัปเดตรายการรถ' : 'บันทึกรายการรถ'}</Button>
                                </div>
                                <div className="mt-auto flex justify-between">
                                    <Button variant="secondary" onClick={prevStep}>ย้อนกลับ</Button>
                                    <Button onClick={nextStep}>ถัดไป <ChevronRight size={18} /></Button>
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
                                                const fallback = Number(cubicPerTrip) || 3;
                                                return activeCars.reduce((sum, entry, idx) => {
                                                    const carTrips = tripsPerCar + (idx < remainder ? 1 : 0);
                                                    const carCubicPerTrip = Number(entry.cubicPerTrip) || detectDefaultCubicPerTrip(entry.vehicle, fallback);
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
                                    <div className="grid grid-cols-3 gap-3">
                                        <div>
                                            <label className="text-xs font-medium text-amber-700 dark:text-amber-300 mb-1 block">☀️ ช่วงเช้า (เที่ยว)</label>
                                            <input type="number" placeholder="0" value={tripMorning} onChange={e => setTripMorning(e.target.value)}
                                                className="w-full px-3 py-2.5 border-2 border-amber-200 dark:border-amber-500/35 rounded-xl text-center text-lg font-bold text-amber-800 dark:text-amber-200 bg-white dark:bg-white/5 focus:border-amber-400 focus:outline-none transition-colors" />
                                        </div>
                                        <div>
                                            <label className="text-xs font-medium text-blue-700 dark:text-blue-300 mb-1 block">🌙 ช่วงบ่าย (เที่ยว)</label>
                                            <input type="number" placeholder="0" value={tripAfternoon} onChange={e => setTripAfternoon(e.target.value)}
                                                className="w-full px-3 py-2.5 border-2 border-blue-200 dark:border-blue-500/35 rounded-xl text-center text-lg font-bold text-blue-800 dark:text-blue-200 bg-white dark:bg-white/5 focus:border-blue-400 focus:outline-none transition-colors" />
                                        </div>
                                        <div>
                                            <label className="text-xs font-medium text-emerald-700 dark:text-emerald-300 mb-1 block">📦 คิว/เที่ยว</label>
                                            <input type="number" placeholder="3" value={cubicPerTrip} onChange={e => setCubicPerTrip(e.target.value)}
                                                className="w-full px-3 py-2.5 border-2 border-emerald-200 dark:border-emerald-500/35 rounded-xl text-center text-lg font-bold text-emerald-800 dark:text-emerald-200 bg-white dark:bg-white/5 focus:border-emerald-400 focus:outline-none transition-colors" />
                                        </div>
                                    </div>
                                    {totalTrips > 0 && (() => {
                                        const validCount = tripEntries.filter(e => e.vehicle).length || 1;
                                        const tripsPerCar = Math.floor(totalTrips / validCount);
                                        const remainder = totalTrips % validCount;
                                        // Calculate total cubic from each car's own cubic-per-trip setting
                                        const cubicDefault = Number(cubicPerTrip) || 3;
                                        let displayTotalCubic = 0;
                                        tripEntries.filter(e => e.vehicle).forEach((entry, idx) => {
                                            const carTrips = tripsPerCar + (idx < remainder ? 1 : 0);
                                            const carCubicPerTrip = Number(entry.cubicPerTrip) || detectDefaultCubicPerTrip(entry.vehicle, cubicDefault);
                                            displayTotalCubic += carTrips * carCubicPerTrip;
                                        });
                                        if (validCount <= 1) displayTotalCubic = totalTrips * cubicDefault;
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
                                            <div className="grid grid-cols-2 gap-3 mb-2">
                                                <Select label="รถ" value={entry.vehicle} onChange={(e: any) => {
                                                    const nextVehicle = e.target.value;
                                                    setTripEntries(prev => prev.map(item => {
                                                        if (item.id !== entry.id) return item;
                                                        const fallback = Number(cubicPerTrip) || 3;
                                                        const autoCubic = detectDefaultCubicPerTrip(nextVehicle, fallback);
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
                                            <div className="grid grid-cols-2 gap-3 mb-2">
                                                <Input
                                                    label="คิว/เที่ยว (คันนี้)"
                                                    type="number"
                                                    value={entry.cubicPerTrip}
                                                    onChange={(e: any) => updateTripCard(entry.id, 'cubicPerTrip', e.target.value)}
                                                    placeholder={String(detectDefaultCubicPerTrip(entry.vehicle, Number(cubicPerTrip) || 3))}
                                                />
                                                <div className="rounded-xl border border-slate-200 bg-slate-50 p-2.5 text-xs text-slate-500 flex items-center">
                                                    ค่าแนะนำ: 6 ล้อ = 3, 10 ล้อ = 6 (แก้เองได้รายวัน)
                                                </div>
                                            </div>
                                            <Input label="รายละเอียดงาน" value={entry.work} onChange={(e: any) => updateTripCard(entry.id, 'work', e.target.value)} placeholder="ขนดิน, ขนทราย..." />
                                        </div>
                                    ))}

                                    <button onClick={addTripCard} className="w-full py-4 border-2 border-dashed border-slate-200 hover:border-blue-400 rounded-xl text-slate-400 hover:text-blue-500 flex items-center justify-center gap-2 transition-all hover:bg-blue-50/50">
                                        <Plus size={20} /> เพิ่มรถอีกคัน
                                    </button>
                                </div>

                                {/* Save all + navigation */}
                                <div className="pt-4 border-t space-y-3">
                                    <Button onClick={() => {
                                        const valid = tripEntries.filter(e => e.vehicle);
                                        if (valid.length === 0) return alert('กรุณาเลือกรถอย่างน้อย 1 คัน');
                                        const tripsPerCar = Math.floor(totalTrips / valid.length);
                                        const remainder = totalTrips % valid.length;
                                        const cubicDefault = Number(cubicPerTrip) || 3;
                                        valid.forEach((entry, idx) => {
                                            const driverName = employees.find(e => e.id === entry.driver)?.nickname || '';
                                            const carTrips = tripsPerCar + (idx < remainder ? 1 : 0);
                                            const carCubicPerTrip = Number(entry.cubicPerTrip) || detectDefaultCubicPerTrip(entry.vehicle, cubicDefault);
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
                                    <div className="flex justify-between">
                                        <Button variant="secondary" onClick={prevStep}>ย้อนกลับ</Button>
                                        <Button onClick={nextStep}>ถัดไป <ChevronRight size={18} /></Button>
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
                                    const drumsDisplay = totalDrumsDay > 0;
                                    return (
                                        <>
                                            {sandTxToday.length > 0 && (
                                                <>
                                                    {drumsDisplay && (
                                                        <div className="mb-3 p-3 rounded-xl bg-amber-50 border border-amber-200 flex items-center gap-3">
                                                            <span className="text-sm font-bold text-amber-800">🪣 จำนวนถังที่ได้วันนี้</span>
                                                            <span className="text-xl font-black text-amber-700">{totalDrumsDay} ถัง</span>
                                                            <span className="text-[10px] text-amber-600">(รวมทั้งวัน ช่วงเช้า+บ่าย)</span>
                                                        </div>
                                                    )}
                                                    <div className="mb-3 flex gap-2 overflow-x-auto pb-2">
                                                        {sandTxToday.map(t => {
                                                            const sandTotal = ((t as any).sandMorning || 0) + ((t as any).sandAfternoon || 0);
                                                            const drums = (t as any).drumsObtained ?? 0;
                                                            const isDrumsOnly = sandTotal === 0 && drums > 0;
                                                            return (
                                                            <div key={t.id} className="min-w-[180px] p-2.5 bg-cyan-50 border border-cyan-200 rounded-xl text-xs relative">
                                                                <div className="font-bold text-cyan-800">🌊 {t.description}</div>
                                                                {isDrumsOnly ? (
                                                                    <div className="text-teal-700 font-semibold">🪣 {drums} ถัง</div>
                                                                ) : (
                                                                    <div className="text-cyan-700 font-semibold">เช้า {(t as any).sandMorning || 0} + บ่าย {(t as any).sandAfternoon || 0} = {sandTotal} คิว</div>
                                                                )}
                                                                {onDeleteTransaction && <button onClick={() => onDeleteTransaction(t.id)} className="absolute top-1.5 right-1.5 p-0.5 text-cyan-300 hover:text-red-500"><Trash2 size={10} /></button>}
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
                                                <input type="number" placeholder="0" value={sand1Morning} onChange={e => setSand1Morning(e.target.value)}
                                                    className="w-full px-3 py-2 border-2 border-amber-200 rounded-xl text-center text-lg font-bold text-amber-800 bg-white focus:border-amber-400 focus:outline-none" />
                                            </div>
                                            <div>
                                                <label className="text-xs font-medium text-blue-700 mb-1 block">🌙 บ่าย (คิว)</label>
                                                <input type="number" placeholder="0" value={sand1Afternoon} onChange={e => setSand1Afternoon(e.target.value)}
                                                    className="w-full px-3 py-2 border-2 border-blue-200 rounded-xl text-center text-lg font-bold text-blue-800 bg-white focus:border-blue-400 focus:outline-none" />
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
                                                    return emp ? <span key={eid} className="px-2.5 py-1 rounded-lg text-xs font-medium bg-blue-500 text-white shadow-sm">{emp.nickname}</span> : null;
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
                                                <input type="number" placeholder="0" value={sand2Morning} onChange={e => setSand2Morning(e.target.value)}
                                                    className="w-full px-3 py-2 border-2 border-amber-200 rounded-xl text-center text-lg font-bold text-amber-800 bg-white focus:border-amber-400 focus:outline-none" />
                                            </div>
                                            <div>
                                                <label className="text-xs font-medium text-blue-700 mb-1 block">🌙 บ่าย (คิว)</label>
                                                <input type="number" placeholder="0" value={sand2Afternoon} onChange={e => setSand2Afternoon(e.target.value)}
                                                    className="w-full px-3 py-2 border-2 border-blue-200 rounded-xl text-center text-lg font-bold text-blue-800 bg-white focus:border-blue-400 focus:outline-none" />
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
                                                    return emp ? <span key={eid} className="px-2.5 py-1 rounded-lg text-xs font-medium bg-cyan-500 text-white shadow-sm">{emp.nickname}</span> : null;
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
                                    <div className="rounded-2xl border border-slate-200 dark:border-white/10 bg-gradient-to-r from-slate-50 to-slate-100/80 dark:from-white/[0.04] dark:to-white/[0.02] p-4 shadow-sm">
                                        <label className="text-sm font-bold text-slate-700 dark:text-slate-200 mb-2 flex items-center gap-2">
                                            <span className="w-7 h-7 rounded-lg bg-amber-500/20 flex items-center justify-center text-amber-700 dark:text-amber-300">🪣</span>
                                            จำนวนถังที่ได้วันนี้
                                        </label>
                                        <div className="flex items-center gap-2">
                                            <input type="number" min="0" placeholder="0" value={sandDrumsObtained} onChange={e => setSandDrumsObtained(e.target.value)}
                                                className="w-24 px-4 py-2.5 border-2 border-slate-200 dark:border-white/15 rounded-xl text-center text-lg font-bold text-slate-800 dark:text-slate-100 bg-white dark:bg-white/5 focus:border-cyan-500 focus:ring-2 focus:ring-cyan-500/20 outline-none transition-all" />
                                            <span className="text-slate-500 dark:text-slate-400 text-sm font-medium">ถัง</span>
                                        </div>
                                    </div>
                                </div>

                                <div className="pt-3 border-t space-y-2">
                                    <Button onClick={() => {
                                        const drumsToday = Number(sandDrumsObtained) || 0;
                                        if (sandGrandTotal === 0 && drumsToday === 0) return alert('กรุณาใส่จำนวนทรายที่ล้างได้หรือจำนวนถังที่ได้วันนี้');
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
                                                ...timePayload
                                            } as Transaction);
                                        }
                                        if (sand2Total > 0) {
                                            onSaveTransaction({
                                                id: Date.now().toString() + '_s2', date, type: 'Expense', category: 'DailyLog', subCategory: 'Sand',
                                                description: `ล้างทราย เครื่องร่อน 2 (ใหม่)${opNames2 ? ` [${opNames2}]` : ''}`, amount: 0,
                                                sandMorning: Number(sand2Morning) || 0, sandAfternoon: Number(sand2Afternoon) || 0,
                                                sandOperators: sand2Operators, sandMachineType: 'New', drumsObtained: drumsToday,
                                                ...timePayload
                                            } as Transaction);
                                        }
                                        if (sandGrandTotal === 0 && drumsToday > 0) {
                                            onSaveTransaction({
                                                id: Date.now().toString() + '_drums', date, type: 'Expense', category: 'DailyLog', subCategory: 'Sand',
                                                description: 'จำนวนถังที่ได้วันนี้', amount: 0, drumsObtained: drumsToday,
                                                ...timePayload
                                            } as Transaction);
                                        }
                                        setSand1Morning(''); setSand1Afternoon(''); setSand2Morning(''); setSand2Afternoon('');
                                        setSand1Operators([]); setSand2Operators([]); setSandDrumsObtained('');
                                        setSandMorningStart(''); setSandAfternoonStart(''); setSandEveningEnd('');
                                    }} className="w-full bg-cyan-500 hover:bg-cyan-600 py-2.5">
                                        <Droplets size={16} className="mr-1" /> บันทึกข้อมูลล้างทราย ({sandGrandTotal} คิว)
                                    </Button>
                                    <div className="flex justify-between">
                                        <Button variant="secondary" onClick={prevStep}>ย้อนกลับ</Button>
                                        <Button onClick={nextStep}>ถัดไป <ChevronRight size={18} /></Button>
                                    </div>
                                </div>
                            </div>
                        )}

                        {/* Step 5: Fuel */}
                        {step === 5 && (
                            <div className="h-full flex flex-col animate-slide-up">
                                <h3 className="font-bold text-xl text-slate-800 dark:text-slate-100 mb-5">Fuel Entry</h3>

                                {/* Saved fuel entries */}
                                {dayTransactions.filter(t => t.category === 'Fuel').length > 0 && (
                                    <div className="mb-4 space-y-2">
                                        <p className="text-sm font-semibold text-slate-500 dark:text-slate-400">รายการซื้อน้ำมันวันนี้ ({dayTransactions.filter(t => t.category === 'Fuel').length} รอบ)</p>
                                        <div className="flex gap-2 overflow-x-auto pb-2">
                                            {dayTransactions.filter(t => t.category === 'Fuel').map(t => (
                                                <div key={t.id} className="min-w-[200px] p-3 bg-red-50 border border-red-100 rounded-xl text-xs relative">
                                                    <div className="font-bold text-red-800">⛽ {(t as any).fuelType === 'Diesel' ? 'ดีเซล' : 'เบนซิน'}</div>
                                                    <div className="text-red-700 mt-1 font-semibold">ค่าน้ำมันที่ซื้อ <span className="font-bold">{t.amount?.toLocaleString()} บาท</span></div>
                                                    {t.workDetails && <div className="text-red-600/70 mt-1">{t.workDetails}</div>}
                                                    {onDeleteTransaction && <button onClick={() => onDeleteTransaction(t.id)} className="absolute top-2 right-2 p-1 text-red-300 hover:text-red-600"><Trash2 size={12} /></button>}
                                                </div>
                                            ))}
                                        </div>
                                        {(() => {
                                            const fuelTx = dayTransactions.filter(t => t.category === 'Fuel');
                                            const totalBaht = fuelTx.reduce((s, t) => s + (t.amount || 0), 0);
                                            return <div className="bg-red-100/50 p-2 rounded-lg text-sm text-center text-red-800 font-medium">รวมวันนี้: <span className="font-bold">{totalBaht.toLocaleString()}</span> บาท</div>;
                                        })()}
                                    </div>
                                )}

                                {/* Clean fuel entry form */}
                                <div className="flex-1 bg-white dark:bg-white/[0.03] p-6 rounded-2xl border border-slate-200 dark:border-white/10 shadow-sm space-y-5">
                                    {/* Date */}
                                    <div>
                                        <label className="text-sm font-medium text-slate-600 dark:text-slate-300 mb-1.5 block">วันที่</label>
                                        <input type="date" value={date} readOnly
                                            className="w-full px-4 py-3 border border-slate-300 dark:border-white/15 rounded-xl text-base text-slate-800 dark:text-slate-100 bg-slate-50 dark:bg-white/5" />
                                    </div>

                                    {/* Fuel Type - Radio style */}
                                    <div className="grid grid-cols-2 gap-3">
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
                                    <div className="grid grid-cols-2 gap-4">
                                        <div>
                                            <label className="text-sm font-medium text-slate-600 dark:text-slate-300 mb-1.5 block">จำนวนลิตร</label>
                                            <input type="number" placeholder="" value={fuelLiters} onChange={e => setFuelLiters(e.target.value)}
                                                className="w-full px-4 py-3 border border-slate-300 dark:border-white/15 rounded-xl text-base text-slate-800 dark:text-slate-100 bg-white dark:bg-white/5 focus:border-slate-500 dark:focus:border-slate-400 focus:outline-none transition-colors" />
                                        </div>
                                        <div>
                                            <label className="text-sm font-medium text-slate-600 dark:text-slate-300 mb-1.5 block">หน่วย</label>
                                            <select value={fuelUnit} onChange={e => setFuelUnit(e.target.value)}
                                                className="w-full px-4 py-3 border border-slate-300 dark:border-white/15 rounded-xl text-base text-slate-800 dark:text-slate-100 bg-white dark:bg-white/5 focus:border-slate-500 dark:focus:border-slate-400 focus:outline-none transition-colors appearance-none">
                                                <option value="ลิตร">ลิตร</option>
                                                <option value="แกลลอน">แกลลอน</option>
                                            </select>
                                        </div>
                                    </div>

                                    {/* Price */}
                                    <div>
                                        <label className="text-sm font-medium text-slate-600 dark:text-slate-300 mb-1.5 block">ราคาซื้อน้ำมัน (บาท)</label>
                                        <input type="number" placeholder="" value={fuelAmount} onChange={e => setFuelAmount(e.target.value)}
                                            className="w-full px-4 py-4 border border-slate-300 dark:border-white/15 rounded-xl text-lg text-slate-800 dark:text-slate-100 bg-white dark:bg-white/5 focus:border-slate-500 dark:focus:border-slate-400 focus:outline-none transition-colors" />
                                    </div>

                                    {/* Details (optional) */}
                                    <div>
                                        <label className="text-sm font-medium text-slate-600 dark:text-slate-300 mb-1.5 block">รายละเอียดเพิ่มเติม <span className="text-slate-400 dark:text-slate-500 font-normal">(ไม่บังคับ)</span></label>
                                        <input type="text" placeholder="เช่น ซื้อที่ปั๊มหน้าแคมป์" value={fuelDetails} onChange={e => setFuelDetails(e.target.value)}
                                            className="w-full px-4 py-3 border border-slate-300 dark:border-white/15 rounded-xl text-base text-slate-800 dark:text-slate-100 bg-white dark:bg-white/5 focus:border-slate-500 dark:focus:border-slate-400 focus:outline-none transition-colors" />
                                    </div>

                                    {/* Save button */}
                                    <button onClick={() => {
                                        if (!fuelAmount) return alert('กรุณาระบุราคาซื้อน้ำมัน');
                                        const unitLabel = fuelUnit === 'แกลลอน' ? 'gallon' : 'L';
                                        onSaveTransaction({
                                            id: Date.now().toString(), date, type: 'Expense', category: 'Fuel',
                                            description: `ซื้อน้ำมัน ${fuelType === 'Diesel' ? 'ดีเซล' : 'เบนซิน'}: ${fuelLiters || 0} ${fuelUnit} ${fuelAmount} บาท${fuelDetails ? ` - ${fuelDetails}` : ''}`,
                                            amount: Number(fuelAmount),
                                            quantity: Number(fuelLiters), unit: unitLabel, fuelType,
                                            workDetails: fuelDetails
                                        } as Transaction);
                                        setFuelAmount(''); setFuelLiters(''); setFuelDetails('');
                                    }} className="w-full py-3.5 bg-slate-800 hover:bg-slate-900 text-white text-base font-bold rounded-xl transition-colors">
                                        บันทึก
                                    </button>
                                </div>

                                <div className="mt-auto pt-3 flex justify-between">
                                    <Button variant="secondary" onClick={prevStep}>ย้อนกลับ</Button>
                                    <Button onClick={nextStep}>ถัดไป <ChevronRight size={18} /></Button>
                                </div>
                            </div>
                        )}

                        {/* Step 6: Important Events */}
                        {step === 6 && (
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
                                    </div>

                                    {/* Quick templates */}
                                    <div>
                                        <p className="text-[10px] text-slate-400 mb-1">🏷️ เทมเพลตด่วน:</p>
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

                                <div className="pt-3 border-t space-y-2">
                                    <Button onClick={() => {
                                        if (!eventDesc.trim()) return alert('กรุณาระบุรายละเอียดเหตุการณ์');
                                        onSaveTransaction({
                                            id: Date.now().toString(), date, type: 'Expense', category: 'DailyLog', subCategory: 'Event',
                                            description: eventDesc.trim(), amount: 0,
                                            eventType, eventPriority
                                        } as Transaction);
                                        setEventDesc(''); setEventType('info'); setEventPriority('normal');
                                    }} className="w-full bg-orange-500 hover:bg-orange-600 py-2.5">
                                        <AlertTriangle size={16} className="mr-1" /> บันทึกเหตุการณ์
                                    </Button>
                                    <div className="flex justify-between">
                                        <Button variant="secondary" onClick={prevStep}>ย้อนกลับ</Button>
                                        <Button onClick={nextStep}>ถัดไป <ChevronRight size={18} /></Button>
                                    </div>
                                </div>
                            </div>
                        )}

                        {/* Step 7: Summary */}
                        {step === 7 && (
                            <div className="h-full flex flex-col animate-slide-up text-center">
                                <div className={`flex flex-col items-center justify-center ${mobileShell ? 'mb-4' : 'mb-6'}`}>
                                    <FileText size={mobileShell ? 40 : 48} className="mb-3 text-emerald-400" />
                                    <h3 className={`font-bold text-slate-800 dark:text-slate-100 ${mobileShell ? 'text-xl' : 'text-2xl'} mb-1`}>เรียบร้อย</h3>
                                    {!mobileShell && (
                                        <p className="text-slate-500">สรุปข้อมูลที่คุณบันทึกในวันนี้ ({new Date(date).toLocaleDateString('th-TH')})</p>
                                    )}
                                </div>

                                <div className={`grid w-full grid-cols-3 gap-2 sm:grid-cols-6 sm:gap-3 ${mobileShell ? 'mb-4' : 'mb-6'}`}>
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
                                    const hasEvent = dayTransactions.some(t => t.category === 'DailyLog' && t.subCategory === 'Event');
                                    const missing: string[] = [];
                                    if (!hasLabor) missing.push('ค่าแรง');
                                    if (!hasVehicle) missing.push('การใช้รถ');
                                    if (!hasTrips) missing.push('เที่ยวรถ');
                                    if (!hasSand) missing.push('ล้างทราย');
                                    if (!hasFuel) missing.push('น้ำมัน');
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
                                                            {t.category === 'Fuel' && <span className="mr-3">ค่าน้ำมันที่ซื้อ: ฿{t.amount?.toLocaleString()} บาท</span>}
                                                            {t.amount > 0 && t.category !== 'Fuel' && <span className="mr-3">ยอดเงิน: ฿{t.amount.toLocaleString()}</span>}
                                                            {((t as any).perCarTrips || (t as any).tripCount) && <span className="mr-3">จำนวน: {(t as any).perCarTrips || (t as any).tripCount} เที่ยว</span>}
                                                            {((t as any).perCarCubic || (t as any).totalCubic) && <span className="mr-3">ปริมาณ: {(t as any).perCarCubic || (t as any).totalCubic} คิว</span>}
                                                            {(t as any).quantity && t.category !== 'Fuel' && <span className="mr-3">ปริมาณ: {(t as any).quantity} {(t as any).unit === 'gallon' ? 'แกลลอน' : 'ลิตร'}</span>}
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

                                <Button onClick={() => setStep(0)} className={`mx-auto mt-auto w-full px-8 sm:w-auto ${mobileShell ? 'min-h-[52px] text-base font-bold' : ''}`}>
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
                    <div className="rounded-2xl border border-slate-200/80 bg-white/70 p-3 shadow-sm backdrop-blur-sm dark:border-white/10 dark:bg-[#0f111a]/50">
                        <p className="text-[10px] font-bold uppercase tracking-wider text-slate-400 dark:text-slate-500 mb-2.5 px-0.5">สรุปวันนี้</p>
                        <div className="grid grid-cols-2 xl:grid-cols-1 gap-2.5 sm:gap-3 [contain:layout]">
                            {[
                                {
                                    label: 'คนงาน',
                                    unit: 'คน',
                                    display: String(atAGlanceStats.laborCount),
                                    Icon: Users,
                                    card: 'bg-emerald-50/90 dark:bg-emerald-500/10 border-emerald-100/90 dark:border-emerald-500/25',
                                    iconWrap: 'bg-emerald-500/15 dark:bg-emerald-500/25 text-emerald-600 dark:text-emerald-400',
                                    labelClass: 'text-emerald-800/90 dark:text-emerald-200',
                                    valueClass: 'text-emerald-700 dark:text-emerald-300',
                                },
                                {
                                    label: 'ทรายล้าง',
                                    unit: 'คิว',
                                    display: atAGlanceStats.sandCubic.toLocaleString(),
                                    Icon: Droplets,
                                    card: 'bg-cyan-50/90 dark:bg-cyan-500/10 border-cyan-100/90 dark:border-cyan-500/25',
                                    iconWrap: 'bg-cyan-500/15 dark:bg-cyan-500/25 text-cyan-600 dark:text-cyan-400',
                                    labelClass: 'text-cyan-800/90 dark:text-cyan-200',
                                    valueClass: 'text-cyan-700 dark:text-cyan-300',
                                },
                                {
                                    label: 'รถ / รายวัน',
                                    unit: 'รายการ',
                                    display: String(atAGlanceStats.vehicleOrDailyCount),
                                    Icon: Truck,
                                    card: 'bg-orange-50/90 dark:bg-orange-500/10 border-orange-100/90 dark:border-orange-500/25',
                                    iconWrap: 'bg-orange-500/15 dark:bg-orange-500/25 text-orange-600 dark:text-orange-400',
                                    labelClass: 'text-orange-800/90 dark:text-orange-200',
                                    valueClass: 'text-orange-700 dark:text-orange-300',
                                },
                                {
                                    label: 'น้ำมัน',
                                    unit: 'บาท',
                                    display: atAGlanceStats.fuelBaht.toLocaleString(),
                                    Icon: Fuel,
                                    card: 'bg-rose-50/90 dark:bg-rose-500/10 border-rose-100/90 dark:border-rose-500/25',
                                    iconWrap: 'bg-rose-500/15 dark:bg-rose-500/25 text-rose-600 dark:text-rose-400',
                                    labelClass: 'text-rose-800/90 dark:text-rose-200',
                                    valueClass: 'text-rose-700 dark:text-rose-300',
                                    prefix: '฿',
                                },
                            ].map((item) => {
                                const GlanceIcon = item.Icon;
                                return (
                                    <Card
                                        key={item.label}
                                        className={`min-w-0 min-h-[5.25rem] sm:min-h-[5.75rem] p-3 sm:p-3.5 ${item.card} flex flex-col gap-2 border shadow-sm`}
                                    >
                                        <div
                                            className={`h-9 w-9 sm:h-10 sm:w-10 rounded-xl flex items-center justify-center shrink-0 ${item.iconWrap}`}
                                            aria-hidden
                                        >
                                            <GlanceIcon className="w-[18px] h-[18px] sm:w-[19px] sm:h-[19px]" strokeWidth={2.25} />
                                        </div>
                                        <p className={`text-[11px] sm:text-xs font-bold leading-snug line-clamp-2 ${item.labelClass}`} title={item.label}>
                                            {item.label}
                                        </p>
                                        <div className="mt-auto flex flex-wrap items-baseline gap-x-1 gap-y-0">
                                            <span className={`text-xl sm:text-2xl font-black tabular-nums tracking-tight leading-none ${item.valueClass}`}>
                                                {'prefix' in item && item.prefix ? <span className="font-black">{item.prefix}</span> : null}
                                                {item.display}
                                            </span>
                                            <span className={`text-[10px] sm:text-xs font-semibold ${item.labelClass} opacity-80`}>{item.unit}</span>
                                        </div>
                                    </Card>
                                );
                            })}
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
                        </div>

                        <div className="flex-1 overflow-y-auto p-3 sm:p-4 space-y-3">
                            {dayTransactions.length === 0 ? (
                                <div className="h-full flex flex-col items-center justify-center text-slate-500 dark:text-slate-300">
                                    <FileText size={48} className="mb-3 text-slate-300 dark:text-slate-500" />
                                    <p className="font-medium">ยังไม่มีรายการบันทึก</p>
                                </div>
                            ) : (
                                dayTransactions.map(t => (
                                    <div key={t.id} className="p-3 bg-white dark:bg-white/[0.03] rounded-xl border border-slate-100 dark:border-white/5 hover:border-indigo-300 dark:hover:border-indigo-500/50 hover:shadow-md transition-all group relative">
                                        <div className="flex justify-between items-start mb-1.5">
                                            <span className={`text-[9px] sm:text-[10px] uppercase font-bold px-1.5 py-0.5 rounded tracking-wide ${t.category === 'Labor' ? 'bg-emerald-100 dark:bg-emerald-500/20 text-emerald-700 dark:text-emerald-400' :
                                                t.category === 'Vehicle' ? 'bg-amber-100 dark:bg-amber-500/20 text-amber-700 dark:text-amber-400' :
                                                    t.category === 'Fuel' ? 'bg-red-100 dark:bg-rose-500/20 text-red-700 dark:text-rose-400' :
                                                        t.category === 'DailyLog' ? 'bg-blue-100 dark:bg-blue-500/20 text-blue-700 dark:text-blue-400' :
                                                            'bg-slate-100 dark:bg-white/10 text-slate-600 dark:text-slate-400'
                                                }`}>{t.category}</span>
                                            {t.amount > 0 && <span className="font-bold text-sm text-slate-800 dark:text-white text-right">฿{t.amount.toLocaleString()}</span>}
                                        </div>
                                        <p className="text-xs font-medium text-slate-700 dark:text-slate-300 mb-1 leading-snug">{t.description}</p>

                                        <div className="flex flex-wrap gap-2 text-[10px] text-slate-500 dark:text-slate-400 mt-2 bg-slate-50 dark:bg-white/[0.02] p-1.5 rounded-lg border border-slate-100 dark:border-white/5">
                                            {t.otHours && <span className="flex items-center gap-1"><span className="w-1.5 h-1.5 rounded-full bg-amber-500"></span>OT: {t.otHours} ชม.</span>}
                                            {t.workDetails && <span className="flex items-center gap-1"><span className="w-1.5 h-1.5 rounded-full bg-indigo-500"></span>งานรถ: {t.workDetails}</span>}
                                            {t.machineHours && <span className="flex items-center gap-1"><span className="w-1.5 h-1.5 rounded-full bg-orange-500"></span>ชม.: {t.machineHours}</span>}
                                            {t.category === 'Fuel' && t.amount != null && <span className="flex items-center gap-1"><span className="w-1.5 h-1.5 rounded-full bg-red-500"></span>ค่าน้ำมัน: ฿{t.amount.toLocaleString()}</span>}
                                            {t.quantity != null && t.category !== 'Fuel' && <span className="flex items-center gap-1"><span className="w-1.5 h-1.5 rounded-full bg-cyan-500"></span>จำนวน: {t.quantity}</span>}
                                            {(!t.otHours && !t.workDetails && !t.machineHours && (t.category !== 'Fuel' || t.amount == null) && !t.quantity) && <span>วันที่: {formatDateBE(t.date)}</span>}
                                        </div>

                                        {/* Simple Delete Button */}
                                        {onDeleteTransaction && (
                                            <button onClick={() => onDeleteTransaction(t.id)} className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 p-1.5 bg-red-100 hover:bg-red-500 text-red-600 hover:text-white rounded-lg transition-all" title="ลบรายการ">
                                                <Trash2 size={12} />
                                            </button>
                                        )}
                                    </div>
                                ))
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
