import { useState, useMemo } from 'react';
import { CalendarDays } from 'lucide-react';
import DashboardOverview from './DashboardOverview';
import DashboardV4 from './DashboardV4';
import DashboardV5 from './DashboardV5';
import AnalyticsView from './AnalyticsView';
import CalendarView from './CalendarView';
import SpecificDashboard from './SpecificDashboard';
import DailyStepRecorder from './DailyStepRecorder';
import { getToday } from '../../utils';
import { Transaction, AppSettings, Employee } from '../../types';

const DASHBOARD_MAIN_TABS = [
    { id: 'Overview', label: 'ภาพรวม (V.1)' },
    { id: 'Analytics', label: 'วิเคราะห์ (V.2)' },
    { id: 'Calendar', label: 'ปฏิทิน (V.3)' },
    { id: 'V4', label: 'Real-time (V.4)' },
    { id: 'V5', label: 'ภาพรวม (V.5)' },
] as const;

const DASHBOARD_DETAIL_TABS = [
    { id: 'Labor', label: 'ค่าแรง' },
    { id: 'Vehicle', label: 'การใช้รถ' },
    { id: 'Fuel', label: 'น้ำมัน' },
    { id: 'Land', label: 'ที่ดิน' },
    { id: 'Income', label: 'รายรับ' },
    { id: 'Wizard', label: 'บันทึกงาน' },
] as const;

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
        <div className="space-y-4 sm:space-y-6">
            <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
                <div className="flex flex-col sm:flex-row gap-2 sm:items-center w-full md:flex-1 md:min-w-0">
                    <label htmlFor="dashboard-tab-select" className="text-xs font-medium text-slate-600 dark:text-slate-400 shrink-0">
                        เลือกหน้าแดชบอร์ด
                    </label>
                    <select
                        id="dashboard-tab-select"
                        value={subTab}
                        onChange={(e) => setSubTab(e.target.value)}
                        className="w-full sm:max-w-md rounded-xl border border-slate-200 dark:border-white/10 bg-white dark:bg-slate-900/50 text-slate-800 dark:text-slate-200 text-sm py-2.5 px-3 shadow-sm focus:outline-none focus:ring-2 focus:ring-amber-500/30 focus:border-amber-500/50"
                    >
                        <optgroup label="ภาพรวมและเครื่องมือ">
                            {DASHBOARD_MAIN_TABS.map((t) => (
                                <option key={t.id} value={t.id}>
                                    {t.label}
                                </option>
                            ))}
                        </optgroup>
                        <optgroup label="รายงานตามหมวด">
                            {DASHBOARD_DETAIL_TABS.map((t) => (
                                <option key={t.id} value={t.id}>
                                    {t.label}
                                </option>
                            ))}
                        </optgroup>
                    </select>
                </div>
                <div className="flex flex-wrap items-center gap-2 bg-white dark:bg-white/[0.06] p-2 sm:p-1 rounded-xl border border-slate-200 dark:border-white/10 shadow-sm shrink-0">
                    <CalendarDays size={18} className="text-slate-400 dark:text-slate-500 ml-0 sm:ml-2 shrink-0" />
                    <select value={filterType} onChange={(e: any) => setFilterType(e.target.value)} className="bg-transparent text-sm p-1 focus:outline-none text-slate-700 dark:text-slate-300 min-w-0">
                        <option value="7">7 วันล่าสุด</option>
                        <option value="14">14 วันล่าสุด</option>
                        <option value="30">30 วันล่าสุด</option>
                        <option value="custom">กำหนดเอง</option>
                    </select>
                    {filterType === 'custom' && (
                        <div className="flex gap-2 items-center px-2">
                            <input type="date" value={customRange.start} onChange={(e) => setCustomRange({ ...customRange, start: e.target.value })} className="text-xs border border-slate-200 dark:border-white/20 rounded p-1 bg-white dark:bg-white/5 text-slate-800 dark:text-slate-200" />
                            <span className="text-xs text-slate-500 dark:text-slate-400">-</span>
                            <input type="date" value={customRange.end} onChange={(e) => setCustomRange({ ...customRange, end: e.target.value })} className="text-xs border border-slate-200 dark:border-white/20 rounded p-1 bg-white dark:bg-white/5 text-slate-800 dark:text-slate-200" />
                        </div>
                    )}
                </div>
            </div>
            {subTab === 'Overview' ? <DashboardOverview transactions={transactions} dateFilter={dateFilter} /> :
                subTab === 'Analytics' ? <AnalyticsView transactions={transactions} settings={settings} dateFilter={dateFilter} /> :
                    subTab === 'Calendar' ? <CalendarView transactions={transactions} employees={employees} onSaveTransaction={onSaveTransaction} onDeleteTransaction={onDeleteTransaction} /> :
                        subTab === 'V4' ? <DashboardV4 transactions={transactions} dateFilter={dateFilter} employees={employees} settings={settings} /> :
                            subTab === 'V5' ? <DashboardV5 transactions={transactions} dateFilter={dateFilter} /> :
                            subTab === 'Wizard' ? <DailyStepRecorder employees={employees} settings={settings} transactions={transactions} dateFilter={dateFilter} onSaveTransaction={onSaveTransaction} onDeleteTransaction={onDeleteTransaction} /> :
                                <SpecificDashboard type={subTab} transactions={transactions} settings={settings} employees={employees} dateFilter={dateFilter} />}
        </div>
    );
};

export default Dashboard;
