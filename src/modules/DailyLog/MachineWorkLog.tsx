import { useState } from 'react';
import { Truck } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import Select from '../../components/ui/Select';
import { getToday } from '../../utils';
import { AppSettings, Transaction } from '../../types';

interface MachineWorkLogProps {
    settings: AppSettings;
    onSave: (t: Transaction) => void;
    transactions: Transaction[];
}

const MachineWorkLog = ({ settings, onSave, transactions }: MachineWorkLogProps) => {
    const [form, setForm] = useState({ date: getToday(), machine: '', hours: '', description: '', location: '' });
    const history = transactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'MachineWork').slice(-5).reverse();

    const handleSave = () => {
        if (!form.machine || !form.hours) return alert('กรุณากรอกข้อมูลให้ครบ');
        onSave({
            id: Date.now().toString(),
            date: form.date,
            type: 'Expense', // Tracking as expense/resource usage
            category: 'DailyLog',
            subCategory: 'MachineWork',
            description: `งานเครื่องจักร: ${form.machine} (${form.hours} ชม.)`,
            amount: 0, // No direct cost here, just logging
            machineId: form.machine,
            machineHours: Number(form.hours),
            location: form.location,
            note: form.description
        } as any);
        setForm({ ...form, hours: '', description: '' });
    };

    return (
        <div className="space-y-6 animate-fade-in">
            <Card className="p-6 max-w-xl mx-auto">
                <h3 className="font-bold text-lg mb-4 flex items-center gap-2"><Truck className="text-amber-500" /> บันทึกการทำงานเครื่องจักร</h3>
                <div className="space-y-4">
                    <Input label="วันที่" type="date" value={form.date} onChange={(e: any) => setForm({ ...form, date: e.target.value })} />
                    <Select label="รถ/เครื่องจักร" value={form.machine} onChange={(e: any) => setForm({ ...form, machine: e.target.value })}>
                        <option value="">-- เลือกเครื่องจักร --</option>
                        {settings.cars.map(c => <option key={c} value={c}>{c}</option>)}
                    </Select>
                    <div className="grid grid-cols-2 gap-4">
                        <Input label="ชั่วโมงทำงาน" type="number" value={form.hours} onChange={(e: any) => setForm({ ...form, hours: e.target.value })} />
                        <Select label="สถานที่" value={form.location} onChange={(e: any) => setForm({ ...form, location: e.target.value })}>
                            <option value="">-- เลือกสถานที่ --</option>
                            {settings.locations.map(l => <option key={l} value={l}>{l}</option>)}
                        </Select>
                    </div>
                    <Input label="รายละเอียดงาน" value={form.description} onChange={(e: any) => setForm({ ...form, description: e.target.value })} placeholder="เช่น ขุดบ่อ, ปรับหน้าดิน" />
                    <Button onClick={handleSave} className="w-full">บันทึก</Button>
                </div>
            </Card>

            <Card className="p-0 overflow-hidden">
                <div className="p-4 bg-slate-50 border-b font-bold text-sm">ประวัติล่าสุด</div>
                <div className="divide-y">
                    {history.map(t => (
                        <div key={t.id} className="p-3 text-sm flex justify-between items-center hover:bg-slate-50">
                            <div>
                                <div className="font-medium text-slate-800">{t.description}</div>
                                <div className="text-xs text-slate-400">{t.date} • {t.location}</div>
                            </div>
                            <span className="font-bold text-slate-600">{t.machineHours} ชม.</span>
                        </div>
                    ))}
                </div>
            </Card>
        </div>
    );
};

export default MachineWorkLog;
