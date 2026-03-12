import { useState, useMemo } from 'react';
import { Wallet, History, Pencil, Trash2, Calendar, TrendingUp, ChevronDown, ChevronUp } from 'lucide-react';
import Card from '../components/ui/Card';
import Button from '../components/ui/Button';
import Input from '../components/ui/Input';
import Select from '../components/ui/Select';
import { getToday, formatDateBE, normalizeDate } from '../utils';
import { Transaction, AppSettings } from '../types';

const MONTH_NAMES_TH = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];

const formatMonthLabel = (yyyyMm: string) => {
    const [y, m] = yyyyMm.split('-').map(Number);
    const beYear = (y || 0) + 543;
    return `${MONTH_NAMES_TH[(m || 1) - 1]} ${beYear}`;
};

interface IncomeEntryProps {
    settings: AppSettings;
    onSave: (t: Transaction) => void;
    onDelete?: (id: string) => void;
    transactions: Transaction[];
}

const IncomeEntry = ({ settings, onSave, onDelete, transactions }: IncomeEntryProps) => {
    const [form, setForm] = useState({ date: getToday(), qty: '', price: '', total: '', type: '' });
    const [editingId, setEditingId] = useState<string | null>(null);
    const [filterMonth, setFilterMonth] = useState<string>(''); // '' = ทั้งหมด
    const [showMonthlyExpand, setShowMonthlyExpand] = useState(true);
    const [showHistoryExpand, setShowHistoryExpand] = useState(true);
    const [searchQuery, setSearchQuery] = useState('');

    const incomeList = useMemo(() => transactions.filter(t => t.type === 'Income'), [transactions]);

    const byMonth = useMemo(() => {
        const map = new Map<string, { total: number; count: number; items: Transaction[] }>();
        incomeList.forEach(t => {
            const d = normalizeDate(t.date);
            const yyyyMm = d ? d.slice(0, 7) : '';
            if (!yyyyMm) return;
            if (!map.has(yyyyMm)) map.set(yyyyMm, { total: 0, count: 0, items: [] });
            const row = map.get(yyyyMm)!;
            row.total += t.amount || 0;
            row.count += 1;
            row.items.push(t);
        });
        return Array.from(map.entries())
            .sort((a, b) => b[0].localeCompare(a[0]))
            .map(([month, data]) => ({ month, ...data }));
    }, [incomeList]);

    const totalAll = useMemo(() => incomeList.reduce((s, t) => s + (t.amount || 0), 0), [incomeList]);

    const currentMonthKey = useMemo(() => {
        const d = new Date();
        return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    }, []);

    const currentMonthTotal = useMemo(() => {
        const row = byMonth.find(m => m.month === currentMonthKey);
        return row ? row.total : 0;
    }, [byMonth, currentMonthKey]);

    const history = useMemo(() => {
        let list = [...incomeList].sort((a, b) => (b.date || '').localeCompare(a.date || ''));
        if (filterMonth) list = list.filter(t => normalizeDate(t.date).slice(0, 7) === filterMonth);
        const q = searchQuery.trim().toLowerCase();
        if (q) list = list.filter(t => (t.description || '').toLowerCase().includes(q));
        return list.slice(0, 100);
    }, [incomeList, filterMonth, searchQuery]);

    const handleCalc = (f: string, v: string) => {
        const n = { ...form, [f]: v };
        if (f !== 'total') n.total = String(Number(n.qty) * Number(n.price));
        else if (Number(n.qty) > 0) n.price = String(Number(n.total) / Number(n.qty));
        setForm(n);
    };

    const loadForEdit = (t: Transaction) => {
        setForm({
            date: normalizeDate(t.date) || getToday(),
            type: t.description || '',
            total: t.amount != null ? String(t.amount) : '',
            qty: t.quantity != null ? String(t.quantity) : '',
            price: t.unitPrice != null ? String(t.unitPrice) : '',
        });
        setEditingId(t.id);
    };

    const handleSave = () => {
        if (!form.type || !form.total) return alert('กรอกข้อมูลให้ครบ');
        if (editingId && onDelete) {
            onDelete(editingId);
            setEditingId(null);
        }
        onSave({
            id: Date.now().toString(),
            date: form.date,
            type: 'Income',
            category: 'Income',
            description: form.type,
            amount: Number(form.total),
            quantity: form.qty ? Number(form.qty) : undefined,
            unitPrice: form.price ? Number(form.price) : undefined,
        } as Transaction);
        setForm({ date: getToday(), qty: '', price: '', total: '', type: '' });
    };

    return (
        <div className="max-w-4xl mx-auto space-y-6 animate-fade-in pb-6">
            {/* สรุปภาพรวม */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <Card className="p-5 bg-gradient-to-br from-emerald-50 to-teal-50 dark:from-emerald-900/20 dark:to-teal-900/20 border-emerald-200 dark:border-emerald-800">
                    <div className="flex items-center gap-3">
                        <div className="w-12 h-12 rounded-xl bg-emerald-500/20 flex items-center justify-center">
                            <Wallet className="w-6 h-6 text-emerald-600 dark:text-emerald-400" />
                        </div>
                        <div>
                            <p className="text-sm font-medium text-slate-600 dark:text-slate-400">รายรับรวมทั้งหมด</p>
                            <p className="text-2xl font-bold text-emerald-700 dark:text-emerald-300 tabular-nums">฿{totalAll.toLocaleString()}</p>
                        </div>
                    </div>
                </Card>
                <Card className="p-5 bg-gradient-to-br from-teal-50 to-cyan-50 dark:from-teal-900/20 dark:to-cyan-900/20 border-teal-200 dark:border-teal-800">
                    <div className="flex items-center gap-3">
                        <div className="w-12 h-12 rounded-xl bg-teal-500/20 flex items-center justify-center">
                            <Calendar className="w-6 h-6 text-teal-600 dark:text-teal-400" />
                        </div>
                        <div>
                            <p className="text-sm font-medium text-slate-600 dark:text-slate-400">รายรับเดือนนี้</p>
                            <p className="text-2xl font-bold text-teal-700 dark:text-teal-300 tabular-nums">฿{currentMonthTotal.toLocaleString()}</p>
                        </div>
                    </div>
                </Card>
            </div>

            {/* รวมรายเดือน */}
            <Card className="p-0 overflow-hidden border border-slate-200 dark:border-white/10">
                <button
                    type="button"
                    onClick={() => setShowMonthlyExpand(!showMonthlyExpand)}
                    className="w-full p-4 flex items-center justify-between bg-slate-50 dark:bg-white/[0.04] border-b border-slate-200 dark:border-white/10 hover:bg-slate-100 dark:hover:bg-white/[0.06] transition-colors"
                >
                    <span className="flex items-center gap-2 font-bold text-slate-800 dark:text-slate-100">
                        <TrendingUp size={20} className="text-emerald-500" /> รวมรายเดือน
                    </span>
                    {showMonthlyExpand ? <ChevronUp size={20} className="text-slate-500" /> : <ChevronDown size={20} className="text-slate-500" />}
                </button>
                {showMonthlyExpand && (
                    <div className="overflow-x-auto max-h-[320px] overflow-y-auto">
                        {byMonth.length === 0 ? (
                            <div className="p-8 text-center text-slate-500 dark:text-slate-400 text-sm">ยังไม่มีข้อมูลรายรับ</div>
                        ) : (
                            <table className="w-full text-sm">
                                <thead className="bg-slate-100 dark:bg-white/5 sticky top-0">
                                    <tr>
                                        <th className="p-3 text-left font-semibold text-slate-700 dark:text-slate-300">เดือน</th>
                                        <th className="p-3 text-right font-semibold text-slate-700 dark:text-slate-300">จำนวนรายการ</th>
                                        <th className="p-3 text-right font-semibold text-slate-700 dark:text-slate-300">รวม (บาท)</th>
                                    </tr>
                                </thead>
                                <tbody className="divide-y divide-slate-100 dark:divide-white/5">
                                    {byMonth.map(({ month, total, count }) => (
                                        <tr
                                            key={month}
                                            className={`hover:bg-slate-50 dark:hover:bg-white/[0.04] ${month === currentMonthKey ? 'bg-emerald-50 dark:bg-emerald-900/20' : ''}`}
                                        >
                                            <td className="p-3">
                                                <span className="font-medium text-slate-800 dark:text-slate-200">{formatMonthLabel(month)}</span>
                                                {month === currentMonthKey && (
                                                    <span className="ml-2 text-xs px-2 py-0.5 rounded bg-emerald-200 dark:bg-emerald-800 text-emerald-800 dark:text-emerald-200">เดือนนี้</span>
                                                )}
                                            </td>
                                            <td className="p-3 text-right text-slate-600 dark:text-slate-400">{count}</td>
                                            <td className="p-3 text-right font-bold text-emerald-600 dark:text-emerald-400 tabular-nums">฿{total.toLocaleString()}</td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        )}
                    </div>
                )}
            </Card>

            {/* บันทึกรายรับ */}
            <Card className="p-6 border border-slate-200 dark:border-white/10 shadow-sm">
                <h3 className="font-bold text-lg mb-6 flex items-center gap-2 text-slate-800 dark:text-slate-100"><Wallet className="text-emerald-500" /> บันทึกรายรับ</h3>
                <div className="space-y-4">
                    <Input label="วันที่" type="date" value={form.date} onChange={(e: any) => { setForm({ ...form, date: e.target.value }); setEditingId(null); }} />
                    <Select label="ประเภท" value={form.type} onChange={(e: any) => setForm({ ...form, type: e.target.value })}>
                        <option value="">-- เลือกประเภท --</option>
                        {settings.incomeTypes.map(t => <option key={t} value={t}>{t}</option>)}
                    </Select>
                    <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 sm:gap-4">
                        <Input label="ปริมาณ" type="number" value={form.qty} onChange={(e: any) => handleCalc('qty', e.target.value)} />
                        <Input label="ราคา/หน่วย" type="number" value={form.price} onChange={(e: any) => handleCalc('price', e.target.value)} />
                        <Input label="รวม (บาท)" type="number" value={form.total} onChange={(e: any) => handleCalc('total', e.target.value)} className="font-bold" />
                    </div>
                    {editingId && <p className="text-xs text-amber-600 dark:text-amber-400">กำลังแก้ไขรายการ — บันทึกจะแทนที่รายการเดิม</p>}
                    <Button onClick={handleSave} className="w-full">บันทึก</Button>
                </div>
            </Card>

            {/* ประวัติรายรับ */}
            <Card className="p-0 overflow-hidden border border-slate-200 dark:border-white/10 shadow-sm">
                <div className="p-4 bg-gradient-to-r from-emerald-50 to-teal-50/50 dark:from-emerald-900/10 dark:to-teal-900/10 border-b border-slate-200 dark:border-white/10 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                    <button
                        type="button"
                        onClick={() => setShowHistoryExpand(!showHistoryExpand)}
                        className="flex items-center gap-2 text-emerald-800 dark:text-emerald-200 font-bold w-full sm:w-auto justify-between sm:justify-start"
                    >
                        <History size={18} /> ประวัติรายรับ ({history.length} รายการ)
                        {showHistoryExpand ? <ChevronUp size={18} /> : <ChevronDown size={18} />}
                    </button>
                    {showHistoryExpand && (
                        <div className="flex flex-col sm:flex-row gap-2 w-full sm:w-auto">
                            <select
                                value={filterMonth}
                                onChange={(e) => setFilterMonth(e.target.value)}
                                className="border border-slate-300 dark:border-white/20 rounded-lg px-3 py-2 text-sm bg-white dark:bg-white/5 text-slate-800 dark:text-slate-200"
                            >
                                <option value="">ทุกเดือน</option>
                                {byMonth.map(({ month }) => (
                                    <option key={month} value={month}>{formatMonthLabel(month)}</option>
                                ))}
                            </select>
                            <input
                                type="text"
                                placeholder="ค้นหารายละเอียด..."
                                value={searchQuery}
                                onChange={(e) => setSearchQuery(e.target.value)}
                                className="border border-slate-300 dark:border-white/20 rounded-lg px-3 py-2 text-sm bg-white dark:bg-white/5 text-slate-800 dark:text-slate-200 placeholder-slate-400 min-w-[140px]"
                            />
                        </div>
                    )}
                </div>
                {showHistoryExpand && (
                    <div className="divide-y divide-slate-100 dark:divide-white/5 max-h-[420px] overflow-y-auto">
                        {history.length === 0 ? (
                            <div className="p-8 text-center text-slate-400 dark:text-slate-500 text-sm">ไม่มีรายการที่ตรงกับเงื่อนไข</div>
                        ) : (
                            history.map(t => (
                                <div key={t.id} className={`p-4 flex justify-between items-center gap-3 hover:bg-slate-50 dark:hover:bg-white/[0.04] transition-colors group ${editingId === t.id ? 'bg-emerald-50 dark:bg-emerald-900/20 ring-1 ring-emerald-200 dark:ring-emerald-700' : ''}`}>
                                    <div className="min-w-0 flex-1">
                                        <div className="font-medium text-emerald-800 dark:text-emerald-200">{t.description}</div>
                                        <div className="text-xs text-slate-500 dark:text-slate-400 mt-0.5">{formatDateBE(t.date)}</div>
                                    </div>
                                    <div className="flex items-center gap-2 shrink-0">
                                        <span className="font-bold text-emerald-600 dark:text-emerald-400 tabular-nums">+฿{(t.amount || 0).toLocaleString()}</span>
                                        <button type="button" onClick={() => loadForEdit(t)} className="p-2 rounded-lg text-slate-400 hover:text-emerald-600 hover:bg-emerald-50 dark:hover:bg-emerald-900/30 opacity-0 group-hover:opacity-100 transition-all" title="แก้ไข"><Pencil size={16} /></button>
                                        {onDelete && <button type="button" onClick={() => { if (confirm('ลบรายการนี้?')) { onDelete(t.id); setEditingId(null); } }} className="p-2 rounded-lg text-slate-400 hover:text-red-600 hover:bg-red-50 dark:hover:bg-red-900/20 opacity-0 group-hover:opacity-100 transition-all" title="ลบ"><Trash2 size={16} /></button>}
                                    </div>
                                </div>
                            ))
                        )}
                    </div>
                )}
            </Card>
        </div>
    );
};

export default IncomeEntry;
