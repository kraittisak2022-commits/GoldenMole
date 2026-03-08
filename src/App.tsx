import { useState, useEffect, useCallback, useRef } from 'react';
import { LayoutDashboard, UserCheck, Users, Truck, Fuel, Wrench, MapPin, Zap, Wallet, Banknote, List, Settings, User, MoreHorizontal, ClipboardList, Menu, X, Shield, LogOut, Sun, Moon, Loader2 } from 'lucide-react';
import { AppSettings, Employee, Transaction, LandProject, AdminUser, AdminLog } from './types';
import Toast from './components/ui/Toast';
import Card from './components/ui/Card';
import FormatNumber from './components/ui/FormatNumber';
import { Trash2 } from 'lucide-react';

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
import DailyLogModule from './modules/DailyLog';
import DailyStepRecorder from './modules/Dashboard/DailyStepRecorder';
import LoginPage from './modules/Auth/LoginPage';
import AdminModule from './modules/Admin/AdminModule';

import { getToday, formatDateBE } from './utils';

// Supabase Services
import * as db from './services/dataService';

// --- Default Admin Account ---
const DEFAULT_ADMINS: AdminUser[] = [
    { id: 'admin-1', username: 'admin', password: '1234', displayName: 'ผู้ดูแลระบบ', role: 'SuperAdmin', createdAt: '2024-01-01' }
];

// --- Mock Data ---
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
    landGroups: ['โครงการหนองจอก', 'โครงการลาดกระบัง']
};
const MOCK_TRANSACTIONS: Transaction[] = [
    { id: '1', date: getToday(), type: 'Expense', category: 'Fuel', description: 'เติมน้ำมัน (ดีเซล)', amount: 2000, quantity: 60, unit: 'ลิตร', vehicleId: 'รถดรัมโอเว่น', fuelType: 'Diesel' },
    { id: '2', date: getToday(), type: 'Income', category: 'Income', description: 'ขายทราย 10 คิว', amount: 5000, quantity: 10, unit: 'คิว' },
    { id: '3', date: getToday(), type: 'Expense', category: 'Labor', subCategory: 'Attendance', description: 'งาน: ล้างทราย', amount: 1500, employeeIds: ['1', '2', '4'], laborStatus: 'Work', workType: 'FullDay' },
];

