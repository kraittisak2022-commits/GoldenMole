import { lazy, Suspense, useState, useEffect, useCallback, useRef, useMemo } from 'react';
import { LayoutDashboard, UserCheck, Users, Truck, Fuel, Wrench, MapPin, Zap, Wallet, Banknote, List, Settings, MoreHorizontal, ClipboardList, CalendarDays, Menu, X, Shield, LogOut, Sun, Moon, Loader2, Smartphone } from 'lucide-react';
import { AppSettings, Employee, Transaction, LandProject, AdminUser, AdminLog, AdminUiTheme, AdminDataAccess } from './types';
import Toast from './components/ui/Toast';
import Card from './components/ui/Card';

// Modules
import Dashboard from './modules/Dashboard';
import EmployeeManager from './modules/Employees/EmployeeManager';
import LaborModule from './modules/Labor/LaborModule';
import VehicleEntry from './modules/Vehicle/VehicleEntry';
import GeneralEntry from './modules/GeneralEntry';
import LandModule from './modules/Land/LandModule';
import IncomeEntry from './modules/IncomeEntry';
import SettingsModule from './modules/Settings/SettingsModule';
import MaintenanceModule from './modules/Maintenance/MaintenanceModule';
import DailyStepRecorder from './modules/Dashboard/DailyStepRecorder';
import LoginPage from './modules/Auth/LoginPage';
import FirstLoginPasswordChange from './modules/Auth/FirstLoginPasswordChange';
import PostLoginModeSelect from './modules/Auth/PostLoginModeSelect';
import MobileFieldApp from './modules/Mobile/MobileFieldApp';
import WorkPlanner from './modules/Planning/WorkPlanner';
import DataVerificationModule from './modules/DataQuality/DataVerificationModule';
import Button from './components/ui/Button';
import AdminProfileModal from './components/AdminProfileModal';
const PayrollModule = lazy(() => import('./modules/Payroll/PayrollModule'));
const RecordManager = lazy(() => import('./modules/DataList/RecordManager'));
const AdminModule = lazy(() => import('./modules/Admin/AdminModule'));

import { getToday, formatDateBE, normalizeDate, formatDateTimeTH } from './utils';
import { fuelTxToLiters } from './utils';
import { hashPasswordForStorage, needsPasswordRehash, validateNewPasswordPolicy, verifyStoredPassword } from './utils/passwordAuth';
import { readSavedLocale, saveLocale, t, type AppLocale } from './utils/i18n';
import { usePwaInstall } from './hooks/usePwaInstall';
import {
    dropOfflineQueueItem,
    enqueueTransaction,
    getOfflineQueue,
    getOfflineSyncSnapshot,
    initOfflineSync,
    retryOfflineQueueItemNow,
    resolveConflictUseLocal,
    resolveConflictUseServer,
    subscribeOfflineSync,
    syncOfflineQueue,
    type OfflineQueueItem,
    type OfflineSyncSnapshot,
} from './services/offlineSync';

// Supabase Services
import * as db from './services/dataService';

// --- Default Admin Account (รหัสผ่านเก็บเป็น SHA-256 — ค่าเริ่มต้นเข้าได้ด้วย 1234) ---
const DEFAULT_ADMINS: AdminUser[] = [
    {
        id: 'admin-1',
        username: 'admin',
        password: 'sha256$03ac674216f3e15c761ee1a5e255f067953623c8b388b4459e13f978d7c846f4',
        displayName: 'ผู้ดูแลระบบ',
        role: 'SuperAdmin',
        createdAt: '2024-01-01',
        mustChangePassword: false,
        uiTheme: 'system',
    },
];

type ClientSurface = 'select' | 'desktop' | 'mobile';
const MOBILE_PIN_KEY = 'cm_mobile_pin_v1';
const MOBILE_PIN_LOCK_MS = 90 * 1000;
const MOBILE_PIN_MAX_FAIL = 5;
const MOBILE_PIN_MIN_LENGTH = 4;
const BOOTSTRAP_CACHE_KEY = 'cm_bootstrap_cache_v1';

type BootstrapCachePayload = {
    savedAt: number;
    employees: Employee[];
    transactions: Transaction[];
    projects: LandProject[];
    settings: AppSettings;
    admins: AdminUser[];
    adminLogs: AdminLog[];
};

const readBootstrapCache = (): BootstrapCachePayload | null => {
    if (typeof window === 'undefined') return null;
    try {
        const raw = window.localStorage.getItem(BOOTSTRAP_CACHE_KEY);
        if (!raw) return null;
        const parsed = JSON.parse(raw) as Partial<BootstrapCachePayload>;
        if (!parsed || !Array.isArray(parsed.employees) || !Array.isArray(parsed.transactions) || !parsed.settings) {
            return null;
        }
        return {
            savedAt: Number(parsed.savedAt) || Date.now(),
            employees: parsed.employees as Employee[],
            transactions: parsed.transactions as Transaction[],
            projects: Array.isArray(parsed.projects) ? (parsed.projects as LandProject[]) : [],
            settings: parsed.settings as AppSettings,
            admins: Array.isArray(parsed.admins) ? (parsed.admins as AdminUser[]) : [],
            adminLogs: Array.isArray(parsed.adminLogs) ? (parsed.adminLogs as AdminLog[]) : [],
        };
    } catch {
        return null;
    }
};

const saveBootstrapCache = (payload: Omit<BootstrapCachePayload, 'savedAt'>) => {
    if (typeof window === 'undefined') return;
    const next: BootstrapCachePayload = { savedAt: Date.now(), ...payload };
    window.localStorage.setItem(BOOTSTRAP_CACHE_KEY, JSON.stringify(next));
};

type MobilePinState = {
    hash: string;
    failedAttempts: number;
    lockUntil?: number;
};

const resolveDarkFromUiTheme = (ui: AdminUiTheme | undefined): boolean => {
    const t = ui ?? 'system';
    if (t === 'dark') return true;
    if (t === 'light') return false;
    return typeof window !== 'undefined' && window.matchMedia('(prefers-color-scheme: dark)').matches;
};


// --- Mock Data (Note: Name now primarily uses nickname per requirement) ---
const MOCK_EMPLOYEES: Employee[] = [
    { id: '1', name: 'นายสมชาย ใจดี', nickname: 'ชาย', type: 'Daily', baseWage: 500 },
    { id: '2', name: 'นายอาทิตย์ สดใส', nickname: 'ซัน', type: 'Daily', baseWage: 450 },
    { id: '3', name: 'นายวิชัย การช่าง', nickname: 'ชัย', type: 'Monthly', baseWage: 18000 },
    { id: '4', name: 'นายมานะ อดทน', nickname: 'นะ', type: 'Daily', baseWage: 500 },
];
const MOCK_PROJECTS: LandProject[] = [
    { id: 'P1', name: 'แปลง A1', group: 'โครงการหนองจอก', sellerName: 'คุณสมศักดิ์', titleDeed: '12345', rai: 5, ngan: 2, sqWah: 50, fullPrice: 2000000, deposit: 50000, purchaseDate: '2023-11-15', status: 'Deposit' }
];
const MOCK_SETTINGS: AppSettings = {
    appName: 'Goldenmole Dashboard', appSubtext: 'ระบบจัดการ', appIcon: 'https://img2.pic.in.th/unnamed-18906f5f592b392df.jpg', appIconDark: 'https://img2.pic.in.th/unnamed-245ad907783477a6c.jpg',
    cars: ['รถแม็คโคร SK200-8 (น้องโกลเด้น)', 'รถแม็คโคร SK200-8 (พี่ยักษ์ใหญ่)', 'รถดรัมโอเว่น', 'รถดรัมนายก', 'รถดรัมนายกนิต'],
    jobDescriptions: ['ล้างทรายที่ท่าทราย', 'ล้างทรายที่บ้าน', 'งานทั่วไป'],
    incomeTypes: ['ขายทราย', 'ขายหิน', 'ขายแร่'],
    expenseTypes: ['ค่าไฟ', 'ค่าน้ำ', 'ค่ากับแกล้ม', 'ค่าอุปกรณ์'],
    maintenanceTypes: ['เปลี่ยนถ่ายน้ำมันเครื่อง', 'ปะยาง', 'ซ่อมเครื่องยนต์', 'อะไหล่สิ้นเปลือง'],
    locations: ['หน้างาน A', 'บ่อทราย B', 'ออฟฟิศใหญ่'],
    landGroups: ['โครงการหนองจอก', 'โครงการลาดกระบัง'],
    employeePositions: ['คนขับรถ', 'รับจ้างรายวัน'],
    versionNotes: ['เปิดใช้ Daily Wizard และซิงก์ข้อมูลกับ Supabase'],
    fuelOpeningStockLiters: { Diesel: 0, Benzine: 0 },
    orgProfile: {},
    appDefaults: { sandCubicPerTrip: 3, vehicleDefaultMachineWage: 4500 },
};
const MOCK_TRANSACTIONS: Transaction[] = [
    { id: '1', date: getToday(), type: 'Expense', category: 'Fuel', description: 'เติมน้ำมัน (ดีเซล)', amount: 2000, quantity: 60, unit: 'L', vehicleId: 'รถดรัมโอเว่น', fuelType: 'Diesel', fuelMovement: 'stock_out' },
    { id: '2', date: getToday(), type: 'Income', category: 'Income', description: 'ขายทราย 10 คิว', amount: 5000, quantity: 10, unit: 'คิว' },
    { id: '3', date: getToday(), type: 'Expense', category: 'Labor', subCategory: 'Attendance', description: 'งาน: ล้างทราย', amount: 1500, employeeIds: ['1', '2', '4'], laborStatus: 'Work', workType: 'FullDay' },
];

const MENU_ITEMS = [
    { id: 'Dashboard', icon: LayoutDashboard, l: 'ภาพรวม' },
    { id: 'DailyWizard', icon: ClipboardList, l: 'บันทึกงานประจำวัน (Daily Wizard)' },
    { id: 'WorkPlanner', icon: ClipboardList, l: 'วางแผนงาน (เดือน/สัปดาห์/วัน)' },
    { id: 'MonthDataAudit', icon: CalendarDays, l: 'ตรวจสอบ' },
    { id: 'Employees', icon: UserCheck, l: 'พนักงาน' },
    { id: 'Labor', icon: Users, l: 'ค่าแรง/ลา' },
    { id: 'Vehicle', icon: Truck, l: 'การใช้รถ' },
    { id: 'Fuel', icon: Fuel, l: 'น้ำมัน' },
    { id: 'Maintenance', icon: Wrench, l: 'ซ่อมบำรุง' },
    { id: 'Land', icon: MapPin, l: 'ที่ดิน' },
    { id: 'Utilities', icon: Zap, l: 'สาธารณูปโภค' },
    { id: 'Income', icon: Wallet, l: 'รายรับ' },
    { id: 'Payroll', icon: Banknote, l: 'เงินเดือน' },
    { id: 'DataList', icon: List, l: 'รายการบันทึก' },
    { id: 'AdminManagement', icon: Shield, l: 'จัดการแอดมิน' },
    { id: 'Settings', icon: Settings, l: 'ตั้งค่า' },
];

const DEFAULT_VISIBLE_TX_CATEGORIES = [
    'Labor', 'Vehicle', 'Fuel', 'Maintenance', 'Land', 'Utilities', 'Income', 'Payroll', 'PayrollUnlock', 'DailyLog',
];

