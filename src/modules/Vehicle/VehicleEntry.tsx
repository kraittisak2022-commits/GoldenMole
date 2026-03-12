import { useState, useEffect, useMemo } from 'react';
import { Truck, Pencil, Trash2, History } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import Select from '../../components/ui/Select';
import { getToday, normalizeDate, formatDateBE } from '../../utils';
import { AppSettings, Employee, Transaction } from '../../types';

interface VehicleEntryProps {
    settings: AppSettings;
    employees: Employee[];
    transactions?: Transaction[];
    onSave: (t: any) => void;
    onDelete?: (id: string) => void;
}

const VEHICLE_DEFAULT_RATES: Record<string, number> = {
    'รถแม็คโคร SK200-8 (น้องโกลเด้น)': 12000,
    'รถแม็คโคร SK200-8 (พี่ยักษ์ใหญ่)': 15000,
    'รถดรัมโอเว่น': 3500,
    'รถดรัมนายก': 3000,
    'รถดรัมนายกนิต': 3000
};

const getEmpPositions = (e: Employee) => e.positions ?? (e.position ? [e.position] : []);
const driverEmployees = (employees: Employee[]) => employees.filter(e => getEmpPositions(e).includes('คนขับรถ'));

const VehicleEntry = ({ settings, employees, transactions = [], onSave, onDelete }: VehicleEntryProps) => {
    const [form, setForm] = useState({ date: getToday(), car: '', driver: '', location: '', wage: '', vehicleWage: '', workDetails: '' });
    const [editingId, setEditingId] = useState<string | null>(null);
    const drivers = driverEmployees(employees);

    const normDate = normalizeDate(form.date);
    const dayVehicleTx = useMemo(() =>
        transactions.filter(t => t.category === 'Vehicle' && normalizeDate(t.date) === normDate),
        [transactions, normDate]
    );

    useEffect(() => {
        if (form.car) {
            const defaultRate = VEHICLE_DEFAULT_RATES[form.car] || 0;
            setForm(prev => ({ ...prev, vehicleWage: defaultRate > 0 ? String(defaultRate) : prev.vehicleWage }));
        }
    }, [form.car]);

    useEffect(() => {
        if (dayVehicleTx.length > 0 && !editingId) {
            const latest = dayVehicleTx[dayVehicleTx.length - 1];
            setForm(prev => ({
                ...prev,
                car: latest.vehicleId || prev.car,
                driver: latest.driverId || prev.driver,
                location: latest.location || prev.location,
                wage: latest.driverWage != null ? String(latest.driverWage) : prev.wage,
                vehicleWage: latest.vehicleWage != null ? String(latest.vehicleWage) : prev.vehicleWage,
                workDetails: (latest as any).workDetails || prev.workDetails,
            }));
        }
    }, [form.date, dayVehicleTx, editingId]);

    const loadForEdit = (t: Transaction) => {
        setForm(prev => ({
            ...prev,
            car: t.vehicleId || '',
            driver: t.driverId || '',
            wage: t.driverWage != null ? String(t.driverWage) : '',
            vehicleWage: t.vehicleWage != null ? String(t.vehicleWage) : '',
            workDetails: (t as any).workDetails || '',
            location: t.location || prev.location,
        }));
        setEditingId(t.id);
    };

    const handleSave = () => {
        if (!form.car || !form.driver) return alert("ข้อมูลไม่ครบ");
        if (editingId && onDelete) {
            onDelete(editingId);
            setEditingId(null);
        }
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
            workDetails: form.workDetails
        } as Transaction);
        setForm(prev => ({ ...prev, wage: '', workDetails: '', car: '', driver: '' }));
    };

    return (
        <>
        <Card className="p-6 max-w-2xl mx-auto animate-fade-in">
            <h3 className="font-bold text-lg mb-6 flex items-center gap-2">
                <Truck className="text-amber-500" /> บันทึกการใช้รถ
            </h3>
            <div className="space-y-4">
                <Input label="วันที่" type="date" value={form.date} onChange={(e: any) => { setForm(prev => ({ ...prev, date: e.target.value })); setEditingId(null); }} />

                {dayVehicleTx.length > 0 && (
                    <div className="p-3 bg-amber-50 rounded-xl border border-amber-200">
                        <p className="text-sm font-semibold text-amber-800 mb-2">รายการรถในวันนี้ ({dayVehicleTx.length})</p>
                        <div className="space-y-2 max-h-48 overflow-y-auto">
                            {dayVehicleTx.map((t: Transaction) => (
                                <div key={t.id} className={`flex items-center justify-between p-2 rounded-lg border text-sm ${editingId === t.id ? 'bg-amber-100 border-amber-400' : 'bg-white border-amber-100'}`}>
                                    <span className="truncate">{t.vehicleId} — ฿{t.amount?.toLocaleString()}</span>
                                    <div className="flex gap-1 shrink-0">
                                        <button type="button" onClick={() => loadForEdit(t)} className="p-1.5 rounded text-slate-600 hover:bg-amber-200" title="แก้ไข"><Pencil size={14} /></button>
                                        {onDelete && <button type="button" onClick={() => { if (confirm('ลบรายการนี้?')) { onDelete(t.id); setEditingId(null); } }} className="p-1.5 rounded text-red-600 hover:bg-red-50" title="ลบ"><Trash2 size={14} /></button>}
                                    </div>
                                </div>
                            ))}
                        </div>
                        {editingId && <button type="button" onClick={() => setEditingId(null)} className="mt-2 text-xs text-amber-700 hover:text-amber-900">ล้างเพื่อเพิ่มใหม่</button>}
                    </div>
                )}
                <Select label="รถ/เครื่องจักร" value={form.car} onChange={(e: any) => setForm({ ...form, car: e.target.value })}>
                    <option value="">-- เลือกรถ --</option>
                    {settings.cars.map((c: string) => <option key={c}>{c}</option>)}
                </Select>
                <div className="grid grid-cols-2 gap-4">
                    <Select label="คนขับ (เฉพาะตำแหน่งคนขับรถ)" value={form.driver} onChange={(e: any) => setForm({ ...form, driver: e.target.value })}>
                        <option value="">-- เลือกคนขับ --</option>
                        {drivers.map((e: Employee) => <option key={e.id} value={e.id}>{e.nickname || e.name}</option>)}
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

        {/* ประวัติการใช้รถ */}
        {transactions && (() => {
            const vehicleHistory = transactions.filter((t: Transaction) => t.category === 'Vehicle').slice(-30).reverse();
            return (
                <Card className="mt-6 p-0 overflow-hidden border border-slate-200 shadow-sm">
                    <div className="p-4 bg-gradient-to-r from-amber-50 to-amber-100/50 border-b flex items-center justify-between">
                        <span className="flex items-center gap-2 text-amber-800 font-bold">
                            <History size={18} /> ประวัติการใช้รถ ({vehicleHistory.length} รายการ)
                        </span>
                    </div>
                    <div className="divide-y divide-slate-100 max-h-[400px] overflow-y-auto">
                        {vehicleHistory.length === 0 ? (
                            <div className="p-8 text-center text-slate-400 text-sm">ยังไม่มีรายการ</div>
                        ) : (
                            vehicleHistory.map((t: Transaction) => (
                                <div key={t.id} className={`p-4 flex justify-between items-center gap-3 hover:bg-slate-50/80 transition-colors group ${editingId === t.id ? 'bg-amber-50 ring-1 ring-amber-200' : ''}`}>
                                    <div className="min-w-0 flex-1">
                                        <div className="font-medium text-slate-800">{t.vehicleId || '—'}</div>
                                        <div className="text-xs text-slate-500 mt-0.5">{formatDateBE(t.date)} {(t as any).workDetails && `• ${(t as any).workDetails}`}</div>
                                    </div>
                                    <div className="flex items-center gap-2 shrink-0">
                                        <span className="font-bold text-amber-700 tabular-nums">฿{(t.amount || 0).toLocaleString()}</span>
                                        <button type="button" onClick={() => loadForEdit(t)} className="p-2 rounded-lg text-slate-400 hover:text-amber-600 hover:bg-amber-50 opacity-0 group-hover:opacity-100 transition-all" title="แก้ไข"><Pencil size={16} /></button>
                                        {onDelete && <button type="button" onClick={() => { if (confirm('ลบรายการนี้?')) { onDelete(t.id); setEditingId(null); } }} className="p-2 rounded-lg text-slate-400 hover:text-red-600 hover:bg-red-50 opacity-0 group-hover:opacity-100 transition-all" title="ลบ"><Trash2 size={16} /></button>}
                                    </div>
                                </div>
                            ))
                        )}
                    </div>
                </Card>
            );
        })()}
    </>
    );
};

export default VehicleEntry;
