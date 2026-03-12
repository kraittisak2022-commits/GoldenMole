import { useState } from 'react';
import { Droplets, User } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import Select from '../../components/ui/Select';
import { getToday, formatDateBE } from '../../utils';
import { Transaction, Employee } from '../../types';

interface SandProductionLogProps {
    onSave: (t: Transaction) => void;
    transactions: Transaction[];
    employees: Employee[];
}

const SandProductionLog = ({ onSave, transactions, employees }: SandProductionLogProps) => {
    const [date, setDate] = useState(getToday());

    // State for Old Machine
    const [oldMachine, setOldMachine] = useState({ morning: '', afternoon: '', op1: '', op2: '', note: '' });

    // State for New Machine
    const [newMachine, setNewMachine] = useState({ morning: '', afternoon: '', op1: '', op2: '', note: '' });

    const history = transactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'SandProduction').slice(-5).reverse();

    const handleSave = () => {
        let savedCount = 0;

        // Save Old Machine Logic
        const oldTotal = (Number(oldMachine.morning) || 0) + (Number(oldMachine.afternoon) || 0);
        if (oldTotal > 0 || oldMachine.op1 || oldMachine.op2) {
            onSave({
                id: Date.now().toString() + '_old',
                date: date,
                type: 'Income',
                category: 'DailyLog',
                subCategory: 'SandProduction',
                description: `ผลิตทราย (เครื่องเก่า): ${oldTotal} คิว`,
                amount: 0,
                sandMorning: Number(oldMachine.morning),
                sandAfternoon: Number(oldMachine.afternoon),
                quantity: oldTotal,
                unit: 'คิว',
                sandMachineType: 'Old',
                sandOperators: [oldMachine.op1, oldMachine.op2].filter(Boolean),
                note: oldMachine.note
            } as any);
            savedCount++;
        }

        // Save New Machine Logic
        const newTotal = (Number(newMachine.morning) || 0) + (Number(newMachine.afternoon) || 0);
        if (newTotal > 0 || newMachine.op1 || newMachine.op2) {
            onSave({
                id: Date.now().toString() + '_new',
                date: date,
                type: 'Income',
                category: 'DailyLog',
                subCategory: 'SandProduction',
                description: `ผลิตทราย (เครื่องใหม่): ${newTotal} คิว`,
                amount: 0,
                sandMorning: Number(newMachine.morning),
                sandAfternoon: Number(newMachine.afternoon),
                quantity: newTotal,
                unit: 'คิว',
                sandMachineType: 'New',
                sandOperators: [newMachine.op1, newMachine.op2].filter(Boolean),
                note: newMachine.note
            } as any);
            savedCount++;
        }

        if (savedCount > 0) {
            setOldMachine({ morning: '', afternoon: '', op1: '', op2: '', note: '' });
            setNewMachine({ morning: '', afternoon: '', op1: '', op2: '', note: '' });
        } else {
            alert('กรุณากรอกข้อมูลอย่างน้อย 1 เครื่อง');
        }
    };

    return (
        <div className="space-y-6 animate-fade-in">
            <div className="flex justify-center mb-4">
                <div className="w-full max-w-xs">
                    <Input label="วันที่บันทึก" type="date" value={date} onChange={(e: any) => setDate(e.target.value)} />
                </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6 max-w-5xl mx-auto">
                {/* Old Machine Column */}
                <Card className="p-6 border-t-4 border-t-amber-500 shadow-lg group hover:shadow-xl transition-all">
                    <h3 className="font-bold text-xl mb-4 text-amber-600 flex items-center justify-between">
                        <span>เครื่องเก่า</span>
                        <Droplets className="text-amber-300" />
                    </h3>
                    <div className="space-y-4">
                        <div className="bg-amber-50 p-4 rounded-xl space-y-3">
                            <h4 className="text-sm font-bold text-amber-800">ปริมาณทราย (คิว)</h4>
                            <div className="grid grid-cols-2 gap-3">
                                <Input label="ช่วงเช้า" type="number" value={oldMachine.morning} onChange={(e: any) => setOldMachine({ ...oldMachine, morning: e.target.value })} className="bg-white" />
                                <Input label="ช่วงบ่าย" type="number" value={oldMachine.afternoon} onChange={(e: any) => setOldMachine({ ...oldMachine, afternoon: e.target.value })} className="bg-white" />
                            </div>
                            <div className="text-right text-xs font-bold text-amber-600">รวม: {(Number(oldMachine.morning) || 0) + (Number(oldMachine.afternoon) || 0)} คิว</div>
                        </div>

                        <div className="p-2 space-y-3">
                            <h4 className="text-sm font-bold text-slate-600 flex items-center gap-1"><User size={14} /> คนคุมเครื่อง</h4>
                            <div className="grid grid-cols-2 gap-3">
                                <Select label="คนที่ 1" value={oldMachine.op1} onChange={(e: any) => setOldMachine({ ...oldMachine, op1: e.target.value })}>
                                    <option value="">-- เลือก --</option>
                                    {employees.map(e => <option key={e.id} value={e.nickname}>{e.nickname}</option>)}
                                </Select>
                                <Select label="คนที่ 2" value={oldMachine.op2} onChange={(e: any) => setOldMachine({ ...oldMachine, op2: e.target.value })}>
                                    <option value="">-- เลือก --</option>
                                    {employees.map(e => <option key={e.id} value={e.nickname}>{e.nickname}</option>)}
                                </Select>
                            </div>
                        </div>
                        <Input label="หมายเหตุ" value={oldMachine.note} onChange={(e: any) => setOldMachine({ ...oldMachine, note: e.target.value })} />
                    </div>
                </Card>

                {/* New Machine Column */}
                <Card className="p-6 border-t-4 border-t-blue-500 shadow-lg group hover:shadow-xl transition-all">
                    <h3 className="font-bold text-xl mb-4 text-blue-600 flex items-center justify-between">
                        <span>เครื่องใหม่</span>
                        <Droplets className="text-blue-300" />
                    </h3>
                    <div className="space-y-4">
                        <div className="bg-blue-50 p-4 rounded-xl space-y-3">
                            <h4 className="text-sm font-bold text-blue-800">ปริมาณทราย (คิว)</h4>
                            <div className="grid grid-cols-2 gap-3">
                                <Input label="ช่วงเช้า" type="number" value={newMachine.morning} onChange={(e: any) => setNewMachine({ ...newMachine, morning: e.target.value })} className="bg-white" />
                                <Input label="ช่วงบ่าย" type="number" value={newMachine.afternoon} onChange={(e: any) => setNewMachine({ ...newMachine, afternoon: e.target.value })} className="bg-white" />
                            </div>
                            <div className="text-right text-xs font-bold text-blue-600">รวม: {(Number(newMachine.morning) || 0) + (Number(newMachine.afternoon) || 0)} คิว</div>
                        </div>

                        <div className="p-2 space-y-3">
                            <h4 className="text-sm font-bold text-slate-600 flex items-center gap-1"><User size={14} /> คนคุมเครื่อง</h4>
                            <div className="grid grid-cols-2 gap-3">
                                <Select label="คนที่ 1" value={newMachine.op1} onChange={(e: any) => setNewMachine({ ...newMachine, op1: e.target.value })}>
                                    <option value="">-- เลือก --</option>
                                    {employees.map(e => <option key={e.id} value={e.nickname}>{e.nickname}</option>)}
                                </Select>
                                <Select label="คนที่ 2" value={newMachine.op2} onChange={(e: any) => setNewMachine({ ...newMachine, op2: e.target.value })}>
                                    <option value="">-- เลือก --</option>
                                    {employees.map(e => <option key={e.id} value={e.nickname}>{e.nickname}</option>)}
                                </Select>
                            </div>
                        </div>
                        <Input label="หมายเหตุ" value={newMachine.note} onChange={(e: any) => setNewMachine({ ...newMachine, note: e.target.value })} />
                    </div>
                </Card>
            </div>

            <div className="flex justify-center mt-6">
                <Button onClick={handleSave} className="w-full max-w-md bg-emerald-600 hover:bg-emerald-700 shadow-lg transform hover:-translate-y-1 transition-all">บันทึกข้อมูลทั้งหมด</Button>
            </div>

            <Card className="p-0 overflow-hidden max-w-5xl mx-auto mt-8">
                <div className="p-4 bg-slate-800 text-white font-bold text-sm">ประวัติการผลิตล่าสุด</div>
                <div className="divide-y">
                    {history.map(t => (
                        <div key={t.id} className="p-4 text-sm flex justify-between items-center hover:bg-slate-50">
                            <div>
                                <div className="font-bold text-slate-800 flex items-center gap-2">
                                    {formatDateBE(t.date)}
                                    <span className={`px-2 py-0.5 rounded text-[10px] ${(t as any).sandMachineType === 'Old' ? 'bg-amber-100 text-amber-700' : 'bg-blue-100 text-blue-700'}`}>
                                        {(t as any).sandMachineType === 'Old' ? 'เครื่องเก่า' : 'เครื่องใหม่'}
                                    </span>
                                </div>
                                <div className="text-xs text-slate-500 mt-1">
                                    คนคุม: {((t as any).sandOperators || []).join(', ') || '-'} {t.note ? `• ${t.note}` : ''}
                                </div>
                            </div>
                            <div className="text-right">
                                <span className="font-bold text-slate-700 text-lg">{t.quantity} คิว</span>
                                <span className="text-xs text-slate-400 block">เช้า {(t as any).sandMorning} / บ่าย {(t as any).sandAfternoon}</span>
                            </div>
                        </div>
                    ))}
                </div>
            </Card>
        </div>
    );
};

export default SandProductionLog;
