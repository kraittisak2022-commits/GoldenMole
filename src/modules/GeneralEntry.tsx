import { useState, useMemo, useEffect } from 'react';
import { History, Pencil, Trash2 } from 'lucide-react';
import Card from '../components/ui/Card';
import Button from '../components/ui/Button';
import Input from '../components/ui/Input';
import Select from '../components/ui/Select';
import { getToday, formatDateBE, normalizeDate } from '../utils';
import { Transaction, AppSettings } from '../types';

interface GeneralEntryProps {
    type: 'Fuel' | 'Maintenance' | 'Utilities';
    settings: AppSettings;
    onSave: (t: Transaction) => void;
    onDelete?: (id: string) => void;
    transactions: Transaction[];
}

const GeneralEntry = ({ type, settings, onSave, onDelete, transactions }: GeneralEntryProps) => {
    const [form, setForm] = useState({ date: getToday(), desc: '', amount: '', extra: '', quantity: '', unit: 'ลิตร', mileage: '', fuelType: 'Diesel', customType: '', workDetails: '' });
    const [editingId, setEditingId] = useState<string | null>(null);

    const normDate = normalizeDate(form.date);
    const dayFuelTx = useMemo(() =>
        type === 'Fuel' ? transactions.filter(t => t.category === 'Fuel' && normalizeDate(t.date) === normDate) : [],
        [type, transactions, normDate]
    );
    const history = useMemo(() => transactions.filter(t => t.category === type).slice(-30).reverse(), [transactions, type]);

    useEffect(() => {
        if (type === 'Fuel' && dayFuelTx.length > 0 && !editingId) {
            const latest = dayFuelTx[dayFuelTx.length - 1];
            setForm(prev => ({
                ...prev,
                amount: latest.amount != null ? String(latest.amount) : prev.amount,
                quantity: latest.quantity != null ? String(latest.quantity) : prev.quantity,
                unit: (latest.unit === 'gallon' || latest.unit === 'L') ? (latest.unit === 'gallon' ? 'แกลลอน' : 'ลิตร') : (latest.unit || prev.unit),
                fuelType: (latest as any).fuelType || prev.fuelType,
                workDetails: (latest as any).workDetails || prev.workDetails,
            }));
        }
    }, [form.date, type, dayFuelTx, editingId]);

    const loadFuelForEdit = (t: Transaction) => {
        setForm(prev => ({
            ...prev,
            date: normalizeDate(t.date) || prev.date,
            amount: t.amount != null ? String(t.amount) : '',
            quantity: t.quantity != null ? String(t.quantity) : '',
            unit: (t.unit === 'gallon' || t.unit === 'L') ? (t.unit === 'gallon' ? 'แกลลอน' : 'ลิตร') : (t.unit || 'ลิตร'),
            fuelType: (t as any).fuelType || 'Diesel',
            workDetails: (t as any).workDetails || '',
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
        if (editingId && onDelete) {
            onDelete(editingId);
            setEditingId(null);
        }
        const subCat = form.desc === 'Other' ? form.customType : form.desc;
        const descText = type === 'Fuel'
            ? `เติมน้ำมัน (${form.fuelType}): ${form.quantity || 0} ${form.unit} ${form.amount} บาท${form.workDetails ? ` - ${form.workDetails}` : ''}`
            : `${subCat}: ${form.extra}`;
        const payload: Transaction = {
            id: Date.now().toString(),
            date: form.date,
            type: 'Expense',
            category: type,
            description: descText,
            amount: Number(form.amount),
            subCategory: subCat,
            quantity: Number(form.quantity),
            unit: type === 'Fuel' ? (form.unit === 'แกลลอน' ? 'gallon' : 'L') : form.unit,
            fuelType: type === 'Fuel' ? (form.fuelType as any) : undefined,
        } as Transaction;
        if (type === 'Fuel') (payload as any).workDetails = form.workDetails;
        onSave(payload);
        setForm(prev => ({ ...prev, amount: '', desc: '', extra: '', quantity: '', customType: '', workDetails: '' }));
    };

    const typeLabel = type === 'Fuel' ? 'น้ำมัน' : type === 'Utilities' ? 'สาธารณูปโภค' : type;
    const amountLabel = type === 'Fuel' ? 'ราคาซื้อน้ำมัน (บาท)' : 'จำนวนเงิน (บาท)';

    return (
        <div className="max-w-xl mx-auto space-y-6 animate-fade-in">
            <Card className="p-6">
                <h3 className="font-bold text-lg mb-6 flex items-center gap-2">{typeLabel} — บันทึก</h3>
                <div className="space-y-4">
                    <Input label="วันที่" type="date" value={form.date} onChange={(e: any) => { setForm(prev => ({ ...prev, date: e.target.value })); setEditingId(null); }} />
                    {type === 'Fuel' && dayFuelTx.length > 0 && (
                        <div className="p-3 bg-red-50 rounded-xl border border-red-200">
                            <p className="text-sm font-semibold text-red-800 mb-2">รายการน้ำมันในวันนี้ ({dayFuelTx.length})</p>
                            <div className="space-y-2 max-h-40 overflow-y-auto">
                                {dayFuelTx.map((t: Transaction) => (
                                    <div key={t.id} className={`flex items-center justify-between p-2 rounded-lg border text-sm ${editingId === t.id ? 'bg-red-100 border-red-400' : 'bg-white border-red-100'}`}>
                                        <span className="truncate">{(t as any).fuelType === 'Diesel' ? 'ดีเซล' : 'เบนซิน'} — ฿{t.amount?.toLocaleString()}</span>
                                        <div className="flex gap-1 shrink-0">
                                            <button type="button" onClick={() => loadFuelForEdit(t)} className="p-1.5 rounded text-slate-600 hover:bg-red-200" title="แก้ไข"><Pencil size={14} /></button>
                                            {onDelete && <button type="button" onClick={() => { if (confirm('ลบรายการนี้?')) { onDelete(t.id); setEditingId(null); } }} className="p-1.5 rounded text-red-600 hover:bg-red-50" title="ลบ"><Trash2 size={14} /></button>}
                                        </div>
                                    </div>
                                ))}
                            </div>
                            {editingId && <button type="button" onClick={() => setEditingId(null)} className="mt-2 text-xs text-red-700 hover:text-red-900">ล้างเพื่อเพิ่มใหม่</button>}
                        </div>
                    )}
                    {type === 'Fuel' ? (
                        <>
                            <div className="flex gap-4">
                                <label className="flex items-center gap-2 border p-3 rounded-lg w-full cursor-pointer hover:bg-slate-50">
                                    <input type="radio" name="fuel" checked={form.fuelType === 'Diesel'} onChange={() => setForm({ ...form, fuelType: 'Diesel' })} /> ดีเซล
                                </label>
                                <label className="flex items-center gap-2 border p-3 rounded-lg w-full cursor-pointer hover:bg-slate-50">
                                    <input type="radio" name="fuel" checked={form.fuelType === 'Benzine'} onChange={() => setForm({ ...form, fuelType: 'Benzine' })} /> เบนซิน
                                </label>
                            </div>
                            <div className="grid grid-cols-2 gap-4">
                                <Input label="จำนวนลิตร" type="number" value={form.quantity} onChange={(e: any) => setForm({ ...form, quantity: e.target.value })} />
                                <Select label="หน่วย" value={form.unit} onChange={(e: any) => setForm({ ...form, unit: e.target.value })}>
                                    <option value="ลิตร">ลิตร</option>
                                    <option value="แกลลอน">แกลลอน</option>
                                    <option value="ถัง">ถัง</option>
                                </Select>
                            </div>
                            <div>
                                <label className="block text-sm font-medium text-slate-700 mb-1">รายละเอียดเพิ่มเติม (ไม่บังคับ)</label>
                                <input type="text" placeholder="เช่น ซื้อที่ปั๊มหน้าแคมป์" value={form.workDetails} onChange={(e: any) => setForm({ ...form, workDetails: e.target.value })} className="w-full border rounded-lg px-3 py-2 text-sm" />
                            </div>
                        </>
                    ) : (
                        <>
                            <Select label="ประเภท" value={form.desc} onChange={(e: any) => setForm({ ...form, desc: e.target.value })}>
                                <option value="">-- เลือก --</option>
                                {(type === 'Maintenance' ? settings.maintenanceTypes : settings.expenseTypes).map(t => <option key={t} value={t}>{t}</option>)}
                                <option value="Other">อื่นๆ</option>
                            </Select>
                            {form.desc === 'Other' && <Input label="ระบุประเภท" value={form.customType} onChange={(e: any) => setForm({ ...form, customType: e.target.value })} />}
                            <Input label="รายละเอียดเพิ่มเติม" value={form.extra} onChange={(e: any) => setForm({ ...form, extra: e.target.value })} />
                        </>
                    )}
                    <Input label={amountLabel} type="number" value={form.amount} onChange={(e: any) => setForm({ ...form, amount: e.target.value })} className="input-highlight" />
                    <Button onClick={handleSave} className="w-full mt-4">บันทึก</Button>
                </div>
            </Card>
            <Card className="p-0 overflow-hidden border border-slate-200 shadow-sm">
                <div className="p-4 bg-gradient-to-r from-slate-50 to-slate-100 border-b flex items-center justify-between">
                    <span className="flex items-center gap-2 text-slate-700 font-bold">
                        <History size={18} className="text-slate-500" /> ประวัติ ({history.length} รายการ)
                    </span>
                </div>
                <div className="divide-y divide-slate-100 max-h-[420px] overflow-y-auto">
                    {history.length === 0 ? (
                        <div className="p-8 text-center text-slate-400 text-sm">ยังไม่มีรายการ</div>
                    ) : (
                        history.map(t => (
                            <div key={t.id} className={`p-3 sm:p-4 flex justify-between items-center gap-3 hover:bg-slate-50/80 transition-colors group ${editingId === t.id && type !== 'Fuel' ? 'bg-amber-50 ring-1 ring-amber-200' : ''}`}>
                                <div className="min-w-0 flex-1">
                                    <div className="font-medium text-slate-800 truncate">{t.description}</div>
                                    <div className="text-xs text-slate-500 mt-0.5">{formatDateBE(t.date)} {type === 'Fuel' && t.quantity != null && `• ${t.quantity} ${t.unit}`}</div>
                                </div>
                                <div className="flex items-center gap-2 shrink-0">
                                    <span className="font-bold text-slate-800 tabular-nums">฿{(t.amount || 0).toLocaleString()}</span>
                                    {type === 'Fuel' && (
                                        <>
                                            <button type="button" onClick={() => loadFuelForEdit(t)} className="p-2 rounded-lg text-slate-400 hover:text-amber-600 hover:bg-amber-50 opacity-0 group-hover:opacity-100 transition-all" title="แก้ไข"><Pencil size={16} /></button>
                                            {onDelete && <button type="button" onClick={() => { if (confirm('ลบรายการนี้?')) { onDelete(t.id); setEditingId(null); } }} className="p-2 rounded-lg text-slate-400 hover:text-red-600 hover:bg-red-50 opacity-0 group-hover:opacity-100 transition-all" title="ลบ"><Trash2 size={16} /></button>}
                                        </>
                                    )}
                                    {type === 'Utilities' && (
                                        <>
                                            <button type="button" onClick={() => loadUtilitiesForEdit(t)} className="p-2 rounded-lg text-slate-400 hover:text-amber-600 hover:bg-amber-50 opacity-0 group-hover:opacity-100 transition-all" title="แก้ไข"><Pencil size={16} /></button>
                                            {onDelete && <button type="button" onClick={() => { if (confirm('ลบรายการนี้?')) { onDelete(t.id); setEditingId(null); } }} className="p-2 rounded-lg text-slate-400 hover:text-red-600 hover:bg-red-50 opacity-0 group-hover:opacity-100 transition-all" title="ลบ"><Trash2 size={16} /></button>}
                                        </>
                                    )}
                                </div>
                            </div>
                        ))
                    )}
                </div>
            </Card>
        </div>
    );
};

export default GeneralEntry;
