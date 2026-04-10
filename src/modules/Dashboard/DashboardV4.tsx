import { useMemo, useState } from 'react';
import {
    ClipboardList,
    Wallet,
    CreditCard,
    ChevronDown,
    ChevronUp,
    Users,
    Truck,
    Droplets,
    Fuel,
    AlertCircle,
    Calendar,
    Activity,
    TrendingUp,
    BarChart3,
} from 'lucide-react';
import Card from '../../components/ui/Card';
import { Transaction, Employee, AppSettings } from '../../types';
import { normalizeDate } from '../../utils';

interface DashboardV4Props {
    transactions: Transaction[];
    dateFilter: { start: string; end: string };
    employees?: Employee[];
    settings?: AppSettings;
}

const formatThaiDate = (d: string) =>
    new Date(d + 'T12:00:00+07:00').toLocaleDateString('th-TH', { timeZone: 'Asia/Bangkok',
        weekday: 'short',
        day: 'numeric',
        month: 'short',
        year: '2-digit',
    });

const isDailyWizardTx = (t: Transaction) =>
    t.category === 'Labor' ||
    t.category === 'Vehicle' ||
    (t.category === 'DailyLog' && (t.subCategory === 'VehicleTrip' || t.subCategory === 'Sand' || t.subCategory === 'Event')) ||
    t.category === 'Fuel';

