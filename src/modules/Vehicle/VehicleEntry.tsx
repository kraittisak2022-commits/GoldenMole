import { useState, useEffect, useMemo } from 'react';
import { Truck, Pencil, Trash2, History, ClipboardList, BarChart3 } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import Select from '../../components/ui/Select';
import { getToday, normalizeDate, formatDateBE } from '../../utils';
import { AppSettings, Employee, Transaction, WorkType } from '../../types';
import { dailyWageForWorkType } from '../../utils/laborWage';

interface VehicleEntryProps {
    settings: AppSettings;
    employees: Employee[];
    transactions?: Transaction[];
    onSave: (t: any) => void;
    onDelete?: (id: string) => void;
    ensureEmployeeWage?: (emp: Employee) => Promise<number>;
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

const VehicleEntry = ({ settings, employees, transactions = [], onSave, onDelete, ensureEmployeeWage }: VehicleEntryProps) => {
    const [section, setSection] = useState<'entry' | 'stats' | 'history'>('entry');
    const [form, setForm] = useState({ date: getToday(), car: '', driver: '', location: '', wage: '', vehicleWage: '', workDetails: '' });
    const [workType, setWorkType] = useState<WorkType>('FullDay');
    const [editingId, setEditingId] = useState<string | null>(null);
    const drivers = driverEmployees(employees);

    const vehicleStats = useMemo(() => {
        const v = transactions.filter(t => t.category === 'Vehicle' && t.type === 'Expense');
        const total = v.reduce((s, t) => s + (t.amount || 0), 0);
        const byCar: Record<string, number> = {};
        const byDriver: Record<string, number> = {};
        v.forEach(t => {
            const c = (t.vehicleId || 'ไม่ระบุรถ').trim();
            byCar[c] = (byCar[c] || 0) + (t.amount || 0);
            const dr = t.driverId
                ? employees.find(e => e.id === t.driverId)?.nickname || employees.find(e => e.id === t.driverId)?.name || t.driverId
                : 'ไม่ระบุคนขับ';
            byDriver[dr] = (byDriver[dr] || 0) + (t.amount || 0);
        });
        const carRows = Object.entries(byCar).sort((a, b) => b[1] - a[1]);
        const driverRows = Object.entries(byDriver).sort((a, b) => b[1] - a[1]);
        return { total, count: v.length, carRows, driverRows };
    }, [transactions, employees]);

    const tabClass = (active: boolean) =>
        `flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-bold transition-colors ${
            active
                ? 'bg-slate-800 text-white dark:bg-slate-100 dark:text-slate-900'
                : 'bg-slate-100 text-slate-600 hover:bg-slate-200 dark:bg-white/[0.08] dark:text-slate-300 dark:hover:bg-white/[0.14]'
        }`;

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

    const applyDriverAllowance = async (driverId: string, wt: WorkType) => {
        if (!driverId) {
            setForm((prev) => ({ ...prev, wage: '' }));
            return;
        }
        const emp = employees.find((e) => e.id === driverId);
        if (!emp) return;
        try {
            const w = ensureEmployeeWage ? await ensureEmployeeWage(emp) : (emp.baseWage ?? 0);
            const allowance = dailyWageForWorkType(emp, w, wt);
            setForm((prev) => ({ ...prev, wage: String(allowance) }));
        } catch {
            /* ignore */
        }
    };

    useEffect(() => {
        if (dayVehicleTx.length > 0 && !editingId) {
            const latest = dayVehicleTx[dayVehicleTx.length - 1];
            const wt: WorkType = (latest as any).workType === 'HalfDay' ? 'HalfDay' : 'FullDay';
            setWorkType(wt);
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
        const wt: WorkType = (t as any).workType === 'HalfDay' ? 'HalfDay' : 'FullDay';
        setWorkType(wt);
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
        const duplicateVeh = dayVehicleTx.find(
            (t) =>
                t.id !== editingId &&
                t.vehicleId === form.car &&
                t.driverId === form.driver &&
                ((t.workType || 'FullDay') === workType)
        );
        if (duplicateVeh) {
            if (!window.confirm(`มีรายการรถคันนี้กับคนขับนี้อยู่แล้วในวันนี้ (${form.car}) — ต้องการบันทึกซ้ำหรือไม่?`)) return;
        }
        if (editingId && onDelete) {
            onDelete(editingId);
            setEditingId(null);
        }
        const dayLabel = workType === 'HalfDay' ? 'ครึ่งวัน' : 'เต็มวัน';
        const detailsPart = (form.workDetails || '').trim();
        onSave({
            id: Date.now().toString(),
            date: form.date,
            type: 'Expense',
            category: 'Vehicle',
            description: `รถ: ${form.car} (${detailsPart || '—'}) [${dayLabel}]`,
            amount: Number(form.wage) + Number(form.vehicleWage),
            driverId: form.driver,
            vehicleId: form.car,
            driverWage: Number(form.wage),
            vehicleWage: Number(form.vehicleWage),
            location: form.location,
            workDetails: form.workDetails,
            workType,
        } as Transaction);
        setForm(prev => ({ ...prev, wage: '', workDetails: '', car: '', driver: '' }));
        setWorkType('FullDay');
    };

    return (
        <div className="space-y-6 animate-fade-in max-w-2xl mx-auto">
            <div className="flex flex-wrap gap-2 border-b border-slate-200 dark:border-white/10 pb-2 mb-2">
                <button type="button" onClick={() => setSection('entry')} className={tabClass(section === 'entry')}>
                    <ClipboardList size={18} /> บันทึก
                </button>
                <button type="button" onClick={() => setSection('stats')} className={tabClass(section === 'stats')}>
                    <BarChart3 size={18} /> สถิติ
                </button>
                <button type="button" onClick={() => setSection('history')} className={tabClass(section === 'history')}>
                    <History size={18} /> ประวัติ
                </button>
            </div>

        {section === 'entry' && (
        <Card className="p-6">
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
                    <Select
                        label="คนขับ (เฉพาะตำแหน่งคนขับรถ)"
                        value={form.driver}
                        onChange={(e: any) => {
                            const val = e.target.value;
                            setForm({ ...form, driver: val });
                            void applyDriverAllowance(val, workType);
                        }}
                    >
                        <option value="">-- เลือกคนขับ --</option>
                        {drivers.map((e: Employee) => <option key={e.id} value={e.id}>{e.nickname || e.name || e.id}</option>)}
                    </Select>
                    <Input label="ค่าเบี้ยเลี้ยงคนขับ" type="number" value={form.wage} onChange={(e: any) => setForm({ ...form, wage: e.target.value })} />
                </div>
                <div className="flex flex-col gap-2">
                    <span className="text-sm font-medium text-slate-700">การทำงานของคนขับ (เดียวกับ Daily Wizard)</span>
                    <div className="flex flex-wrap gap-2">
                        <button
                            type="button"
                            onClick={() => {
                                setWorkType('FullDay');
                                void applyDriverAllowance(form.driver, 'FullDay');
                            }}
                            className={`rounded-lg border px-3 py-1.5 text-sm font-medium transition-colors ${workType === 'FullDay' ? 'border-emerald-600 bg-emerald-600 text-white' : 'border-slate-200 bg-white text-slate-600 hover:border-emerald-300'}`}
                        >
                            เต็มวัน
                        </button>
                        <button
                            type="button"
                            onClick={() => {
                                setWorkType('HalfDay');
                                void applyDriverAllowance(form.driver, 'HalfDay');
                            }}
                            className={`rounded-lg border px-3 py-1.5 text-sm font-medium transition-colors ${workType === 'HalfDay' ? 'border-amber-500 bg-amber-500 text-white' : 'border-slate-200 bg-white text-slate-600 hover:border-amber-300'}`}
                        >
                            ครึ่งวัน
                        </button>
                    </div>
                    <p className="text-xs text-slate-500">ครึ่งวัน = เบี้ยเลี้ยงคนขับครึ่งหนึ่งของค่าแรงรายวัน (ค่าจ้างรถไม่เปลี่ยน)</p>
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
        )}

        {section === 'stats' && (
            <div className="space-y-4">
                <Card className="p-6">
                    <h3 className="font-bold text-lg mb-4 flex items-center gap-2 text-slate-800 dark:text-slate-100">
                        <BarChart3 className="text-amber-500" /> สรุปการใช้รถทั้งหมด
                    </h3>
                    <div className="grid grid-cols-2 gap-3 mb-6">
                        <div className="rounded-xl border border-amber-100 dark:border-amber-500/20 bg-amber-50/80 dark:bg-amber-950/20 p-4">
                            <p className="text-xs text-amber-800 dark:text-amber-200">จำนวนครั้ง</p>
                            <p className="text-2xl font-bold text-slate-900 dark:text-white">{vehicleStats.count}</p>
                        </div>
                        <div className="rounded-xl border border-slate-200 dark:border-white/10 p-4">
                            <p className="text-xs text-slate-500">ยอดรวมค่าใช้รถ</p>
                            <p className="text-2xl font-bold text-amber-700 dark:text-amber-300">฿{vehicleStats.total.toLocaleString()}</p>
                        </div>
                    </div>
                </Card>
                <Card className="p-6">
                    <h4 className="font-semibold text-slate-700 dark:text-slate-200 mb-3">แยกตามคันรถ</h4>
                    {vehicleStats.carRows.length === 0 ? (
                        <p className="text-sm text-slate-400">ยังไม่มีข้อมูล</p>
                    ) : (
                        <ul className="space-y-2 max-h-52 overflow-y-auto">
                            {vehicleStats.carRows.map(([name, amt]) => (
                                <li key={name} className="flex justify-between text-sm border-b border-slate-100 dark:border-white/10 pb-2">
                                    <span className="text-slate-700 dark:text-slate-300 truncate pr-2">{name}</span>
                                    <span className="font-semibold text-amber-700 dark:text-amber-300 shrink-0">฿{amt.toLocaleString()}</span>
                                </li>
                            ))}
                        </ul>
                    )}
                </Card>
                <Card className="p-6">
                    <h4 className="font-semibold text-slate-700 dark:text-slate-200 mb-3">แยกตามคนขับ</h4>
                    {vehicleStats.driverRows.length === 0 ? (
                        <p className="text-sm text-slate-400">ยังไม่มีข้อมูล</p>
                    ) : (
                        <ul className="space-y-2 max-h-52 overflow-y-auto">
                            {vehicleStats.driverRows.map(([name, amt]) => (
                                <li key={name} className="flex justify-between text-sm border-b border-slate-100 dark:border-white/10 pb-2">
                                    <span className="text-slate-700 dark:text-slate-300 truncate pr-2">{name}</span>
                                    <span className="font-semibold text-slate-800 dark:text-slate-100 shrink-0">฿{amt.toLocaleString()}</span>
                                </li>
                            ))}
                        </ul>
                    )}
                </Card>
            </div>
        )}

        {section === 'history' && transactions && (() => {
            const vehicleHistory = transactions.filter((t: Transaction) => t.category === 'Vehicle').slice(-30).reverse();
            return (
                <Card className="p-0 overflow-hidden border border-slate-200 shadow-sm">
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
        </div>
    );
};

export default VehicleEntry;
