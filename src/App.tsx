import { useState, useEffect, useCallback } from 'react';
import { LayoutDashboard, UserCheck, Users, Truck, Fuel, Wrench, MapPin, Zap, Wallet, Banknote, List, Settings, User, MoreHorizontal, ClipboardList, Menu, X, Shield, LogOut, Sun, Moon } from 'lucide-react';
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

import { getToday } from './utils';

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
    appName: 'Goldenmole Dashboard', appSubtext: 'ระบบจัดการ', appIcon: 'GM',
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
                            <td className="p-2 sm:p-4 whitespace-nowrap">{t.date}</td>
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
    const [admins, setAdmins] = useState<AdminUser[]>(DEFAULT_ADMINS);
    const [adminLogs, setAdminLogs] = useState<AdminLog[]>([]);

    // --- App State ---
    const [activeMenu, setActiveMenu] = useState('Dashboard');
    const [isSidebarOpen, setIsSidebarOpen] = useState(false);
    const [isMobile, setIsMobile] = useState(false);
    const [darkMode, setDarkMode] = useState(false);
    const [employees, setEmployees] = useState(MOCK_EMPLOYEES);
    const [transactions, setTransactions] = useState(MOCK_TRANSACTIONS);
    const [projects, setProjects] = useState<LandProject[]>(MOCK_PROJECTS);
    const [settings, setSettings] = useState(MOCK_SETTINGS);
    const [toast, setToast] = useState<string | null>(null);

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
    }, [currentAdmin]);

    const handleLogin = (admin: AdminUser) => {
        const updatedAdmin = { ...admin, lastLogin: new Date().toLocaleString('th-TH') };
        setAdmins(prev => prev.map(a => a.id === admin.id ? updatedAdmin : a));
        setCurrentAdmin(updatedAdmin);
        setIsLoggedIn(true);
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

    const handleSave = (t: Transaction) => { setTransactions(p => [...p, t]); setToast('บันทึกสำเร็จ'); setTimeout(() => setToast(null), 3000); };

    const renderContent = () => {
        switch (activeMenu) {
            case 'Dashboard': return <Dashboard transactions={transactions} settings={settings} employees={employees} onSaveTransaction={handleSave} onDeleteTransaction={(id: string) => setTransactions((prev: Transaction[]) => prev.filter(t => t.id !== id))} />;
            case 'Employees': return <EmployeeManager employees={employees} setEmployees={setEmployees} transactions={transactions} />;
            case 'Labor': return <LaborModule employees={employees} settings={settings} onSaveTransaction={handleSave} transactions={transactions} setTransactions={setTransactions} />;
            case 'Vehicle': return <VehicleEntry settings={settings} employees={employees} onSave={handleSave} />;
            case 'Fuel': return <GeneralEntry type="Fuel" settings={settings} onSave={handleSave} transactions={transactions} />;
            case 'Maintenance': return <GeneralEntry type="Maintenance" settings={settings} onSave={handleSave} transactions={transactions} />;
            case 'Utilities': return <GeneralEntry type="Utilities" settings={settings} onSave={handleSave} transactions={transactions} />;
            case 'Land': return <LandModule projects={projects} setProjects={setProjects} onSave={handleSave} transactions={transactions} />;
            case 'Income': return <IncomeEntry settings={settings} onSave={handleSave} transactions={transactions} />;
            case 'Payroll': return <PayrollModule employees={employees} transactions={transactions} onSaveTransaction={handleSave} />;
            case 'DataList': return <RecordManager transactions={transactions} setTransactions={setTransactions} />;
            case 'DailyLog': return <DailyLogModule settings={settings} onSaveTransaction={handleSave} transactions={transactions} employees={employees} />;
            case 'DailyWizard': return <DailyStepRecorder employees={employees} settings={settings} transactions={transactions} onSaveTransaction={handleSave} onDeleteTransaction={(id: string) => setTransactions((prev: Transaction[]) => prev.filter(t => t.id !== id))} />;
            case 'AdminManagement': return currentAdmin ? <AdminModule admins={admins} setAdmins={setAdmins} currentAdmin={currentAdmin} logs={adminLogs} addLog={addLog} /> : null;
            case 'Settings': return <SettingsModule settings={settings} setSettings={setSettings} />;
            default: return <div className="p-8 text-center text-slate-400">Coming Soon</div>;
        }
    };

    // --- LOGIN GATE ---
    if (!isLoggedIn) {
        return <LoginPage admins={admins} onLogin={handleLogin} appName={settings.appName} appIcon={settings.appIcon} />;
    }

    const activeMenuItem = MENU_ITEMS.find(m => m.id === activeMenu);

    return (
        <div className={`flex min-h-screen min-h-[100dvh] font-sans transition-colors duration-300 ${darkMode ? 'bg-gray-900 text-gray-100' : 'bg-[#F9FAFB] text-slate-800'}`}>
            {toast && <Toast message={toast} onClose={() => setToast(null)} />}

            {/* Mobile Overlay Backdrop */}
            {isMobile && isSidebarOpen && (
                <div
                    className="fixed inset-0 bg-black/50 z-40 transition-opacity duration-300"
                    onClick={() => setIsSidebarOpen(false)}
                />
            )}

            {/* Sidebar */}
            <aside className={`
                fixed top-0 left-0 h-screen z-50 flex flex-col
                transition-all duration-300 ease-in-out border-r
                ${darkMode ? 'bg-gray-800 border-gray-700' : 'bg-white border-slate-100'}
                ${isMobile
                    ? `w-72 ${isSidebarOpen ? 'translate-x-0 shadow-2xl' : '-translate-x-full'}`
                    : `lg:sticky ${isSidebarOpen ? 'w-64' : 'w-20'}`
                }
            `}>
                <div className={`p-4 sm:p-6 flex items-center gap-3 border-b ${darkMode ? 'border-gray-700' : 'border-slate-50'}`}>
                    <div className={`w-10 h-10 rounded-xl flex items-center justify-center text-white font-bold shadow-lg overflow-hidden shrink-0 ${darkMode ? 'bg-emerald-600' : 'bg-slate-900'}`}>
                        {settings.appIcon.startsWith('http') || settings.appIcon.startsWith('data:') ? (
                            <img src={settings.appIcon} alt="Logo" className="w-full h-full object-cover" />
                        ) : (
                            settings.appIcon
                        )}
                    </div>
                    {(isSidebarOpen || isMobile) && (
                        <div className="flex-1 min-w-0">
                            <h1 className="font-bold text-lg truncate">{settings.appName}</h1>
                            <p className="text-[10px] text-slate-400 uppercase">{settings.appSubtext}</p>
                        </div>
                    )}
                    {isMobile && (
                        <button onClick={() => setIsSidebarOpen(false)} className={`p-1.5 rounded-lg shrink-0 ${darkMode ? 'hover:bg-gray-700 text-gray-400' : 'hover:bg-slate-100 text-slate-400'}`}>
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
                                ? (darkMode ? 'bg-gray-700 text-white font-bold shadow-sm' : 'bg-slate-50 text-slate-900 font-bold shadow-sm')
                                : (darkMode ? 'text-gray-400 hover:bg-gray-700' : 'text-slate-500 hover:bg-slate-50')
                                }`}
                        >
                            <m.icon size={20} className={`shrink-0 ${activeMenu === m.id ? 'text-emerald-500' : ''}`} />
                            {(isSidebarOpen || isMobile) && <span className="text-sm truncate">{m.l}</span>}
                        </button>
                    ))}
                </nav>

                {/* Sidebar Footer — Logout (Desktop) */}
                {!isMobile && (
                    <div className={`p-4 border-t space-y-2 ${darkMode ? 'border-gray-700' : ''}`}>
                        {isSidebarOpen && currentAdmin && (
                            <div className="flex items-center gap-2 px-2 mb-2">
                                <div className="w-7 h-7 rounded-full bg-emerald-100 flex items-center justify-center text-emerald-600 text-xs font-bold shrink-0">
                                    {currentAdmin.displayName.charAt(0)}
                                </div>
                                <div className="min-w-0">
                                    <p className="text-xs font-medium text-slate-700 truncate">{currentAdmin.displayName}</p>
                                    <p className="text-[10px] text-slate-400">{currentAdmin.role}</p>
                                </div>
                            </div>
                        )}
                        <div className="flex gap-2">
                            <button onClick={() => setIsSidebarOpen(!isSidebarOpen)} className={`flex-1 flex items-center justify-center p-2 rounded-lg ${darkMode ? 'hover:bg-gray-700 text-gray-400' : 'hover:bg-slate-50 text-slate-400'}`}>
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
                    <div className={`p-4 border-t ${darkMode ? 'border-gray-700' : ''}`}>
                        {currentAdmin && (
                            <div className="flex items-center gap-3 px-2 mb-3">
                                <div className="w-9 h-9 rounded-full bg-emerald-100 flex items-center justify-center text-emerald-600 font-bold shrink-0">
                                    {currentAdmin.displayName.charAt(0)}
                                </div>
                                <div className="min-w-0 flex-1">
                                    <p className="text-sm font-medium text-slate-700 truncate">{currentAdmin.displayName}</p>
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
                            className={`p-2 rounded-xl transition-all ${darkMode ? 'bg-gray-700 text-yellow-400 hover:bg-gray-600' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'}`}
                            title={darkMode ? 'เปลี่ยนเป็นโหมดสว่าง' : 'เปลี่ยนเป็นโหมดมืด'}
                        >
                            {darkMode ? <Sun size={18} /> : <Moon size={18} />}
                        </button>
                        {currentAdmin && (
                            <div className={`hidden sm:flex items-center gap-2 text-sm ${darkMode ? 'text-gray-400' : 'text-slate-500'}`}>
                                <span className={`font-medium ${darkMode ? 'text-gray-200' : 'text-slate-700'}`}>{currentAdmin.displayName}</span>
                                <span className={`px-1.5 py-0.5 rounded text-[10px] font-bold ${currentAdmin.role === 'SuperAdmin' ? 'bg-purple-100 text-purple-700' : 'bg-blue-100 text-blue-700'}`}>
                                    {currentAdmin.role}
                                </span>
                            </div>
                        )}
                        <div className={`w-8 h-8 sm:w-10 sm:h-10 rounded-full flex items-center justify-center font-bold ${darkMode ? 'bg-emerald-900 text-emerald-400' : 'bg-emerald-100 text-emerald-600'}`}>
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
