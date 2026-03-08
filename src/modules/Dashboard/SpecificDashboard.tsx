import { useMemo, useState } from 'react';
import { Users, Truck, Fuel, MapPin, TrendingUp, Droplets, PieChart, Wallet, Clock, Coins, ChevronDown, ChevronUp } from 'lucide-react';
import Card from '../../components/ui/Card';
import LineChart from '../../components/charts/LineChart';
import { StatCard } from './DashboardOverview';
import { Transaction, AppSettings, Employee } from '../../types';

const SpecificDashboard = ({ type, transactions, settings, employees = [], dateFilter }: { type: string, transactions: Transaction[], settings: AppSettings, employees?: Employee[], dateFilter: any }) => {
    const [expandedDate, setExpandedDate] = useState<string | null>(null);

    const filteredTransactions = useMemo(() => {
        const start = new Date(dateFilter.start);
        const end = new Date(dateFilter.end);
        end.setHours(23, 59, 59, 999);
        return transactions.filter(t => { const tDate = new Date(t.date); return tDate >= start && tDate <= end; });
    }, [transactions, dateFilter]);

    const getSum = (cat: string) => filteredTransactions.filter(t => t.category === cat && t.type === 'Expense').reduce((s, t) => s + t.amount, 0);
    const getTrend = (cat: string) => {
        const points = 7; const res = [];
        const start = new Date(dateFilter.start); const end = new Date(dateFilter.end);
        const diff = Math.ceil((end.getTime() - start.getTime()) / (1000 * 60 * 60 * 24)) + 1;
        const step = Math.max(1, Math.floor(diff / points));
        for (let i = 0; i < points; i++) {
            const d = new Date(start); d.setDate(d.getDate() + (i * step)); if (d > end) break;
            const dateStr = d.toISOString().split('T')[0];
            res.push(filteredTransactions.filter(t => t.date === dateStr && t.category === cat).reduce((s, t) => s + t.amount, 0));
        }
        return res;
    };

    const getEmpName = (id: string) => employees.find(e => e.id === id)?.nickname || id;

    // Group transactions by date for detail view
    const groupByDate = (txs: Transaction[]) => {
        const map: Record<string, Transaction[]> = {};
        txs.forEach(t => { if (!map[t.date]) map[t.date] = []; map[t.date].push(t); });
        return Object.entries(map).sort(([a], [b]) => b.localeCompare(a));
    };

    const formatThaiDate = (d: string) => new Date(d).toLocaleDateString('th-TH', { weekday: 'short', day: 'numeric', month: 'short', year: '2-digit' });

    if (type === 'Labor') {
        const totalWage = getSum('Labor');
        const otTotal = filteredTransactions.filter(t => t.category === 'Labor').reduce((s, t) => s + (t.otAmount || 0), 0);
        const advanceTotal = filteredTransactions.filter(t => t.category === 'Labor').reduce((s, t) => s + (t.advanceAmount || 0), 0);
        const activeWorkers = new Set(filteredTransactions.filter(t => t.category === 'Labor').flatMap(t => t.employeeIds || [])).size;
        const laborTxByDate = groupByDate(filteredTransactions.filter(t => t.category === 'Labor'));

        return (
            <div className="space-y-6 animate-fade-in">
                <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-4 sm:gap-6">
                    <StatCard title="ค่าแรงรวม" value={totalWage} icon={Users} color="#10b981" />
                    <StatCard title="ค่า OT รวม" value={otTotal} icon={Clock} color="#f59e0b" />
                    <StatCard title="ยอดเบิก" value={advanceTotal} icon={Coins} color="#ef4444" />
                    <Card className="p-5 flex flex-col justify-center items-center">
                        <span className="text-4xl font-bold text-slate-800">{activeWorkers}</span>
                        <span className="text-sm text-slate-500">คนงานที่ปฏิบัติงาน</span>
                    </Card>
                </div>
                <Card className="p-6 h-80"><h3 className="font-bold text-slate-700 mb-6 flex items-center gap-2"><TrendingUp size={20} /> แนวโน้มค่าแรง</h3><div className="h-60"><LineChart data={getTrend('Labor')} color="#10b981" /></div></Card>

                {/* Daily details */}
                <Card className="p-6">
                    <h3 className="font-bold text-slate-700 mb-4 flex items-center gap-2"><Users size={20} /> รายละเอียดค่าแรงรายวัน</h3>
                    <div className="space-y-2">
                        {laborTxByDate.map(([d, txs]) => (
                            <div key={d} className="border rounded-xl overflow-hidden">
                                <button onClick={() => setExpandedDate(expandedDate === d ? null : d)}
                                    className="w-full flex justify-between items-center p-3 bg-emerald-50 hover:bg-emerald-100 transition-colors">
                                    <div className="flex items-center gap-3">
                                        <span className="text-sm font-bold text-emerald-800">{formatThaiDate(d)}</span>
                                        <span className="text-xs bg-emerald-200 text-emerald-800 px-2 py-0.5 rounded-full">{txs.length} รายการ</span>
                                        <span className="text-xs font-bold text-emerald-700">฿{txs.reduce((s, t) => s + t.amount, 0).toLocaleString()}</span>
                                    </div>
                                    {expandedDate === d ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
                                </button>
                                {expandedDate === d && (
                                    <div className="p-3 bg-white space-y-2">
                                        {txs.map(t => (
                                            <div key={t.id} className="flex justify-between items-center p-2.5 bg-slate-50 rounded-lg text-sm">
                                                <div>
                                                    <span className={`px-1.5 py-0.5 rounded text-xs font-bold mr-2 ${t.laborStatus === 'OT' ? 'bg-amber-100 text-amber-700' : t.laborStatus === 'Leave' ? 'bg-yellow-100 text-yellow-700' : 'bg-emerald-100 text-emerald-700'}`}>
                                                        {t.laborStatus === 'OT' ? 'OT' : t.laborStatus === 'Leave' ? 'ลา' : 'ทำงาน'}
                                                    </span>
                                                    <span className="text-slate-600">{t.description}</span>
                                                    {t.employeeIds && <span className="text-xs text-slate-400 ml-2">({t.employeeIds.map(id => getEmpName(id)).join(', ')})</span>}
                                                </div>
                                                <span className="font-bold text-slate-800">฿{t.amount.toLocaleString()}</span>
                                            </div>
                                        ))}
                                    </div>
                                )}
                            </div>
                        ))}
                        {laborTxByDate.length === 0 && <p className="text-center text-sm text-slate-400 py-8">ไม่มีข้อมูลค่าแรงในช่วงนี้</p>}
                    </div>
                </Card>
            </div>
        );
    }

    if (type === 'Vehicle' || type === 'Fuel') {
        const isFuel = type === 'Fuel';
        const totalCost = getSum(type);
        const items = filteredTransactions.filter(t => isFuel ? t.category === 'Fuel' : (t.category === 'Vehicle' || (t.category === 'DailyLog' && t.subCategory === 'VehicleTrip')));
        const totalQty = isFuel ? items.reduce((s, t) => s + (t.quantity || 0), 0) : 0;
        const detailByDate = groupByDate(items);

        return (
            <div className="space-y-6 animate-fade-in">
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 sm:gap-6">
                    <StatCard title={`รวม${isFuel ? 'น้ำมัน' : 'การใช้รถ'}`} value={isFuel ? totalCost : getSum('Vehicle')} icon={isFuel ? Fuel : Truck} color={isFuel ? "#ea580c" : "#f59e0b"} />
                    {isFuel && (
                        <Card className="p-5 flex flex-col justify-between h-32 relative overflow-hidden bg-slate-800 text-white">
                            <div className="flex items-center gap-2 mb-1"><Droplets size={18} /> <span className="text-sm font-medium opacity-80">ปริมาณรวม</span></div>
                            <h3 className="text-3xl font-bold">{totalQty.toLocaleString()} <span className="text-sm font-normal opacity-60">ลิตร</span></h3>
                            <div className="h-1 w-full bg-slate-700 mt-auto rounded-full"><div className="h-full bg-orange-500 rounded-full" style={{ width: '70%' }}></div></div>
                        </Card>
                    )}
                </div>
                <Card className="p-6 h-80"><h3 className="font-bold text-slate-700 mb-4">แนวโน้มค่าใช้จ่าย</h3><div className="h-60"><LineChart data={getTrend(type)} color={isFuel ? "#ea580c" : "#f59e0b"} /></div></Card>

                {/* Daily details */}
                <Card className="p-6">
                    <h3 className="font-bold text-slate-700 mb-4 flex items-center gap-2">
                        {isFuel ? <Fuel size={20} /> : <Truck size={20} />} รายละเอียด{isFuel ? 'น้ำมัน' : 'การใช้รถ'}รายวัน
                    </h3>
                    <div className="space-y-2">
                        {detailByDate.map(([d, txs]) => (
                            <div key={d} className="border rounded-xl overflow-hidden">
                                <button onClick={() => setExpandedDate(expandedDate === d ? null : d)}
                                    className={`w-full flex justify-between items-center p-3 ${isFuel ? 'bg-red-50 hover:bg-red-100' : 'bg-amber-50 hover:bg-amber-100'} transition-colors`}>
                                    <div className="flex items-center gap-3">
                                        <span className={`text-sm font-bold ${isFuel ? 'text-red-800' : 'text-amber-800'}`}>{formatThaiDate(d)}</span>
                                        <span className={`text-xs px-2 py-0.5 rounded-full ${isFuel ? 'bg-red-200 text-red-800' : 'bg-amber-200 text-amber-800'}`}>{txs.length} รายการ</span>
                                        <span className={`text-xs font-bold ${isFuel ? 'text-red-700' : 'text-amber-700'}`}>฿{txs.reduce((s, t) => s + t.amount, 0).toLocaleString()}</span>
                                    </div>
                                    {expandedDate === d ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
                                </button>
                                {expandedDate === d && (
                                    <div className="p-3 bg-white space-y-2">
                                        {txs.map(t => (
                                            <div key={t.id} className="flex justify-between items-start p-2.5 bg-slate-50 rounded-lg text-sm">
                                                <div className="flex-1">
                                                    <div className="text-slate-700 font-medium">{t.description}</div>
                                                    {isFuel && (
                                                        <div className="text-xs text-slate-400 mt-0.5">
                                                            {(t as any).fuelType === 'Diesel' ? 'ดีเซล' : 'เบนซิน'} • {t.quantity || 0} {(t as any).unit === 'gallon' ? 'แกลลอน' : 'ลิตร'}
                                                        </div>
                                                    )}
                                                    {!isFuel && t.driverId && <div className="text-xs text-slate-400">คนขับ: {getEmpName(t.driverId)}</div>}
                                                    {t.workDetails && <div className="text-xs text-slate-400">{t.workDetails}</div>}
                                                </div>
                                                <span className="font-bold text-slate-800 shrink-0 ml-3">฿{t.amount.toLocaleString()}</span>
                                            </div>
                                        ))}
                                    </div>
                                )}
                            </div>
                        ))}
                        {detailByDate.length === 0 && <p className="text-center text-sm text-slate-400 py-8">ไม่มีข้อมูลในช่วงนี้</p>}
                    </div>
                </Card>
            </div>
        );
    }

    if (type === 'Land') {
        const totalLand = getSum('Land');
        return (
            <div className="space-y-6 animate-fade-in">
                <div className="grid grid-cols-1 gap-6"><StatCard title="ค่าใช้จ่ายที่ดินรวม" value={totalLand} icon={MapPin} color="#8b5cf6" /></div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <Card className="p-6 h-80"><h3 className="font-bold text-slate-700 mb-4">สัดส่วนค่าใช้จ่ายรายโครงการ</h3><div className="h-full flex items-center justify-center text-slate-400"><PieChart size={64} className="opacity-20" /></div></Card>
                    <Card className="p-6 h-80"><h3 className="font-bold text-slate-700 mb-6">History Trend</h3><div className="h-60"><LineChart data={getTrend('Land')} color="#8b5cf6" /></div></Card>
                </div>
            </div>
        );
    }

    if (type === 'Income') {
        const totalIncome = filteredTransactions.filter(t => t.type === 'Income').reduce((s, t) => s + t.amount, 0);
        const incomeByType = settings.incomeTypes.map(type => ({
            type, val: filteredTransactions.filter(t => t.type === 'Income' && t.category === 'Income' && (t.subCategory === type || t.description.includes(type))).reduce((s, t) => s + t.amount, 0)
        }));
        return (
            <div className="space-y-6 animate-fade-in">
                <StatCard title="รายรับรวมทั้งหมด" value={totalIncome} icon={Wallet} color="#3b82f6" />
                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <Card className="p-6 h-80"><h3 className="font-bold text-slate-700 mb-4">สัดส่วนรายได้</h3><div className="space-y-4 pt-4">{incomeByType.map((d, i) => (<div key={i}><div className="flex justify-between text-sm mb-1"><span>{d.type}</span><span className="font-bold">฿{d.val.toLocaleString()}</span></div><div className="h-2 bg-slate-100 rounded-full w-full"><div style={{ width: `${totalIncome > 0 ? (d.val / totalIncome) * 100 : 0}%` }} className="h-full bg-blue-500 rounded-full" /></div></div>))}</div></Card>
                    <Card className="p-6 h-80"><h3 className="font-bold text-slate-700 mb-6">แนวโน้มรายรับ</h3><div className="h-60"><LineChart data={getTrend('Income')} color="#3b82f6" /></div></Card>
                </div>
            </div>
        );
    }
    return <div className="p-8 text-center text-slate-400">Select a dashboard</div>;
};

export default SpecificDashboard;
