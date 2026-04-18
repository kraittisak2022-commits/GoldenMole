import { useState, useMemo, useEffect } from 'react';
import { History, Pencil, Trash2, Package, Truck, Droplets, Zap, BarChart3, ClipboardList } from 'lucide-react';
import Card from '../components/ui/Card';
import Button from '../components/ui/Button';
import Input from '../components/ui/Input';
import Select from '../components/ui/Select';
import { getToday, formatDateBE, normalizeDate, computeFuelStockBalances, inferFuelMovement, fuelTxToLiters } from '../utils';
import { Transaction, AppSettings } from '../types';

interface GeneralEntryProps {
    type: 'Fuel' | 'Maintenance' | 'Utilities';
    settings: AppSettings;
    /** ใช้บันทึกยอดยกมาสต็อกน้ำมัน (เมนู น้ำมัน) */
    setSettings?: (updater: AppSettings | ((prev: AppSettings) => AppSettings)) => void;
    onSave: (t: Transaction) => void;
    onDelete?: (id: string) => void;
    transactions: Transaction[];
}

const GeneralEntry = ({ type, settings, setSettings, onSave, onDelete, transactions }: GeneralEntryProps) => {
    const [form, setForm] = useState({
        date: getToday(),
        desc: '',
        amount: '',
        extra: '',
        quantity: '',
        unit: 'ลิตร',
        mileage: '',
        fuelType: 'Diesel' as 'Diesel' | 'Benzine',
        customType: '',
        workDetails: '',
        fuelMovement: 'stock_out' as 'stock_in' | 'stock_out',
        vehicleId: '',
    });
    const [editingId, setEditingId] = useState<string | null>(null);
    const [openingDraft, setOpeningDraft] = useState({ d: '0', b: '0' });
    /** แท็บย่อยเมนูน้ำมัน — สไตล์เดียวกับ EmployeeManager */
    const [fuelSection, setFuelSection] = useState<'overview' | 'entry' | 'history'>('overview');
    /** แท็บย่อยเมนูสาธารณูปโภค */
    const [utilitiesSection, setUtilitiesSection] = useState<'entry' | 'stats' | 'history'>('entry');

    const normDate = normalizeDate(form.date);
    const dayFuelTx = useMemo(
        () => (type === 'Fuel' ? transactions.filter(t => t.category === 'Fuel' && normalizeDate(t.date) === normDate) : []),
        [type, transactions, normDate]
    );

    const fuelStock = useMemo(
        () => (type === 'Fuel' ? computeFuelStockBalances(transactions, settings.fuelOpeningStockLiters) : { Diesel: 0, Benzine: 0 }),
        [type, transactions, settings.fuelOpeningStockLiters]
    );

    const dispenseHistory = useMemo(() => {
        if (type !== 'Fuel') return [];
        return transactions
            .filter(t => t.category === 'Fuel' && t.type === 'Expense' && inferFuelMovement(t) === 'stock_out')
            .sort((a, b) => (normalizeDate(b.date) + (b.id || '')).localeCompare(normalizeDate(a.date) + (a.id || '')))
            .slice(0, 25);
    }, [transactions, type]);

    const history = useMemo(() => transactions.filter(t => t.category === type).slice(-30).reverse(), [transactions, type]);

    const utilitiesStats = useMemo(() => {
        if (type !== 'Utilities') return { total: 0, count: 0, rows: [] as { key: string; amount: number }[] };
        const u = transactions.filter(t => t.category === 'Utilities' && t.type === 'Expense');
        const total = u.reduce((s, t) => s + (t.amount || 0), 0);
        const bySub: Record<string, number> = {};
        u.forEach(t => {
            const k = (t.subCategory && String(t.subCategory).trim()) || 'ทั่วไป';
            bySub[k] = (bySub[k] || 0) + (t.amount || 0);
        });
        const rows = Object.entries(bySub)
            .map(([key, amount]) => ({ key, amount }))
            .sort((a, b) => b.amount - a.amount);
        return { total, count: u.length, rows };
    }, [transactions, type]);

    useEffect(() => {
        setOpeningDraft({
            d: String(settings.fuelOpeningStockLiters?.Diesel ?? 0),
            b: String(settings.fuelOpeningStockLiters?.Benzine ?? 0),
        });
    }, [settings.fuelOpeningStockLiters]);

    useEffect(() => {
        if (type === 'Fuel' && dayFuelTx.length > 0 && !editingId) {
            const latest = dayFuelTx[dayFuelTx.length - 1];
            setForm(prev => ({
                ...prev,
                amount: latest.amount != null ? String(latest.amount) : prev.amount,
                quantity: latest.quantity != null ? String(latest.quantity) : prev.quantity,
                unit: latest.unit === 'gallon' || latest.unit === 'L' ? (latest.unit === 'gallon' ? 'แกลลอน' : 'ลิตร') : latest.unit || prev.unit,
                fuelType: (latest.fuelType as 'Diesel' | 'Benzine') || prev.fuelType,
                workDetails: latest.workDetails || prev.workDetails,
                fuelMovement: latest.fuelMovement || (latest.vehicleId ? 'stock_out' : 'stock_in'),
                vehicleId: latest.vehicleId || '',
            }));
        }
    }, [form.date, type, dayFuelTx, editingId]);

    const saveOpeningStock = () => {
        if (!setSettings) return;
        setSettings(prev => ({
            ...prev,
            fuelOpeningStockLiters: {
                Diesel: Number(openingDraft.d.replace(/,/g, '')) || 0,
                Benzine: Number(openingDraft.b.replace(/,/g, '')) || 0,
            },
        }));
    };

    const loadFuelForEdit = (t: Transaction) => {
        setForm(prev => ({
            ...prev,
            date: normalizeDate(t.date) || prev.date,
            amount: t.amount != null ? String(t.amount) : '',
            quantity: t.quantity != null ? String(t.quantity) : '',
            unit: t.unit === 'gallon' || t.unit === 'L' ? (t.unit === 'gallon' ? 'แกลลอน' : 'ลิตร') : t.unit || 'ลิตร',
            fuelType: (t.fuelType as 'Diesel' | 'Benzine') || 'Diesel',
            workDetails: t.workDetails || '',
            fuelMovement: t.fuelMovement || (t.vehicleId ? 'stock_out' : 'stock_in'),
            vehicleId: t.vehicleId || '',
        }));
        setEditingId(t.id);
    };

    const loadUtilitiesForEdit = (t: Transaction) => {
        const sub = t.subCategory || '';
        const descStr = t.description || '';
        const extraPart = sub ? descStr.replace(new RegExp(`^${sub.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*:\\s*`), '').trim() : descStr;
        setForm(prev => ({
            ...prev,
            date: normalizeDate(t.date) || prev.date,
            desc: sub === 'Other' ? 'Other' : sub,
            customType: sub === 'Other' ? extraPart : '',
            extra: sub === 'Other' ? '' : extraPart,
            amount: t.amount != null ? String(t.amount) : '',
        }));
        setEditingId(t.id);
    };

    const handleSave = () => {
        if (!form.amount) return;
        if (type === 'Fuel') {
            if (form.fuelMovement === 'stock_out' && !form.vehicleId) {
                alert('กรุณาเลือกรถที่เติมน้ำมัน');
                return;
            }
            const q = Number(form.quantity);
            if (form.fuelMovement !== 'stock_in' && (!q || q <= 0)) {
                alert('กรุณาระบุจำนวนที่เติม (ลิตร/หน่วย)');
                return;
            }
            if (form.fuelMovement === 'stock_in' && (!q || q <= 0)) {
                alert('กรุณาระบุจำนวนลิตรที่รับเข้าสต็อก');
                return;
            }
        }
        if (editingId && onDelete) {
            onDelete(editingId);
            setEditingId(null);
        }
        const subCat = form.desc === 'Other' ? form.customType : form.desc;
        const qtyNum = Number(form.quantity) || 0;
        const ftTh = form.fuelType === 'Diesel' ? 'ดีเซล' : 'เบนซิน';
        const unitLabel = form.unit === 'แกลลอน' ? 'แกลลอน' : form.unit === 'ถัง' ? 'ถัง' : 'ลิตร';

        let descText = '';
        if (type === 'Fuel') {
            if (form.fuelMovement === 'stock_in') {
                descText = `รับน้ำมันเข้าสต็อก (${ftTh}): ${qtyNum} ${unitLabel} ฿${form.amount}${form.workDetails ? ` — ${form.workDetails}` : ''}`;
            } else {
                descText = `เติมน้ำมันรถ (${ftTh}): ${qtyNum} ${unitLabel} → ${form.vehicleId} ฿${form.amount}${form.workDetails ? ` — ${form.workDetails}` : ''}`;
            }
        } else {
            descText = `${subCat}: ${form.extra}`;
        }

        const payload: Transaction = {
            id: Date.now().toString(),
            date: form.date,
            type: 'Expense',
            category: type,
            description: descText,
            amount: Number(form.amount),
            subCategory: subCat,
            quantity: qtyNum,
            unit: type === 'Fuel' ? (form.unit === 'แกลลอน' ? 'gallon' : 'L') : form.unit,
            fuelType: type === 'Fuel' ? form.fuelType : undefined,
            fuelMovement: type === 'Fuel' ? form.fuelMovement : undefined,
            vehicleId: type === 'Fuel' && form.fuelMovement === 'stock_out' ? form.vehicleId : undefined,
        } as Transaction;
        if (type === 'Fuel') payload.workDetails = form.workDetails;
        onSave(payload);
        setForm(prev => ({
            ...prev,
            amount: '',
            desc: '',
            extra: '',
            quantity: '',
            customType: '',
            workDetails: '',
            vehicleId: '',
            fuelMovement: 'stock_out',
        }));
    };

    const typeLabel = type === 'Fuel' ? 'น้ำมัน' : type === 'Utilities' ? 'สาธารณูปโภค' : type;
    const amountLabel = type === 'Fuel' ? (form.fuelMovement === 'stock_in' ? 'ราคาซื้อ (บาท)' : 'ราคา (บาท)') : 'จำนวนเงิน (บาท)';

    const fuelTabClass = (active: boolean) =>
        `flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-bold transition-colors ${
            active
                ? 'bg-slate-800 text-white dark:bg-slate-100 dark:text-slate-900'
                : 'bg-slate-100 text-slate-600 hover:bg-slate-200 dark:bg-white/[0.08] dark:text-slate-300 dark:hover:bg-white/[0.14]'
        }`;

    return (
        <div className="max-w-xl mx-auto space-y-6 animate-fade-in">
            {type === 'Fuel' && (
                <div className="flex flex-wrap gap-2 border-b border-slate-200 dark:border-white/10 pb-2 mb-4">
                    <button type="button" onClick={() => setFuelSection('overview')} className={fuelTabClass(fuelSection === 'overview')}>
                        <Droplets size={18} /> ภาพรวม & สต็อก
                    </button>
                    <button type="button" onClick={() => setFuelSection('entry')} className={fuelTabClass(fuelSection === 'entry')}>
                        <Truck size={18} /> บันทึกรายการ
                    </button>
                    <button type="button" onClick={() => setFuelSection('history')} className={fuelTabClass(fuelSection === 'history')}>
                        <History size={18} /> ประวัติ
                    </button>
                </div>
            )}

            {type === 'Utilities' && (
                <div className="flex flex-wrap gap-2 border-b border-slate-200 dark:border-white/10 pb-2 mb-4">
                    <button type="button" onClick={() => setUtilitiesSection('entry')} className={fuelTabClass(utilitiesSection === 'entry')}>
                        <ClipboardList size={18} /> บันทึก
                    </button>
                    <button type="button" onClick={() => setUtilitiesSection('stats')} className={fuelTabClass(utilitiesSection === 'stats')}>
                        <BarChart3 size={18} /> สถิติ
                    </button>
                    <button type="button" onClick={() => setUtilitiesSection('history')} className={fuelTabClass(utilitiesSection === 'history')}>
                        <History size={18} /> ประวัติ
                    </button>
                </div>
            )}

            {type === 'Fuel' && fuelSection === 'overview' && (
                <>
                    <Card className="p-5 border-orange-200/80 dark:border-orange-500/20 bg-gradient-to-br from-orange-50/90 to-white dark:from-orange-950/30 dark:to-slate-900/40">
                        <h3 className="font-bold text-slate-800 dark:text-slate-100 mb-3 flex items-center gap-2">
                            <Droplets className="text-orange-500" size={20} /> สต็อกน้ำมันคงเหลือ (ลิตร)
                        </h3>
                        <div className="grid grid-cols-2 gap-3">
                            <div className={`rounded-xl p-4 border ${fuelStock.Diesel < 0 ? 'border-red-300 bg-red-50/80 dark:bg-red-950/30' : 'border-slate-200 dark:border-white/10 bg-white/80 dark:bg-white/5'}`}>
                                <p className="text-xs text-slate-500 dark:text-slate-400 mb-1">ดีเซล</p>
                                <p className="text-2xl font-bold tabular-nums text-slate-900 dark:text-white">{Math.round(fuelStock.Diesel * 10) / 10}</p>
                                {fuelStock.Diesel < 0 && <p className="text-[11px] text-red-600 mt-1">ติดลบ — ตรวจสอบยอดยกมาหรือรายการรับเข้า</p>}
                            </div>
                            <div className={`rounded-xl p-4 border ${fuelStock.Benzine < 0 ? 'border-red-300 bg-red-50/80 dark:bg-red-950/30' : 'border-slate-200 dark:border-white/10 bg-white/80 dark:bg-white/5'}`}>
                                <p className="text-xs text-slate-500 dark:text-slate-400 mb-1">เบนซิน</p>
                                <p className="text-2xl font-bold tabular-nums text-slate-900 dark:text-white">{Math.round(fuelStock.Benzine * 10) / 10}</p>
                                {fuelStock.Benzine < 0 && <p className="text-[11px] text-red-600 mt-1">ติดลบ — ตรวจสอบยอดยกมาหรือรายการรับเข้า</p>}
                            </div>
                        </div>
                        <p className="text-[11px] text-slate-500 dark:text-slate-400 mt-3">
                            คำนวณจาก: ยอดยกมา + รับเข้าสต็อก − เติมรถ (ตามรายการด้านล่าง)
                        </p>
                    </Card>

                    {setSettings && (
                        <Card className="p-5">
                            <h4 className="font-semibold text-slate-800 dark:text-slate-100 mb-3 flex items-center gap-2">
                                <Package size={18} className="text-amber-600" /> ยอดยกมาต้นงวด (ลิตร)
                            </h4>
                            <div className="grid grid-cols-2 gap-3 mb-3">
                                <Input
                                    label="ดีเซล"
                                    type="number"
                                    value={openingDraft.d}
                                    onChange={(e: any) => setOpeningDraft(o => ({ ...o, d: e.target.value }))}
                                />
                                <Input
                                    label="เบนซิน"
                                    type="number"
                                    value={openingDraft.b}
                                    onChange={(e: any) => setOpeningDraft(o => ({ ...o, b: e.target.value }))}
                                />
                            </div>
                            <Button type="button" variant="outline" className="w-full" onClick={saveOpeningStock}>
                                บันทึกยอดยกมา
                            </Button>
                        </Card>
                    )}

                    <Card className="p-0 overflow-hidden border border-slate-200 dark:border-white/10 shadow-sm">
                        <div className="p-4 bg-slate-50 dark:bg-white/[0.04] border-b border-slate-200 dark:border-white/10 flex items-center gap-2">
                            <Truck size={18} className="text-orange-600" />
                            <span className="font-bold text-slate-800 dark:text-slate-100">การเติมน้ำมันให้รถ (ล่าสุด)</span>
                        </div>
                        <div className="max-h-56 overflow-y-auto divide-y divide-slate-100 dark:divide-white/10">
                            {dispenseHistory.length === 0 ? (
                                <div className="p-6 text-center text-sm text-slate-400">ยังไม่มีรายการเติมรถ</div>
                            ) : (
                                dispenseHistory.map(t => (
                                    <div key={t.id} className="px-4 py-3 flex justify-between gap-3 text-sm">
                                        <div className="min-w-0">
                                            <div className="font-medium text-slate-800 dark:text-slate-100 truncate">{t.vehicleId || '—'}</div>
                                            <div className="text-xs text-slate-500 mt-0.5">
                                                {formatDateBE(t.date)} · {t.fuelType === 'Benzine' ? 'เบนซิน' : 'ดีเซล'} · {Math.round(fuelTxToLiters(t) * 10) / 10} ลิตร
                                            </div>
                                        </div>
                                        <span className="font-semibold text-slate-700 dark:text-slate-200 shrink-0">฿{(t.amount || 0).toLocaleString()}</span>
                                    </div>
                                ))
                            )}
                        </div>
                    </Card>
                </>
            )}

            {type === 'Utilities' && utilitiesSection === 'stats' && (
                <div className="space-y-4 mb-6">
                    <Card className="p-6 border border-violet-100 dark:border-violet-500/20 bg-violet-50/40 dark:bg-violet-950/20">
                        <h3 className="font-bold text-lg mb-4 flex items-center gap-2 text-slate-800 dark:text-slate-100">
                            <Zap className="text-violet-500" size={22} /> สรุปสาธารณูปโภคทั้งหมด
                        </h3>
                        <div className="grid grid-cols-2 gap-3">
                            <div className="rounded-xl border border-violet-100 dark:border-violet-500/30 bg-white/80 dark:bg-white/5 p-4">
                                <p className="text-xs text-violet-700 dark:text-violet-300">จำนวนรายการ</p>
                                <p className="text-2xl font-bold text-slate-900 dark:text-white">{utilitiesStats.count}</p>
                            </div>
                            <div className="rounded-xl border border-slate-200 dark:border-white/10 p-4">
                                <p className="text-xs text-slate-500">ยอดรวม</p>
                                <p className="text-2xl font-bold text-violet-700 dark:text-violet-300">฿{utilitiesStats.total.toLocaleString()}</p>
                            </div>
                        </div>
                    </Card>
                    <Card className="p-6">
                        <h4 className="font-semibold text-slate-700 dark:text-slate-200 mb-3">แยกตามประเภท (subCategory)</h4>
                        {utilitiesStats.rows.length === 0 ? (
                            <p className="text-sm text-slate-400">ยังไม่มีรายการสาธารณูปโภค</p>
                        ) : (
                            <ul className="space-y-2 max-h-64 overflow-y-auto">
                                {utilitiesStats.rows.map(r => (
                                    <li key={r.key} className="flex justify-between text-sm border-b border-slate-100 dark:border-white/10 pb-2">
                                        <span className="text-slate-700 dark:text-slate-300">{r.key}</span>
                                        <span className="font-semibold text-slate-800 dark:text-slate-100 shrink-0">฿{r.amount.toLocaleString()}</span>
                                    </li>
                                ))}
                            </ul>
                        )}
                    </Card>
                </div>
            )}

            {((type === 'Fuel' && fuelSection === 'entry') || (type === 'Utilities' && utilitiesSection === 'entry') || type === 'Maintenance') && (
            <Card className="p-6">
                <h3 className="font-bold text-lg mb-6 flex items-center gap-2">{typeLabel} — บันทึก</h3>
                <div className="space-y-4">
                    <Input label="วันที่" type="date" value={form.date} onChange={(e: any) => { setForm(prev => ({ ...prev, date: e.target.value })); setEditingId(null); }} />
                    {type === 'Fuel' && dayFuelTx.length > 0 && (
                        <div className="p-3 bg-red-50 dark:bg-red-950/30 rounded-xl border border-red-200 dark:border-red-500/20">
                            <p className="text-sm font-semibold text-red-800 dark:text-red-200 mb-2">รายการน้ำมันในวันนี้ ({dayFuelTx.length})</p>
                            <div className="space-y-2 max-h-40 overflow-y-auto">
                                {dayFuelTx.map((t: Transaction) => (
                                    <div key={t.id} className={`flex items-center justify-between p-2 rounded-lg border text-sm ${editingId === t.id ? 'bg-red-100 dark:bg-red-900/40 border-red-400' : 'bg-white dark:bg-white/5 border-red-100 dark:border-white/10'}`}>
                                        <span className="truncate">
                                            {inferFuelMovement(t) === 'stock_in' ? 'รับเข้า' : 'เติมรถ'} · {(t as any).fuelType === 'Diesel' ? 'ดีเซล' : 'เบนซิน'}
                                            {t.vehicleId ? ` · ${t.vehicleId}` : ''}
                                        </span>
                                        <div className="flex gap-1 shrink-0">
                                            <button type="button" onClick={() => loadFuelForEdit(t)} className="p-1.5 rounded text-slate-600 hover:bg-red-200 dark:hover:bg-red-800/50" title="แก้ไข">
                                                <Pencil size={14} />
                                            </button>
                                            {onDelete && (
                                                <button
                                                    type="button"
                                                    onClick={() => {
                                                        if (confirm('ลบรายการนี้?')) {
                                                            onDelete(t.id);
                                                            setEditingId(null);
                                                        }
                                                    }}
                                                    className="p-1.5 rounded text-red-600 hover:bg-red-50 dark:hover:bg-red-900/30"
                                                    title="ลบ"
                                                >
                                                    <Trash2 size={14} />
                                                </button>
                                            )}
                                        </div>
                                    </div>
                                ))}
                            </div>
                            {editingId && (
                                <button type="button" onClick={() => setEditingId(null)} className="mt-2 text-xs text-red-700 dark:text-red-300 hover:underline">
                                    ล้างเพื่อเพิ่มใหม่
                                </button>
                            )}
                        </div>
                    )}
                    {type === 'Fuel' ? (
                        <>
                            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                                <label className={`flex items-center gap-3 border p-3 rounded-xl cursor-pointer transition-colors ${form.fuelMovement === 'stock_in' ? 'border-orange-400 bg-orange-50/80 dark:bg-orange-950/40' : 'border-slate-200 dark:border-white/15 hover:bg-slate-50 dark:hover:bg-white/5'}`}>
                                    <input type="radio" name="fuelMov" checked={form.fuelMovement === 'stock_in'} onChange={() => setForm({ ...form, fuelMovement: 'stock_in', vehicleId: '' })} />
                                    <div>
                                        <div className="font-medium text-slate-800 dark:text-slate-100">รับน้ำมันเข้าสต็อก</div>
                                        <div className="text-[11px] text-slate-500">เพิ่มยอดในถัง/คลัง</div>
                                    </div>
                                </label>
                                <label className={`flex items-center gap-3 border p-3 rounded-xl cursor-pointer transition-colors ${form.fuelMovement === 'stock_out' ? 'border-orange-400 bg-orange-50/80 dark:bg-orange-950/40' : 'border-slate-200 dark:border-white/15 hover:bg-slate-50 dark:hover:bg-white/5'}`}>
                                    <input type="radio" name="fuelMov" checked={form.fuelMovement === 'stock_out'} onChange={() => setForm({ ...form, fuelMovement: 'stock_out' })} />
                                    <div>
                                        <div className="font-medium text-slate-800 dark:text-slate-100">เติมรถ</div>
                                        <div className="text-[11px] text-slate-500">หักจากสต็อก — เลือกคันรถ</div>
                                    </div>
                                </label>
                            </div>
                            <div className="flex gap-4">
                                <label className="flex items-center gap-2 border p-3 rounded-lg w-full cursor-pointer hover:bg-slate-50 dark:hover:bg-white/5">
                                    <input type="radio" name="fuel" checked={form.fuelType === 'Diesel'} onChange={() => setForm({ ...form, fuelType: 'Diesel' })} /> ดีเซล
                                </label>
                                <label className="flex items-center gap-2 border p-3 rounded-lg w-full cursor-pointer hover:bg-slate-50 dark:hover:bg-white/5">
                                    <input type="radio" name="fuel" checked={form.fuelType === 'Benzine'} onChange={() => setForm({ ...form, fuelType: 'Benzine' })} /> เบนซิน
                                </label>
                            </div>
                            {form.fuelMovement === 'stock_out' && (
                                <Select label="รถที่เติมน้ำมัน" value={form.vehicleId} onChange={(e: any) => setForm({ ...form, vehicleId: e.target.value })}>
                                    <option value="">-- เลือกรถ --</option>
                                    {(settings.cars || []).map(c => (
                                        <option key={c} value={c}>
                                            {c}
                                        </option>
                                    ))}
                                </Select>
                            )}
                            <div className="grid grid-cols-2 gap-4">
                                <Input label="จำนวน" type="number" value={form.quantity} onChange={(e: any) => setForm({ ...form, quantity: e.target.value })} />
                                <Select label="หน่วย" value={form.unit} onChange={(e: any) => setForm({ ...form, unit: e.target.value })}>
                                    <option value="ลิตร">ลิตร</option>
                                    <option value="แกลลอน">แกลลอน</option>
                                    <option value="ถัง">ถัง</option>
                                </Select>
                            </div>
                            <div>
                                <label className="block text-sm font-medium text-slate-700 dark:text-slate-300 mb-1">รายละเอียดเพิ่มเติม (ไม่บังคับ)</label>
                                <input
                                    type="text"
                                    placeholder="เช่น ซื้อที่ปั๊ม / ใบเสร็จเลขที่"
                                    value={form.workDetails}
                                    onChange={(e: any) => setForm({ ...form, workDetails: e.target.value })}
                                    className="w-full border border-slate-200 dark:border-white/15 rounded-lg px-3 py-2 text-sm bg-white dark:bg-white/5 text-slate-800 dark:text-slate-100"
                                />
                            </div>
                        </>
                    ) : (
                        <>
                            <Select label="ประเภท" value={form.desc} onChange={(e: any) => setForm({ ...form, desc: e.target.value })}>
                                <option value="">-- เลือก --</option>
                                {(type === 'Maintenance' ? settings.maintenanceTypes : settings.expenseTypes).map(t => (
                                    <option key={t} value={t}>
                                        {t}
                                    </option>
                                ))}
                                <option value="Other">อื่นๆ</option>
                            </Select>
                            {form.desc === 'Other' && <Input label="ระบุประเภท" value={form.customType} onChange={(e: any) => setForm({ ...form, customType: e.target.value })} />}
                            <Input label="รายละเอียดเพิ่มเติม" value={form.extra} onChange={(e: any) => setForm({ ...form, extra: e.target.value })} />
                        </>
                    )}
                    <Input label={amountLabel} type="number" value={form.amount} onChange={(e: any) => setForm({ ...form, amount: e.target.value })} className="input-highlight" />
                    <Button onClick={handleSave} className="w-full mt-4">
                        บันทึก
                    </Button>
                </div>
            </Card>
            )}
            {((type === 'Fuel' && fuelSection === 'history') || (type === 'Utilities' && utilitiesSection === 'history') || type === 'Maintenance') && (
            <Card className="p-0 overflow-hidden border border-slate-200 dark:border-white/10 shadow-sm">
                <div className="p-4 bg-gradient-to-r from-slate-50 to-slate-100 dark:from-white/[0.06] dark:to-transparent border-b border-slate-200 dark:border-white/10 flex items-center justify-between">
                    <span className="flex items-center gap-2 text-slate-700 dark:text-slate-200 font-bold">
                        <History size={18} className="text-slate-500" /> ประวัติ ({history.length} รายการ)
                    </span>
                </div>
                <div className="divide-y divide-slate-100 dark:divide-white/10 max-h-[420px] overflow-y-auto">
                    {history.length === 0 ? (
                        <div className="p-8 text-center text-slate-400 text-sm">ยังไม่มีรายการ</div>
                    ) : (
                        history.map(t => (
                            <div key={t.id} className={`p-3 sm:p-4 flex justify-between items-center gap-3 hover:bg-slate-50/80 dark:hover:bg-white/[0.04] transition-colors group ${editingId === t.id && type !== 'Fuel' ? 'bg-amber-50 dark:bg-amber-950/30 ring-1 ring-amber-200 dark:ring-amber-500/30' : ''}`}>
                                <div className="min-w-0 flex-1">
                                    <div className="font-medium text-slate-800 dark:text-slate-100 truncate">{t.description}</div>
                                    <div className="text-xs text-slate-500 dark:text-slate-400 mt-0.5">
                                        {formatDateBE(t.date)}{' '}
                                        {type === 'Fuel' && t.quantity != null && (
                                            <>
                                                · {inferFuelMovement(t) === 'stock_in' ? 'รับเข้า' : 'เติมรถ'}
                                                {t.vehicleId ? ` · ${t.vehicleId}` : ''} · {t.quantity} {t.unit === 'gallon' ? 'แกลลอน' : t.unit}
                                            </>
                                        )}
                                    </div>
                                </div>
                                <div className="flex items-center gap-2 shrink-0">
                                    <span className="font-bold text-slate-800 dark:text-slate-100 tabular-nums">฿{(t.amount || 0).toLocaleString()}</span>
                                    {type === 'Fuel' && (
                                        <>
                                            <button type="button" onClick={() => loadFuelForEdit(t)} className="p-2 rounded-lg text-slate-400 hover:text-amber-600 hover:bg-amber-50 dark:hover:bg-amber-950/40 opacity-0 group-hover:opacity-100 transition-all" title="แก้ไข">
                                                <Pencil size={16} />
                                            </button>
                                            {onDelete && (
                                                <button
                                                    type="button"
                                                    onClick={() => {
                                                        if (confirm('ลบรายการนี้?')) {
                                                            onDelete(t.id);
                                                            setEditingId(null);
                                                        }
                                                    }}
                                                    className="p-2 rounded-lg text-slate-400 hover:text-red-600 hover:bg-red-50 dark:hover:bg-red-950/30 opacity-0 group-hover:opacity-100 transition-all"
                                                    title="ลบ"
                                                >
                                                    <Trash2 size={16} />
                                                </button>
                                            )}
                                        </>
                                    )}
                                    {type === 'Utilities' && (
                                        <>
                                            <button type="button" onClick={() => loadUtilitiesForEdit(t)} className="p-2 rounded-lg text-slate-400 hover:text-amber-600 hover:bg-amber-50 opacity-0 group-hover:opacity-100 transition-all" title="แก้ไข">
                                                <Pencil size={16} />
                                            </button>
                                            {onDelete && (
                                                <button
                                                    type="button"
                                                    onClick={() => {
                                                        if (confirm('ลบรายการนี้?')) {
                                                            onDelete(t.id);
                                                            setEditingId(null);
                                                        }
                                                    }}
                                                    className="p-2 rounded-lg text-slate-400 hover:text-red-600 hover:bg-red-50 opacity-0 group-hover:opacity-100 transition-all"
                                                    title="ลบ"
                                                >
                                                    <Trash2 size={16} />
                                                </button>
                                            )}
                                        </>
                                    )}
                                </div>
                            </div>
                        ))
                    )}
                </div>
            </Card>
            )}
        </div>
    );
};

export default GeneralEntry;
