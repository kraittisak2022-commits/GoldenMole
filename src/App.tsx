import { useState } from 'react';
import { LayoutDashboard, UserCheck, Users, Truck, Fuel, Wrench, MapPin, Zap, Wallet, Banknote, List, Settings, User, MoreHorizontal, ClipboardList } from 'lucide-react';
import { AppSettings, Employee, Transaction, LandProject } from './types';
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

import { getToday } from './utils';

// --- Mock Data (Should be in a separate file in real app, but simplified here) ---
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
    appName: 'ConstructFlow', appSubtext: 'Management', appIcon: 'CF',
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

const RecordManager = ({ transactions, setTransactions }: { transactions: Transaction[], setTransactions: any }) => (
    <Card className="p-0 overflow-hidden animate-fade-in">
        <div className="p-4 bg-slate-50 border-b"><h3 className="font-bold">รายการบันทึกทั้งหมด</h3></div>
        <div className="max-h-[600px] overflow-y-auto">
            <table className="w-full text-sm text-left">
                <thead className="bg-white sticky top-0"><tr><th className="p-4">Date</th><th className="p-4">Desc</th><th className="p-4 text-right">Amount</th><th className="p-4"></th></tr></thead>
                <tbody>
                    {transactions.map(t => (
                        <tr key={t.id} className="border-b hover:bg-slate-50">
                            <td className="p-4">{t.date}</td>
                            <td className="p-4">{t.description}</td>
                            <td className={`p-4 text-right font-bold ${t.type === 'Income' ? 'text-emerald-600' : 'text-red-500'}`}><FormatNumber value={t.amount} /></td>
                            <td className="p-4 text-center">
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
    const [activeMenu, setActiveMenu] = useState('Dashboard');
    const [isSidebarOpen, setIsSidebarOpen] = useState(true);
    const [employees, setEmployees] = useState(MOCK_EMPLOYEES);
    const [transactions, setTransactions] = useState(MOCK_TRANSACTIONS);
    const [projects, setProjects] = useState<LandProject[]>(MOCK_PROJECTS);
    const [settings, setSettings] = useState(MOCK_SETTINGS);
    const [toast, setToast] = useState<string | null>(null);

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
            case 'Settings': return <SettingsModule settings={settings} setSettings={setSettings} />;
            default: return <div className="p-8 text-center text-slate-400">Coming Soon</div>;
        }
    };

    return (
        <div className="flex min-h-screen bg-[#F9FAFB] text-slate-800 font-sans">
            {toast && <Toast message={toast} onClose={() => setToast(null)} />}
            <aside className={`fixed lg:sticky top-0 h-screen bg-white border-r border-slate-100 transition-all duration-300 z-50 ${isSidebarOpen ? 'w-64' : 'w-20'} flex flex-col`}>
                <div className="p-6 flex items-center gap-3 border-b border-slate-50">
                    <div className="w-10 h-10 bg-slate-900 rounded-xl flex items-center justify-center text-white font-bold shadow-lg overflow-hidden">
                        {settings.appIcon.startsWith('http') || settings.appIcon.startsWith('data:') ? (
                            <img src={settings.appIcon} alt="Logo" className="w-full h-full object-cover" />
                        ) : (
                            settings.appIcon
                        )}
                    </div>
                    {isSidebarOpen && <div><h1 className="font-bold text-lg">{settings.appName}</h1><p className="text-[10px] text-slate-400 uppercase">{settings.appSubtext}</p></div>}
                </div>
                <nav className="flex-1 py-6 px-3 space-y-1 overflow-y-auto hide-scrollbar">
                    {[{ id: 'Dashboard', icon: LayoutDashboard, l: 'ภาพรวม' }, { id: 'DailyWizard', icon: ClipboardList, l: 'บันทึกงานประจำวัน' }, { id: 'Employees', icon: UserCheck, l: 'พนักงาน' }, { id: 'Labor', icon: Users, l: 'ค่าแรง/ลา' }, { id: 'Vehicle', icon: Truck, l: 'การใช้รถ' }, { id: 'DailyLog', icon: ClipboardList, l: 'บันทึกประจำวัน' }, { id: 'Fuel', icon: Fuel, l: 'น้ำมัน' }, { id: 'Maintenance', icon: Wrench, l: 'ซ่อมบำรุง' }, { id: 'Land', icon: MapPin, l: 'ที่ดิน' }, { id: 'Utilities', icon: Zap, l: 'สาธารณูปโภค' }, { id: 'Income', icon: Wallet, l: 'รายรับ' }, { id: 'Payroll', icon: Banknote, l: 'เงินเดือน' }, { id: 'DataList', icon: List, l: 'รายการบันทึก' }, { id: 'Settings', icon: Settings, l: 'ตั้งค่า' }].map(m => <button key={m.id} onClick={() => setActiveMenu(m.id)} className={`w-full flex items-center gap-3 px-3 py-3 rounded-xl transition-all ${activeMenu === m.id ? 'bg-slate-50 text-slate-900 font-bold shadow-sm' : 'text-slate-500 hover:bg-slate-50'}`}><m.icon size={20} className={activeMenu === m.id ? 'text-emerald-500' : ''} />{isSidebarOpen && <span className="text-sm">{m.l}</span>}</button>)}
                </nav>
                <div className="p-4 border-t"><button onClick={() => setIsSidebarOpen(!isSidebarOpen)} className="w-full flex items-center justify-center p-2 hover:bg-slate-50 rounded-lg text-slate-400"><MoreHorizontal /></button></div>
            </aside>
            <main className="flex-1 p-4 lg:p-8 overflow-y-auto"><header className="flex justify-between items-center mb-8"><h2 className="text-2xl font-bold text-slate-800 tracking-tight">{activeMenu}</h2><div className="flex items-center gap-4"><div className="w-10 h-10 rounded-full bg-emerald-100 flex items-center justify-center text-emerald-600 font-bold"><User size={20} /></div></div></header>{renderContent()}</main>
        </div>
    );
}

export default App;
