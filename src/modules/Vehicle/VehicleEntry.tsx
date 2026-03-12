import { useState, useEffect } from 'react';
import { Truck } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import Select from '../../components/ui/Select';
import { getToday } from '../../utils';
import { AppSettings, Employee, Transaction } from '../../types';

interface VehicleEntryProps {
    settings: AppSettings;
    employees: Employee[];
    onSave: (t: any) => void;
}

const VEHICLE_DEFAULT_RATES: Record<string, number> = {
    'รถแม็คโคร SK200-8 (น้องโกลเด้น)': 12000,
    'รถแม็คโคร SK200-8 (พี่ยักษ์ใหญ่)': 15000,
    'รถดรัมโอเว่น': 3500,
    'รถดรัมนายก': 3000,
    'รถดรัมนายกนิต': 3000
};

const VehicleEntry = ({ settings, employees, onSave }: VehicleEntryProps) => {
    const [form, setForm] = useState({ date: getToday(), car: '', driver: '', location: '', wage: '', vehicleWage: '', workDetails: '' }); // Added workDetails

    useEffect(() => {
        if (form.car) {
            const defaultRate = VEHICLE_DEFAULT_RATES[form.car] || 0;
            setForm(prev => ({ ...prev, vehicleWage: defaultRate > 0 ? String(defaultRate) : prev.vehicleWage }));
        }
    }, [form.car]);

    const handleSave = () => {
        if (!form.car || !form.driver) return alert("ข้อมูลไม่ครบ");
        onSave({
            id: Date.now().toString(),
            date: form.date,
            type: 'Expense',
            category: 'Vehicle',
            description: `ขับรถ: ${form.car} ${form.workDetails ? `(${form.workDetails})` : ''}`,
            amount: Number(form.wage) + Number(form.vehicleWage),
            driverId: form.driver,
            vehicleId: form.car,
            driverWage: Number(form.wage),
            vehicleWage: Number(form.vehicleWage),
            location: form.location,
            workDetails: form.workDetails // Save field
        } as Transaction);
        setForm({ ...form, wage: '', workDetails: '' }); // Clear
    };

    return (
        <Card className="p-6 max-w-2xl mx-auto animate-fade-in">
            <h3 className="font-bold text-lg mb-6 flex items-center gap-2">
                <Truck className="text-amber-500" /> บันทึกการใช้รถ
            </h3>
            <div className="space-y-4">
                <Input label="วันที่" type="date" value={form.date} onChange={(e: any) => setForm({ ...form, date: e.target.value })} />
                <Select label="รถ/เครื่องจักร" value={form.car} onChange={(e: any) => setForm({ ...form, car: e.target.value })}>
                    <option value="">-- เลือกรถ --</option>
                    {settings.cars.map((c: string) => <option key={c}>{c}</option>)}
                </Select>
                <div className="grid grid-cols-2 gap-4">
                    <Select label="คนขับ" value={form.driver} onChange={(e: any) => setForm({ ...form, driver: e.target.value })}>
                        <option value="">-- เลือกคนขับ --</option>
                        {employees.map((e: Employee) => <option key={e.id} value={e.id}>{e.nickname}</option>)}
                    </Select>
                    <Input label="ค่าเบี้ยเลี้ยงคนขับ" type="number" value={form.wage} onChange={(e: any) => setForm({ ...form, wage: e.target.value })} />
                </div>
                <Input label="ค่าจ้างรถ (บาท)" type="number" value={form.vehicleWage} onChange={(e: any) => setForm({ ...form, vehicleWage: e.target.value })} className="input-highlight border-amber-200 text-amber-700" />
                <Select label="สถานที่" value={form.location} onChange={(e: any) => setForm({ ...form, location: e.target.value })}>
                    <option value="">-- เลือกสถานที่ --</option>
                    {settings.locations.map((l: string) => <option key={l}>{l}</option>)}
                </Select>
                <div className="flex flex-col gap-1">
                    <label className="text-sm font-medium text-slate-700">รายละเอียดงาน (Work Details)</label>
                    <textarea
                        className="border rounded-xl p-3 text-sm focus:outline-none focus:border-emerald-500"
                        rows={2}
                        placeholder="เช่น ขนดินจากบ่อ 1 ไปถมที่..."
                        value={form.workDetails}
                        onChange={(e) => setForm({ ...form, workDetails: e.target.value })}
                    />
                </div>
                <Button onClick={handleSave} className="w-full mt-4">บันทึก</Button>
            </div>
        </Card>
    );
};

export default VehicleEntry;
