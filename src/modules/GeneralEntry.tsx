import { useState } from 'react';
import { History } from 'lucide-react';
import Card from '../components/ui/Card';
import Button from '../components/ui/Button';
import Input from '../components/ui/Input';
import Select from '../components/ui/Select';
import { getToday } from '../utils';
import { Transaction, AppSettings } from '../types';

interface GeneralEntryProps {
    type: 'Fuel' | 'Maintenance' | 'Utilities';
    settings: AppSettings;
    onSave: (t: Transaction) => void;
    transactions: Transaction[];
}

const GeneralEntry = ({ type, settings, onSave, transactions }: GeneralEntryProps) => {
    const [form, setForm] = useState({ date: getToday(), desc: '', amount: '', extra: '', quantity: '', unit: 'แกลอน', mileage: '', fuelType: 'Diesel', customType: '' });
    const history = transactions.filter(t => t.category === type).slice(-5).reverse();

    const handleSave = () => {
        if (!form.amount) return;
        const subCat = form.desc === 'Other' ? form.customType : form.desc;
        const descText = type === 'Fuel' ? `เติมน้ำมัน (${form.fuelType})` : `${subCat}: ${form.extra}`;
        onSave({
            id: Date.now().toString(),
            date: form.date,
            type: 'Expense',
            category: type,
            description: descText,
            amount: Number(form.amount),
            subCategory: subCat,
            quantity: Number(form.quantity),
            unit: form.unit,
            fuelType: form.fuelType as any,
            vehicleId: type === 'Fuel' ? undefined : undefined
        } as Transaction);
        setForm({ ...form, amount: '', desc: '', extra: '', quantity: '', customType: '' });
    }

    return (
        <div className="max-w-xl mx-auto space-y-6 animate-fade-in">
            <Card className="p-6">
                <h3 className="font-bold text-lg mb-6 flex items-center gap-2">{type} Entry</h3>
                <div className="space-y-4">
                    <Input label="วันที่" type="date" value={form.date} onChange={(e: any) => setForm({ ...form, date: e.target.value })} />
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
                                <Input label="ปริมาณ" type="number" value={form.quantity} onChange={(e: any) => setForm({ ...form, quantity: e.target.value })} />
                                <Select label="หน่วย" value={form.unit} onChange={(e: any) => setForm({ ...form, unit: e.target.value })}>
                                    <option>แกลอน</option>
                                    <option>ลิตร</option>
                                    <option>ถัง</option>
                                </Select>
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
                    <Input label="จำนวนเงิน" type="number" value={form.amount} onChange={(e: any) => setForm({ ...form, amount: e.target.value })} className="input-highlight" />
                    <Button onClick={handleSave} className="w-full mt-4">บันทึก</Button>
                </div>
            </Card>
            <Card className="p-0 overflow-hidden">
                <div className="p-4 bg-slate-50 border-b flex items-center gap-2 text-slate-600 font-bold text-sm">
                    <History size={16} /> ประวัติล่าสุด
                </div>
                <div className="divide-y">
                    {history.map(t => (
                        <div key={t.id} className="p-3 text-sm flex justify-between items-center hover:bg-slate-50">
                            <div>
                                <div className="font-medium text-slate-800">{t.description}</div>
                                <div className="text-xs text-slate-400">{t.date} {t.category === 'Fuel' && `• ${t.quantity} ${t.unit}`}</div>
                            </div>
                            <span className="font-bold text-slate-700">฿{t.amount.toLocaleString()}</span>
                        </div>
                    ))}
                </div>
            </Card>
        </div>
    );
};

export default GeneralEntry;
