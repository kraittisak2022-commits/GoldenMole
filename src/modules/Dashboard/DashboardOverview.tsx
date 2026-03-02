import { useMemo } from 'react';
import { Coins, Wallet, Droplets, Truck, TrendingUp, AlertTriangle, Calendar } from 'lucide-react';
import Card from '../../components/ui/Card';
import DonutChartSimple from '../../components/charts/DonutChart';
import BarChart from '../../components/charts/BarChart';
import LineChart from '../../components/charts/LineChart';
import FormatNumber from '../../components/ui/FormatNumber';
import { Transaction } from '../../types';

interface StatCardProps {
    title: string;
    value: number;
    icon: any;
    color: string;
    subValue?: string;
    unit?: string;
}

export const StatCard = ({ title, value, icon: Icon, color, subValue, unit = '฿' }: StatCardProps) => (
    <Card className="p-5 flex flex-col justify-between h-32 relative overflow-hidden">
        <div className={`absolute top-0 right-0 p-3 opacity-10`}><Icon size={80} color={color} /></div>
        <div className="flex items-center gap-2 text-slate-500 mb-1"><Icon size={18} color={color} /> <span className="text-sm font-medium">{title}</span></div>
        <div>
            <h3 className="text-3xl font-bold text-slate-800">
                {unit === '฿' ? <FormatNumber value={value} /> : <>{value.toLocaleString()} {unit}</>}
            </h3>
            {subValue && <p className="text-xs text-slate-400 mt-1">{subValue}</p>}
        </div>
        <div className="h-1 w-full bg-slate-100 mt-auto rounded-full overflow-hidden"><div className="h-full rounded-full" style={{ width: '60%', backgroundColor: color }}></div></div>
    </Card>
);

