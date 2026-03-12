import { useMemo, useState } from 'react';
import { Users, Truck, Fuel, MapPin, TrendingUp, Droplets, Wallet, Clock, Coins, ChevronDown, ChevronUp, BarChart3, PieChart } from 'lucide-react';
import Card from '../../components/ui/Card';
import LineChart from '../../components/charts/LineChart';
import BarChart from '../../components/charts/BarChart';
import DonutChartSimple from '../../components/charts/DonutChart';
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

    /** ข้อมูลรายวันสำหรับกราฟแท่งเปรียบเทียบ (ทุกวันในช่วง ไม่เกิน 14 วัน) */
    const getDailyBarData = (getAmountForDate: (dateStr: string) => number, maxDays = 14) => {
        const start = new Date(dateFilter.start);
        const end = new Date(dateFilter.end);
        const labels: string[] = [];
        const data: number[] = [];
        const totalDays = Math.ceil((end.getTime() - start.getTime()) / (1000 * 60 * 60 * 24)) + 1;
        const step = totalDays <= maxDays ? 1 : Math.max(1, Math.floor(totalDays / maxDays));
        for (let i = 0; i < totalDays; i += step) {
            const d = new Date(start);
            d.setDate(d.getDate() + i);
            const dateStr = d.toISOString().split('T')[0];
            if (dateStr > dateFilter.end) break;
            labels.push(`${d.getDate()}/${d.getMonth() + 1}`);
            data.push(getAmountForDate(dateStr));
        }
        return { labels, data };
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
        const baseWage = Math.max(0, totalWage - otTotal - advanceTotal);
        const activeWorkers = new Set(filteredTransactions.filter(t => t.category === 'Labor').flatMap(t => t.employeeIds || [])).size;
        const laborTxByDate = groupByDate(filteredTransactions.filter(t => t.category === 'Labor'));
        const laborBar = getDailyBarData((dateStr) => filteredTransactions.filter(t => t.date === dateStr && t.category === 'Labor').reduce((s, t) => s + t.amount, 0));
        const laborDonutData = [
            ...(baseWage > 0 ? [{ label: 'ค่าแรงหลัก', value: baseWage, color: '#10b981' }] : []),
            ...(otTotal > 0 ? [{ label: 'OT', value: otTotal, color: '#f59e0b' }] : []),
            ...(advanceTotal > 0 ? [{ label: 'ยอดเบิก', value: advanceTotal, color: '#ef4444' }] : []),
        ];

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
                {/* กราฟเปรียบเทียบ: แท่งรายวัน + สัดส่วนค่าแรง/OT/เบิก */}
                <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
                    <Card className="lg:col-span-2 p-4 sm:p-5">
                        <h3 className="font-bold text-slate-700 text-sm mb-3 flex items-center gap-2"><BarChart3 size={18} /> เปรียบเทียบค่าแรงรายวัน</h3>
                        <div className="h-44">
                            <BarChart data={laborBar.data} labels={laborBar.labels} color="#10b981" />
                        </div>
                    </Card>
                    <Card className="p-4 sm:p-5 flex flex-col">
                        <h3 className="font-bold text-slate-700 text-sm mb-3 flex items-center gap-2"><PieChart size={18} /> สัดส่วนค่าแรง</h3>
                        {laborDonutData.length > 0 ? (
                            <>
                                <div className="flex-1 flex items-center justify-center min-h-[140px]">
                                    <DonutChartSimple data={laborDonutData} />
                                </div>
                                <div className="flex flex-wrap gap-3 justify-center mt-2 pt-2 border-t border-slate-100">
                                    {laborDonutData.map((d, i) => (
                                        <span key={i} className="flex items-center gap-1.5 text-xs">
                                            <span className="w-2 h-2 rounded-full" style={{ backgroundColor: d.color }} />
                                            {d.label}: ฿{d.value.toLocaleString()}
                                        </span>
                                    ))}
                                </div>
                            </>
                        ) : (
                            <div className="flex-1 flex items-center justify-center text-slate-400 text-sm min-h-[140px]">ไม่มีข้อมูล</div>
                        )}
                    </Card>
                </div>
                {/* แนวโน้ม + รายละเอียดรายวัน */}
                <div className="grid grid-cols-1 lg:grid-cols-12 gap-4">
                    <Card className="lg:col-span-4 p-4 sm:p-5">
                        <h3 className="font-bold text-slate-700 text-sm mb-3 flex items-center gap-2"><TrendingUp size={18} /> แนวโน้มค่าแรง</h3>
                        <div className="h-32"><LineChart data={getTrend('Labor')} color="#10b981" height={48} /></div>
                    </Card>
                    <Card className="lg:col-span-8 p-6">
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
                                                    <span className={`px-1.5 py-0.5 rounded text-xs font-bold mr-2 ${t.laborStatus === 'OT' ? 'bg-amber-100 text-amber-700' : t.laborStatus === 'Leave' ? 'bg-yellow-100 text-yellow-700' : t.laborStatus === 'Sick' ? 'bg-rose-100 text-rose-700' : t.laborStatus === 'Personal' ? 'bg-slate-200 text-slate-700' : 'bg-emerald-100 text-emerald-700'}`}>
                                                        {t.laborStatus === 'OT' ? 'OT' : t.laborStatus === 'Leave' ? 'ลา' : t.laborStatus === 'Sick' ? 'ป่วย' : t.laborStatus === 'Personal' ? 'กิจส่วนตัว' : 'ทำงาน'}
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
            </div>
        );
    }

    if (type === 'Vehicle' || type === 'Fuel') {
        const isFuel = type === 'Fuel';
        const totalCost = getSum(type);
        const items = filteredTransactions.filter(t => isFuel ? t.category === 'Fuel' : (t.category === 'Vehicle' || (t.category === 'DailyLog' && t.subCategory === 'VehicleTrip')));
        const totalQty = isFuel ? items.reduce((s, t) => s + (t.quantity || 0), 0) : 0;
        const detailByDate = groupByDate(items);
        const getDayAmount = (dateStr: string) => items.filter(t => t.date === dateStr).reduce((s, t) => s + t.amount, 0);
        const vehicleFuelBar = getDailyBarData(getDayAmount);
        const vehicleFuelDonutData = isFuel ? (() => {
            const diesel = items.filter(t => t.fuelType === 'Diesel').reduce((s, t) => s + t.amount, 0);
            const benzine = items.filter(t => t.fuelType === 'Benzine').reduce((s, t) => s + t.amount, 0);
            return [
                ...(diesel > 0 ? [{ label: 'ดีเซล', value: diesel, color: '#ea580c' }] : []),
                ...(benzine > 0 ? [{ label: 'เบนซิน', value: benzine, color: '#f59e0b' }] : []),
            ];
        })() : (() => {
            const vehicleSum = filteredTransactions.filter(t => t.category === 'Vehicle').reduce((s, t) => s + t.amount, 0);
            const tripSum = filteredTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'VehicleTrip').reduce((s, t) => s + t.amount, 0);
            return [
                ...(vehicleSum > 0 ? [{ label: 'ใช้รถ', value: vehicleSum, color: '#f59e0b' }] : []),
                ...(tripSum > 0 ? [{ label: 'เที่ยวรถ', value: tripSum, color: '#3b82f6' }] : []),
            ];
        })();

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
                {/* กราฟเปรียบเทียบ: แท่งรายวัน + สัดส่วน */}
                <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
                    <Card className="lg:col-span-2 p-4 sm:p-5">
                        <h3 className="font-bold text-slate-700 text-sm mb-3 flex items-center gap-2"><BarChart3 size={18} /> เปรียบเทียบ{isFuel ? 'ค่าน้ำมัน' : 'การใช้รถ'}รายวัน</h3>
                        <div className="h-44">
                            <BarChart data={vehicleFuelBar.data} labels={vehicleFuelBar.labels} color={isFuel ? '#ea580c' : '#f59e0b'} />
                        </div>
                    </Card>
                    <Card className="p-4 sm:p-5 flex flex-col">
                        <h3 className="font-bold text-slate-700 text-sm mb-3 flex items-center gap-2"><PieChart size={18} /> สัดส่วน{isFuel ? 'ประเภทน้ำมัน' : 'ใช้รถ vs เที่ยวรถ'}</h3>
                        {vehicleFuelDonutData.length > 0 ? (
                            <>
                                <div className="flex-1 flex items-center justify-center min-h-[140px]">
                                    <DonutChartSimple data={vehicleFuelDonutData} />
                                </div>
                                <div className="flex flex-wrap gap-3 justify-center mt-2 pt-2 border-t border-slate-100">
                                    {vehicleFuelDonutData.map((d, i) => (
                                        <span key={i} className="flex items-center gap-1.5 text-xs">
                                            <span className="w-2 h-2 rounded-full" style={{ backgroundColor: d.color }} />
                                            {d.label}: ฿{d.value.toLocaleString()}
                                        </span>
                                    ))}
                                </div>
                            </>
                        ) : (
                            <div className="flex-1 flex items-center justify-center text-slate-400 text-sm min-h-[140px]">ไม่มีข้อมูล</div>
                        )}
                    </Card>
                </div>
                <div className="grid grid-cols-1 lg:grid-cols-12 gap-4">
                    <Card className="lg:col-span-4 p-4 sm:p-5">
                        <h3 className="font-bold text-slate-700 text-sm mb-3">แนวโน้มค่าใช้จ่าย</h3>
                        <div className="h-32"><LineChart data={getTrend(type)} color={isFuel ? "#ea580c" : "#f59e0b"} height={48} /></div>
                    </Card>
                    <Card className="lg:col-span-8 p-6">
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
                                                            {t.fuelType === 'Diesel' ? 'ดีเซล' : t.fuelType === 'Benzine' ? 'เบนซิน' : ''} • {t.quantity ?? 0} {t.unit === 'gallon' ? 'แกลลอน' : 'ลิตร'}
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
            </div>
        );
    }

    if (type === 'Land') {
        const totalLand = getSum('Land');
        const landItems = filteredTransactions.filter(t => t.category === 'Land');
        const landTxByDate = groupByDate(landItems);
        const landBar = getDailyBarData((dateStr) => landItems.filter(t => t.date === dateStr).reduce((s, t) => s + t.amount, 0));
        const landDonutData = (() => {
            const byKey: Record<string, number> = {};
            landItems.forEach(t => {
                const key = t.projectId || t.description || 'อื่นๆ';
                byKey[key] = (byKey[key] || 0) + t.amount;
            });
            const colors = ['#8b5cf6', '#a78bfa', '#c4b5fd', '#7c3aed'];
            return Object.entries(byKey).filter(([, v]) => v > 0).map(([label, value], i) => ({
                label: label.length > 12 ? label.slice(0, 12) + '…' : label,
                value,
                color: colors[i % colors.length],
            }));
        })();

        return (
            <div className="space-y-6 animate-fade-in">
                <div className="grid grid-cols-1 gap-6"><StatCard title="ค่าใช้จ่ายที่ดินรวม" value={totalLand} icon={MapPin} color="#8b5cf6" /></div>
                {/* กราฟเปรียบเทียบ: แท่งรายวัน + สัดส่วนรายโครงการ/รายการ */}
                <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
                    <Card className="lg:col-span-2 p-4 sm:p-5">
                        <h3 className="font-bold text-slate-700 text-sm mb-3 flex items-center gap-2"><BarChart3 size={18} /> เปรียบเทียบค่าใช้จ่ายที่ดินรายวัน</h3>
                        <div className="h-44">
                            <BarChart data={landBar.data} labels={landBar.labels} color="#8b5cf6" />
                        </div>
                    </Card>
                    <Card className="p-4 sm:p-5 flex flex-col">
                        <h3 className="font-bold text-slate-700 text-sm mb-3 flex items-center gap-2"><PieChart size={18} /> สัดส่วนรายโครงการ/รายการ</h3>
                        {landDonutData.length > 0 ? (
                            <>
                                <div className="flex-1 flex items-center justify-center min-h-[140px]">
                                    <DonutChartSimple data={landDonutData} />
                                </div>
                                <div className="flex flex-wrap gap-2 justify-center mt-2 pt-2 border-t border-slate-100 text-xs">
                                    {landDonutData.map((d, i) => (
                                        <span key={i} className="flex items-center gap-1.5" title={d.label}>
                                            <span className="w-2 h-2 rounded-full shrink-0" style={{ backgroundColor: d.color }} />
                                            <span className="truncate max-w-[80px]">{d.label}</span>: ฿{d.value.toLocaleString()}
                                        </span>
                                    ))}
                                </div>
                            </>
                        ) : (
                            <div className="flex-1 flex items-center justify-center text-slate-400 text-sm min-h-[140px]">ไม่มีข้อมูล</div>
                        )}
                    </Card>
                </div>
                <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                    <Card className="p-4 sm:p-5">
                        <h3 className="font-bold text-slate-700 text-sm mb-3 flex items-center gap-2"><MapPin size={18} /> แนวโน้มค่าใช้จ่ายที่ดิน</h3>
                        <div className="h-32"><LineChart data={getTrend('Land')} color="#8b5cf6" height={48} /></div>
                    </Card>
                    <Card className="p-6">
                        <h3 className="font-bold text-slate-700 mb-4 flex items-center gap-2"><MapPin size={20} /> รายละเอียดรายการที่ดินรายวัน</h3>
                        <div className="space-y-2 max-h-80 overflow-y-auto">
                            {landTxByDate.map(([d, txs]) => (
                                <div key={d} className="border rounded-xl overflow-hidden">
                                    <button type="button" onClick={() => setExpandedDate(expandedDate === d ? null : d)}
                                        className="w-full flex justify-between items-center p-3 bg-purple-50 hover:bg-purple-100 transition-colors text-left">
                                        <span className="text-sm font-bold text-purple-800">{formatThaiDate(d)}</span>
                                        <span className="text-xs bg-purple-200 text-purple-800 px-2 py-0.5 rounded-full">{txs.length} รายการ • ฿{txs.reduce((s, t) => s + t.amount, 0).toLocaleString()}</span>
                                        {expandedDate === d ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
                                    </button>
                                    {expandedDate === d && (
                                        <div className="p-3 bg-white space-y-2">
                                            {txs.map(t => (
                                                <div key={t.id} className="flex justify-between items-start p-2.5 bg-slate-50 rounded-lg text-sm">
                                                    <div>
                                                        <div className="font-medium text-slate-700">{t.description}</div>
                                                        {t.projectId && <div className="text-xs text-slate-500">โครงการ: {t.projectId}</div>}
                                                    </div>
                                                    <span className="font-bold text-slate-800 shrink-0 ml-3">฿{t.amount.toLocaleString()}</span>
                                                </div>
                                            ))}
                                        </div>
                                    )}
                                </div>
                            ))}
                            {landTxByDate.length === 0 && <p className="text-center text-sm text-slate-400 py-6">ไม่มีข้อมูลที่ดินในช่วงนี้</p>}
                        </div>
                    </Card>
                </div>
            </div>
        );
    }

    if (type === 'Income') {
        const incomeTxs = filteredTransactions.filter(t => t.type === 'Income');
        const totalIncome = incomeTxs.reduce((s, t) => s + t.amount, 0);
        const incomeByType = (settings.incomeTypes || []).map(tp => ({
            type: tp,
            val: incomeTxs.filter(t => t.category === 'Income' && (t.subCategory === tp || (t.description || '').includes(tp))).reduce((s, t) => s + t.amount, 0)
        }));
        const incomeBar = getDailyBarData((dateStr) => incomeTxs.filter(t => t.date === dateStr).reduce((s, t) => s + t.amount, 0));
        const incomeDonutData = incomeByType.filter(d => d.val > 0).map((d, i) => ({
            label: d.type,
            value: d.val,
            color: ['#3b82f6', '#0ea5e9', '#06b6d4', '#8b5cf6', '#6366f1'][i % 5]
        }));
        const incomeTrendData = (() => {
            const points = 7;
            const res: number[] = [];
            const start = new Date(dateFilter.start);
            const end = new Date(dateFilter.end);
            const diff = Math.ceil((end.getTime() - start.getTime()) / (1000 * 60 * 60 * 24)) + 1;
            const step = Math.max(1, Math.floor(diff / points));
            for (let i = 0; i < points; i++) {
                const d = new Date(start);
                d.setDate(d.getDate() + (i * step));
                if (d > end) break;
                const dateStr = d.toISOString().split('T')[0];
                res.push(incomeTxs.filter(t => t.date === dateStr).reduce((s, t) => s + t.amount, 0));
            }
            return res;
        })();

        return (
            <div className="space-y-6 animate-fade-in">
                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                    <StatCard title="รายรับรวมทั้งหมด" value={totalIncome} icon={Wallet} color="#3b82f6" />
                    <Card className="p-5 flex flex-col justify-center">
                        <p className="text-xs text-slate-500 mb-1">จำนวนวันที่มีรายรับ</p>
                        <p className="text-2xl font-bold text-slate-800">{new Set(incomeTxs.map(t => t.date)).size} วัน</p>
                    </Card>
                    <Card className="p-5 flex flex-col justify-center">
                        <p className="text-xs text-slate-500 mb-1">เฉลี่ยต่อวัน</p>
                        <p className="text-2xl font-bold text-blue-600">
                            ฿{incomeTxs.length ? Math.round(totalIncome / Math.max(1, new Set(incomeTxs.map(t => t.date)).size)).toLocaleString() : 0}
                        </p>
                    </Card>
                </div>
                {/* กราฟเปรียบเทียบ: แท่งรายวัน + สัดส่วนประเภทรายได้ */}
                <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
                    <Card className="lg:col-span-2 p-4 sm:p-5">
                        <h3 className="font-bold text-slate-700 text-sm mb-3 flex items-center gap-2"><BarChart3 size={18} /> เปรียบเทียบรายรับรายวัน</h3>
                        <div className="h-44">
                            <BarChart data={incomeBar.data} labels={incomeBar.labels} color="#3b82f6" />
                        </div>
                    </Card>
                    <Card className="p-4 sm:p-5 flex flex-col">
                        <h3 className="font-bold text-slate-700 text-sm mb-3 flex items-center gap-2"><PieChart size={18} /> สัดส่วนประเภทรายได้</h3>
                        {incomeDonutData.length > 0 ? (
                            <>
                                <div className="flex-1 flex items-center justify-center min-h-[140px]">
                                    <DonutChartSimple data={incomeDonutData} />
                                </div>
                                <div className="flex flex-wrap gap-2 justify-center mt-2 pt-2 border-t border-slate-100 text-xs">
                                    {incomeDonutData.map((d, i) => (
                                        <span key={i} className="flex items-center gap-1.5">
                                            <span className="w-2 h-2 rounded-full shrink-0" style={{ backgroundColor: d.color }} />
                                            {d.label}: ฿{d.value.toLocaleString()}
                                        </span>
                                    ))}
                                </div>
                            </>
                        ) : (
                            <div className="flex-1 flex items-center justify-center text-slate-400 text-sm min-h-[140px]">ไม่มีข้อมูล</div>
                        )}
                    </Card>
                </div>
                {/* สัดส่วนรายได้ (แถบ) + แนวโน้ม */}
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <Card className="p-6">
                        <h3 className="font-bold text-slate-700 text-sm mb-4">แยกตามประเภทรายได้</h3>
                        <div className="space-y-4 pt-2">
                            {incomeByType.map((d, i) => (
                                <div key={i}>
                                    <div className="flex justify-between text-sm mb-1">
                                        <span className="text-slate-600">{d.type}</span>
                                        <span className="font-bold text-slate-800">฿{d.val.toLocaleString()}</span>
                                    </div>
                                    <div className="h-2 bg-slate-100 rounded-full w-full overflow-hidden">
                                        <div
                                            className="h-full rounded-full transition-all duration-500"
                                            style={{ width: `${totalIncome > 0 ? (d.val / totalIncome) * 100 : 0}%`, backgroundColor: ['#3b82f6', '#0ea5e9', '#06b6d4', '#8b5cf6'][i % 4] }}
                                        />
                                    </div>
                                </div>
                            ))}
                            {incomeByType.every(d => d.val === 0) && <p className="text-sm text-slate-400 py-4 text-center">ไม่มีรายรับในช่วงนี้</p>}
                        </div>
                    </Card>
                    <Card className="p-4 sm:p-5">
                        <h3 className="font-bold text-slate-700 text-sm mb-3 flex items-center gap-2"><TrendingUp size={18} /> แนวโน้มรายรับ</h3>
                        <div className="h-32"><LineChart data={incomeTrendData} color="#3b82f6" height={48} /></div>
                    </Card>
                </div>
            </div>
        );
    }
    return <div className="p-8 text-center text-slate-400">Select a dashboard</div>;
};

export default SpecificDashboard;
