import { useState } from 'react';
import { Wallet, History } from 'lucide-react';
import Card from '../components/ui/Card';
import Button from '../components/ui/Button';
import Input from '../components/ui/Input';
import Select from '../components/ui/Select';
import { getToday } from '../utils';
import { Transaction, AppSettings } from '../types';

interface IncomeEntryProps {
    settings: AppSettings;
    onSave: (t: Transaction) => void;
    transactions: Transaction[];
}

const IncomeEntry = ({ settings, onSave, transactions }: IncomeEntryProps) => {
    const [form, setForm] = useState({ qty: '', price: '', total: '', type: '' });
    const history = transactions.filter(t => t.type === 'Income').slice(-5).reverse();
    const handleCalc = (f: string, v: string) => {
        const n = { ...form, [f]: v };
        if (f !== 'total') n.total = String(Number(n.qty) * Number(n.price));
        else if (Number(n.qty) > 0) n.price = String(Number(n.total) / Number(n.qty));
        setForm(n);
    };
    return (
        <div className="max-w-2xl mx-auto space-y-6 animate-fade-in">
            <Card className="p-6">
                <h3 className="font-bold text-lg mb-6 flex items-center gap-2"><Wallet className="text-emerald-500" /> รายรับ</h3>
                <div className="space-y-4">
                    <Select label="ประเภท" value={form.type} onChange={(e: any) => setForm({ ...form, type: e.target.value })}>
                        <option value="">-- เลือกประเภท --</option>
                        {settings.incomeTypes.map(t => <option key={t} value={t}>{t}</option>)}
                    </Select>
                    <div className="grid grid-cols-3 gap-4">
                        <Input label="ปริมาณ" type="number" value={form.qty} onChange={(e: any) => handleCalc('qty', e.target.value)} />
                        <Input label="ราคา/หน่วย" type="number" value={form.price} onChange={(e: any) => handleCalc('price', e.target.value)} />
                        <Input label="รวม (บาท)" type="number" value={form.total} onChange={(e: any) => handleCalc('total', e.target.value)} className="font-bold" />
                    </div>
                    <Button onClick={() => {
                        if (!form.type || !form.total) return alert('กรอกข้อมูลให้ครบ');
                        onSave({ id: Date.now().toString(), date: getToday(), type: 'Income', category: 'Income', description: form.type, amount: Number(form.total) });
                        setForm({ qty: '', price: '', total: '', type: '' });
                    }} className="w-full">บันทึก</Button>
                </div>
            </Card>
            <Card className="p-0 overflow-hidden">
                <div className="p-4 bg-slate-50 border-b flex items-center gap-2 text-slate-600 font-bold text-sm"><History size={16} /> ประวัติรายรับล่าสุด</div>
                <div className="divide-y">
                    {history.map(t => (
                        <div key={t.id} className="p-3 text-sm flex justify-between items-center hover:bg-slate-50">
                            <div>
                                <div className="font-medium text-emerald-700">{t.description}</div>
                                <div className="text-xs text-slate-400">{t.date}</div>
                            </div>
                            <span className="font-bold text-emerald-600">+฿{t.amount.toLocaleString()}</span>
                        </div>
                    ))}
                </div>
            </Card>
        </div>
    );
};

export default IncomeEntry;