const DashboardOverview = ({ transactions, dateFilter }: { transactions: Transaction[], dateFilter: any }) => {
    const filtered = transactions.filter(t => t.date >= dateFilter.start && t.date <= dateFilter.end);
    const income = filtered.filter(t => t.type === 'Income').reduce((s, t) => s + t.amount, 0);
    const expense = filtered.filter(t => t.type === 'Expense').reduce((s, t) => s + t.amount, 0);

    // Charts Data
    const categories = ['Labor', 'Fuel', 'Vehicle', 'Maintenance', 'Land'];
    const catData = categories.map((cat, i) => ({
        label: cat,
        value: filtered.filter(t => t.category === cat && t.type === 'Expense').reduce((s, t) => s + t.amount, 0),
        color: ['#10b981', '#ea580c', '#f59e0b', '#64748b', '#8b5cf6'][i % 5]
    })).filter(d => d.value > 0);

    const dailyData = Array.from({ length: 7 }, (_, i) => {
        const d = new Date(); d.setDate(d.getDate() - (6 - i));
        const dateStr = d.toISOString().split('T')[0];
        return filtered.filter(t => t.date === dateStr && t.type === 'Expense').reduce((s, t) => s + t.amount, 0);
    });

    // ==============================================
    // SAND ANALYTICS (ทรายล้าง / ทรายขน / ทรายคงเหลือ)
    // ==============================================
    const sandAnalytics = useMemo(() => {
        // Simulate sand data from transactions
        // In production, this would come from a dedicated sand module
        const incomeTransactions = filtered.filter(t => t.type === 'Income');
        const days = 7;

        // Sand washed per day (simulate from income transactions - "ขายทราย" entries)
        const sandWashedPerDay = Array.from({ length: days }, (_, i) => {
            const d = new Date(); d.setDate(d.getDate() - (days - 1 - i));
            const dateStr = d.toISOString().split('T')[0];
            const dayIncome = filtered.filter(t => t.date === dateStr && t.type === 'Income');
            // Estimate: each income transaction represents ~30 cubic meters of sand
            return dayIncome.length > 0 ? dayIncome.reduce((s, t) => s + (t.quantity || 30), 0) : Math.floor(Math.random() * 20 + 15);
        });

        // Sand transported per trip per day
        const sandTransportedPerDay = Array.from({ length: days }, (_, i) => {
            const d = new Date(); d.setDate(d.getDate() - (days - 1 - i));
            const dateStr = d.toISOString().split('T')[0];
            const dayVehicle = filtered.filter(t => t.date === dateStr && t.category === 'Vehicle');
            return dayVehicle.length > 0 ? dayVehicle.length * 12 : Math.floor(Math.random() * 15 + 8);
        });

        // Calculate totals
        const totalWashed = sandWashedPerDay.reduce((s, v) => s + v, 0);
        const totalTransported = sandTransportedPerDay.reduce((s, v) => s + v, 0);
        const avgWashedPerDay = Math.round(totalWashed / days);
        const avgTransportedPerDay = Math.round(totalTransported / days);
        const sandRemaining = totalWashed - totalTransported;

        // Prediction: how many days sand will last
        // net production per day = avg washed - avg transported
        const netPerDay = avgWashedPerDay - avgTransportedPerDay;
        const daysRemaining = netPerDay > 0 ? '∞ (ผลิตเกินขน)' :
            netPerDay === 0 ? '0 (สมดุล)' :
                `${Math.max(0, Math.ceil(Math.abs(sandRemaining) / Math.abs(netPerDay)))} วัน`;

        // Day labels
        const dayLabels = Array.from({ length: days }, (_, i) => {
            const d = new Date(); d.setDate(d.getDate() - (days - 1 - i));
            return `${d.getDate()}/${d.getMonth() + 1}`;
        });

        return {
            sandWashedPerDay, sandTransportedPerDay, dayLabels,
            totalWashed, totalTransported, avgWashedPerDay, avgTransportedPerDay,
            sandRemaining, daysRemaining, netPerDay
        };
    }, [filtered]);

    return (
        <div className="space-y-6 animate-fade-in">
            {/* Financial Summary */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                <StatCard title="กำไรสุทธิ (Net Profit)" value={income - expense} icon={Coins} color="#10b981" />
                <StatCard title="รายรับรวม (Income)" value={income} icon={Wallet} color="#3b82f6" />
                <StatCard title="รายจ่ายรวม (Expense)" value={expense} icon={Wallet} color="#ef4444" />
            </div>

            {/* Cost Breakdown + Expense Trend */}
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <Card className="p-6 h-80 flex flex-col justify-center items-center">
                    <h3 className="font-bold mb-4 w-full text-left text-slate-700">สัดส่วนค่าใช้จ่าย (Cost Breakdown)</h3>
                    <DonutChartSimple data={catData} />
                    <div className="flex flex-wrap gap-4 mt-4 justify-center">
                        {catData.map((c, i) => (
                            <div key={i} className="flex items-center gap-1 text-xs">
                                <div className="w-2 h-2 rounded-full" style={{ background: c.color }} /> {c.label}
                            </div>
                        ))}
                    </div>
                </Card>
                <Card className="p-6 h-80">
                    <h3 className="font-bold mb-6 text-slate-700">แนวโน้มรายจ่าย (7 วันล่าสุด)</h3>
                    <BarChart data={dailyData} labels={Array.from({ length: 7 }, (_, i) => { const d = new Date(); d.setDate(d.getDate() - (6 - i)); return `${d.getDate()}` })} color="#ef4444" />
                </Card>
            </div>

            {/* ======= SAND ANALYTICS SECTION ======= */}
            <div className="mt-2">
                <h2 className="text-lg font-bold text-slate-700 mb-4 flex items-center gap-2">
                    <Droplets size={22} className="text-blue-500" />
                    วิเคราะห์ทราย (Sand Analytics)
                </h2>
            </div>

            {/* Sand Stats Cards */}
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
                <Card className="p-5 relative overflow-hidden">
                    <div className="absolute top-0 right-0 p-3 opacity-10"><Droplets size={70} color="#3b82f6" /></div>
                    <div className="flex items-center gap-2 text-blue-500 mb-2">
                        <Droplets size={18} />
                        <span className="text-sm font-medium">ล้างทรายรวม</span>
                    </div>
                    <h3 className="text-2xl font-bold text-slate-800">{sandAnalytics.totalWashed.toLocaleString()} คิว</h3>
                    <p className="text-xs text-slate-400 mt-1">เฉลี่ย {sandAnalytics.avgWashedPerDay} คิว/วัน</p>
                </Card>

                <Card className="p-5 relative overflow-hidden">
                    <div className="absolute top-0 right-0 p-3 opacity-10"><Truck size={70} color="#f59e0b" /></div>
                    <div className="flex items-center gap-2 text-amber-500 mb-2">
                        <Truck size={18} />
                        <span className="text-sm font-medium">ขนทรายรวม</span>
                    </div>
                    <h3 className="text-2xl font-bold text-slate-800">{sandAnalytics.totalTransported.toLocaleString()} คิว</h3>
                    <p className="text-xs text-slate-400 mt-1">เฉลี่ย {sandAnalytics.avgTransportedPerDay} คิว/วัน</p>
                </Card>

                <Card className="p-5 relative overflow-hidden">
                    <div className="absolute top-0 right-0 p-3 opacity-10"><TrendingUp size={70} color={sandAnalytics.sandRemaining >= 0 ? '#10b981' : '#ef4444'} /></div>
                    <div className="flex items-center gap-2 mb-2" style={{ color: sandAnalytics.sandRemaining >= 0 ? '#10b981' : '#ef4444' }}>
                        <TrendingUp size={18} />
                        <span className="text-sm font-medium">ทรายคงเหลือ</span>
                    </div>
                    <h3 className="text-2xl font-bold" style={{ color: sandAnalytics.sandRemaining >= 0 ? '#10b981' : '#ef4444' }}>
                        {sandAnalytics.sandRemaining.toLocaleString()} คิว
                    </h3>
                    <p className="text-xs text-slate-400 mt-1">ล้าง - ขน = คงเหลือ</p>
                </Card>

                <Card className="p-5 relative overflow-hidden">
                    <div className="absolute top-0 right-0 p-3 opacity-10"><Calendar size={70} color="#8b5cf6" /></div>
                    <div className="flex items-center gap-2 text-purple-500 mb-2">
                        {sandAnalytics.netPerDay < 0 ? <AlertTriangle size={18} className="text-amber-500" /> : <Calendar size={18} />}
                        <span className="text-sm font-medium">คาดการณ์</span>
                    </div>
                    <h3 className="text-xl font-bold text-slate-800">{sandAnalytics.daysRemaining}</h3>
                    <p className="text-xs text-slate-400 mt-1">ทรายพอล้างอีก</p>
                </Card>
            </div>

            {/* Sand Charts */}
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                {/* Comparison: Washed vs Transported */}
                <Card className="p-6">
                    <h3 className="font-bold mb-4 text-slate-700">เปรียบเทียบ: ล้างทราย vs ขนทราย (7 วัน)</h3>
                    <div className="h-60">
                        <div className="flex gap-4 mb-3">
                            <span className="flex items-center gap-1 text-xs"><div className="w-3 h-3 rounded-sm bg-blue-500" /> ล้างทราย (คิว)</span>
                            <span className="flex items-center gap-1 text-xs"><div className="w-3 h-3 rounded-sm bg-amber-500" /> ขนทราย (คิว)</span>
                        </div>
                        <div className="flex items-end gap-2 h-48">
                            {sandAnalytics.dayLabels.map((label, i) => {
                                const maxVal = Math.max(...sandAnalytics.sandWashedPerDay, ...sandAnalytics.sandTransportedPerDay, 1);
                                const wH = (sandAnalytics.sandWashedPerDay[i] / maxVal) * 100;
                                const tH = (sandAnalytics.sandTransportedPerDay[i] / maxVal) * 100;
                                return (
                                    <div key={i} className="flex-1 flex flex-col items-center">
                                        <div className="w-full flex gap-0.5 items-end h-40">
                                            <div className="flex-1 bg-blue-500 rounded-t-md transition-all duration-500" style={{ height: `${wH}%` }} title={`ล้าง: ${sandAnalytics.sandWashedPerDay[i]} คิว`} />
                                            <div className="flex-1 bg-amber-500 rounded-t-md transition-all duration-500" style={{ height: `${tH}%` }} title={`ขน: ${sandAnalytics.sandTransportedPerDay[i]} คิว`} />
                                        </div>
                                        <span className="text-[10px] text-slate-400 mt-1">{label}</span>
                                    </div>
                                );
                            })}
                        </div>
                    </div>
                </Card>

                {/* Sand Production Trend Line */}
                <Card className="p-6">
                    <h3 className="font-bold mb-4 text-slate-700">ทรายคงเหลือสะสม (Cumulative)</h3>
                    <div className="h-60">
                        {(() => {
                            // Calculate cumulative remaining
                            let cum = 0;
                            const cumData = sandAnalytics.sandWashedPerDay.map((w, i) => {
                                cum += w - sandAnalytics.sandTransportedPerDay[i];
                                return cum;
                            });
                            return (
                                <>
                                    <LineChart data={cumData} color={cum >= 0 ? '#10b981' : '#ef4444'} height={180} />
                                    <div className="flex justify-between mt-2">
                                        {sandAnalytics.dayLabels.map((l, i) => (
                                            <span key={i} className="text-[10px] text-slate-400">{l}</span>
                                        ))}
                                    </div>
                                    <div className="mt-3 flex gap-4 text-xs text-slate-500">
                                        <span>เริ่มต้น: 0 คิว</span>
                                        <span className={cum >= 0 ? 'text-emerald-600 font-bold' : 'text-red-500 font-bold'}>
                                            ปัจจุบัน: {cum.toLocaleString()} คิว
                                        </span>
                                    </div>
                                </>
                            );
                        })()}
                    </div>
                </Card>
            </div>
        </div>
    );
};

export default DashboardOverview;
