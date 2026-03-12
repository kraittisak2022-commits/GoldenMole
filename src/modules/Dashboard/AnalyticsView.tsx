import { useMemo } from 'react';
import { TrendingDown, Truck, Calendar, DollarSign, BarChart3, ArrowDown, ArrowUp, Minus } from 'lucide-react';
import Card from '../../components/ui/Card';
import BarChart from '../../components/charts/BarChart';
import DonutChartSimple from '../../components/charts/DonutChart';
import LineChart from '../../components/charts/LineChart';
import FormatNumber from '../../components/ui/FormatNumber';
import { Transaction, AppSettings } from '../../types';

const AnalyticsView = ({ transactions, settings, dateFilter }: { transactions: Transaction[], settings: AppSettings, dateFilter: any }) => {
    const filtered = transactions.filter(t => t.date >= dateFilter.start && t.date <= dateFilter.end);

    // ============================
    // EXPENSE ANALYTICS
    // ============================
    const analytics = useMemo(() => {
        const expenses = filtered.filter(t => t.type === 'Expense');
        const incomes = filtered.filter(t => t.type === 'Income');
        const totalExpense = expenses.reduce((s, t) => s + t.amount, 0);
        const totalIncome = incomes.reduce((s, t) => s + t.amount, 0);

        // --- Daily Expenses (ตามช่วง dateFilter) ---
        const numDays = Math.max(1, Math.ceil((new Date(dateFilter.end).getTime() - new Date(dateFilter.start).getTime()) / (1000 * 60 * 60 * 24)) + 1);
        const dailyExpenses: { date: string; label: string; total: number; labor: number; fuel: number; vehicle: number; maintenance: number; land: number }[] = [];
        for (let i = 0; i < numDays; i++) {
            const d = new Date(dateFilter.start);
            d.setDate(d.getDate() + i);
            const dateStr = d.toISOString().split('T')[0];
            if (dateStr > dateFilter.end) break;
            dailyExpenses.push({
                date: dateStr,
                label: `${d.getDate()}/${d.getMonth() + 1}`,
                total: expenses.filter(t => t.date === dateStr).reduce((s, t) => s + t.amount, 0),
                labor: expenses.filter(t => t.date === dateStr && t.category === 'Labor').reduce((s, t) => s + t.amount, 0),
                fuel: expenses.filter(t => t.date === dateStr && t.category === 'Fuel').reduce((s, t) => s + t.amount, 0),
                vehicle: expenses.filter(t => t.date === dateStr && (t.category === 'Vehicle' || (t.category === 'DailyLog' && t.subCategory === 'VehicleTrip'))).reduce((s, t) => s + t.amount, 0),
                maintenance: expenses.filter(t => t.date === dateStr && t.category === 'Maintenance').reduce((s, t) => s + t.amount, 0),
                land: expenses.filter(t => t.date === dateStr && t.category === 'Land').reduce((s, t) => s + t.amount, 0),
            });
        }

        // --- Weekly Expenses (ตามช่วง dateFilter) ---
        const weeklyExpenses: { label: string; total: number; labor: number; fuel: number; vehicle: number; land: number }[] = [];
        const endDate = new Date(dateFilter.end);
        const startDate = new Date(dateFilter.start);
        const totalWeeks = Math.max(1, Math.ceil(numDays / 7));
        for (let w = 0; w < totalWeeks; w++) {
            const weekStart = new Date(startDate);
            weekStart.setDate(startDate.getDate() + (w * 7));
            const weekEnd = new Date(weekStart);
            weekEnd.setDate(weekStart.getDate() + 6);
            const wStart = weekStart.toISOString().split('T')[0];
            let wEnd = weekEnd.toISOString().split('T')[0];
            if (wEnd > dateFilter.end) wEnd = dateFilter.end;
            const weekExpenses = expenses.filter(t => t.date >= wStart && t.date <= wEnd);
            weeklyExpenses.push({
                label: `สัปดาห์ ${w + 1}`,
                total: weekExpenses.reduce((s, t) => s + t.amount, 0),
                labor: weekExpenses.filter(t => t.category === 'Labor').reduce((s, t) => s + t.amount, 0),
                fuel: weekExpenses.filter(t => t.category === 'Fuel').reduce((s, t) => s + t.amount, 0),
                vehicle: weekExpenses.filter(t => t.category === 'Vehicle' || (t.category === 'DailyLog' && t.subCategory === 'VehicleTrip')).reduce((s, t) => s + t.amount, 0),
                land: weekExpenses.filter(t => t.category === 'Land').reduce((s, t) => s + t.amount, 0),
            });
        }

        // --- By Category ---
        const categories = ['Labor', 'Fuel', 'Vehicle', 'Maintenance', 'Land'];
        const categoryNames: Record<string, string> = { 'Labor': 'ค่าแรง', 'Fuel': 'น้ำมัน', 'Vehicle': 'การใช้รถ', 'Maintenance': 'ซ่อมบำรุง', 'Land': 'ที่ดิน' };
        const catColors = ['#10b981', '#ea580c', '#f59e0b', '#64748b', '#8b5cf6'];
        const catData = categories.map((cat, i) => ({
            label: categoryNames[cat] || cat,
            value: expenses.filter(t => t.category === cat).reduce((s, t) => s + t.amount, 0),
            color: catColors[i]
        })).filter(d => d.value > 0);

        // --- Vehicle Cost Breakdown (เฉพาะข้อมูลจริง ไม่จำลอง) ---
        const vehicleCosts = (settings.cars || []).map((car, i) => ({
            name: car,
            fuel: expenses.filter(t => t.category === 'Fuel' && t.description?.includes(car)).reduce((s, t) => s + t.amount, 0),
            maintenance: expenses.filter(t => t.category === 'Maintenance' && t.description?.includes(car)).reduce((s, t) => s + t.amount, 0),
            total: expenses.filter(t => (t.category === 'Fuel' || t.category === 'Maintenance' || t.category === 'Vehicle') && t.description?.includes(car)).reduce((s, t) => s + t.amount, 0),
            color: ['#3b82f6', '#ef4444', '#f59e0b', '#8b5cf6', '#ec4899'][i % 5]
        }));
        const vehicleDisplay = vehicleCosts.filter(v => v.total > 0);

        // --- Average per day ---
        const avgPerDay = numDays > 0 ? Math.round(totalExpense / numDays) : 0;
        const avgPerWeek = Math.round(totalExpense / Math.max(1, numDays / 7));

        // Today vs yesterday comparison
        const today = dailyExpenses[dailyExpenses.length - 1]?.total || 0;
        const yesterday = dailyExpenses[dailyExpenses.length - 2]?.total || 0;
        const dayChange = yesterday > 0 ? Math.round(((today - yesterday) / yesterday) * 100) : 0;

        // This week vs last week
        const thisWeek = weeklyExpenses[weeklyExpenses.length - 1]?.total || 0;
        const lastWeek = weeklyExpenses[weeklyExpenses.length - 2]?.total || 0;
        const weekChange = lastWeek > 0 ? Math.round(((thisWeek - lastWeek) / lastWeek) * 100) : 0;

        return {
            totalExpense, totalIncome, dailyExpenses, weeklyExpenses,
            catData, vehicleDisplay, avgPerDay, avgPerWeek,
            today, yesterday, dayChange, thisWeek, lastWeek, weekChange,
            numDays
        };
    }, [filtered, dateFilter, settings]);

    const ChangeIndicator = ({ value }: { value: number }) => (
        <span className={`inline-flex items-center gap-0.5 text-xs font-bold ${value > 0 ? 'text-red-500' : value < 0 ? 'text-emerald-500' : 'text-slate-400'}`}>
            {value > 0 ? <ArrowUp size={12} /> : value < 0 ? <ArrowDown size={12} /> : <Minus size={12} />}
            {Math.abs(value)}%
        </span>
    );

    return (
        <div className="space-y-6 animate-fade-in">
            {/* Summary Stats Row */}
            <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
                <Card className="p-5 relative overflow-hidden">
                    <div className="absolute top-0 right-0 p-2 opacity-10"><DollarSign size={60} color="#ef4444" /></div>
                    <p className="text-xs font-medium text-slate-500 mb-1">รายจ่ายรวม</p>
                    <h3 className="text-2xl font-bold text-slate-800"><FormatNumber value={analytics.totalExpense} /></h3>
                    <p className="text-xs text-slate-400 mt-1">{analytics.numDays} วัน</p>
                </Card>
                <Card className="p-5 relative overflow-hidden">
                    <div className="absolute top-0 right-0 p-2 opacity-10"><Calendar size={60} color="#3b82f6" /></div>
                    <p className="text-xs font-medium text-slate-500 mb-1">เฉลี่ย/วัน</p>
                    <h3 className="text-2xl font-bold text-slate-800"><FormatNumber value={analytics.avgPerDay} /></h3>
                    <div className="flex items-center gap-1 mt-1">
                        <span className="text-xs text-slate-400">vs เมื่อวาน</span>
                        <ChangeIndicator value={analytics.dayChange} />
                    </div>
                </Card>
                <Card className="p-5 relative overflow-hidden">
                    <div className="absolute top-0 right-0 p-2 opacity-10"><BarChart3 size={60} color="#f59e0b" /></div>
                    <p className="text-xs font-medium text-slate-500 mb-1">เฉลี่ย/สัปดาห์</p>
                    <h3 className="text-2xl font-bold text-slate-800"><FormatNumber value={analytics.avgPerWeek} /></h3>
                    <div className="flex items-center gap-1 mt-1">
                        <span className="text-xs text-slate-400">vs สัปดาห์ก่อน</span>
                        <ChangeIndicator value={analytics.weekChange} />
                    </div>
                </Card>
                <Card className="p-5 relative overflow-hidden">
                    <div className="absolute top-0 right-0 p-2 opacity-10"><TrendingDown size={60} color="#10b981" /></div>
                    <p className="text-xs font-medium text-slate-500 mb-1">กำไรสุทธิ (ช่วงนี้)</p>
                    <h3 className={`text-2xl font-bold ${(analytics.totalIncome - analytics.totalExpense) >= 0 ? 'text-emerald-600' : 'text-red-500'}`}>
                        <FormatNumber value={analytics.totalIncome - analytics.totalExpense} />
                    </h3>
                    <p className="text-xs text-slate-400 mt-1">รายรับ - รายจ่าย</p>
                </Card>
            </div>

            {/* Charts Grid */}
            <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
                {/* Left: Main Charts */}
                <div className="lg:col-span-8 space-y-6">
                    {/* Daily Expense Trend with Breakdown */}
                    <Card className="p-6">
                        <h3 className="font-bold text-slate-700 mb-4">รายจ่ายประจำวัน (Daily Expenses)</h3>
                        <div className="h-56">
                            <BarChart
                                data={analytics.dailyExpenses.map(d => d.total)}
                                labels={analytics.dailyExpenses.map(d => d.label)}
                                color="#64748b"
                            />
                        </div>
                        {/* Daily breakdown table */}
                        <div className="mt-4 overflow-x-auto">
                            <table className="w-full text-xs">
                                <thead>
                                    <tr className="border-b border-slate-100">
                                        <th className="text-left py-2 text-slate-500 font-medium">วันที่</th>
                                        <th className="text-right py-2 text-slate-500 font-medium">ค่าแรง</th>
                                        <th className="text-right py-2 text-slate-500 font-medium">น้ำมัน</th>
                                        <th className="text-right py-2 text-slate-500 font-medium">รถ</th>
                                        <th className="text-right py-2 text-slate-500 font-medium">ซ่อม</th>
                                        <th className="text-right py-2 text-slate-500 font-medium">ที่ดิน</th>
                                        <th className="text-right py-2 text-slate-700 font-bold">รวม</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {analytics.dailyExpenses.slice(-Math.min(10, analytics.dailyExpenses.length)).map((d, i) => (
                                        <tr key={i} className="border-b border-slate-50 hover:bg-slate-50">
                                            <td className="py-2 text-slate-600">{d.label}</td>
                                            <td className="text-right text-emerald-600">{d.labor > 0 ? `฿${d.labor.toLocaleString()}` : '-'}</td>
                                            <td className="text-right text-orange-600">{d.fuel > 0 ? `฿${d.fuel.toLocaleString()}` : '-'}</td>
                                            <td className="text-right text-amber-600">{d.vehicle > 0 ? `฿${d.vehicle.toLocaleString()}` : '-'}</td>
                                            <td className="text-right text-slate-600">{d.maintenance > 0 ? `฿${d.maintenance.toLocaleString()}` : '-'}</td>
                                            <td className="text-right text-purple-600">{d.land > 0 ? `฿${d.land.toLocaleString()}` : '-'}</td>
                                            <td className="text-right font-bold text-slate-800">฿{d.total.toLocaleString()}</td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    </Card>

                    {/* Weekly Comparison */}
                    <Card className="p-6">
                        <h3 className="font-bold text-slate-700 mb-4">เปรียบเทียบรายสัปดาห์ (Weekly Comparison)</h3>
                        <div className="h-48">
                            <BarChart
                                data={analytics.weeklyExpenses.map(w => w.total)}
                                labels={analytics.weeklyExpenses.map(w => w.label)}
                                color="#8b5cf6"
                            />
                        </div>
                        {/* Weekly detail cards */}
                        <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mt-4">
                            {analytics.weeklyExpenses.map((w, i) => (
                                <div key={i} className="bg-slate-50 rounded-xl p-3">
                                    <p className="text-xs text-slate-500 font-medium">{w.label}</p>
                                    <p className="text-lg font-bold text-slate-800 mt-1">฿{w.total.toLocaleString()}</p>
                                    <div className="mt-2 space-y-1">
                                        <div className="flex justify-between text-[10px]">
                                            <span className="text-emerald-600">ค่าแรง</span>
                                            <span className="font-bold">฿{w.labor.toLocaleString()}</span>
                                        </div>
                                        <div className="flex justify-between text-[10px]">
                                            <span className="text-orange-600">น้ำมัน</span>
                                            <span className="font-bold">฿{w.fuel.toLocaleString()}</span>
                                        </div>
                                        <div className="flex justify-between text-[10px]">
                                            <span className="text-amber-600">รถ</span>
                                            <span className="font-bold">฿{w.vehicle.toLocaleString()}</span>
                                        </div>
                                        <div className="flex justify-between text-[10px]">
                                            <span className="text-purple-600">ที่ดิน</span>
                                            <span className="font-bold">฿{w.land.toLocaleString()}</span>
                                        </div>
                                    </div>
                                </div>
                            ))}
                        </div>
                    </Card>
                </div>

                {/* Right Sidebar */}
                <div className="lg:col-span-4 space-y-6">
                    {/* Category Donut */}
                    <Card className="p-6">
                        <h3 className="font-bold text-slate-700 mb-4">สัดส่วนรายจ่าย</h3>
                        <DonutChartSimple data={analytics.catData} />
                        <div className="mt-4 space-y-2">
                            {analytics.catData.map((c, i) => (
                                <div key={i} className="flex items-center justify-between p-2 bg-slate-50 rounded-lg">
                                    <div className="flex items-center gap-2">
                                        <div className="w-3 h-3 rounded-full" style={{ background: c.color }} />
                                        <span className="text-xs font-medium text-slate-700">{c.label}</span>
                                    </div>
                                    <span className="text-xs font-bold text-slate-800">฿{c.value.toLocaleString()}</span>
                                </div>
                            ))}
                        </div>
                    </Card>

                    {/* Vehicle Cost Comparison */}
                    <Card className="p-6">
                        <h3 className="font-bold text-slate-700 mb-1 flex items-center gap-2">
                            <Truck size={18} className="text-amber-500" />
                            ค่าใช้จ่ายต่อรถ
                        </h3>
                        <p className="text-xs text-slate-400 mb-4">รวมน้ำมัน + ซ่อมบำรุง (เฉพาะข้อมูลที่บันทึก)</p>
                        <div className="space-y-3">
                            {analytics.vehicleDisplay.length === 0 ? (
                                <p className="text-sm text-slate-400 py-2">ไม่มีข้อมูลค่าใช้จ่ายต่อรถในช่วงนี้</p>
                            ) : analytics.vehicleDisplay.slice(0, 5).map((v, i) => {
                                const maxCost = Math.max(...analytics.vehicleDisplay.map(x => x.total), 1);
                                const pct = Math.round((v.total / maxCost) * 100);
                                return (
                                    <div key={i}>
                                        <div className="flex justify-between text-xs mb-1">
                                            <span className="text-slate-600 truncate max-w-[65%]" title={v.name}>
                                                {v.name.length > 20 ? v.name.substring(0, 20) + '...' : v.name}
                                            </span>
                                            <span className="font-bold text-slate-800">฿{v.total.toLocaleString()}</span>
                                        </div>
                                        <div className="h-2 w-full bg-slate-100 rounded-full overflow-hidden">
                                            <div className="h-full rounded-full transition-all duration-700" style={{ width: `${pct}%`, backgroundColor: v.color }} />
                                        </div>
                                        <div className="flex gap-3 mt-0.5 text-[10px] text-slate-400">
                                            <span>น้ำมัน: ฿{v.fuel.toLocaleString()}</span>
                                            <span>ซ่อม: ฿{v.maintenance.toLocaleString()}</span>
                                        </div>
                                    </div>
                                );
                            })}
                        </div>
                    </Card>

                    {/* Daily Trend Mini Chart */}
                    <Card className="p-6">
                        <h3 className="font-bold text-slate-500 text-sm mb-2">แนวโน้มรายจ่ายรวม</h3>
                        <div className="h-16 mb-2">
                            <LineChart data={analytics.dailyExpenses.map(d => d.total)} color="#ef4444" height={50} />
                        </div>
                        <div className="flex justify-between items-end">
                            <div>
                                <p className="text-xs text-slate-400">วันนี้</p>
                                <p className="text-xl font-bold text-slate-800">฿{analytics.today.toLocaleString()}</p>
                            </div>
                            <div className="text-right">
                                <p className="text-xs text-slate-400">เมื่อวาน</p>
                                <p className="text-sm font-medium text-slate-500">฿{analytics.yesterday.toLocaleString()}</p>
                            </div>
                        </div>
                    </Card>
                </div>
            </div>
        </div>
    );
};

export default AnalyticsView;