const MENU_ITEMS = [
    { id: 'Dashboard', icon: LayoutDashboard, l: 'ภาพรวม' },
    { id: 'DailyWizard', icon: ClipboardList, l: 'บันทึกงานประจำวัน' },
    { id: 'Employees', icon: UserCheck, l: 'พนักงาน' },
    { id: 'Labor', icon: Users, l: 'ค่าแรง/ลา' },
    { id: 'Vehicle', icon: Truck, l: 'การใช้รถ' },
    { id: 'DailyLog', icon: ClipboardList, l: 'บันทึกประจำวัน' },
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

const RecordManager = ({ transactions, setTransactions }: { transactions: Transaction[], setTransactions: any }) => (
    <Card className="p-0 overflow-hidden animate-fade-in">
        <div className="p-3 sm:p-4 bg-slate-50 border-b"><h3 className="font-bold">รายการบันทึกทั้งหมด</h3></div>
        <div className="max-h-[600px] overflow-y-auto overflow-x-auto">
            <table className="w-full text-sm text-left min-w-[500px]">
                <thead className="bg-white sticky top-0"><tr><th className="p-2 sm:p-4">Date</th><th className="p-2 sm:p-4">Desc</th><th className="p-2 sm:p-4 text-right">Amount</th><th className="p-2 sm:p-4"></th></tr></thead>
                <tbody>
                    {transactions.map(t => (
                        <tr key={t.id} className="border-b hover:bg-slate-50">
                            <td className="p-2 sm:p-4 whitespace-nowrap">{formatDateBE(t.date)}</td>
                            <td className="p-2 sm:p-4">{t.description}</td>
                            <td className={`p-2 sm:p-4 text-right font-bold whitespace-nowrap ${t.type === 'Income' ? 'text-emerald-600' : 'text-red-500'}`}><FormatNumber value={t.amount} /></td>
                            <td className="p-2 sm:p-4 text-center">
                                <button onClick={() => { if (confirm('Delete?')) setTransactions(transactions.filter(x => x.id !== t.id)) }}><Trash2 size={16} className="text-slate-400 hover:text-red-500" /></button>
                            </td>
                        </tr>
                    ))}
                </tbody>
            </table>
        </div>
    </Card>
);

function App() {
    // --- Auth State ---
    const [isLoggedIn, setIsLoggedIn] = useState(false);
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
    const [toast, setToast] = useState<string | null>(null);
    const [isLoading, setIsLoading] = useState(true);
    const hasSeeded = useRef(false);

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
            timestamp: new Date().toLocaleString('th-TH'),
        };
        setAdminLogs(prev => [log, ...prev]);
        db.saveAdminLog(log);
    }, [currentAdmin]);

    const handleLogin = (admin: AdminUser) => {
        const updatedAdmin = { ...admin, lastLogin: new Date().toLocaleString('th-TH') };
        setAdmins(prev => prev.map(a => a.id === admin.id ? updatedAdmin : a));
        setCurrentAdmin(updatedAdmin);
        setIsLoggedIn(true);
        db.saveAdmin(updatedAdmin);
        // Log the login event
        const log: AdminLog = {
            id: Date.now().toString(),
            adminId: admin.id,
            adminName: admin.displayName,
            action: 'login',
            details: `เข้าสู่ระบบสำเร็จ`,
            timestamp: new Date().toLocaleString('th-TH'),
        };
        setAdminLogs(prev => [log, ...prev]);
        db.saveAdminLog(log);
    };

    const handleLogout = () => {
        if (currentAdmin) {
            addLog('logout', 'ออกจากระบบ');
        }
        setIsLoggedIn(false);
        setCurrentAdmin(null);
        setActiveMenu('Dashboard');
    };

    const handleMenuClick = useCallback((menuId: string) => {
        setActiveMenu(menuId);
        if (isMobile) setIsSidebarOpen(false);
    }, [isMobile]);

    const handleSave = (t: Transaction) => {
        setTransactions(p => [...p, t]);
        db.saveTransaction(t);
        setToast('บันทึกสำเร็จ');
        setTimeout(() => setToast(null), 3000);
    };

    // --- Wrapped setters that persist to Supabase ---
    const handleSetEmployees = useCallback((updater: Employee[] | ((prev: Employee[]) => Employee[])) => {
        setEmployees(prev => {
            const next = typeof updater === 'function' ? updater(prev) : updater;
            // Persist changes: save any new/updated employees
            next.forEach(emp => db.saveEmployee(emp));
            // Delete removed employees
            const nextIds = new Set(next.map(e => e.id));
            prev.forEach(emp => { if (!nextIds.has(emp.id)) db.deleteEmployee(emp.id); });
            return next;
        });
    }, []);

    const handleSetTransactions = useCallback((updater: Transaction[] | ((prev: Transaction[]) => Transaction[])) => {
        setTransactions(prev => {
            const next = typeof updater === 'function' ? updater(prev) : updater;
            // Delete removed transactions
            const nextIds = new Set(next.map(t => t.id));
            prev.forEach(t => { if (!nextIds.has(t.id)) db.deleteTransaction(t.id); });
            return next;
        });
    }, []);

    const handleDeleteTransaction = useCallback((id: string) => {
        setTransactions(prev => prev.filter(t => t.id !== id));
        db.deleteTransaction(id);
    }, []);

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

    const renderContent = () => {
        switch (activeMenu) {
            case 'Dashboard': return <Dashboard transactions={transactions} settings={settings} employees={employees} onSaveTransaction={handleSave} onDeleteTransaction={handleDeleteTransaction} />;
            case 'Employees': return <EmployeeManager employees={employees} setEmployees={handleSetEmployees} transactions={transactions} />;
            case 'Labor': return <LaborModule employees={employees} settings={settings} onSaveTransaction={handleSave} transactions={transactions} setTransactions={handleSetTransactions} />;
            case 'Vehicle': return <VehicleEntry settings={settings} employees={employees} onSave={handleSave} />;
            case 'Fuel': return <GeneralEntry type="Fuel" settings={settings} onSave={handleSave} transactions={transactions} />;
            case 'Maintenance': return <GeneralEntry type="Maintenance" settings={settings} onSave={handleSave} transactions={transactions} />;
            case 'Utilities': return <GeneralEntry type="Utilities" settings={settings} onSave={handleSave} transactions={transactions} />;
            case 'Land': return <LandModule projects={projects} setProjects={handleSetProjects} onSave={handleSave} transactions={transactions} />;
            case 'Income': return <IncomeEntry settings={settings} onSave={handleSave} transactions={transactions} />;
            case 'Payroll': return <PayrollModule employees={employees} transactions={transactions} onSaveTransaction={handleSave} />;
            case 'DataList': return <RecordManager transactions={transactions} setTransactions={handleSetTransactions} />;
            case 'DailyLog': return <DailyLogModule settings={settings} onSaveTransaction={handleSave} transactions={transactions} employees={employees} />;
            case 'DailyWizard': return <DailyStepRecorder employees={employees} settings={settings} transactions={transactions} onSaveTransaction={handleSave} onDeleteTransaction={handleDeleteTransaction} />;
            case 'AdminManagement': return currentAdmin ? <AdminModule admins={admins} setAdmins={handleSetAdmins} currentAdmin={currentAdmin} logs={adminLogs} addLog={addLog} /> : null;
            case 'Settings': return <SettingsModule settings={settings} setSettings={handleSetSettings} />;
            default: return <div className="p-8 text-center text-slate-400">Coming Soon</div>;
        }
    };

    // --- LOADING STATE ---
    if (isLoading) {
        return (
            <div className="flex items-center justify-center min-h-screen bg-[#0a0a0f]">
                <div className="text-center">
                    <Loader2 className="w-12 h-12 text-amber-400 animate-spin mx-auto mb-4" />
                    <p className="text-gray-400 text-sm">กำลังโหลดข้อมูล...</p>
                </div>
            </div>
        );
    }

    // --- LOGIN GATE ---
    if (!isLoggedIn) {
        return <LoginPage admins={admins} onLogin={handleLogin} appName={settings.appName} appIcon={darkMode && settings.appIconDark ? settings.appIconDark : settings.appIcon} darkMode={darkMode} onToggleDarkMode={() => setDarkMode(!darkMode)} />;
    }

    const activeMenuItem = MENU_ITEMS.find(m => m.id === activeMenu);

    return (
        <div className={`flex min-h-screen min-h-[100dvh] font-sans transition-colors duration-300 relative overflow-hidden ${darkMode ? 'dark bg-[#0a0a0f] text-gray-100' : 'bg-[#FAFAF8] text-gray-800'}`}>

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

            {/* Mobile Overlay Backdrop */}
            {isMobile && isSidebarOpen && (
                <div
                    className="fixed inset-0 bg-black/50 z-40 transition-opacity duration-300 backdrop-blur-sm"
                    onClick={() => setIsSidebarOpen(false)}
                />
            )}

            {/* Sidebar */}
            <aside className={`
                fixed top-0 left-0 h-screen z-50 flex flex-col
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
                        </div>
                    )}
                    {isMobile && (
                        <button onClick={() => setIsSidebarOpen(false)} className={`p-1.5 rounded-lg shrink-0 ${darkMode ? 'hover:bg-gray-800 text-gray-400' : 'hover:bg-stone-100 text-stone-400'}`}>
                            <X size={20} />
                        </button>
                    )}
                </div>
                <nav className="flex-1 py-4 sm:py-6 px-2 sm:px-3 space-y-1 overflow-y-auto hide-scrollbar">
                    {MENU_ITEMS.map(m => (
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
                            <div className="flex items-center gap-2 px-2 mb-2">
                                <div className={`w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold shrink-0 ${darkMode ? 'bg-amber-500/20 text-amber-400' : 'bg-amber-50 text-amber-700'}`}>
                                    {currentAdmin.displayName.charAt(0)}
                                </div>
                                <div className="min-w-0">
                                    <p className={`text-xs font-medium truncate ${darkMode ? 'text-gray-300' : 'text-gray-700'}`}>{currentAdmin.displayName}</p>
                                    <p className="text-[10px] text-slate-400">{currentAdmin.role}</p>
                                </div>
                            </div>
                        )}
                        <div className="flex gap-2">
                            <button onClick={() => setIsSidebarOpen(!isSidebarOpen)} className={`flex-1 flex items-center justify-center p-2 rounded-lg ${darkMode ? 'hover:bg-gray-800 text-gray-500' : 'hover:bg-stone-50 text-stone-400'}`}>
                                <MoreHorizontal size={18} />
                            </button>
                            <button onClick={handleLogout} className="flex items-center justify-center p-2 hover:bg-red-50 rounded-lg text-slate-400 hover:text-red-500 transition-colors" title="ออกจากระบบ">
                                <LogOut size={18} />
                            </button>
                        </div>
                    </div>
                )}

                {/* Sidebar Footer — Logout (Mobile) */}
                {isMobile && (
                    <div className={`p-4 border-t ${darkMode ? 'border-gray-800' : ''}`}>
                        {currentAdmin && (
                            <div className="flex items-center gap-3 px-2 mb-3">
                                <div className={`w-9 h-9 rounded-full flex items-center justify-center font-bold shrink-0 ${darkMode ? 'bg-amber-500/20 text-amber-400' : 'bg-amber-50 text-amber-700'}`}>
                                    {currentAdmin.displayName.charAt(0)}
                                </div>
                                <div className="min-w-0 flex-1">
                                    <p className={`text-sm font-medium truncate ${darkMode ? 'text-gray-300' : 'text-gray-700'}`}>{currentAdmin.displayName}</p>
                                    <p className="text-xs text-slate-400">@{currentAdmin.username} • {currentAdmin.role}</p>
                                </div>
                            </div>
                        )}
                        <button onClick={handleLogout} className="w-full flex items-center justify-center gap-2 px-4 py-2.5 bg-red-50 text-red-600 rounded-xl text-sm font-medium hover:bg-red-100 transition-colors">
                            <LogOut size={16} /> ออกจากระบบ
                        </button>
                    </div>
                )}
            </aside>

            {/* Main Content */}
            <main className="flex-1 min-w-0 overflow-y-auto">
                {/* Header */}
                <header className="flex justify-between items-center p-3 sm:p-4 lg:p-8 lg:pb-0 mb-2 lg:mb-8">
                    <div className="flex items-center gap-3">
                        {isMobile && (
                            <button
                                onClick={() => setIsSidebarOpen(true)}
                                className="p-2 hover:bg-slate-100 rounded-xl text-slate-600 transition-colors"
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
                            <div className={`hidden sm:flex items-center gap-2 text-sm ${darkMode ? 'text-gray-400' : 'text-stone-500'}`}>
                                <span className={`font-medium ${darkMode ? 'text-gray-200' : 'text-gray-700'}`}>{currentAdmin.displayName}</span>
                                <span className={`px-1.5 py-0.5 rounded text-[10px] font-bold ${currentAdmin.role === 'SuperAdmin' ? 'bg-purple-100 text-purple-700' : 'bg-blue-100 text-blue-700'}`}>
                                    {currentAdmin.role}
                                </span>
                            </div>
                        )}
                        <div className={`w-8 h-8 sm:w-10 sm:h-10 rounded-full flex items-center justify-center font-bold ${darkMode ? 'bg-amber-500/20 text-amber-400 border border-amber-500/20' : 'bg-amber-50 text-amber-700'}`}>
                            <User size={18} />
                        </div>
                    </div>
                </header>

                <div className="px-3 sm:px-4 lg:px-8 pb-6 sm:pb-8">
                    {renderContent()}
                </div>
            </main>
        </div>
    );
}

export default App;
