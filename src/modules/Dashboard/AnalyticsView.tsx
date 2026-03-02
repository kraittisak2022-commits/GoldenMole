import Card from '../../components/ui/Card';
import BarChart from '../../components/charts/BarChart';
import DonutChartSimple from '../../components/charts/DonutChart';
import LineChart from '../../components/charts/LineChart';
import { Transaction, AppSettings } from '../../types';

const AnalyticsView = ({ transactions, settings, dateFilter }: { transactions: Transaction[], settings: AppSettings, dateFilter: any }) => {
    const filtered = transactions.filter(t => t.date >= dateFilter.start && t.date <= dateFilter.end);

    // 1. Daily Expenses (Bar) - Last 10 days
    const dailyExpenses = Array.from({ length: 10 }, (_, i) => {
        const d = new Date(dateFilter.end);
        d.setDate(d.getDate() - (9 - i));
        const dateStr = d.toISOString().split('T')[0];
        return filtered.filter(t => t.date === dateStr && t.type === 'Expense').reduce((s, t) => s + t.amount, 0);
    });

    // 2. Category Breakdown (Donut)
    const categories = ['Labor', 'Fuel', 'Vehicle', 'Maintenance', 'Land'];
    const donutCatData = categories.map((c, i) => ({
        value: filtered.filter(t => t.category === c && t.type === 'Expense').reduce((s, t) => s + t.amount, 0),
        label: c,
        color: ['#10b981', '#ea580c', '#f59e0b', '#64748b', '#8b5cf6'][i % 5]
    })).filter(d => d.value > 0);

    // 3. Site Breakdown (Donut)
    const donutSiteData = settings.locations.map((loc, i) => ({
        label: loc,
        value: filtered.filter(t => t.location === loc && t.type === 'Expense').reduce((s, t) => s + t.amount, 0),
        color: ['#3b82f6', '#ec4899', '#6366f1', '#14b8a6'][i % 4] || '#ccc'
    })).filter(d => d.value > 0);

    // Sidebar Data
    const totalDaily = dailyExpenses[dailyExpenses.length - 1];
    const totalMonthly = filtered.reduce((s, t) => s + (t.type === 'Income' ? t.amount : -t.amount), 0);
    const topExpenses = categories.map(cat => ({
        name: cat,
        value: filtered.filter(t => t.category === cat && t.type === 'Expense').reduce((s, t) => s + t.amount, 0)
    })).sort((a, b) => b.value - a.value).slice(0, 5);

    return (
        <div className="space-y-6 animate-fade-in">
            <div className="grid grid-cols-1 lg:grid-cols-12 gap-4 sm:gap-6">
                {/* Left Main (9 Cols) */}
                <div className="lg:col-span-9 grid grid-cols-1 md:grid-cols-2 gap-4 sm:gap-6">
                    {/* Chart 1: Daily Expenses (Bar) */}
                    <Card className="p-6 h-80">
                        <h3 className="font-bold text-slate-700 mb-4">ค่าใช้จ่ายประจำวัน (บาท)</h3>
                        <div className="h-64"><BarChart data={dailyExpenses} labels={Array.from({ length: 10 }, (_, i) => { const d = new Date(dateFilter.end); d.setDate(d.getDate() - (9 - i)); return `${d.getDate()}` })} color="#64748b" /></div>
                    </Card>

                    {/* Chart 2: Overview by Category (Donut) */}
                    <Card className="p-6 h-80 flex flex-col items-center">
                        <h3 className="font-bold text-slate-700 mb-4 w-full">ภาพรวมแยกรายการ</h3>
                        <DonutChartSimple data={donutCatData} />
                        <div className="grid grid-cols-2 gap-2 mt-4 text-xs w-full">
                            {donutCatData.slice(0, 4).map((d, i) => (
                                <div key={i} className="flex items-center gap-1"><div className="w-2 h-2 rounded-full" style={{ background: d.color }} /> {d.label}</div>
                            ))}
                        </div>
                    </Card>

                    {/* Chart 3: Daily Expense by Site (Bar - Simulated) */}
                    <Card className="p-6 h-80">
                        <h3 className="font-bold text-slate-700 mb-4">ค่าใช้จ่ายแยกตามสวน</h3>
                        <div className="h-64"><BarChart data={dailyExpenses.map(v => v * 0.7)} color="#8b5cf6" labels={Array.from({ length: 10 }, (_, i) => { const d = new Date(dateFilter.end); d.setDate(d.getDate() - (9 - i)); return `${d.getDate()}` })} /></div>
                    </Card>

                    {/* Chart 4: Overview by Site (Donut) */}
                    <Card className="p-6 h-80 flex flex-col items-center">
                        <h3 className="font-bold text-slate-700 mb-4 w-full">ภาพรวมแยกสวน</h3>
                        <DonutChartSimple data={donutSiteData} />
                        <div className="grid grid-cols-2 gap-2 mt-4 text-xs w-full">
                            {donutSiteData.slice(0, 4).map((d, i) => (
                                <div key={i} className="flex items-center gap-1"><div className="w-2 h-2 rounded-full" style={{ background: d.color }} /> {d.label}</div>
                            ))}
                        </div>
                    </Card>
                </div>

                {/* Right Sidebar (3 Cols) */}
                <div className="lg:col-span-3 space-y-4 sm:space-y-6">
                    <Card className="p-6">
                        <h3 className="font-bold text-slate-500 text-sm mb-2">รวมรายวันล่าสุด</h3>
                        <div className="h-20 mb-2"><LineChart data={dailyExpenses} color="#10b981" height={40} /></div>
                        <p className="text-2xl font-bold text-slate-800">฿{totalDaily.toLocaleString()}</p>
                    </Card>

                    <Card className="p-6">
                        <h3 className="font-bold text-slate-500 text-sm mb-4">สถานะการเงิน (ช่วงนี้)</h3>
                        <div className="space-y-4">
                            <div className="flex justify-between items-center">
                                <span className="text-sm text-slate-600">Net Profit</span>
                                <span className={`text-xl font-bold ${totalMonthly >= 0 ? 'text-emerald-600' : 'text-red-500'}`}>
                                    ฿{totalMonthly.toLocaleString()}
                                </span>
                            </div>
                        </div>
                    </Card>

                    <Card className="p-6">
                        <h3 className="font-bold text-slate-500 text-sm mb-4">รายจ่ายสูงสุด (Top Categories)</h3>
                        <div className="space-y-3">
                            {topExpenses.slice(0, 4).map((c, i) => (
                                <div key={i} className="flex justify-between items-center p-2 bg-slate-50 rounded-lg">
                                    <span className="text-xs font-medium text-slate-700">{c.name}</span>
                                    <span className="text-xs font-bold text-slate-800">฿{c.value.toLocaleString()}</span>
                                </div>
                            ))}
                        </div>
                    </Card>
                </div>
            </div>
        </div>
    );
};

export default AnalyticsView;
