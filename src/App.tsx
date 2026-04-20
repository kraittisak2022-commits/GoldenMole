import { useState, useEffect, useCallback, useRef, useMemo } from 'react';
import { LayoutDashboard, UserCheck, Users, Truck, Fuel, Wrench, MapPin, Zap, Wallet, Banknote, List, Settings, MoreHorizontal, ClipboardList, Menu, X, Shield, LogOut, Sun, Moon, Loader2, Smartphone } from 'lucide-react';
import { AppSettings, Employee, Transaction, LandProject, AdminUser, AdminLog, AdminUiTheme } from './types';
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
import PayrollModule from './modules/Payroll/PayrollModule';
import SettingsModule from './modules/Settings/SettingsModule';
import MaintenanceModule from './modules/Maintenance/MaintenanceModule';
import DailyStepRecorder from './modules/Dashboard/DailyStepRecorder';
import LoginPage from './modules/Auth/LoginPage';
import FirstLoginPasswordChange from './modules/Auth/FirstLoginPasswordChange';
import PostLoginModeSelect from './modules/Auth/PostLoginModeSelect';
import MobileFieldApp from './modules/Mobile/MobileFieldApp';
import RecordManager from './modules/DataList/RecordManager';
import AdminModule from './modules/Admin/AdminModule';
import Button from './components/ui/Button';
import AdminProfileModal from './components/AdminProfileModal';

import { getToday, formatDateBE, normalizeDate, formatDateTimeTH } from './utils';
import { hashPasswordForStorage, needsPasswordRehash, validateNewPasswordPolicy, verifyStoredPassword } from './utils/passwordAuth';

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
    appDefaults: { sandCubicPerTrip: 3 },
};
const MOCK_TRANSACTIONS: Transaction[] = [
    { id: '1', date: getToday(), type: 'Expense', category: 'Fuel', description: 'เติมน้ำมัน (ดีเซล)', amount: 2000, quantity: 60, unit: 'L', vehicleId: 'รถดรัมโอเว่น', fuelType: 'Diesel', fuelMovement: 'stock_out' },
    { id: '2', date: getToday(), type: 'Income', category: 'Income', description: 'ขายทราย 10 คิว', amount: 5000, quantity: 10, unit: 'คิว' },
    { id: '3', date: getToday(), type: 'Expense', category: 'Labor', subCategory: 'Attendance', description: 'งาน: ล้างทราย', amount: 1500, employeeIds: ['1', '2', '4'], laborStatus: 'Work', workType: 'FullDay' },
];

