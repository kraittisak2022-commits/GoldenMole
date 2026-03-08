import { useState, useMemo } from 'react';
import { LayoutDashboard, BarChart3, Calendar as CalIcon, Users, Truck, Fuel, MapPin, Wallet, CalendarDays, Activity, ClipboardList } from 'lucide-react';
import DashboardOverview from './DashboardOverview';
import DashboardV4 from './DashboardV4';
import AnalyticsView from './AnalyticsView';
import CalendarView from './CalendarView';
import SpecificDashboard from './SpecificDashboard';
import DailyStepRecorder from './DailyStepRecorder';
import { getToday } from '../../utils';
import { Transaction, AppSettings, Employee } from '../../types';

const Dashboard = ({ transactions, settings, employees, onSaveTransaction, onDeleteTransaction }: { transactions: Transaction[], settings: AppSettings, employees: Employee[], onSaveTransaction: any, onDeleteTransaction: any }) => {
    const [subTab, setSubTab] = useState('Overview');
    const [filterType, setFilterType] = useState<'7' | '14' | '30' | 'custom'>('7');
    const [customRange, setCustomRange] = useState({ start: '', end: '' });

    const dateFilter = useMemo(() => {
        const today = new Date();
        const end = new Date();
        const start = new Date();
        if (filterType === 'custom') {
            return { start: customRange.start || getToday(), end: customRange.end || getToday() };
        } else {
            const days = parseInt(filterType);
            start.setDate(today.getDate() - days + 1);
            return { start: start.toISOString().split('T')[0], end: end.toISOString().split('T')[0] };
        }
    }, [filterType, customRange]);

    return (
        <div className="space-y-6">
            <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
                <div className="flex gap-2 overflow-x-auto pb-2 hide-scrollbar">
                    {[{ id: 'Overview', label: 'ภาพรวม (V.1)', icon: LayoutDashboard }, { id: 'Analytics', label: 'วิเคราะห์ (V.2)', icon: BarChart3 }, { id: 'Calendar', label: 'ปฏิทิน (V.3)', icon: CalIcon }, { id: 'V4', label: 'Real-time (V.4)', icon: Activity }, { id: 'Wizard', label: 'บันทึกงานประจำวัน', icon: ClipboardList }].map(t => (
                        <button key={t.id} onClick={() => setSubTab(t.id)} className={`flex items-center gap-2 px-4 py-2.5 rounded-xl whitespace-nowrap transition-all border ${subTab === t.id ? 'bg-slate-800 text-white border-slate-800 shadow-md' : 'bg-white text-slate-500 border-slate-200 hover:bg-slate-50'}`}>
                            <t.icon size={18} /> <span className="text-sm font-medium">{t.label}</span>
                        </button>
                    ))}
                    <div className="w-px h-8 bg-slate-300 mx-2"></div>
                    {[{ id: 'Labor', label: 'ค่าแรง', icon: Users }, { id: 'Vehicle', label: 'การใช้รถ', icon: Truck }, { id: 'Fuel', label: 'น้ำมัน', icon: Fuel }, { id: 'Land', label: 'ที่ดิน', icon: MapPin }, { id: 'Income', label: 'รายรับ', icon: Wallet }].map(t => (
                        <button key={t.id} onClick={() => setSubTab(t.id)} className={`flex items-center gap-2 px-4 py-2.5 rounded-xl whitespace-nowrap transition-all border ${subTab === t.id ? 'bg-slate-800 text-white border-slate-800 shadow-md' : 'bg-white text-slate-500 border-slate-200 hover:bg-slate-50'}`}>
                            <t.icon size={18} /> <span className="text-sm font-medium">{t.label}</span>
                        </button>
                    ))}
                </div>
                <div className="flex items-center gap-2 bg-white p-1 rounded-xl border shadow-sm">
                    <CalendarDays size={18} className="text-slate-400 ml-2" />
                    <select value={filterType} onChange={(e: any) => setFilterType(e.target.value)} className="bg-transparent text-sm p-1 focus:outline-none">
                        <option value="7">7 วันล่าสุด</option>
                        <option value="14">14 วันล่าสุด</option>
                        <option value="30">30 วันล่าสุด</option>
                        <option value="custom">กำหนดเอง</option>
                    </select>
                    {filterType === 'custom' && (
                        <div className="flex gap-2 items-center px-2">
                            <input type="date" value={customRange.start} onChange={(e) => setCustomRange({ ...customRange, start: e.target.value })} className="text-xs border rounded p-1" />
                            <span className="text-xs">-</span>
                            <input type="date" value={customRange.end} onChange={(e) => setCustomRange({ ...customRange, end: e.target.value })} className="text-xs border rounded p-1" />
                        </div>
                    )}
                </div>
            </div>
            {subTab === 'Overview' ? <DashboardOverview transactions={transactions} dateFilter={dateFilter} /> :
                subTab === 'Analytics' ? <AnalyticsView transactions={transactions} settings={settings} dateFilter={dateFilter} /> :
                    subTab === 'Calendar' ? <CalendarView transactions={transactions} employees={employees} /> :
                        subTab === 'V4' ? <DashboardV4 transactions={transactions} /> :
                            subTab === 'Wizard' ? <DailyStepRecorder employees={employees} settings={settings} transactions={transactions} onSaveTransaction={onSaveTransaction} onDeleteTransaction={onDeleteTransaction} /> :
                                <SpecificDashboard type={subTab} transactions={transactions} settings={settings} employees={employees} dateFilter={dateFilter} />}
        </div>
    );
};

export default Dashboard;