const isDateInRange = (date: string, start: string, end: string) => {
    const d = normalizeDate(date);
    return d >= normalizeDate(start) && d <= normalizeDate(end);
};
const getPeriodLockState = (txs: Transaction[], period: { start: string; end: string }) => {
    const key = `${normalizeDate(period.start)}|${normalizeDate(period.end)}`;
    const items = txs
        .filter(x => x.category === 'PayrollUnlock' && x.payrollPeriod && `${normalizeDate(x.payrollPeriod.start)}|${normalizeDate(x.payrollPeriod.end)}` === key)
        .sort((a, b) => {
            const d = normalizeDate(a.date).localeCompare(normalizeDate(b.date));
            if (d !== 0) return d;
            return String(a.id).localeCompare(String(b.id));
        });
    if (items.length === 0) return false;
    const latest = items[items.length - 1];
    return (latest.payrollLockAction || 'unlock') === 'unlock';
};
const getPrevDayYmd = () => {
    const d = new Date(`${getToday()}T12:00:00`);
    d.setDate(d.getDate() - 1);
    return d.toLocaleDateString('en-CA', { timeZone: 'Asia/Bangkok' });
};
const getDayTransactions = (txs: Transaction[], dateYmd: string) => txs.filter(t => normalizeDate(t.date) === normalizeDate(dateYmd));
const detectDailyAuditAlertCount = (txs: Transaction[], dateYmd: string, thresholds: { incomeZeroThreshold?: number; laborHighAmountThreshold?: number; fuelHighLitersThreshold?: number } | undefined) => {
    const dayTx = getDayTransactions(txs, dateYmd);
    const empty = !dayTx.some(t =>
        t.category === 'Labor' ||
        t.category === 'Vehicle' ||
        t.category === 'Fuel' ||
        (t.category === 'Income' && t.type === 'Income') ||
        (t.category === 'DailyLog' && (t.subCategory === 'VehicleTrip' || t.subCategory === 'Sand' || t.subCategory === 'Event'))
    );
    const exactDupCount = (() => {
        const map = new Map<string, number>();
        for (const t of dayTx) {
            if (t.category === 'Payroll' || t.category === 'PayrollUnlock') continue;
            const k = `${normalizeDate(t.date)}|${t.category}|${t.subCategory || ''}|${t.amount}|${(t.description || '').trim()}`;
            map.set(k, (map.get(k) || 0) + 1);
        }
        let c = 0;
        for (const [, n] of map) if (n >= 2) c += 1;
        return c;
    })();
    const incomeZeroThreshold = Math.max(0, thresholds?.incomeZeroThreshold ?? 0);
    const laborHighAmountThreshold = Math.max(0, thresholds?.laborHighAmountThreshold ?? 25000);
    const fuelHighLitersThreshold = Math.max(0, thresholds?.fuelHighLitersThreshold ?? 400);
    const incomeAmount = dayTx.filter(t => t.category === 'Income' && t.type === 'Income').reduce((s, t) => s + Number(t.amount || 0), 0);
    const laborAmount = dayTx.filter(t => t.category === 'Labor').reduce((s, t) => s + Number(t.amount || 0), 0);
    const fuelLiters = dayTx.filter(t => t.category === 'Fuel').reduce((s, t) => s + fuelTxToLiters(t), 0);
    const tripCount = dayTx.filter(t => (t.category === 'DailyLog' && t.subCategory === 'VehicleTrip') || t.category === 'Vehicle').length;
    let count = 0;
    if (empty) count += 1;
    if (exactDupCount > 0) count += exactDupCount;
    if (incomeAmount <= incomeZeroThreshold && dayTx.some(t => t.category === 'Income')) count += 1;
    if (laborAmount >= laborHighAmountThreshold) count += 1;
    if (fuelLiters >= fuelHighLitersThreshold && tripCount === 0) count += 1;
    return count;
};

