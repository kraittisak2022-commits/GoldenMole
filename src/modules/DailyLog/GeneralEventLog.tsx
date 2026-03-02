import { useState } from 'react';
import { FileText } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import { getToday } from '../../utils';
import { Transaction } from '../../types';

interface GeneralEventLogProps {
    onSave: (t: Transaction) => void;
    transactions: Transaction[];
}

const GeneralEventLog = ({ onSave, transactions }: GeneralEventLogProps) => {
    const [form, setForm] = useState({ date: getToday(), time: new Date().toLocaleTimeString('th-TH', { hour: '2-digit', minute: '2-digit' }), description: '' });
    const history = transactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'GeneralEvent').slice(-5).reverse();

    const handleSave = () => {
        if (!form.description) return alert('กรุณากรอกรายละเอียด');
        onSave({
            id: Date.now().toString(),
            date: form.date,
            type: 'Expense', // Just logging
            category: 'DailyLog',
            subCategory: 'GeneralEvent',
            description: form.description,
            amount: 0,
            eventTime: form.time
        } as any);
        setForm({ ...form, description: '' });
    };

    return (
        <div className="space-y-6 animate-fade-in">
            <Card className="p-6 max-w-xl mx-auto">
                <h3 className="font-bold text-lg mb-4 flex items-center gap-2"><FileText className="text-purple-500" /> บันทึกเหตุการณ์ทั่วไป</h3>
                <div className="space-y-4">
                    <div className="flex gap-4">
                        <Input label="วันที่" type="date" value={form.date} onChange={(e: any) => setForm({ ...form, date: e.target.value })} />
                        <Input label="เวลา" type="time" value={form.time} onChange={(e: any) => setForm({ ...form, time: e.target.value })} />
                    </div>
                    <div className="flex flex-col gap-1.5">
                        <label className="text-xs font-bold text-slate-500 uppercase tracking-wider">รายละเอียดเหตุการณ์</label>
                        <textarea
                            className="w-full px-4 py-2.5 rounded-xl border border-slate-200 focus:outline-none focus:ring-2 focus:ring-emerald-500/20 focus:border-emerald-500 transition-all bg-white text-slate-800 h-32 resize-none"
                            value={form.description}
                            onChange={(e) => setForm({ ...form, description: e.target.value })}
                            placeholder="เช่น ฝนตกหนักหยุดงาน, รถปูนเข้า 5 คัน, ลูกค้ามาดูหน้างาน..."
                        />
                    </div>
                    <Button onClick={handleSave} className="w-full">บันทึก</Button>
                </div>
            </Card>

            <Card className="p-0 overflow-hidden">
                <div className="p-4 bg-slate-50 border-b font-bold text-sm">เหตุการณ์ล่าสุด</div>
                <div className="divide-y">
                    {history.map(t => (
                        <div key={t.id} className="p-4 hover:bg-slate-50 flex gap-4 items-start">
                            <div className="text-xs font-bold text-slate-500 min-w-[60px] pt-1">{t.date}<br />{(t as any).eventTime}</div>
                            <div className="text-sm text-slate-800">{t.description}</div>
                        </div>
                    ))}
                </div>
            </Card>
        </div>
    );
};

export default GeneralEventLog;