const MENU_ITEMS = [
    { id: 'Dashboard', icon: LayoutDashboard, l: 'ภาพรวม' },
    { id: 'DailyWizard', icon: ClipboardList, l: 'บันทึกงานประจำวัน (Daily Wizard)' },
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
    const [clientSurface, setClientSurface] = useState<'select' | 'desktop' | 'mobile'>('select');
    const [currentAdmin, setCurrentAdmin] = useState<AdminUser | null>(null);
    const [admins, setAdmins] = useState<AdminUser[]>([]);
    const [adminLogs, setAdminLogs] = useState<AdminLog[]>([]);

    // --- App State ---
    const [activeMenu, setActiveMenu] = useState('Dashboard');
    const [isSidebarOpen, setIsSidebarOpen] = useState(false);
    const [isMobile, setIsMobile] = useState(false);
    const [darkMode, setDarkMode] = useState(false);
    const [employees, setEmployees] = useState<Employee[]>([]);
    const [transactions, setTransactions] = useState<Transaction[]>([]);
    const [projects, setProjects] = useState<LandProject[]>([]);
    const [settings, setSettings] = useState<AppSettings>(MOCK_SETTINGS);
    const latestVersionNote = (settings.versionNotes && settings.versionNotes.length > 0)
        ? settings.versionNotes[settings.versionNotes.length - 1]
        : (autoVersionNotes[0] || 'พร้อมใช้งาน');
    const [toast, setToast] = useState<string | null>(null);
    const [accountModalOpen, setAccountModalOpen] = useState(false);
    const [isLoading, setIsLoading] = useState(true);
    const [pendingForcedPasswordAdmin, setPendingForcedPasswordAdmin] = useState<AdminUser | null>(null);
    const hasSeeded = useRef(false);
    const hasAutoVersionSynced = useRef(false);
    const currentAdminRef = useRef<AdminUser | null>(null);
    useEffect(() => {
        currentAdminRef.current = currentAdmin;
    }, [currentAdmin]);

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
        const loadData = async () => {
            try {
                setIsLoading(true);

                // Seed default data if needed (only once)
                if (!hasSeeded.current) {
                    hasSeeded.current = true;
                    await db.seedDefaultData(MOCK_EMPLOYEES, MOCK_TRANSACTIONS, MOCK_PROJECTS, MOCK_SETTINGS, DEFAULT_ADMINS);
                }

                // Load all data in parallel
                const [emps, txs, projs, sett, adms, logs] = await Promise.all([
                    db.fetchEmployees(),
                    db.fetchTransactions(),
                    db.fetchProjects(),
                    db.fetchSettings(),
                    db.fetchAdmins(),
                    db.fetchAdminLogs(),
                ]);

                setEmployees(emps);
                setTransactions(txs);
                setProjects(projs);
                if (sett) setSettings(sett);
                setAdmins(adms.length > 0 ? adms : DEFAULT_ADMINS);
                setAdminLogs(logs);
            } catch (err) {
                console.error('Failed to load data from Supabase:', err);
                // Fallback to mock data
                setEmployees(MOCK_EMPLOYEES);
                setTransactions(MOCK_TRANSACTIONS);
                setProjects(MOCK_PROJECTS);
                setSettings(MOCK_SETTINGS);
                setAdmins(DEFAULT_ADMINS);
            } finally {
                setIsLoading(false);
            }
        };
        loadData();
    }, []);

    const applyUiThemeToApp = useCallback((ui: AdminUiTheme | undefined) => {
        setDarkMode(resolveDarkFromUiTheme(ui));
    }, []);

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

    // Detect mobile vs desktop
    useEffect(() => {
        const checkMobile = () => {
            const mobile = window.innerWidth < 1024;
            setIsMobile(mobile);
            setIsSidebarOpen(!mobile);
        };
        checkMobile();
        window.addEventListener('resize', checkMobile);
        return () => window.removeEventListener('resize', checkMobile);
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

    const finalizeSuccessfulLogin = useCallback(async (updatedAdmin: AdminUser) => {
        setClientSurface('select');
        setAdmins(prev => prev.map(a => a.id === updatedAdmin.id ? updatedAdmin : a));
        setCurrentAdmin(updatedAdmin);
        setIsLoggedIn(true);
        await db.saveAdmin(updatedAdmin);
        const log: AdminLog = {
            id: Date.now().toString(),
            adminId: updatedAdmin.id,
            adminName: updatedAdmin.displayName,
            action: 'login',
            details: `สถานะ: สำเร็จ | เหตุการณ์: เข้าสู่ระบบ`,
            timestamp: formatDateTimeTH(),
        };
        setAdminLogs(prev => [log, ...prev]);
        db.saveAdminLog(log);
    }, []);

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
        if (currentAdmin) {
            addLog('logout', 'สถานะ: สำเร็จ | เหตุการณ์: ออกจากระบบ');
        }
        setIsLoggedIn(false);
        setCurrentAdmin(null);
        setClientSurface('select');
        setActiveMenu('Dashboard');
    };

    /** ออกจากระบบอัตโนมัติเมื่อไม่มีการใช้งาน (คลิก/พิมพ์/เลื่อน) เกินกำหนด */
    const SESSION_IDLE_MS = 45 * 60 * 1000;
    useEffect(() => {
        if (!isLoggedIn) return;
        const idleLastRef = { current: Date.now() };
        const bump = () => {
            idleLastRef.current = Date.now();
        };
        const events: (keyof WindowEventMap)[] = ['mousedown', 'keydown', 'scroll', 'touchstart', 'click'];
        events.forEach(ev => window.addEventListener(ev, bump as EventListener, { passive: true }));
        const tick = window.setInterval(() => {
            if (Date.now() - idleLastRef.current < SESSION_IDLE_MS) return;
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
            setIsLoggedIn(false);
            setCurrentAdmin(null);
            setClientSurface('select');
            setActiveMenu('Dashboard');
            setToast('ออกจากระบบอัตโนมัติ — ไม่มีการใช้งานเกิน 45 นาที กรุณาเข้าสู่ระบบใหม่');
            setTimeout(() => setToast(null), 6000);
        }, 30_000);
        return () => {
            events.forEach(ev => window.removeEventListener(ev, bump as EventListener));
            window.clearInterval(tick);
        };
    }, [isLoggedIn]);

    const handleMenuClick = useCallback((menuId: string) => {
        setActiveMenu(menuId);
        if (isMobile) setIsSidebarOpen(false);
    }, [isMobile]);

    const handleSave = async (t: Transaction) => {
        setTransactions(p => [...p, t]);
        const ok = await db.saveTransaction(t);

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
            addLog('create_transaction', `สร้างรายการ: ${t.category}/${t.subCategory || '-'} วันที่ ${normalizeDate(t.date)} จำนวนเงิน ${t.amount || 0} รายละเอียด: ${t.description || '-'} | snapshot=${JSON.stringify(summary)}`);
        }

        setToast(ok ? 'บันทึกสำเร็จ' : 'เกิดข้อผิดพลาดในการบันทึก กรุณาลองใหม่');
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
        setTransactions(prev => {
            const target = prev.find(t => t.id === id);
            if (target && currentAdmin) {
                const snap = {
                    id: target.id,
                    date: normalizeDate(target.date),
                    type: target.type,
                    category: target.category,
                    subCategory: target.subCategory,
                    amount: target.amount,
                    description: target.description,
                };
                addLog('delete_transaction', `ลบรายการ: ${target.category}/${target.subCategory || '-'} วันที่ ${normalizeDate(target.date)} จำนวนเงิน ${target.amount || 0} รายละเอียด: ${target.description || '-'} | before=${JSON.stringify(snap)}`);
            }
            return prev.filter(t => t.id !== id);
        });
        db.deleteTransaction(id);
    }, [addLog, currentAdmin]);

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

    /** ล้างข้อมูลที่บันทึกทั้งหมด (ธุรกรรม + โครงการที่ดิน) ไม่ลบพนักงานและตั้งค่า */
    const handleClearAllData = useCallback(async () => {
        if (!confirm('ต้องการล้างข้อมูลที่บันทึกทั้งหมด (รายการธุรกรรม + โครงการที่ดิน) หรือไม่?\n\nข้อมูลพนักงานและตั้งค่าจะไม่ถูกลบ')) return;
        try {
            if (currentAdmin) {
                addLog('clear_daily_data', 'การดำเนินการ: ล้างข้อมูลที่บันทึกทั้งหมด | ครอบคลุม: ธุรกรรม + โครงการที่ดิน | ต้นทาง: เมนู การตั้งค่า');
            }
            await db.deleteAllTransactions();
            await db.deleteAllProjects();
            setTransactions([]);
            setProjects([]);
            setToast('ล้างข้อมูลที่บันทึกทั้งหมดแล้ว');
            setTimeout(() => setToast(null), 3000);
        } catch (e) {
            console.error(e);
            setToast('เกิดข้อผิดพลาดในการล้างข้อมูล');
            setTimeout(() => setToast(null), 3000);
        }
    }, []);

    const renderContent = () => {
        switch (activeMenu) {
            case 'Dashboard': return <Dashboard transactions={transactions} settings={settings} employees={employees} onSaveTransaction={handleSave} onDeleteTransaction={handleDeleteTransaction} isMobile={isMobile} />;
            case 'Employees': return <EmployeeManager employees={employees} setEmployees={handleSetEmployees} transactions={transactions} settings={settings} setSettings={handleSetSettings} />;
            case 'Labor': return <LaborModule employees={employees} settings={settings} onSaveTransaction={handleSave} onDeleteTransaction={handleDeleteTransaction} transactions={transactions} setTransactions={handleSetTransactions} ensureEmployeeWage={ensureEmployeeWage} />;
            case 'Vehicle': return <VehicleEntry settings={settings} employees={employees} transactions={transactions} onSave={handleSave} onDelete={handleDeleteTransaction} />;
            case 'Fuel': return <GeneralEntry type="Fuel" settings={settings} setSettings={handleSetSettings} onSave={handleSave} onDelete={handleDeleteTransaction} transactions={transactions} />;
            case 'Maintenance': return <MaintenanceModule settings={settings} transactions={transactions} onSave={handleSave} onDelete={handleDeleteTransaction} />;
            case 'Utilities': return <GeneralEntry type="Utilities" settings={settings} onSave={handleSave} onDelete={handleDeleteTransaction} transactions={transactions} />;
            case 'Land': return <LandModule projects={projects} setProjects={handleSetProjects} onSave={handleSave} transactions={transactions} />;
            case 'Income': return <IncomeEntry settings={settings} onSave={handleSave} onDelete={handleDeleteTransaction} transactions={transactions} />;
            case 'Payroll': return <PayrollModule employees={employees} transactions={transactions} onSaveTransaction={handleSave} />;
            case 'DataList': return <RecordManager transactions={transactions} onDeleteTransaction={handleDeleteTransaction} />;
            case 'DailyWizard': return <DailyStepRecorder mobileShell={isMobile} employees={employees} settings={settings} transactions={transactions} onSaveTransaction={handleSave} onDeleteTransaction={handleDeleteTransaction} ensureEmployeeWage={ensureEmployeeWage} />;
            case 'AdminManagement': return currentAdmin?.role === 'SuperAdmin' ? <AdminModule admins={admins} setAdmins={handleSetAdmins} currentAdmin={currentAdmin} logs={adminLogs} addLog={addLog} /> : <div className="p-8 text-center text-slate-500 dark:text-slate-400">ไม่มีสิทธิ์เข้าถึง — เฉพาะ SuperAdmin เท่านั้น</div>;
            case 'Settings': return (
                <SettingsModule
                    settings={settings}
                    setSettings={handleSetSettings}
                    autoVersionNotes={autoVersionNotes}
                    onClearAllData={handleClearAllData}
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
                <div className="text-center">
                    <Loader2 className="w-12 h-12 text-amber-400 animate-spin mx-auto mb-4" />
                    <p className="text-gray-400 text-sm">กำลังโหลดข้อมูล...</p>
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
                <PostLoginModeSelect
                    appName={settings.appName}
                    appIcon={darkMode && settings.appIconDark ? settings.appIconDark : settings.appIcon}
                    currentAdmin={currentAdmin}
                    darkMode={darkMode}
                    onToggleDarkMode={() => setDarkMode(!darkMode)}
                    onChooseMobile={() => setClientSurface('mobile')}
                    onChooseDesktop={() => setClientSurface('desktop')}
                />
            </>
        );
    }

    if (currentAdmin && clientSurface === 'mobile') {
        return (
            <>
                {toast && <div className="relative z-50"><Toast message={toast} onClose={() => setToast(null)} /></div>}
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
                <MobileFieldApp
                    settings={settings}
                    employees={employees}
                    transactions={transactions}
                    admins={admins}
                    adminLogs={adminLogs}
                    currentAdmin={currentAdmin}
                    appVersion={appVersion}
                    latestVersionNote={latestVersionNote}
                    autoVersionNotes={autoVersionNotes}
                    appIcon={darkMode && settings.appIconDark ? settings.appIconDark : settings.appIcon}
                    darkMode={darkMode}
                    onToggleDarkMode={() => setDarkMode(!darkMode)}
                    onLogout={handleLogout}
                    onSwitchToDesktop={() => setClientSurface('desktop')}
                    onOpenAccount={() => setAccountModalOpen(true)}
                    onSaveTransaction={handleSave}
                    onDeleteTransaction={handleDeleteTransaction}
                    handleSetTransactions={handleSetTransactions}
                    ensureEmployeeWage={ensureEmployeeWage}
                    handleSetSettings={handleSetSettings}
                    handleSetAdmins={handleSetAdmins}
                    onClearAllData={handleClearAllData}
                    onUpdateAdminProfile={handleUpdateAdminProfile}
                    addLog={addLog}
                />
            </>
        );
    }

    const activeMenuItem = MENU_ITEMS.find(m => m.id === activeMenu);

    return (
        <div className={`flex min-h-screen min-h-[100dvh] font-sans transition-colors duration-300 relative overflow-hidden max-w-full ${darkMode ? 'dark bg-[#0a0a0f] text-gray-100' : 'bg-[#FAFAF8] text-gray-800'}`}>

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
                    {MENU_ITEMS.filter(m => m.id !== 'AdminManagement' || currentAdmin?.role === 'SuperAdmin').map(m => (
                        <button
                            key={m.id}
                            onClick={() => handleMenuClick(m.id)}
                            className={`w-full flex items-center gap-3 px-3 py-3 rounded-xl transition-all ${activeMenu === m.id
                                ? (darkMode ? 'bg-amber-500/10 text-amber-400 font-bold shadow-sm border border-amber-500/20' : 'bg-stone-50 text-gray-900 font-bold shadow-sm')
                                : (darkMode ? 'text-gray-500 hover:bg-gray-800/50 hover:text-gray-300' : 'text-gray-500 hover:bg-stone-50')
                                }`}
                        >
                            <m.icon size={20} className={`shrink-0 ${activeMenu === m.id ? (darkMode ? 'text-amber-400' : 'text-amber-600') : ''}`} />
                            {(isSidebarOpen || isMobile) && <span className="text-sm truncate">{m.l}</span>}
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
                            <button type="button" onClick={() => setClientSurface('mobile')} className={`flex items-center justify-center p-2 rounded-lg ${darkMode ? 'hover:bg-emerald-500/10 text-emerald-400' : 'hover:bg-emerald-50 text-emerald-700'}`} title="โหมดมือถือ (กรอกข้อมูลง่าย)">
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
                        <button type="button" onClick={() => { setClientSurface('mobile'); setIsSidebarOpen(false); }} className={`mb-2 w-full flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl text-sm font-medium transition-colors ${darkMode ? 'bg-emerald-500/15 text-emerald-300 hover:bg-emerald-500/25' : 'bg-emerald-50 text-emerald-800 hover:bg-emerald-100'}`}>
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