function App() {
    const appVersion = import.meta.env.VITE_APP_VERSION || 'dev';
    const appLastUpdated = import.meta.env.VITE_APP_UPDATED_AT || '';
    const autoVersionNotes = useMemo(() => {
        try {
            const raw = import.meta.env.VITE_APP_AUTO_CHANGELOG || '[]';
            const parsed = JSON.parse(raw);
            return Array.isArray(parsed) ? parsed.filter((x: unknown): x is string => typeof x === 'string' && x.trim().length > 0) : [];
        } catch {
            return [];
        }
    }, []);
    // --- Auth State ---
    const [isLoggedIn, setIsLoggedIn] = useState(false);
    /** หลังล็อกอิน: เลือกโหมดมือถือหรือเว็บปกติ */
    const [clientSurface, setClientSurface] = useState<ClientSurface>('select');
    const [currentAdmin, setCurrentAdmin] = useState<AdminUser | null>(null);
    const [admins, setAdmins] = useState<AdminUser[]>([]);
    const [adminLogs, setAdminLogs] = useState<AdminLog[]>([]);

    // --- App State ---
    const [activeMenu, setActiveMenu] = useState('Dashboard');
    const [dailyWizardJumpDate, setDailyWizardJumpDate] = useState<string | undefined>(undefined);
    const [dailyWizardJumpStep, setDailyWizardJumpStep] = useState<number | undefined>(undefined);
    const [auditBadgeCount, setAuditBadgeCount] = useState(0);
    const [isSidebarOpen, setIsSidebarOpen] = useState(false);
    const [isMobile, setIsMobile] = useState(false);
    const [isTouchLayout, setIsTouchLayout] = useState(false);
    const [darkMode, setDarkMode] = useState(false);
    const [employees, setEmployees] = useState<Employee[]>([]);
    const [transactions, setTransactions] = useState<Transaction[]>([]);
    const [projects, setProjects] = useState<LandProject[]>([]);
    const [settings, setSettings] = useState<AppSettings>(MOCK_SETTINGS);
    const [locale, setLocale] = useState<AppLocale>(() => readSavedLocale());
    const [undoAction, setUndoAction] = useState<{ message: string; expiresAt: number; onUndo: () => void } | null>(null);
    const lazyFallback = (
        <div className="flex min-h-[240px] items-center justify-center">
            <Loader2 className="h-8 w-8 animate-spin text-slate-400" />
        </div>
    );
    const latestVersionNote = (settings.versionNotes && settings.versionNotes.length > 0)
        ? settings.versionNotes[settings.versionNotes.length - 1]
        : (autoVersionNotes[0] || 'พร้อมใช้งาน');
    const [toast, setToast] = useState<string | null>(null);
    const [accountModalOpen, setAccountModalOpen] = useState(false);
    const [offlineSync, setOfflineSync] = useState<OfflineSyncSnapshot>(getOfflineSyncSnapshot());
    const [offlineQueueItems, setOfflineQueueItems] = useState<OfflineQueueItem[]>(getOfflineQueue());
    const [showIdleWarning, setShowIdleWarning] = useState(false);
    const [idleDeadline, setIdleDeadline] = useState<number | null>(null);
    const [idleTick, setIdleTick] = useState(0);
    const [isLoading, setIsLoading] = useState(true);
    const [loadProgress, setLoadProgress] = useState(0);
    const [loadMessage, setLoadMessage] = useState(t(readSavedLocale(), 'loadingPreparing'));
    const [pendingForcedPasswordAdmin, setPendingForcedPasswordAdmin] = useState<AdminUser | null>(null);
    const [mobilePinEnabled, setMobilePinEnabled] = useState(false);
    const [pinInput, setPinInput] = useState('');
    const [showPinLock, setShowPinLock] = useState(false);
    const [pinLockedUntil, setPinLockedUntil] = useState<number | null>(null);
    const currentAdminAccess: AdminDataAccess | null = useMemo(() => {
        if (!currentAdmin) return null;
        return settings.appDefaults?.adminDataAccessByAdminId?.[currentAdmin.id] || null;
    }, [currentAdmin, settings.appDefaults?.adminDataAccessByAdminId]);
    const canViewMenu = useCallback((menuId: string) => {
        if (!currentAdmin) return false;
        if (currentAdmin.role === 'SuperAdmin') return true;
        if (menuId === 'AdminManagement') return false;
        const allowed = currentAdminAccess?.visibleMenus;
        if (!allowed || allowed.length === 0) return true;
        return allowed.includes(menuId);
    }, [currentAdmin, currentAdminAccess?.visibleMenus]);
    const canViewTransactions = currentAdmin?.role === 'SuperAdmin'
        ? true
        : (currentAdminAccess?.transactionPermissions?.view ?? true);
    const canCreateTransactions = currentAdmin?.role === 'SuperAdmin'
        ? true
        : (currentAdminAccess?.transactionPermissions?.create ?? true);
    const canEditTransactions = currentAdmin?.role === 'SuperAdmin'
        ? true
        : (currentAdminAccess?.transactionPermissions?.edit ?? true);
    const canDeleteTransactions = currentAdmin?.role === 'SuperAdmin'
        ? true
        : (currentAdminAccess?.transactionPermissions?.delete ?? true);
    const isFinancialMaskEnabled = !!currentAdminAccess?.maskFinancialAmountsAsPercent;
    const isDataEntryDailyWizardOnly = !!currentAdminAccess?.dataEntryDailyWizardOnly;
    const canMutateTransactionsInCurrentMenu = useCallback(() => {
        if (!currentAdmin) return false;
        if (currentAdmin.role === 'SuperAdmin') return true;
        if (!isDataEntryDailyWizardOnly) return true;
        return activeMenu === 'DailyWizard';
    }, [activeMenu, currentAdmin, isDataEntryDailyWizardOnly]);
    const visibleTransactions = useMemo(() => {
        if (!canViewTransactions) return [];
        const hidden = new Set(settings.appDefaults?.hiddenTransactionIds || []);
        const allowedCategories = currentAdminAccess?.visibleTransactionCategories;
        return transactions.filter(t => {
            if (hidden.has(t.id)) return false;
            if (!allowedCategories || allowedCategories.length === 0) return true;
            return allowedCategories.includes(t.category);
        });
    }, [transactions, settings.appDefaults?.hiddenTransactionIds, currentAdminAccess?.visibleTransactionCategories, canViewTransactions]);
    const maskedTransactions = useMemo(() => {
        if (!isFinancialMaskEnabled) return visibleTransactions;
        const totalAbsAmount = visibleTransactions.reduce((sum, tx) => sum + Math.abs(Number(tx.amount || 0)), 0);
        return visibleTransactions.map(tx => {
            const raw = Math.abs(Number(tx.amount || 0));
            const pct = totalAbsAmount > 0 ? (raw / totalAbsAmount) * 100 : 0;
            return { ...tx, amount: Number(pct.toFixed(2)), unit: '%' };
        });
    }, [isFinancialMaskEnabled, visibleTransactions]);
    useEffect(() => {
        if (isLoading) return;
        const prevDay = getPrevDayYmd();
        const thresholds = settings.appDefaults?.dataQualityThresholds;
        const count = detectDailyAuditAlertCount(visibleTransactions, prevDay, thresholds);
        setAuditBadgeCount(count);
        const lastDate = settings.appDefaults?.dataQualityDailyAlert?.lastAlertDate;
        if (count <= 0 || lastDate === getToday()) return;
        setToast(`แจ้งเตือนตรวจสอบข้อมูล: เมื่อวานพบ ${count} รายการผิดปกติ`);
        setTimeout(() => setToast(null), 5000);
        setSettings(prev => ({
            ...prev,
            appDefaults: {
                ...(prev.appDefaults || {}),
                dataQualityDailyAlert: {
                    lastAlertDate: getToday(),
                    lastAlertCount: count,
                },
            },
        }));
    }, [isLoading, visibleTransactions, settings.appDefaults?.dataQualityThresholds, settings.appDefaults?.dataQualityDailyAlert?.lastAlertDate]);
    const hasSeeded = useRef(false);
    const hasAutoVersionSynced = useRef(false);
    const hasRestoredAuthSession = useRef(false);
    const currentAdminRef = useRef<AdminUser | null>(null);
    const { canInstall, promptInstall } = usePwaInstall();
    useEffect(() => {
        currentAdminRef.current = currentAdmin;
    }, [currentAdmin]);

    useEffect(() => {
        initOfflineSync();
        const unsub = subscribeOfflineSync((snap) => {
            setOfflineSync(snap);
            setOfflineQueueItems(getOfflineQueue());
        });
        if (navigator.onLine) {
            void syncOfflineQueue();
        }
        const onOnline = () => { void syncOfflineQueue(); };
        window.addEventListener('online', onOnline);
        const timer = window.setInterval(() => {
            if (navigator.onLine) void syncOfflineQueue();
        }, 30_000);
        return () => {
            unsub();
            window.removeEventListener('online', onOnline);
            window.clearInterval(timer);
        };
    }, []);

    useEffect(() => {
        saveLocale(locale);
    }, [locale]);

    const readMobilePinState = useCallback((): MobilePinState | null => {
        try {
            const raw = window.localStorage.getItem(MOBILE_PIN_KEY);
            if (!raw) return null;
            const parsed = JSON.parse(raw) as MobilePinState;
            if (!parsed || typeof parsed.hash !== 'string' || parsed.hash.length < 16) return null;
            return {
                hash: parsed.hash,
                failedAttempts: Number(parsed.failedAttempts) || 0,
                lockUntil: Number(parsed.lockUntil) || undefined,
            };
        } catch {
            return null;
        }
    }, []);

    const saveMobilePinState = useCallback((state: MobilePinState | null) => {
        if (!state) {
            window.localStorage.removeItem(MOBILE_PIN_KEY);
            return;
        }
        window.localStorage.setItem(MOBILE_PIN_KEY, JSON.stringify(state));
    }, []);

    const hashPin = useCallback(async (plain: string) => {
        const encoder = new TextEncoder();
        const buff = await crypto.subtle.digest('SHA-256', encoder.encode(plain));
        return Array.from(new Uint8Array(buff)).map(b => b.toString(16).padStart(2, '0')).join('');
    }, []);

    useEffect(() => {
        const pinState = readMobilePinState();
        setMobilePinEnabled(!!pinState);
        setPinLockedUntil(pinState?.lockUntil || null);
    }, [readMobilePinState]);

    useEffect(() => {
        if (isLoading || hasAutoVersionSynced.current) return;
        if (autoVersionNotes.length === 0) return;
        if (settings.versionNotes && settings.versionNotes.length > 0) return;
        hasAutoVersionSynced.current = true;
        const next = { ...settings, versionNotes: [...autoVersionNotes] };
        setSettings(next);
        db.saveSettings(next);
    }, [isLoading, autoVersionNotes, settings]);

    // --- Load all data from Supabase on mount ---
    useEffect(() => {
        const withTimeout = async <T,>(promise: Promise<T>, timeoutMs: number, fallback: T): Promise<T> => {
            let timeoutHandle: ReturnType<typeof setTimeout> | null = null;
            const timeoutPromise = new Promise<T>((resolve) => {
                timeoutHandle = setTimeout(() => resolve(fallback), timeoutMs);
            });
            const result = await Promise.race([promise, timeoutPromise]);
            if (timeoutHandle) clearTimeout(timeoutHandle);
            return result;
        };

        const loadData = async () => {
            const cached = readBootstrapCache();
            try {
                setIsLoading(!cached);
                setLoadProgress(5);
                setLoadMessage(t(locale, 'loadingPreparing'));
                if (cached) {
                    setEmployees(cached.employees);
                    setTransactions(cached.transactions);
                    setProjects(cached.projects);
                    setSettings(cached.settings);
                    setAdmins(cached.admins.length > 0 ? cached.admins : DEFAULT_ADMINS);
                    setAdminLogs(cached.adminLogs);
                    setLoadProgress(40);
                }

                // Seed default data if needed (only once)
                if (!hasSeeded.current) {
                    setLoadProgress(20);
                    setLoadMessage(t(locale, 'loadingSeed'));
                    hasSeeded.current = true;
                    await db.seedDefaultData(MOCK_EMPLOYEES, MOCK_TRANSACTIONS, MOCK_PROJECTS, MOCK_SETTINGS, DEFAULT_ADMINS);
                }

                // Load all data in parallel
                setLoadProgress(55);
                setLoadMessage(t(locale, 'loadingRemote'));
                const [emps, txs, projs, sett, adms, logs] = await Promise.all([
                    withTimeout(db.fetchEmployees(), 12000, MOCK_EMPLOYEES),
                    withTimeout(db.fetchTransactions(), 12000, MOCK_TRANSACTIONS),
                    withTimeout(db.fetchProjects(), 12000, MOCK_PROJECTS),
                    withTimeout(db.fetchSettings(), 12000, MOCK_SETTINGS),
                    withTimeout(db.fetchAdmins(), 12000, DEFAULT_ADMINS),
                    withTimeout(db.fetchAdminLogs(), 12000, [] as AdminLog[]),
                ]);

                setLoadProgress(85);
                setLoadMessage(t(locale, 'loadingProcess'));
                setEmployees(emps);
                setTransactions(txs);
                setProjects(projs);
                const nextSettings = sett || MOCK_SETTINGS;
                const nextAdmins = adms.length > 0 ? adms : DEFAULT_ADMINS;
                setSettings(nextSettings);
                setAdmins(nextAdmins);
                setAdminLogs(logs);
                saveBootstrapCache({
                    employees: emps,
                    transactions: txs,
                    projects: projs,
                    settings: nextSettings,
                    admins: nextAdmins,
                    adminLogs: logs,
                });
                setLoadProgress(100);
                setLoadMessage(t(locale, 'loadingOk'));
            } catch (err) {
                console.error('Failed to load data from Supabase:', err);
                setLoadProgress(80);
                setLoadMessage(t(locale, 'loadingFallback'));
                // Fallback to mock data
                setEmployees(MOCK_EMPLOYEES);
                setTransactions(MOCK_TRANSACTIONS);
                setProjects(MOCK_PROJECTS);
                setSettings(MOCK_SETTINGS);
                setAdmins(DEFAULT_ADMINS);
                setLoadProgress(100);
                setLoadMessage(t(locale, 'loadingFallbackOk'));
            } finally {
                setIsLoading(false);
            }
        };
        loadData();
    }, [locale]);

    const applyUiThemeToApp = useCallback((ui: AdminUiTheme | undefined) => {
        setDarkMode(resolveDarkFromUiTheme(ui));
    }, []);

    // Restore auth session from Supabase after initial data load
    useEffect(() => {
        if (isLoading || hasRestoredAuthSession.current) return;
        hasRestoredAuthSession.current = true;
        const activeSessions = admins
            .filter(a => a.sessionActive)
            .sort((a, b) => String(b.lastLogin || '').localeCompare(String(a.lastLogin || '')));
        const matchedAdmin = activeSessions[0];
        if (!matchedAdmin) return;
        setCurrentAdmin(matchedAdmin);
        setIsLoggedIn(true);
        // หลังล็อกอินให้ผู้ใช้เลือกโหมดก่อนทุกครั้ง
        setClientSurface('select');
        applyUiThemeToApp(matchedAdmin.uiTheme);
    }, [isLoading, admins, applyUiThemeToApp]);

    // Sync dark mode to <html> for full-page background and Tailwind dark:
    useEffect(() => {
        if (darkMode) {
            document.documentElement.classList.add('dark');
        } else {
            document.documentElement.classList.remove('dark');
        }
    }, [darkMode]);

    /** เมื่อเลือกโหมด system ให้ตามธีม OS */
    useEffect(() => {
        if (!isLoggedIn || !currentAdmin || (currentAdmin.uiTheme ?? 'system') !== 'system') return;
        const mq = window.matchMedia('(prefers-color-scheme: dark)');
        const onChange = () => setDarkMode(mq.matches);
        mq.addEventListener('change', onChange);
        return () => mq.removeEventListener('change', onChange);
    }, [isLoggedIn, currentAdmin?.id, currentAdmin?.uiTheme]);

    // Detect viewport + touch layout (phone vs tablet touch / hybrid touch)
    useEffect(() => {
        const checkLayout = () => {
            const width = window.innerWidth;
            const isPhoneViewport = width < 768;
            const isNarrowViewport = width < 1024;
            const coarsePointer = window.matchMedia('(pointer: coarse)').matches;
            const touchCapable = coarsePointer || navigator.maxTouchPoints > 0;
            const touchFriendlyLayout = isPhoneViewport || (touchCapable && width < 1366);
            setIsMobile(isNarrowViewport);
            setIsTouchLayout(touchFriendlyLayout);
            setIsSidebarOpen(!isNarrowViewport);
        };
        checkLayout();
        window.addEventListener('resize', checkLayout);
        return () => window.removeEventListener('resize', checkLayout);
    }, []);

    // --- Auth Helpers ---
    const addLog = useCallback((action: string, details: string) => {
        if (!currentAdmin) return;
        const log: AdminLog = {
            id: Date.now().toString(),
            adminId: currentAdmin.id,
            adminName: currentAdmin.displayName,
            action,
            details,
            timestamp: formatDateTimeTH(),
        };
        setAdminLogs(prev => [log, ...prev]);
        db.saveAdminLog(log);
    }, [currentAdmin]);

    const persistAdminSession = useCallback(async (
        admin: AdminUser,
        sessionActive: boolean,
        surface?: ClientSurface
    ) => {
        const nextAdmin: AdminUser = {
            ...admin,
            sessionActive,
            lastClientSurface: surface ?? admin.lastClientSurface ?? 'select',
        };
        setAdmins(prev => prev.map(a => a.id === nextAdmin.id ? nextAdmin : a));
        if (currentAdminRef.current?.id === nextAdmin.id) {
            setCurrentAdmin(nextAdmin);
            currentAdminRef.current = nextAdmin;
        }
        await db.saveAdmin(nextAdmin);
        return nextAdmin;
    }, []);

    const changeClientSurface = useCallback((surface: ClientSurface) => {
        setClientSurface(surface);
        const admin = currentAdminRef.current;
        if (!admin) return;
        const nextAdmin: AdminUser = {
            ...admin,
            sessionActive: true,
            lastClientSurface: surface,
        };
        setAdmins(prev => prev.map(a => a.id === nextAdmin.id ? nextAdmin : a));
        setCurrentAdmin(nextAdmin);
        currentAdminRef.current = nextAdmin;
        void db.saveAdmin(nextAdmin);
    }, []);

    const finalizeSuccessfulLogin = useCallback(async (updatedAdmin: AdminUser) => {
        const loggedInAdmin: AdminUser = { ...updatedAdmin, sessionActive: true, lastClientSurface: 'select' };
        const otherActiveAdmins = admins
            .filter(a => a.id !== loggedInAdmin.id && a.sessionActive)
            .map(a => ({ ...a, sessionActive: false as const }));
        setClientSurface('select');
        setAdmins(prev => prev.map(a => {
            if (a.id === loggedInAdmin.id) return loggedInAdmin;
            if (a.sessionActive) return { ...a, sessionActive: false };
            return a;
        }));
        setCurrentAdmin(loggedInAdmin);
        currentAdminRef.current = loggedInAdmin;
        setIsLoggedIn(true);
        await Promise.all([
            db.saveAdmin(loggedInAdmin),
            ...otherActiveAdmins.map(a => db.saveAdmin(a)),
        ]);
        const log: AdminLog = {
            id: Date.now().toString(),
            adminId: loggedInAdmin.id,
            adminName: loggedInAdmin.displayName,
            action: 'login',
            details: `สถานะ: สำเร็จ | เหตุการณ์: เข้าสู่ระบบ`,
            timestamp: formatDateTimeTH(),
        };
        setAdminLogs(prev => [log, ...prev]);
        db.saveAdminLog(log);
    }, [admins]);

    const handleLogin = async (admin: AdminUser, plainPassword: string) => {
        if (admin.mustChangePassword) {
            setPendingForcedPasswordAdmin(admin);
            return;
        }
        let storedPassword = admin.password;
        if (needsPasswordRehash(admin.password)) {
            storedPassword = await hashPasswordForStorage(plainPassword);
        }
        const updatedAdmin = { ...admin, password: storedPassword, lastLogin: formatDateTimeTH() };
        applyUiThemeToApp(updatedAdmin.uiTheme);
        await finalizeSuccessfulLogin(updatedAdmin);
    };

    const handleForcedFirstLoginPassword = async (newPlain: string) => {
        const admin = pendingForcedPasswordAdmin;
        if (!admin) return;
        const policy = validateNewPasswordPolicy(newPlain);
        if (!policy.ok) throw new Error(policy.message);
        const hashed = await hashPasswordForStorage(newPlain);
        const updatedAdmin: AdminUser = {
            ...admin,
            password: hashed,
            mustChangePassword: false,
            lastLogin: formatDateTimeTH(),
        };
        setPendingForcedPasswordAdmin(null);
        applyUiThemeToApp(updatedAdmin.uiTheme);
        await finalizeSuccessfulLogin(updatedAdmin);
    };

    const handleLogout = () => {
        const admin = currentAdminRef.current;
        if (admin) {
            addLog('logout', 'สถานะ: สำเร็จ | เหตุการณ์: ออกจากระบบ');
            void persistAdminSession(admin, false, 'select');
        }
        setIsLoggedIn(false);
        setCurrentAdmin(null);
        currentAdminRef.current = null;
        setClientSurface('select');
        setActiveMenu('Dashboard');
    };

    /** ออกจากระบบอัตโนมัติเมื่อไม่มีการใช้งาน (คลิก/พิมพ์/เลื่อน) เกินกำหนด */
    const SESSION_IDLE_MS = 45 * 60 * 1000;
    const SESSION_WARN_MS = 60 * 1000;
    useEffect(() => {
        if (!isLoggedIn) return;
        const idleLastRef = { current: Date.now() };
        let warned = false;
        const bump = () => {
            idleLastRef.current = Date.now();
            warned = false;
            setShowIdleWarning(false);
            setIdleDeadline(null);
        };
        const events: (keyof WindowEventMap)[] = ['mousedown', 'keydown', 'scroll', 'touchstart', 'click'];
        events.forEach(ev => window.addEventListener(ev, bump as EventListener, { passive: true }));
        const tick = window.setInterval(() => {
            const idleFor = Date.now() - idleLastRef.current;
            const remaining = SESSION_IDLE_MS - idleFor;
            if (!warned && remaining <= SESSION_WARN_MS && remaining > 0) {
                warned = true;
                setShowIdleWarning(true);
                setIdleDeadline(Date.now() + remaining);
            }
            if (idleFor < SESSION_IDLE_MS) return;
            const admin = currentAdminRef.current;
            if (admin) {
                const log: AdminLog = {
                    id: `${Date.now()}_idle`,
                    adminId: admin.id,
                    adminName: admin.displayName,
                    action: 'logout',
                    details: `สถานะ: สำเร็จ | เหตุการณ์: ออกจากระบบ (หมดเวลาเซสชันจากไม่มีการใช้งาน)`,
                    timestamp: formatDateTimeTH(),
                };
                setAdminLogs(prev => [log, ...prev]);
                db.saveAdminLog(log);
            }
            if (admin) void persistAdminSession(admin, false, 'select');
            setIsLoggedIn(false);
            setCurrentAdmin(null);
            currentAdminRef.current = null;
            setClientSurface('select');
            setActiveMenu('Dashboard');
            setShowIdleWarning(false);
            setIdleDeadline(null);
            setToast('ออกจากระบบอัตโนมัติ — ไม่มีการใช้งานเกิน 45 นาที กรุณาเข้าสู่ระบบใหม่');
            setTimeout(() => setToast(null), 6000);
        }, 30_000);
        return () => {
            events.forEach(ev => window.removeEventListener(ev, bump as EventListener));
            window.clearInterval(tick);
        };
    }, [isLoggedIn, persistAdminSession]);

    const handleMenuClick = useCallback((menuId: string) => {
        if (!canViewMenu(menuId)) {
            setToast('ไม่มีสิทธิ์เข้าถึงเมนูนี้');
            setTimeout(() => setToast(null), 3000);
            return;
        }
        setActiveMenu(menuId);
        if (isMobile) setIsSidebarOpen(false);
    }, [canViewMenu, isMobile]);

    const extendSession = useCallback(() => {
        window.dispatchEvent(new Event('click'));
        setShowIdleWarning(false);
        setIdleDeadline(null);
        setToast('ต่อเวลาเซสชันแล้ว');
        setTimeout(() => setToast(null), 2200);
    }, []);

    useEffect(() => {
        if (!showIdleWarning) return;
        const t = window.setInterval(() => setIdleTick(prev => prev + 1), 1000);
        return () => window.clearInterval(t);
    }, [showIdleWarning]);

    useEffect(() => {
        if (!isLoggedIn || !mobilePinEnabled) return;
        const onHidden = () => {
            if (document.hidden && clientSurface === 'mobile') {
                setShowPinLock(true);
                setPinInput('');
            }
        };
        document.addEventListener('visibilitychange', onHidden);
        return () => document.removeEventListener('visibilitychange', onHidden);
    }, [isLoggedIn, mobilePinEnabled, clientSurface]);

    const idleCountdownLabel = useMemo(() => {
        void idleTick;
        if (!idleDeadline) return '';
        const remainSec = Math.max(0, Math.ceil((idleDeadline - Date.now()) / 1000));
        const min = Math.floor(remainSec / 60);
        const sec = remainSec % 60;
        return `${min}:${String(sec).padStart(2, '0')}`;
    }, [idleDeadline, showIdleWarning]);

    const pinLockRemain = useMemo(() => {
        if (!pinLockedUntil) return 0;
        return Math.max(0, Math.ceil((pinLockedUntil - Date.now()) / 1000));
    }, [pinLockedUntil, idleTick]);

    const idleWarningModal = showIdleWarning ? (
        <div className="fixed inset-0 z-[120] flex items-center justify-center bg-black/45 p-4">
            <Card className="w-full max-w-sm p-5">
                <h3 className="text-lg font-bold text-slate-900 dark:text-slate-100">เซสชันกำลังจะหมดเวลา</h3>
                <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">
                    ระบบจะออกจากระบบอัตโนมัติในอีก {idleCountdownLabel} นาที
                </p>
                <div className="mt-4 flex gap-2">
                    <Button className="flex-1" onClick={extendSession}>ต่อเวลา</Button>
                    <Button variant="outline" className="flex-1" onClick={handleLogout}>ออกจากระบบ</Button>
                </div>
            </Card>
        </div>
    ) : null;

    const setupMobilePin = useCallback(async () => {
        const next = window.prompt('ตั้งรหัส PIN มือถือ 4-6 หลัก');
        if (!next) return;
        const cleaned = next.trim();
        if (!/^\d{4,6}$/.test(cleaned)) {
            setToast('PIN ต้องเป็นตัวเลข 4-6 หลัก');
            setTimeout(() => setToast(null), 2200);
            return;
        }
        const confirm = window.prompt('ยืนยัน PIN อีกครั้ง');
        if ((confirm || '').trim() !== cleaned) {
            setToast('PIN ไม่ตรงกัน');
            setTimeout(() => setToast(null), 2200);
            return;
        }
        const hash = await hashPin(cleaned);
        saveMobilePinState({ hash, failedAttempts: 0 });
        setMobilePinEnabled(true);
        setPinLockedUntil(null);
        setToast('ตั้งค่า PIN แล้ว');
        setTimeout(() => setToast(null), 2200);
    }, [hashPin, saveMobilePinState]);

    const disableMobilePin = useCallback(() => {
        saveMobilePinState(null);
        setMobilePinEnabled(false);
        setShowPinLock(false);
        setPinInput('');
        setPinLockedUntil(null);
        setToast('ปิด PIN lock แล้ว');
        setTimeout(() => setToast(null), 2200);
    }, [saveMobilePinState]);

    const unlockWithPin = useCallback(async () => {
        const state = readMobilePinState();
        if (!state) {
            setShowPinLock(false);
            return;
        }
        const now = Date.now();
        if (state.lockUntil && now < state.lockUntil) {
            setPinLockedUntil(state.lockUntil);
            setToast('PIN ถูกล็อกชั่วคราว');
            setTimeout(() => setToast(null), 2000);
            return;
        }
        const inputHash = await hashPin(pinInput);
        if (inputHash === state.hash) {
            saveMobilePinState({ hash: state.hash, failedAttempts: 0 });
            setShowPinLock(false);
            setPinInput('');
            setPinLockedUntil(null);
            return;
        }
        const failed = (state.failedAttempts || 0) + 1;
        const nextState: MobilePinState = {
            hash: state.hash,
            failedAttempts: failed,
        };
        if (failed >= MOBILE_PIN_MAX_FAIL) {
            nextState.lockUntil = Date.now() + MOBILE_PIN_LOCK_MS;
            setPinLockedUntil(nextState.lockUntil);
        }
        saveMobilePinState(nextState);
        setToast(nextState.lockUntil ? 'PIN ผิดเกินกำหนด ล็อกชั่วคราว 90 วินาที' : 'PIN ไม่ถูกต้อง');
        setTimeout(() => setToast(null), 2300);
    }, [hashPin, pinInput, readMobilePinState, saveMobilePinState]);
    const appendPinDigit = useCallback((digit: string) => {
        if (!/^\d$/.test(digit)) return;
        setPinInput(prev => (prev.length >= 6 ? prev : `${prev}${digit}`));
    }, []);
    const backspacePinDigit = useCallback(() => {
        setPinInput(prev => prev.slice(0, -1));
    }, []);
    const clearPinInput = useCallback(() => {
        setPinInput('');
    }, []);
    const touchFeedback = useCallback(() => {
        if (typeof navigator !== 'undefined' && 'vibrate' in navigator) {
            navigator.vibrate(12);
        }
    }, []);

    const handleSave = async (t: Transaction) => {
        if (!canMutateTransactionsInCurrentMenu()) {
            setToast('สิทธิ์นี้คีย์ข้อมูลได้เฉพาะเมนู บันทึกงานประจำวัน (Daily Wizard)');
            setTimeout(() => setToast(null), 3500);
            return;
        }
        const wasUpdate = transactions.some(x => x.id === t.id);
        if (!wasUpdate && !canCreateTransactions) {
            setToast('ไม่มีสิทธิ์สร้างรายการ (Create)');
            setTimeout(() => setToast(null), 3000);
            return;
        }
        if (wasUpdate && !canEditTransactions) {
            setToast('ไม่มีสิทธิ์แก้ไขรายการ (Edit)');
            setTimeout(() => setToast(null), 3000);
            return;
        }
        if (t.category !== 'Payroll' && t.category !== 'PayrollUnlock') {
            const lockRef = transactions.find(x =>
                x.category === 'Payroll' &&
                x.payrollPeriod &&
                isDateInRange(t.date, x.payrollPeriod.start, x.payrollPeriod.end)
            );
            if (lockRef && !getPeriodLockState(transactions, lockRef.payrollPeriod!)) {
                setToast(`งวด ${formatDateBE(lockRef.payrollPeriod!.start)} - ${formatDateBE(lockRef.payrollPeriod!.end)} ถูกจ่ายแล้ว จึงไม่อนุญาตให้แก้ข้อมูลย้อนหลัง`);
                setTimeout(() => setToast(null), 4500);
                return;
            }
        }
        setTransactions(p => {
            const i = p.findIndex(x => x.id === t.id);
            if (i >= 0) {
                const next = [...p];
                next[i] = t;
                return next;
            }
            return [...p, t];
        });
        let ok = false;
        if (!navigator.onLine) {
            enqueueTransaction(t);
            setToast('บันทึกในเครื่องแล้ว (ออฟไลน์) จะซิงก์อัตโนมัติเมื่อออนไลน์');
            setTimeout(() => setToast(null), 3500);
            return;
        }
        ok = await db.saveTransaction(t);
        if (!ok) {
            enqueueTransaction(t);
            setToast('ซิงก์ไม่สำเร็จ บันทึกไว้ในเครื่องแล้ว จะลองซิงก์อีกครั้งอัตโนมัติ');
            setTimeout(() => setToast(null), 3500);
            return;
        }
        if (offlineSync.queueSize > 0) {
            void syncOfflineQueue();
        }

        // Audit log - create transaction (DailyLog / รายการอื่นๆ)
        if (ok && currentAdmin) {
            const summary = {
                id: t.id,
                date: normalizeDate(t.date),
                type: t.type,
                category: t.category,
                subCategory: t.subCategory,
                amount: t.amount,
                description: t.description,
            };
            const verb = wasUpdate ? 'อัปเดตรายการ' : 'สร้างรายการ';
            addLog(wasUpdate ? 'update_transaction' : 'create_transaction', `${verb}: ${t.category}/${t.subCategory || '-'} วันที่ ${normalizeDate(t.date)} จำนวนเงิน ${t.amount || 0} รายละเอียด: ${t.description || '-'} | snapshot=${JSON.stringify(summary)}`);
        }

        setToast(ok ? 'ซิงก์แล้ว' : 'เกิดข้อผิดพลาดในการบันทึก กรุณาลองใหม่');
        setTimeout(() => setToast(null), 3000);
    };

    // --- Wrapped setters that persist to Supabase ---
    const handleSetEmployees = useCallback((updater: Employee[] | ((prev: Employee[]) => Employee[])) => {
        setEmployees(prev => {
            const next = typeof updater === 'function' ? updater(prev) : updater;
            next.forEach(emp => db.saveEmployee(emp));
            const nextIds = new Set(next.map(e => e.id));
            prev.forEach(emp => { if (!nextIds.has(emp.id)) db.deleteEmployee(emp.id); });
            return next;
        });
    }, []);

    const wagePromptRef = useRef<{ resolve: (w: number) => void; reject: () => void } | null>(null);
    const [wagePromptEmp, setWagePromptEmp] = useState<Employee | null>(null);
    const [wagePromptValue, setWagePromptValue] = useState('');
    const ensureEmployeeWage = useCallback((emp: Employee): Promise<number> => {
        if (emp.baseWage != null && emp.baseWage > 0) return Promise.resolve(emp.baseWage);
        return new Promise<number>((resolve, reject) => {
            wagePromptRef.current = { resolve, reject };
            setWagePromptEmp(emp);
            setWagePromptValue('');
        });
    }, []);
    const submitWagePrompt = useCallback(() => {
        const wage = Number(wagePromptValue);
        if (!wagePromptEmp || !(wage > 0)) return;
        setEmployees(prev => {
            const next = prev.map(e => e.id === wagePromptEmp.id ? { ...e, baseWage: wage } : e);
            next.forEach(emp => db.saveEmployee(emp));
            return next;
        });
        wagePromptRef.current?.resolve(wage);
        wagePromptRef.current = null;
        setWagePromptEmp(null);
        setWagePromptValue('');
    }, [wagePromptEmp, wagePromptValue]);
    const cancelWagePrompt = useCallback(() => {
        wagePromptRef.current?.reject();
        wagePromptRef.current = null;
        setWagePromptEmp(null);
        setWagePromptValue('');
    }, []);

    const handleSetTransactions = useCallback((updater: Transaction[] | ((prev: Transaction[]) => Transaction[])) => {
        setTransactions(prev => {
            const next = typeof updater === 'function' ? updater(prev) : updater;
            next.forEach(t => db.saveTransaction(t));
            // Delete removed transactions
            const nextIds = new Set(next.map(t => t.id));
            prev.forEach(t => { if (!nextIds.has(t.id)) db.deleteTransaction(t.id); });
            return next;
        });
    }, []);

    const handleDeleteTransaction = useCallback((id: string) => {
        if (!canMutateTransactionsInCurrentMenu()) {
            setToast('สิทธิ์นี้คีย์ข้อมูลได้เฉพาะเมนู บันทึกงานประจำวัน (Daily Wizard)');
            setTimeout(() => setToast(null), 3500);
            return;
        }
        if (!canDeleteTransactions) {
            setToast('ไม่มีสิทธิ์ลบรายการ (Delete)');
            setTimeout(() => setToast(null), 3000);
            return;
        }
        const target = transactions.find(t => t.id === id);
        if (!target) return;
        if (target.category !== 'Payroll') {
            const lockRef = transactions.find(x =>
                x.category === 'Payroll' &&
                x.payrollPeriod &&
                isDateInRange(target.date, x.payrollPeriod.start, x.payrollPeriod.end)
            );
            if (lockRef && !getPeriodLockState(transactions, lockRef.payrollPeriod!)) {
                setToast(`งวด ${formatDateBE(lockRef.payrollPeriod!.start)} - ${formatDateBE(lockRef.payrollPeriod!.end)} ถูกจ่ายแล้ว จึงไม่อนุญาตให้ลบรายการย้อนหลัง`);
                setTimeout(() => setToast(null), 4500);
                return;
            }
        }
        if (currentAdmin) {
            const snap = {
                id: target.id,
                date: normalizeDate(target.date),
                type: target.type,
                category: target.category,
                subCategory: target.subCategory,
                amount: target.amount,
                description: target.description,
            };
            addLog('soft_delete_transaction', `ซ่อนรายการ: ${target.category}/${target.subCategory || '-'} วันที่ ${normalizeDate(target.date)} จำนวนเงิน ${target.amount || 0} รายละเอียด: ${target.description || '-'} | snapshot=${JSON.stringify(snap)}`);
        }
        const prevHidden = settings.appDefaults?.hiddenTransactionIds || [];
        setSettings(prev => ({
            ...prev,
            appDefaults: {
                ...(prev.appDefaults || {}),
                hiddenTransactionIds: Array.from(new Set([...(prev.appDefaults?.hiddenTransactionIds || []), id])),
            },
        }));
        const expiresAt = Date.now() + 20000;
        setUndoAction({
            message: 'ซ่อนรายการแล้ว (Undo ได้ใน 20 วินาที)',
            expiresAt,
            onUndo: () => {
                setSettings(prev => ({
                    ...prev,
                    appDefaults: {
                        ...(prev.appDefaults || {}),
                        hiddenTransactionIds: (prev.appDefaults?.hiddenTransactionIds || []).filter(x => x !== id),
                    },
                }));
                setToast('กู้คืนรายการแล้ว');
                setTimeout(() => setToast(null), 2500);
                setUndoAction(null);
            },
        });
        // keep a no-op read to bind previous hidden list for stale closures
        void prevHidden;
    }, [addLog, canDeleteTransactions, canMutateTransactionsInCurrentMenu, currentAdmin, settings.appDefaults?.hiddenTransactionIds, transactions]);

    useEffect(() => {
        if (!undoAction) return;
        const ms = Math.max(0, undoAction.expiresAt - Date.now());
        const timer = window.setTimeout(() => setUndoAction(null), ms);
        return () => window.clearTimeout(timer);
    }, [undoAction]);

    const handleSetProjects = useCallback((updater: LandProject[] | ((prev: LandProject[]) => LandProject[])) => {
        setProjects(prev => {
            const next = typeof updater === 'function' ? updater(prev) : updater;
            next.forEach(p => db.saveProject(p));
            const nextIds = new Set(next.map(p => p.id));
            prev.forEach(p => { if (!nextIds.has(p.id)) db.deleteProject(p.id); });
            return next;
        });
    }, []);

    const handleSetSettings = useCallback((updater: AppSettings | ((prev: AppSettings) => AppSettings)) => {
        setSettings(prev => {
            const next = typeof updater === 'function' ? updater(prev) : updater;
            db.saveSettings(next);
            return next;
        });
    }, []);

    const handleSetAdmins = useCallback((updater: AdminUser[] | ((prev: AdminUser[]) => AdminUser[])) => {
        setAdmins(prev => {
            const next = typeof updater === 'function' ? updater(prev) : updater;
            next.forEach(a => db.saveAdmin(a));
            const nextIds = new Set(next.map(a => a.id));
            prev.forEach(a => { if (!nextIds.has(a.id)) db.deleteAdmin(a.id); });
            return next;
        });
    }, []);

    const handleUpdateAdminProfile = useCallback(async (updates: {
        displayName?: string;
        avatar?: string;
        uiTheme?: AdminUiTheme;
        currentPassword?: string;
        newPassword?: string;
    }): Promise<{ ok: boolean; message?: string }> => {
        const admin = currentAdminRef.current;
        if (!admin) return { ok: false, message: 'ไม่พบผู้ใช้' };
        let next: AdminUser = { ...admin };

        if (updates.displayName !== undefined) {
            const d = updates.displayName.trim();
            if (!d) return { ok: false, message: 'กรุณาระบุชื่อที่แสดง' };
            next.displayName = d;
        }
        if (updates.avatar !== undefined) {
            next.avatar = updates.avatar.trim() || undefined;
        }
        if (updates.uiTheme !== undefined) {
            next.uiTheme = updates.uiTheme;
            applyUiThemeToApp(updates.uiTheme);
        }
        if (updates.newPassword) {
            if (!updates.currentPassword) return { ok: false, message: 'กรุณากรอกรหัสผ่านปัจจุบัน' };
            const match = await verifyStoredPassword(admin.password, updates.currentPassword);
            if (!match) return { ok: false, message: 'รหัสผ่านปัจจุบันไม่ถูกต้อง' };
            const pol = validateNewPasswordPolicy(updates.newPassword);
            if (!pol.ok) return { ok: false, message: pol.message };
            next.password = await hashPasswordForStorage(updates.newPassword);
            next.mustChangePassword = false;
        }

        setAdmins(prev => prev.map(a => a.id === next.id ? next : a));
        setCurrentAdmin(next);
        await db.saveAdmin(next);
        if (currentAdminRef.current?.id === next.id) {
            const log: AdminLog = {
                id: Date.now().toString(),
                adminId: next.id,
                adminName: next.displayName,
                action: 'profile_update',
                details: `อัปเดตโปรไฟล์${updates.newPassword ? ' และเปลี่ยนรหัสผ่าน' : ''} | @${next.username}`,
                timestamp: formatDateTimeTH(),
            };
            setAdminLogs(prevLogs => [log, ...prevLogs]);
            db.saveAdminLog(log);
        }
        return { ok: true };
    }, [applyUiThemeToApp]);

    const renderContent = () => {
        if (!canViewMenu(activeMenu)) {
            return <div className="p-8 text-center text-slate-500 dark:text-slate-400">ไม่มีสิทธิ์เข้าถึงเมนูนี้</div>;
        }
        switch (activeMenu) {
            case 'Dashboard': return <Dashboard transactions={maskedTransactions} settings={settings} employees={employees} onSaveTransaction={handleSave} onDeleteTransaction={handleDeleteTransaction} setSettings={handleSetSettings} isMobile={isMobile} />;
            case 'Employees': return <EmployeeManager employees={employees} setEmployees={handleSetEmployees} transactions={maskedTransactions} setTransactions={handleSetTransactions} settings={settings} setSettings={handleSetSettings} />;
            case 'Labor': return <LaborModule employees={employees} settings={settings} onSaveTransaction={handleSave} onDeleteTransaction={canDeleteTransactions ? handleDeleteTransaction : undefined} transactions={maskedTransactions} setTransactions={handleSetTransactions} ensureEmployeeWage={ensureEmployeeWage} />;
            case 'Vehicle': return <VehicleEntry settings={settings} employees={employees} transactions={maskedTransactions} onSave={handleSave} onDelete={canDeleteTransactions ? handleDeleteTransaction : undefined} ensureEmployeeWage={ensureEmployeeWage} />;
            case 'Fuel': return <GeneralEntry type="Fuel" settings={settings} setSettings={handleSetSettings} onSave={handleSave} onDelete={canDeleteTransactions ? handleDeleteTransaction : undefined} transactions={maskedTransactions} />;
            case 'Maintenance': return <MaintenanceModule settings={settings} transactions={maskedTransactions} onSave={handleSave} onDelete={canDeleteTransactions ? handleDeleteTransaction : undefined} />;
            case 'Utilities': return <GeneralEntry type="Utilities" settings={settings} onSave={handleSave} onDelete={canDeleteTransactions ? handleDeleteTransaction : undefined} transactions={maskedTransactions} />;
            case 'Land': return <LandModule projects={projects} setProjects={handleSetProjects} onSave={handleSave} transactions={maskedTransactions} />;
            case 'Income': return <IncomeEntry settings={settings} setSettings={handleSetSettings} onSave={handleSave} onDelete={canDeleteTransactions ? handleDeleteTransaction : undefined} transactions={maskedTransactions} />;
            case 'Payroll': return (
                <Suspense fallback={lazyFallback}>
                    <PayrollModule
                        employees={employees}
                        transactions={maskedTransactions}
                        onSaveTransaction={handleSave}
                        canUnlockPeriod={currentAdmin?.role === 'SuperAdmin'}
                        onUnlockPeriod={(period, reason) => {
                            const unlockTx: Transaction = {
                                id: Date.now().toString() + '_unlock',
                                date: getToday(),
                                type: 'Expense',
                                category: 'PayrollUnlock',
                                description: `ปลดล็อกงวดเงินเดือน ${formatDateBE(period.start)} - ${formatDateBE(period.end)}`,
                                amount: 0,
                                payrollPeriod: period,
                                payrollLockAction: 'unlock',
                                unlockedByAdminId: currentAdmin?.id,
                                unlockedByAdminName: currentAdmin?.displayName || currentAdmin?.username || 'Unknown',
                                unlockedAt: formatDateTimeTH(),
                                note: reason,
                            };
                            handleSave(unlockTx);
                            addLog('unlock_payroll_period', `ปลดล็อกงวดเงินเดือน ${period.start} - ${period.end} | เหตุผล: ${reason}`);
                        }}
                        onRelockPeriod={(period, reason) => {
                            const relockTx: Transaction = {
                                id: Date.now().toString() + '_relock',
                                date: getToday(),
                                type: 'Expense',
                                category: 'PayrollUnlock',
                                description: `ล็อกกลับงวดเงินเดือน ${formatDateBE(period.start)} - ${formatDateBE(period.end)}`,
                                amount: 0,
                                payrollPeriod: period,
                                payrollLockAction: 'relock',
                                unlockedByAdminId: currentAdmin?.id,
                                unlockedByAdminName: currentAdmin?.displayName || currentAdmin?.username || 'Unknown',
                                unlockedAt: formatDateTimeTH(),
                                note: reason,
                            };
                            handleSave(relockTx);
                            addLog('relock_payroll_period', `ล็อกกลับงวดเงินเดือน ${period.start} - ${period.end} | เหตุผล: ${reason}`);
                        }}
                    />
                </Suspense>
            );
            case 'DataList': return (
                <Suspense fallback={lazyFallback}>
                    <RecordManager
                        transactions={maskedTransactions}
                        onDeleteTransaction={canDeleteTransactions ? handleDeleteTransaction : undefined}
                        amountMode={isFinancialMaskEnabled ? 'percent' : 'currency'}
                    />
                </Suspense>
            );
            case 'MonthDataAudit': return (
                <DataVerificationModule
                    monthOverviewMode
                    transactions={maskedTransactions}
                    settings={settings}
                    setSettings={handleSetSettings}
                    currentAdmin={currentAdmin}
                    addLog={addLog}
                    onGoToDailyWizard={(date, step) => {
                        if (date) setDailyWizardJumpDate(normalizeDate(date));
                        if (typeof step === 'number') setDailyWizardJumpStep(step);
                        handleMenuClick('DailyWizard');
                    }}
                />
            );
            case 'DailyWizard': return <DailyStepRecorder mobileShell={isMobile} touchLayout={isTouchLayout} initialDate={dailyWizardJumpDate} initialStep={dailyWizardJumpStep} employees={employees} settings={settings} transactions={maskedTransactions} onSaveTransaction={handleSave} onDeleteTransaction={canDeleteTransactions ? handleDeleteTransaction : undefined} ensureEmployeeWage={ensureEmployeeWage} setSettings={handleSetSettings} />;
            case 'WorkPlanner': return currentAdmin ? (
                <WorkPlanner
                    adminId={currentAdmin.id}
                    adminName={currentAdmin.displayName}
                    settings={settings}
                    setSettings={handleSetSettings}
                    addLog={addLog}
                    darkMode={darkMode}
                />
            ) : null;
            case 'AdminManagement': return currentAdmin?.role === 'SuperAdmin' ? (
                <Suspense fallback={lazyFallback}>
                    <AdminModule
                        admins={admins}
                        setAdmins={handleSetAdmins}
                        currentAdmin={currentAdmin}
                        logs={adminLogs}
                        addLog={addLog}
                        settings={settings}
                        setSettings={handleSetSettings}
                    />
                </Suspense>
            ) : <div className="p-8 text-center text-slate-500 dark:text-slate-400">ไม่มีสิทธิ์เข้าถึง — เฉพาะ SuperAdmin เท่านั้น</div>;
            case 'Settings': return (
                <SettingsModule
                    settings={settings}
                    setSettings={handleSetSettings}
                    autoVersionNotes={autoVersionNotes}
                    currentAdmin={currentAdmin}
                    onUpdateAdminProfile={handleUpdateAdminProfile}
                />
            );
            default: return <div className="p-8 text-center text-slate-400 dark:text-slate-500">Coming Soon</div>;
        }
    };

    // --- LOADING STATE ---
    if (isLoading) {
        return (
            <div className="flex items-center justify-center min-h-screen min-h-[100dvh] bg-[#0a0a0f]">
                <div className="text-center w-full max-w-sm px-6">
                    <div className="animate-pulse space-y-3">
                        <div className="mx-auto h-10 w-10 rounded-full bg-amber-400/30" />
                        <div className="mx-auto h-3 w-48 rounded bg-white/15" />
                        <div className="mx-auto h-3 w-36 rounded bg-white/10" />
                    </div>
                    <p className="text-gray-300 text-sm font-medium mt-4 mb-2">{loadMessage}</p>
                    <div className="w-full h-2 rounded-full bg-white/10 overflow-hidden">
                        <div
                            className="h-full bg-amber-400 transition-all duration-300"
                            style={{ width: `${Math.max(0, Math.min(100, loadProgress))}%` }}
                        />
                    </div>
                    <p className="text-amber-300 text-sm mt-2 font-semibold">{Math.round(loadProgress)}%</p>
                </div>
            </div>
        );
    }

    // --- LOGIN GATE ---
    if (!isLoggedIn) {
        if (pendingForcedPasswordAdmin) {
            return (
                <FirstLoginPasswordChange
                    displayName={pendingForcedPasswordAdmin.displayName}
                    username={pendingForcedPasswordAdmin.username}
                    darkMode={darkMode}
                    onToggleDarkMode={() => setDarkMode(!darkMode)}
                    onComplete={handleForcedFirstLoginPassword}
                />
            );
        }
        return <LoginPage admins={admins} onLogin={handleLogin} appName={settings.appName} appIcon={darkMode && settings.appIconDark ? settings.appIconDark : settings.appIcon} appVersion={appVersion} appLastUpdated={appLastUpdated} latestVersionNote={latestVersionNote} darkMode={darkMode} onToggleDarkMode={() => setDarkMode(!darkMode)} />;
    }

    if (currentAdmin && clientSurface === 'select') {
        return (
            <>
                {toast && <div className="relative z-50"><Toast message={toast} onClose={() => setToast(null)} /></div>}
                {idleWarningModal}
                {undoAction && (
                    <div className="fixed bottom-20 right-4 z-[60] rounded-xl border border-amber-300 bg-amber-50 px-4 py-3 shadow-lg text-sm text-amber-900 flex items-center gap-3">
                        <span>{undoAction.message}</span>
                        <button type="button" onClick={undoAction.onUndo} className="px-2 py-1 rounded bg-amber-600 text-white hover:bg-amber-700">Undo</button>
                    </div>
                )}
                <PostLoginModeSelect
                    appName={settings.appName}
                    appIcon={darkMode && settings.appIconDark ? settings.appIconDark : settings.appIcon}
                    currentAdmin={currentAdmin}
                    darkMode={darkMode}
                    onToggleDarkMode={() => setDarkMode(!darkMode)}
                    onChooseMobile={() => changeClientSurface('mobile')}
                    onChooseDesktop={() => changeClientSurface('desktop')}
                    onChooseDesktopMenu={(menuId) => {
                        setActiveMenu(menuId);
                        changeClientSurface('desktop');
                    }}
                />
            </>
        );
    }

    if (currentAdmin && clientSurface === 'mobile') {
        return (
            <>
                {toast && <div className="relative z-50"><Toast message={toast} onClose={() => setToast(null)} /></div>}
                {idleWarningModal}
                {undoAction && (
                    <div className="fixed bottom-20 right-4 z-[60] rounded-xl border border-amber-300 bg-amber-50 px-4 py-3 shadow-lg text-sm text-amber-900 flex items-center gap-3">
                        <span>{undoAction.message}</span>
                        <button type="button" onClick={undoAction.onUndo} className="px-2 py-1 rounded bg-amber-600 text-white hover:bg-amber-700">Undo</button>
                    </div>
                )}
                <AdminProfileModal
                    open={accountModalOpen}
                    onClose={() => setAccountModalOpen(false)}
                    currentAdmin={currentAdmin}
                    darkMode={darkMode}
                    onUpdateAdminProfile={handleUpdateAdminProfile}
                />
                {wagePromptEmp && (
                    <div className="fixed inset-0 bg-black/50 dark:bg-black/70 flex items-center justify-center z-[100] p-4">
                        <Card className="w-full max-w-sm p-6 shadow-xl">
                            <h3 className="font-bold text-lg text-slate-800 dark:text-slate-100 mb-2">ระบุค่าแรง</h3>
                            <p className="text-sm text-slate-600 dark:text-slate-400 mb-4">พนักงาน <span className="font-semibold text-slate-800 dark:text-slate-200">{wagePromptEmp.nickname || wagePromptEmp.name || 'คนนี้'}</span> ยังไม่มีค่าแรง — กรุณาใส่ค่าแรง (บาท)</p>
                            <input type="number" min="1" className="w-full border border-slate-300 dark:border-white/20 rounded-lg px-4 py-3 text-lg font-bold text-slate-800 dark:text-slate-100 bg-white dark:bg-white/5 mb-4 placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:ring-2 focus:ring-amber-500/50 focus:border-amber-500 dark:focus:ring-amber-400/30" placeholder="บาท" value={wagePromptValue} onChange={e => setWagePromptValue(e.target.value)} />
                            <div className="flex gap-2">
                                <Button variant="outline" className="flex-1" onClick={cancelWagePrompt}>ยกเลิก</Button>
                                <Button className="flex-1" onClick={submitWagePrompt}>บันทึก</Button>
                            </div>
                        </Card>
                    </div>
                )}
                {showPinLock && (
                    <div className="fixed inset-0 z-[130] flex items-center justify-center bg-slate-950/75 p-4 backdrop-blur-sm">
                        <Card className="w-full max-w-sm overflow-hidden border border-white/15 bg-white/95 p-0 shadow-2xl dark:bg-[#121725]/95">
                            <div className="bg-gradient-to-r from-amber-500/90 via-yellow-500/80 to-amber-600/90 px-6 py-5 text-white">
                                <h3 className="text-xl font-extrabold tracking-tight">PIN Lock</h3>
                                <p className="mt-1 text-sm text-amber-50/95">ปลดล็อกเพื่อกลับเข้าใช้งานระบบ</p>
                            </div>
                            <div className="p-5">
                                <div className="mb-4 rounded-2xl border border-slate-200/80 bg-gradient-to-b from-white to-slate-50 p-3 shadow-inner dark:border-white/10 dark:from-white/[0.06] dark:to-white/[0.03]">
                                    <div className="mb-1 flex items-center justify-between px-1">
                                        <span className="text-[11px] font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-400">PIN</span>
                                        <span className="text-[11px] font-medium text-slate-400 dark:text-slate-500">{pinInput.length}/6</span>
                                    </div>
                                    <div className="flex items-center justify-center gap-2">
                                    {Array.from({ length: 6 }).map((_, idx) => {
                                        const filled = idx < pinInput.length;
                                        const active = idx === pinInput.length && pinInput.length < 6;
                                        return (
                                            <div
                                                key={idx}
                                                className={`flex h-11 w-10 items-center justify-center rounded-xl border text-lg font-black transition-all ${filled
                                                    ? 'border-amber-400/80 bg-amber-50 text-amber-600 shadow-[0_0_0_3px_rgba(245,158,11,0.18)] dark:border-amber-400/50 dark:bg-amber-500/10 dark:text-amber-300'
                                                    : active
                                                        ? 'border-indigo-300 bg-indigo-50 text-indigo-500 shadow-[0_0_0_2px_rgba(99,102,241,0.18)] dark:border-indigo-400/40 dark:bg-indigo-500/10 dark:text-indigo-300'
                                                        : 'border-slate-200 bg-white text-transparent dark:border-white/10 dark:bg-white/[0.03]'
                                                    }`}
                                            >
                                                {filled ? '•' : ' '}
                                            </div>
                                        );
                                    })}
                                    </div>
                                </div>
                                <p className="mb-3 text-center text-xs font-medium text-slate-500 dark:text-slate-400">
                                    อุปกรณ์ไม่มีคีย์บอร์ดก็ใช้งานได้: แตะตัวเลขบนหน้าจอ
                                </p>
                            {pinLockRemain > 0 && (
                                <p className="mb-3 rounded-lg border border-rose-300/60 bg-rose-50 px-3 py-2 text-center text-xs font-semibold text-rose-600 dark:border-rose-500/40 dark:bg-rose-500/10 dark:text-rose-300">
                                    ล็อกอยู่ {pinLockRemain} วินาที
                                </p>
                            )}
                                <div className="grid touch-manipulation select-none grid-cols-3 gap-2">
                                    {['1', '2', '3', '4', '5', '6', '7', '8', '9', 'ล้าง', '0', 'OK'].map((key) => {
                                        const isAction = key === 'ล้าง' || key === 'OK';
                                        return (
                                            <button
                                                key={key}
                                                type="button"
                                                disabled={pinLockRemain > 0 || (key === 'OK' && pinInput.length < MOBILE_PIN_MIN_LENGTH)}
                                                onClick={() => {
                                                    touchFeedback();
                                                    if (key === 'ล้าง') {
                                                        clearPinInput();
                                                        return;
                                                    }
                                                    if (key === 'OK') {
                                                        void unlockWithPin();
                                                        return;
                                                    }
                                                    appendPinDigit(key);
                                                }}
                                                className={`min-h-[56px] rounded-xl border text-base font-bold transition-all active:scale-[0.98] ${isAction
                                                    ? 'border-amber-400/70 bg-amber-50 text-amber-700 hover:bg-amber-100 dark:border-amber-400/40 dark:bg-amber-500/10 dark:text-amber-300 dark:hover:bg-amber-500/20'
                                                    : 'border-slate-200 bg-white text-slate-800 hover:border-slate-300 hover:bg-slate-50 dark:border-white/10 dark:bg-white/5 dark:text-slate-100 dark:hover:bg-white/10'
                                                    } disabled:cursor-not-allowed disabled:opacity-45`}
                                            >
                                                {key}
                                            </button>
                                        );
                                    })}
                                </div>
                                <div className="mt-2 flex gap-2">
                                    <button
                                        type="button"
                                        onClick={backspacePinDigit}
                                        disabled={pinLockRemain > 0 || pinInput.length === 0}
                                        className="min-h-[44px] flex-1 rounded-xl border border-slate-200 bg-white text-sm font-semibold text-slate-700 transition-all active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-45 dark:border-white/10 dark:bg-white/5 dark:text-slate-200"
                                    >
                                        ลบทีละตัว
                                    </button>
                                    <Button className="flex-1 min-h-[44px]" onClick={() => void unlockWithPin()} disabled={pinLockRemain > 0 || pinInput.length < MOBILE_PIN_MIN_LENGTH}>ปลดล็อก</Button>
                                    <Button variant="outline" className="flex-1" onClick={handleLogout}>ออกจากระบบ</Button>
                                </div>
                            </div>
                        </Card>
                    </div>
                )}
                <MobileFieldApp
                    settings={settings}
                    employees={employees}
                    transactions={isFinancialMaskEnabled ? maskedTransactions : visibleTransactions}
                    admins={admins}
                    adminLogs={adminLogs}
                    currentAdmin={currentAdmin}
                    appVersion={appVersion}
                    latestVersionNote={latestVersionNote}
                    autoVersionNotes={autoVersionNotes}
                    appIcon={darkMode && settings.appIconDark ? settings.appIconDark : settings.appIcon}
                    darkMode={darkMode}
                    locale={locale}
                    touchLayout={isTouchLayout}
                    onToggleDarkMode={() => setDarkMode(!darkMode)}
                    onToggleLocale={() => setLocale(prev => (prev === 'th' ? 'en' : 'th'))}
                    onLogout={handleLogout}
                    onSwitchToDesktop={() => changeClientSurface('desktop')}
                    onOpenAccount={() => setAccountModalOpen(true)}
                    onSaveTransaction={handleSave}
                    onDeleteTransaction={handleDeleteTransaction}
                    handleSetTransactions={handleSetTransactions}
                    ensureEmployeeWage={ensureEmployeeWage}
                    handleSetSettings={handleSetSettings}
                    handleSetAdmins={handleSetAdmins}
                    onUpdateAdminProfile={handleUpdateAdminProfile}
                    addLog={addLog}
                    offlineSync={offlineSync}
                    offlineQueueItems={offlineQueueItems}
                    onRetrySync={() => {
                        void syncOfflineQueue();
                    }}
                    onDropQueueItem={(id) => {
                        dropOfflineQueueItem(id);
                        setOfflineQueueItems(getOfflineQueue());
                        addLog('sync_queue_drop', `ลบรายการค้างออกจากคิว #${id}`);
                    }}
                    onRetryQueueItem={(id) => {
                        retryOfflineQueueItemNow(id);
                        setOfflineQueueItems(getOfflineQueue());
                        addLog('sync_queue_retry_item', `สั่ง retry รายการค้าง #${id}`);
                    }}
                    onResolveConflictUseLocal={async (id) => {
                        const ok = await resolveConflictUseLocal(id);
                        setOfflineQueueItems(getOfflineQueue());
                        setToast(ok ? 'บังคับใช้ข้อมูลในเครื่องแล้ว' : 'ยังแก้ conflict ไม่สำเร็จ');
                        setTimeout(() => setToast(null), 2200);
                        addLog('sync_conflict_resolve_local', `เลือกใช้ข้อมูลในเครื่องสำหรับคิว #${id}`);
                    }}
                    onResolveConflictUseServer={(id) => {
                        resolveConflictUseServer(id);
                        setOfflineQueueItems(getOfflineQueue());
                        addLog('sync_conflict_resolve_server', `เลือกใช้ข้อมูลบนเซิร์ฟเวอร์สำหรับคิว #${id}`);
                    }}
                    canInstallPwa={canInstall}
                    onInstallPwa={async () => {
                        const ok = await promptInstall();
                        setToast(ok ? 'ติดตั้งแอปสำเร็จ' : 'ยกเลิกการติดตั้งแอป');
                        setTimeout(() => setToast(null), 2500);
                    }}
                    mobilePinEnabled={mobilePinEnabled}
                    onSetupMobilePin={setupMobilePin}
                    onDisableMobilePin={disableMobilePin}
                    financialMaskEnabled={isFinancialMaskEnabled}
                />
            </>
        );
    }

    const activeMenuItem = MENU_ITEMS.find(m => m.id === activeMenu);

    return (
        <div className={`flex min-h-screen min-h-[100dvh] font-sans transition-colors duration-300 relative overflow-hidden max-w-full ${darkMode ? 'dark app-shell-dark' : 'app-shell-light'}`}>

            {/* Global Darktech X Background Auras */}
            {darkMode && (
                <div className="absolute inset-0 z-0 pointer-events-none overflow-hidden">
                    <div className="absolute top-[-20%] left-[-10%] w-[50%] h-[50%] rounded-full bg-indigo-600/20 blur-[120px]" />
                    <div className="absolute bottom-[-20%] right-[-10%] w-[60%] h-[60%] rounded-full bg-emerald-600/10 blur-[150px]" />
                    <div className="absolute top-[20%] right-[10%] w-[40%] h-[40%] rounded-full bg-purple-600/15 blur-[120px]" />
                    <div className="absolute bottom-[10%] left-[10%] w-[40%] h-[40%] rounded-full bg-amber-500/10 blur-[150px]" />
                </div>
            )}

            {toast && <div className="relative z-50"><Toast message={toast} onClose={() => setToast(null)} /></div>}
            {idleWarningModal}
            {undoAction && (
                <div className="fixed bottom-20 right-4 z-[60] rounded-xl border border-amber-300 bg-amber-50 px-4 py-3 shadow-lg text-sm text-amber-900 flex items-center gap-3">
                    <span>{undoAction.message}</span>
                    <button type="button" onClick={undoAction.onUndo} className="px-2 py-1 rounded bg-amber-600 text-white hover:bg-amber-700">Undo</button>
                </div>
            )}

            {currentAdmin && (
                <AdminProfileModal
                    open={accountModalOpen}
                    onClose={() => setAccountModalOpen(false)}
                    currentAdmin={currentAdmin}
                    darkMode={darkMode}
                    onUpdateAdminProfile={handleUpdateAdminProfile}
                />
            )}

            {/* Popup ใส่ค่าแรงเมื่อใช้พนักงานที่ยังไม่มีค่าแรง */}
            {wagePromptEmp && (
                <div className="fixed inset-0 bg-black/50 dark:bg-black/70 flex items-center justify-center z-[100] p-4">
                    <Card className="w-full max-w-sm p-6 shadow-xl">
                        <h3 className="font-bold text-lg text-slate-800 dark:text-slate-100 mb-2">ระบุค่าแรง</h3>
                        <p className="text-sm text-slate-600 dark:text-slate-400 mb-4">พนักงาน <span className="font-semibold text-slate-800 dark:text-slate-200">{wagePromptEmp.nickname || wagePromptEmp.name || 'คนนี้'}</span> ยังไม่มีค่าแรง — กรุณาใส่ค่าแรง (บาท)</p>
                        <input type="number" min="1" className="w-full border border-slate-300 dark:border-white/20 rounded-lg px-4 py-3 text-lg font-bold text-slate-800 dark:text-slate-100 bg-white dark:bg-white/5 mb-4 placeholder:text-slate-400 dark:placeholder:text-slate-500 focus:ring-2 focus:ring-amber-500/50 focus:border-amber-500 dark:focus:ring-amber-400/30" placeholder="บาท" value={wagePromptValue} onChange={e => setWagePromptValue(e.target.value)} />
                        <div className="flex gap-2">
                            <Button variant="outline" className="flex-1" onClick={cancelWagePrompt}>ยกเลิก</Button>
                            <Button className="flex-1" onClick={submitWagePrompt}>บันทึก</Button>
                        </div>
                    </Card>
                </div>
            )}

            {/* Mobile Overlay Backdrop */}
            {isMobile && isSidebarOpen && (
                <div
                    className="fixed inset-0 bg-black/50 z-40 transition-opacity duration-300 backdrop-blur-sm"
                    onClick={() => setIsSidebarOpen(false)}
                />
            )}

            {/* Sidebar */}
            <aside className={`
                fixed top-0 left-0 h-[100dvh] z-50 flex flex-col
                transition-all duration-300 ease-in-out border-r
                ${darkMode ? 'bg-[#0a0a0f]/40 backdrop-blur-xl border-white/[0.05]' : 'bg-white border-stone-100'}
                ${isMobile
                    ? `w-72 ${isSidebarOpen ? 'translate-x-0 shadow-2xl' : '-translate-x-full'}`
                    : `lg:sticky ${isSidebarOpen ? 'w-64' : 'w-20'}`
                }
            `}>
                <div className={`p-4 sm:p-6 flex items-center gap-3 border-b ${darkMode ? 'border-gray-800' : 'border-stone-50'}`}>
                    <div className={`w-10 h-10 rounded-xl flex items-center justify-center text-white font-bold shadow-lg overflow-hidden shrink-0`} style={{ background: darkMode ? '#1a1a1a' : '#0a0a0a' }}>
                        {(darkMode && settings.appIconDark ? settings.appIconDark : settings.appIcon).startsWith('http') || (darkMode && settings.appIconDark ? settings.appIconDark : settings.appIcon).startsWith('data:') ? (
                            <img src={darkMode && settings.appIconDark ? settings.appIconDark : settings.appIcon} alt="Logo" className="w-full h-full object-cover" />
                        ) : (
                            darkMode && settings.appIconDark ? settings.appIconDark : settings.appIcon
                        )}
                    </div>
                    {(isSidebarOpen || isMobile) && (
                        <div className="flex-1 min-w-0">
                            <h1 className="font-bold text-lg truncate">{settings.appName}</h1>
                            <p className="text-[10px] text-slate-400 uppercase">{settings.appSubtext}</p>
                            <p className="text-[10px] mt-1 text-slate-500 truncate">v{appVersion} • {latestVersionNote}</p>
                        </div>
                    )}
                    {isMobile && (
                        <button onClick={() => setIsSidebarOpen(false)} className={`p-1.5 rounded-lg shrink-0 ${darkMode ? 'hover:bg-gray-800 text-gray-400' : 'hover:bg-stone-100 text-stone-400'}`}>
                            <X size={20} />
                        </button>
                    )}
                </div>
                <nav className="flex-1 py-4 sm:py-6 px-2 sm:px-3 space-y-1 overflow-y-auto hide-scrollbar">
                    {MENU_ITEMS.filter(m => canViewMenu(m.id)).map(m => (
                        <button
                            key={m.id}
                            onClick={() => handleMenuClick(m.id)}
                            className={`w-full flex items-center gap-3 px-3 py-3 rounded-xl transition-all ${activeMenu === m.id
                                ? (darkMode ? 'bg-amber-500/10 text-amber-400 font-bold shadow-sm border border-amber-500/20' : 'bg-stone-50 text-gray-900 font-bold shadow-sm')
                                : (darkMode ? 'text-gray-500 hover:bg-gray-800/50 hover:text-gray-300' : 'text-gray-500 hover:bg-stone-50')
                                }`}
                        >
                            <m.icon size={20} className={`shrink-0 ${activeMenu === m.id ? (darkMode ? 'text-amber-400' : 'text-amber-600') : ''}`} />
                            {(isSidebarOpen || isMobile) && (
                                <span className="text-sm truncate flex items-center gap-2">
                                    <span className="truncate">{m.l}</span>
                                    {m.id === 'MonthDataAudit' && auditBadgeCount > 0 && (
                                        <span className={`inline-flex min-w-[20px] items-center justify-center rounded-full px-1.5 py-0.5 text-[10px] font-bold ${darkMode ? 'bg-rose-500/20 text-rose-300' : 'bg-rose-100 text-rose-700'}`}>
                                            {auditBadgeCount}
                                        </span>
                                    )}
                                </span>
                            )}
                        </button>
                    ))}
                </nav>

                {/* Sidebar Footer — Logout (Desktop) */}
                {!isMobile && (
                    <div className={`p-4 border-t space-y-2 ${darkMode ? 'border-gray-800' : ''}`}>
                        {isSidebarOpen && currentAdmin && (
                            <button
                                type="button"
                                onClick={() => setAccountModalOpen(true)}
                                className={`mb-2 flex w-full items-center gap-2 rounded-xl px-2 py-2 text-left transition-colors ${darkMode ? 'hover:bg-white/[0.06]' : 'hover:bg-stone-100'}`}
                                title="แก้ไขบัญชีแอดมิน"
                            >
                                <div className={`flex h-7 w-7 shrink-0 items-center justify-center overflow-hidden rounded-full text-xs font-bold ${darkMode ? 'bg-amber-500/20 text-amber-400' : 'bg-amber-50 text-amber-700'}`}>
                                    {currentAdmin.avatar && (currentAdmin.avatar.startsWith('http') || currentAdmin.avatar.startsWith('data:')) ? (
                                        <img src={currentAdmin.avatar} alt="" className="h-full w-full object-cover" />
                                    ) : (
                                        currentAdmin.displayName.charAt(0)
                                    )}
                                </div>
                                <div className="min-w-0">
                                    <p className={`truncate text-xs font-medium ${darkMode ? 'text-gray-300' : 'text-gray-700'}`}>{currentAdmin.displayName}</p>
                                    <p className="text-[10px] text-slate-400">{currentAdmin.role}</p>
                                </div>
                            </button>
                        )}
                        <div className="flex gap-2">
                            <button onClick={() => setIsSidebarOpen(!isSidebarOpen)} className={`flex-1 flex items-center justify-center p-2 rounded-lg ${darkMode ? 'hover:bg-gray-800 text-gray-500' : 'hover:bg-stone-50 text-stone-400'}`}>
                                <MoreHorizontal size={18} />
                            </button>
                            <button type="button" onClick={() => changeClientSurface('mobile')} className={`flex items-center justify-center p-2 rounded-lg ${darkMode ? 'hover:bg-emerald-500/10 text-emerald-400' : 'hover:bg-emerald-50 text-emerald-700'}`} title="โหมดมือถือ (กรอกข้อมูลง่าย)">
                                <Smartphone size={18} />
                            </button>
                            <button onClick={handleLogout} className="flex items-center justify-center p-2 hover:bg-red-50 dark:hover:bg-red-500/10 rounded-lg text-slate-400 dark:text-slate-500 hover:text-red-500 dark:hover:text-red-400 transition-colors" title="ออกจากระบบ">
                                <LogOut size={18} />
                            </button>
                        </div>
                    </div>
                )}

                {/* Sidebar Footer — Logout (Mobile) */}
                {isMobile && (
                    <div className={`p-4 border-t ${darkMode ? 'border-gray-800' : ''}`}>
                        {currentAdmin && (
                            <button
                                type="button"
                                onClick={() => { setAccountModalOpen(true); setIsSidebarOpen(false); }}
                                className={`mb-3 flex w-full items-center gap-3 rounded-xl px-2 py-2 text-left transition-colors ${darkMode ? 'hover:bg-white/[0.06]' : 'hover:bg-stone-100'}`}
                                title="แก้ไขบัญชีแอดมิน"
                            >
                                <div className={`flex h-9 w-9 shrink-0 items-center justify-center overflow-hidden rounded-full font-bold ${darkMode ? 'bg-amber-500/20 text-amber-400' : 'bg-amber-50 text-amber-700'}`}>
                                    {currentAdmin.avatar && (currentAdmin.avatar.startsWith('http') || currentAdmin.avatar.startsWith('data:')) ? (
                                        <img src={currentAdmin.avatar} alt="" className="h-full w-full object-cover" />
                                    ) : (
                                        currentAdmin.displayName.charAt(0)
                                    )}
                                </div>
                                <div className="min-w-0 flex-1">
                                    <p className={`truncate text-sm font-medium ${darkMode ? 'text-gray-300' : 'text-gray-700'}`}>{currentAdmin.displayName}</p>
                                    <p className="text-xs text-slate-400">@{currentAdmin.username} • {currentAdmin.role}</p>
                                </div>
                            </button>
                        )}
                        <button type="button" onClick={() => { changeClientSurface('mobile'); setIsSidebarOpen(false); }} className={`mb-2 w-full flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl text-sm font-medium transition-colors ${darkMode ? 'bg-emerald-500/15 text-emerald-300 hover:bg-emerald-500/25' : 'bg-emerald-50 text-emerald-800 hover:bg-emerald-100'}`}>
                            <Smartphone size={16} /> โหมดมือถือ (กรอกเร็ว)
                        </button>
                        <button onClick={handleLogout} className="w-full flex items-center justify-center gap-2 px-4 py-2.5 bg-red-50 dark:bg-red-500/10 text-red-600 dark:text-red-400 rounded-xl text-sm font-medium hover:bg-red-100 dark:hover:bg-red-500/20 transition-colors">
                            <LogOut size={16} /> ออกจากระบบ
                        </button>
                    </div>
                )}
            </aside>

            {/* Main Content — padding-bottom on mobile clears fixed bottom nav */}
            <main className={`flex-1 min-w-0 overflow-y-auto min-h-screen min-h-[100dvh] ${darkMode ? 'bg-transparent' : ''} ${isMobile ? 'pb-[calc(4.5rem+env(safe-area-inset-bottom,0px))]' : ''}`}>
                {/* Header */}
                <header className="flex justify-between items-center p-3 sm:p-4 lg:p-8 lg:pb-0 mb-2 lg:mb-8">
                    <div className="flex items-center gap-3">
                        {isMobile && (
                            <button
                                onClick={() => setIsSidebarOpen(true)}
                                className="p-2 hover:bg-slate-100 dark:hover:bg-white/10 rounded-xl text-slate-600 dark:text-slate-400 transition-colors"
                            >
                                <Menu size={24} />
                            </button>
                        )}
                        <div>
                            <h2 className={`text-lg sm:text-2xl font-bold tracking-tight ${darkMode ? 'text-white' : 'text-slate-800'}`}>
                                {activeMenuItem?.l || activeMenu}
                            </h2>
                        </div>
                    </div>
                    <div className="flex items-center gap-2 sm:gap-3">
                        {/* Dark Mode Toggle */}
                        <button
                            onClick={() => setLocale(prev => (prev === 'th' ? 'en' : 'th'))}
                            className={`p-2 rounded-xl transition-all ${darkMode ? 'bg-gray-800 text-indigo-300 hover:bg-gray-700 border border-gray-700' : 'bg-stone-100 text-stone-600 hover:bg-stone-200'}`}
                            title={t(locale, 'toggleLanguage')}
                        >
                            {t(locale, 'languageShort')}
                        </button>
                        <button
                            onClick={() => setDarkMode(!darkMode)}
                            className={`p-2 rounded-xl transition-all ${darkMode ? 'bg-gray-800 text-amber-400 hover:bg-gray-700 border border-gray-700' : 'bg-stone-100 text-stone-600 hover:bg-stone-200'}`}
                            title={darkMode ? 'เปลี่ยนเป็นโหมดสว่าง' : 'เปลี่ยนเป็นโหมดมืด'}
                        >
                            {darkMode ? <Sun size={18} /> : <Moon size={18} />}
                        </button>
                        {currentAdmin && (
                            <button
                                type="button"
                                onClick={() => setAccountModalOpen(true)}
                                className={`flex max-w-[min(100%,320px)] items-center gap-2 rounded-xl py-1.5 pl-2 pr-1.5 transition-colors sm:gap-3 sm:py-2 sm:pl-3 sm:pr-2 ${darkMode ? 'hover:bg-white/[0.06]' : 'hover:bg-stone-200/60'}`}
                                title="แก้ไขบัญชีแอดมิน"
                            >
                                <div className={`hidden min-w-0 items-center gap-2 text-sm sm:flex ${darkMode ? 'text-gray-400' : 'text-stone-500'}`}>
                                    <span className={`truncate font-medium ${darkMode ? 'text-gray-200' : 'text-gray-700'}`}>{currentAdmin.displayName}</span>
                                    <span
                                        className={`shrink-0 rounded px-1.5 py-0.5 text-[10px] font-bold ${
                                            currentAdmin.role === 'SuperAdmin'
                                                ? 'bg-purple-100 text-purple-700 dark:bg-purple-500/20 dark:text-purple-300'
                                                : currentAdmin.role === 'Assistant'
                                                    ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-500/20 dark:text-emerald-300'
                                                    : 'bg-blue-100 text-blue-700 dark:bg-blue-500/20 dark:text-blue-300'
                                        }`}
                                    >
                                        {currentAdmin.role}
                                    </span>
                                </div>
                                <div
                                    className={`flex h-8 w-8 shrink-0 items-center justify-center overflow-hidden rounded-full font-bold sm:h-10 sm:w-10 ${darkMode ? 'border border-amber-500/20 bg-amber-500/20 text-amber-400' : 'bg-amber-50 text-amber-700'}`}
                                >
                                    {currentAdmin.avatar && (currentAdmin.avatar.startsWith('http') || currentAdmin.avatar.startsWith('data:')) ? (
                                        <img src={currentAdmin.avatar} alt="" className="h-full w-full object-cover" />
                                    ) : (
                                        <span className="text-sm sm:text-base">{currentAdmin.displayName.charAt(0) ?? '?'}</span>
                                    )}
                                </div>
                            </button>
                        )}
                    </div>
                </header>

                <div className="px-3 sm:px-4 lg:px-8 pb-6 sm:pb-8">
                    {renderContent()}
                </div>
            </main>

            {/* Mobile app-style bottom bar: quick access to Daily Wizard & common screens */}
            {isMobile && (
                <nav
                    className={`fixed bottom-0 inset-x-0 z-[45] flex items-stretch justify-around gap-0 border-t backdrop-blur-xl touch-manipulation ${
                        darkMode
                            ? 'border-white/[0.08] bg-[#0a0a0f]/92 text-gray-300'
                            : 'border-stone-200/90 bg-white/95 text-stone-600'
                    }`}
                    style={{ paddingBottom: 'max(0.35rem, env(safe-area-inset-bottom, 0px))' }}
                    aria-label="เมนูลัดมือถือ"
                >
                    {[
                        { id: 'Dashboard', icon: LayoutDashboard, label: 'ภาพรวม' },
                        { id: 'DailyWizard', icon: ClipboardList, label: 'Daily Wizard' },
                        { id: 'DataList', icon: List, label: 'รายการ' },
                        { id: '__menu__', icon: Menu, label: 'เมนู' },
                    ].map((item) => {
                        const active = item.id !== '__menu__' && activeMenu === item.id;
                        const Icon = item.icon;
                        return (
                            <button
                                key={item.id}
                                type="button"
                                onClick={() => {
                                    if (item.id === '__menu__') {
                                        setIsSidebarOpen(true);
                                        return;
                                    }
                                    handleMenuClick(item.id);
                                }}
                                className={`flex min-w-0 flex-1 flex-col items-center justify-center gap-0.5 py-2 text-[10px] font-semibold leading-tight transition-colors ${
                                    active
                                        ? darkMode
                                            ? 'text-amber-400'
                                            : 'text-amber-700'
                                        : darkMode
                                          ? 'text-gray-500 active:bg-white/[0.06]'
                                          : 'text-stone-500 active:bg-stone-100'
                                }`}
                            >
                                <Icon size={22} strokeWidth={active ? 2.5 : 2} className="shrink-0" aria-hidden />
                                <span className="truncate px-0.5">{item.label}</span>
                            </button>
                        );
                    })}
                </nav>
            )}
        </div>
    );
}

export default App;
