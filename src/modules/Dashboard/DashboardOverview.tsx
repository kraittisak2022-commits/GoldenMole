import { Coins, Wallet } from 'lucide-react';
import Card from '../../components/ui/Card';
import DonutChartSimple from '../../components/charts/DonutChart';
import BarChart from '../../components/charts/BarChart';
import FormatNumber from '../../components/ui/FormatNumber';
import { Transaction } from '../../types';

interface StatCardProps {
    title: string;
    value: number;
    icon: any;
    color: string;
    subValue?: string;
}

export const StatCard = ({ title, value, icon: Icon, color, subValue }: StatCardProps) => (
    <Card className="p-5 flex flex-col justify-between h-32 relative overflow-hidden">
        <div className={`absolute top-0 right-0 p-3 opacity-10`}><Icon size={80} color={color} /></div>
        <div className="flex items-center gap-2 text-slate-500 mb-1"><Icon size={18} color={color} /> <span className="text-sm font-medium">{title}</span></div>
        <div>
            <h3 className="text-3xl font-bold text-slate-800"><FormatNumber value={value} /></h3>
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

    return (
        <div className="space-y-6 animate-fade-in">
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                <StatCard title="กำไรสุทธิ (Net Profit)" value={income - expense} icon={Coins} color="#10b981" />
                <StatCard title="รายรับรวม (Income)" value={income} icon={Wallet} color="#3b82f6" />
                <StatCard title="รายจ่ายรวม (Expense)" value={expense} icon={Wallet} color="#ef4444" />
            </div>
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
        </div>
    );
};

export default DashboardOverview;