const DashboardV4 = ({ transactions, dateFilter, employees = [], settings }: DashboardV4Props) => {
    const [expandedDate, setExpandedDate] = useState<string | null>(null);
    const [selectedDate, setSelectedDate] = useState('');

    const filteredByRange = useMemo(() => {
        const start = new Date(dateFilter.start);
        const end = new Date(dateFilter.end);
        end.setHours(23, 59, 59, 999);
        return transactions.filter((t) => {
            const tDate = new Date(normalizeDate(t.date));
            return tDate >= start && tDate <= end;
        });
    }, [transactions, dateFilter]);

    const displayTransactions = useMemo(() => {
        if (!selectedDate) return filteredByRange;
        return filteredByRange.filter((t) => normalizeDate(t.date) === selectedDate);
    }, [filteredByRange, selectedDate]);

    const byDate = useMemo(() => {
        const map: Record<string, Transaction[]> = {};
        displayTransactions.forEach((t) => {
            const d = normalizeDate(t.date);
            if (!map[d]) map[d] = [];
            map[d].push(t);
        });
        return Object.entries(map).sort(([a], [b]) => b.localeCompare(a));
    }, [displayTransactions]);

    const summary = useMemo(() => {
        const totalExpense = displayTransactions.filter((t) => t.type === 'Expense').reduce((s, t) => s + t.amount, 0);
        const totalIncome = displayTransactions.filter((t) => t.type === 'Income').reduce((s, t) => s + t.amount, 0);
        const wizardCount = displayTransactions.filter(isDailyWizardTx).length;
        return {
            days: byDate.length,
            totalExpense,
            totalIncome,
            net: totalIncome - totalExpense,
            wizardCount,
        };
    }, [displayTransactions, byDate.length]);

    return (
        <div className="space-y-6 animate-fade-in">
            {/* Header */}
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
                <div>
                    <h2 className="text-xl font-bold text-slate-800 flex items-center gap-2">
                        <span className="w-9 h-9 rounded-xl bg-gradient-to-br from-indigo-500 to-violet-600 flex items-center justify-center text-white shadow-lg shadow-indigo-500/25">
                            <Activity size={18} />
                        </span>
                        Real-time V.4
                    </h2>
                    <p className="text-sm text-slate-500 mt-1">
                        บันทึกงานประจำวัน • ค่าใช้จ่าย • รายรับ • อัปเดตรายวัน
                    </p>
                </div>
            </div>

            {/* Date selector for V4 detail view */}
            <div className="rounded-2xl border border-slate-200 bg-white p-3 sm:p-4">
                <div className="flex flex-col sm:flex-row sm:items-center gap-3 sm:gap-4">
                    <label className="text-sm font-medium text-slate-700 flex items-center gap-2">
                        <Calendar size={16} className="text-indigo-500" />
                        เลือกวันที่ (Real-time)
                    </label>
                    <div className="flex flex-col xs:flex-row gap-2 w-full sm:w-auto">
                        <input
                            type="date"
                            value={selectedDate}
                            onChange={(e) => setSelectedDate(e.target.value)}
                            className="w-full sm:w-auto px-3 py-2 rounded-xl border border-slate-200 text-sm text-slate-700"
                        />
                        {selectedDate && (
                            <button
                                type="button"
                                onClick={() => setSelectedDate('')}
                                className="px-3 py-2 rounded-xl border border-slate-200 text-sm text-slate-600 hover:bg-slate-50"
                            >
                                ล้างตัวกรองวัน
                            </button>
                        )}
                    </div>
                    <p className="text-xs text-slate-400 sm:ml-auto">
                        {selectedDate ? `แสดงเฉพาะวันที่ ${formatThaiDate(selectedDate)}` : `แสดงตามช่วงวันที่ ${dateFilter.start} ถึง ${dateFilter.end}`}
                    </p>
                </div>
            </div>

            {/* Summary Cards — แดชบอร์ดสรุปทันสมัย */}
            {byDate.length > 0 && (
                <div className="grid grid-cols-2 lg:grid-cols-5 gap-3 sm:gap-4">
                    <div className="rounded-2xl bg-gradient-to-br from-slate-800 to-slate-900 p-4 sm:p-5 text-white shadow-xl shadow-slate-900/20 border border-white/5">
                        <div className="flex items-center justify-between">
                            <Calendar size={20} className="text-slate-400" />
                            <span className="text-2xl sm:text-3xl font-bold tabular-nums">{summary.days}</span>
                        </div>
                        <p className="text-xs sm:text-sm text-slate-400 mt-1">วันที่มีข้อมูล</p>
                    </div>
                    <div className="rounded-2xl bg-gradient-to-br from-indigo-500 to-indigo-600 p-4 sm:p-5 text-white shadow-xl shadow-indigo-500/25 border border-white/10">
                        <div className="flex items-center justify-between">
                            <ClipboardList size={20} className="text-indigo-200" />
                            <span className="text-xl sm:text-2xl font-bold tabular-nums">{summary.wizardCount}</span>
                        </div>
                        <p className="text-xs sm:text-sm text-indigo-200 mt-1">รายการบันทึกงาน</p>
                    </div>
                    <div className="rounded-2xl bg-gradient-to-br from-rose-500 to-rose-600 p-4 sm:p-5 text-white shadow-xl shadow-rose-500/25 border border-white/10">
                        <div className="flex items-center justify-between">
                            <CreditCard size={20} className="text-rose-200" />
                            <span className="text-lg sm:text-xl font-bold tabular-nums truncate">฿{(summary.totalExpense / 1000).toFixed(0)}k</span>
                        </div>
                        <p className="text-xs sm:text-sm text-rose-200 mt-1">ค่าใช้จ่ายรวม</p>
                    </div>
                    <div className="rounded-2xl bg-gradient-to-br from-emerald-500 to-emerald-600 p-4 sm:p-5 text-white shadow-xl shadow-emerald-500/25 border border-white/10">
                        <div className="flex items-center justify-between">
                            <Wallet size={20} className="text-emerald-200" />
                            <span className="text-lg sm:text-xl font-bold tabular-nums truncate">฿{(summary.totalIncome / 1000).toFixed(0)}k</span>
                        </div>
                        <p className="text-xs sm:text-sm text-emerald-200 mt-1">รายรับรวม</p>
                    </div>
                    <div className="col-span-2 lg:col-span-1 rounded-2xl p-4 sm:p-5 border-2 border-dashed border-slate-200 bg-slate-50 flex flex-col justify-center">
                        <div className="flex items-center gap-2 text-slate-600">
                            <TrendingUp size={18} />
                            <span className="text-sm font-medium">กำไรสุทธิ</span>
                        </div>
                        <p className={`text-xl sm:text-2xl font-bold tabular-nums mt-0.5 ${summary.net >= 0 ? 'text-emerald-600' : 'text-rose-600'}`}>
                            ฿{summary.net.toLocaleString()}
                        </p>
                    </div>
                </div>
            )}

            {byDate.length === 0 ? (
                <Card className="p-10 sm:p-12 text-center rounded-2xl border-2 border-dashed border-slate-200 bg-slate-50/50">
                    <div className="w-14 h-14 rounded-2xl bg-slate-200/80 flex items-center justify-center mx-auto mb-4">
                        <Calendar size={28} className="text-slate-500" />
                    </div>
                    <p className="text-slate-600 font-medium">ไม่มีข้อมูลในช่วงวันที่เลือก</p>
                    <p className="text-sm text-slate-400 mt-1">ลองเปลี่ยนช่วงวันที่หรือบันทึกข้อมูลใหม่</p>
                </Card>
            ) : (
                <div className="space-y-3">
                    <h3 className="text-sm font-semibold text-slate-500 uppercase tracking-wider flex items-center gap-2">
                        <BarChart3 size={16} />
                        รายวัน
                    </h3>
                    <div className="space-y-3">
                        {byDate.map(([dateStr, txs]) => {
                            const wizardTx = txs.filter(isDailyWizardTx);
                            const expenses = txs.filter((t) => t.type === 'Expense');
                            const incomes = txs.filter((t) => t.type === 'Income');
                            const expenseTotal = expenses.reduce((s, t) => s + t.amount, 0);
                            const incomeTotal = incomes.reduce((s, t) => s + t.amount, 0);
                            const isExpanded = expandedDate === dateStr;

                            const laborTx = wizardTx.filter((t) => t.category === 'Labor');
                            const vehicleTx = wizardTx.filter((t) => t.category === 'Vehicle');
                            const tripTx = wizardTx.filter((t) => t.category === 'DailyLog' && t.subCategory === 'VehicleTrip');
                            const sandTx = wizardTx.filter((t) => t.category === 'DailyLog' && t.subCategory === 'Sand');
                            const fuelTx = wizardTx.filter((t) => t.category === 'Fuel');
                            const eventTx = wizardTx.filter((t) => t.category === 'DailyLog' && t.subCategory === 'Event');

                            return (
                                <div
                                    key={dateStr}
                                    className="rounded-2xl border border-slate-200 bg-white shadow-sm hover:shadow-md transition-shadow overflow-hidden"
                                >
                                    <button
                                        type="button"
                                        onClick={() => setExpandedDate(isExpanded ? null : dateStr)}
                                        className="w-full flex justify-between items-center p-4 sm:p-5 text-left hover:bg-slate-50/80 transition-colors"
                                    >
                                        <div className="flex items-center gap-3 flex-wrap">
                                            <span className="font-bold text-slate-800">{formatThaiDate(dateStr)}</span>
                                            <span className="text-xs bg-indigo-100 text-indigo-700 px-2.5 py-1 rounded-full font-medium">
                                                {wizardTx.length} รายการ
                                            </span>
                                            <span className="text-xs bg-rose-100 text-rose-700 px-2.5 py-1 rounded-full font-medium">
                                                ฿{expenseTotal.toLocaleString()}
                                            </span>
                                            <span className="text-xs bg-emerald-100 text-emerald-700 px-2.5 py-1 rounded-full font-medium">
                                                ฿{incomeTotal.toLocaleString()}
                                            </span>
                                        </div>
                                        <span className={`text-slate-400 transition-transform ${isExpanded ? 'rotate-180' : ''}`}>
                                            <ChevronDown size={20} />
                                        </span>
                                    </button>

                                    {isExpanded && (
                                        <div className="px-4 sm:px-5 pb-5 pt-0 space-y-5 border-t border-slate-100 bg-slate-50/50">
                                            <div>
                                                <h4 className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-3 flex items-center gap-2">
                                                    <ClipboardList size={14} className="text-indigo-500" />
                                                    บันทึกงานประจำวัน
                                                </h4>
                                                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
                                                    {laborTx.length > 0 && (
                                                        <div className="bg-white rounded-xl p-3 border border-emerald-200/80 shadow-sm">
                                                            <div className="flex items-center gap-2 text-emerald-700 font-medium text-sm">
                                                                <Users size={14} /> ค่าแรง ({laborTx.length})
                                                            </div>
                                                            <p className="text-xs text-slate-600 mt-1">฿{laborTx.reduce((s, t) => s + t.amount, 0).toLocaleString()}</p>
                                                        </div>
                                                    )}
                                                    {vehicleTx.length > 0 && (
                                                        <div className="bg-white rounded-xl p-3 border border-amber-200/80 shadow-sm">
                                                            <div className="flex items-center gap-2 text-amber-700 font-medium text-sm">
                                                                <Truck size={14} /> ใช้รถ ({vehicleTx.length})
                                                            </div>
                                                            <p className="text-xs text-slate-600 mt-1">฿{vehicleTx.reduce((s, t) => s + t.amount, 0).toLocaleString()}</p>
                                                        </div>
                                                    )}
                                                    {tripTx.length > 0 && (
                                                        <div className="bg-white rounded-xl p-3 border border-blue-200/80 shadow-sm">
                                                            <div className="flex items-center gap-2 text-blue-700 font-medium text-sm">
                                                                <Truck size={14} /> เที่ยวรถ ({tripTx.length})
                                                            </div>
                                                            <p className="text-xs text-slate-600 mt-1">฿{tripTx.reduce((s, t) => s + t.amount, 0).toLocaleString()}</p>
                                                        </div>
                                                    )}
                                                    {sandTx.length > 0 && (
                                                        <div className="bg-white rounded-xl p-3 border border-cyan-200/80 shadow-sm">
                                                            <div className="flex items-center gap-2 text-cyan-700 font-medium text-sm">
                                                                <Droplets size={14} /> ล้างทราย ({sandTx.reduce((s, t) => s + (t.sandMorning || 0) + (t.sandAfternoon || 0), 0)} คิว)
                                                            </div>
                                                            <p className="text-xs text-slate-600 mt-1">฿{sandTx.reduce((s, t) => s + t.amount, 0).toLocaleString()}</p>
                                                        </div>
                                                    )}
                                                    {fuelTx.length > 0 && (
                                                        <div className="bg-white rounded-xl p-3 border border-red-200/80 shadow-sm">
                                                            <div className="flex items-center gap-2 text-red-700 font-medium text-sm">
                                                                <Fuel size={14} /> น้ำมัน ({fuelTx.length})
                                                            </div>
                                                            <p className="text-xs text-slate-600 mt-1">฿{fuelTx.reduce((s, t) => s + t.amount, 0).toLocaleString()}</p>
                                                        </div>
                                                    )}
                                                    {eventTx.length > 0 && (
                                                        <div className="bg-white rounded-xl p-3 border border-orange-200/80 shadow-sm">
                                                            <div className="flex items-center gap-2 text-orange-700 font-medium text-sm">
                                                                <AlertCircle size={14} /> เหตุการณ์ ({eventTx.length})
                                                            </div>
                                                        </div>
                                                    )}
                                                    {wizardTx.length === 0 && (
                                                        <p className="text-sm text-slate-400 col-span-full py-2">ไม่มีบันทึกงานประจำวันในวันนี้</p>
                                                    )}
                                                </div>
                                            </div>

                                            <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                                                <div>
                                                    <h4 className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-2 flex items-center gap-2">
                                                        <CreditCard size={14} className="text-rose-500" />
                                                        ค่าใช้จ่าย ({expenses.length}) — ฿{expenseTotal.toLocaleString()}
                                                    </h4>
                                                    <div className="space-y-1 max-h-40 overflow-y-auto rounded-xl bg-white border border-slate-200 p-2">
                                                        {expenses.map((t) => (
                                                            <div key={t.id} className="flex justify-between items-center py-1.5 px-2 rounded-lg hover:bg-slate-50 text-sm">
                                                                <span className="text-slate-600 truncate flex-1 mr-2">[{t.category}] {t.description}</span>
                                                                <span className="font-semibold text-slate-800 shrink-0">฿{t.amount.toLocaleString()}</span>
                                                            </div>
                                                        ))}
                                                        {expenses.length === 0 && <p className="text-sm text-slate-400 py-3 text-center">ไม่มี</p>}
                                                    </div>
                                                </div>
                                                <div>
                                                    <h4 className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-2 flex items-center gap-2">
                                                        <Wallet size={14} className="text-emerald-500" />
                                                        รายรับ ({incomes.length}) — ฿{incomeTotal.toLocaleString()}
                                                    </h4>
                                                    <div className="space-y-1 max-h-40 overflow-y-auto rounded-xl bg-white border border-slate-200 p-2">
                                                        {incomes.map((t) => (
                                                            <div key={t.id} className="flex justify-between items-center py-1.5 px-2 rounded-lg hover:bg-slate-50 text-sm">
                                                                <span className="text-slate-600 truncate flex-1 mr-2">[{t.category}] {t.description}</span>
                                                                <span className="font-semibold text-emerald-700 shrink-0">฿{t.amount.toLocaleString()}</span>
                                                            </div>
                                                        ))}
                                                        {incomes.length === 0 && <p className="text-sm text-slate-400 py-3 text-center">ไม่มี</p>}
                                                    </div>
                                                </div>
                                            </div>
                                        </div>
                                    )}
                                </div>
                            );
                        })}
                    </div>
                </div>
            )}
        </div>
    );
};

export default DashboardV4;
