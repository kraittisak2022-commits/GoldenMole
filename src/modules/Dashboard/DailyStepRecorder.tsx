import { useState, useMemo } from 'react';
import { Calendar, Users, Truck, Fuel, CheckCircle2, ChevronRight, FileText, Plus, Trash2, Droplets, AlertTriangle } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import DatePicker from '../../components/ui/DatePicker';
import Select from '../../components/ui/Select';
import { getToday, formatDateBE } from '../../utils';
import { Employee, Transaction, AppSettings } from '../../types';

interface DailyStepRecorderProps {
    employees: Employee[];
    settings: AppSettings;
    transactions: Transaction[];
    onSaveTransaction: (t: Transaction) => void;
    onDeleteTransaction?: (id: string) => void;
}

const STEPS = [
    { id: 0, label: 'วันที่ทำงาน', icon: Calendar },
    { id: 1, label: 'ค่าแรง', icon: Users },
    { id: 2, label: 'การใช้รถ', icon: Truck },
    { id: 3, label: 'เที่ยวรถ', icon: Truck },
    { id: 4, label: 'ล้างทราย', icon: Droplets },
    { id: 5, label: 'น้ำมัน', icon: Fuel },
    { id: 6, label: 'เหตุการณ์', icon: AlertTriangle },
    { id: 7, label: 'ตรวจสอบ', icon: CheckCircle2 }
];

// Default work categories for labor canvas
const DEFAULT_WORK_CATEGORIES = [
    { id: 'wash1', label: 'ล้างทราย เครื่องร่อน 1 (เก่า)', color: 'bg-blue-500', bgLight: 'bg-blue-50 border-blue-200' },
    { id: 'wash2', label: 'ล้างทราย เครื่องร่อน 2 (ใหม่)', color: 'bg-cyan-500', bgLight: 'bg-cyan-50 border-cyan-200' },
    { id: 'washHome', label: 'ล้างทรายที่บ้าน', color: 'bg-teal-500', bgLight: 'bg-teal-50 border-teal-200' },
    { id: 'other', label: 'ทำอื่นๆ', color: 'bg-slate-500', bgLight: 'bg-slate-50 border-slate-200' },
];

const DailyStepRecorder = ({ employees, settings, transactions, onSaveTransaction, onDeleteTransaction }: DailyStepRecorderProps) => {
    const [step, setStep] = useState(0);
    const [date, setDate] = useState(getToday());

    // Derived: Transactions for the selected date
    const dayTransactions = useMemo(() => {
        return transactions.filter(t => t.date === date);
    }, [transactions, date]);

    // Labor State
    const [laborSearch, setLaborSearch] = useState('');
    const [selectedEmps, setSelectedEmps] = useState<string[]>([]);
    const [laborStatus, setLaborStatus] = useState<'Work' | 'OT' | 'Leave'>('Work');
    const [otHours, setOtHours] = useState('');
    const [otDesc, setOtDesc] = useState('');
    const [otRate, setOtRate] = useState('');
    // Canvas-style work category assignments: { categoryId: employeeId[] }
    const [workAssignments, setWorkAssignments] = useState<Record<string, string[]>>({});
    const [customCategories, setCustomCategories] = useState<Array<{ id: string; label: string }>>([]);
    const [newCategoryName, setNewCategoryName] = useState('');
    const [dragEmployee, setDragEmployee] = useState<string | null>(null);

    // Vehicle State
    const [vehCar, setVehCar] = useState('');
    const [vehDriver, setVehDriver] = useState('');
    const [vehWage, setVehWage] = useState('');
    const [vehMachineWage, setVehMachineWage] = useState('');
    const [vehDetails, setVehDetails] = useState('');
    const [vehLocation] = useState(settings.locations[0] || '');

    // Daily Log State (Vehicle Trips - Multi-card Canvas)
    const [tripEntries, setTripEntries] = useState<Array<{ id: string; vehicle: string; driver: string; work: string }>>([
        { id: Date.now().toString(), vehicle: '', driver: '', work: '' }
    ]);
    const [tripMorning, setTripMorning] = useState('');
    const [tripAfternoon, setTripAfternoon] = useState('');
    const [cubicPerTrip, setCubicPerTrip] = useState('3');
    const totalTrips = (Number(tripMorning) || 0) + (Number(tripAfternoon) || 0);
    const totalCubic = totalTrips * (Number(cubicPerTrip) || 0);
    const addTripCard = () => setTripEntries(prev => [...prev, { id: Date.now().toString(), vehicle: '', driver: '', work: '' }]);
    const removeTripCard = (id: string) => setTripEntries(prev => prev.length > 1 ? prev.filter(e => e.id !== id) : prev);
    const updateTripCard = (id: string, field: string, value: string) => setTripEntries(prev => prev.map(e => e.id === id ? { ...e, [field]: value } : e));

    // Sand Washing State
    const [sand1Morning, setSand1Morning] = useState('');
    const [sand1Afternoon, setSand1Afternoon] = useState('');
    const [sand2Morning, setSand2Morning] = useState('');
    const [sand2Afternoon, setSand2Afternoon] = useState('');
    const [sand1Operators, setSand1Operators] = useState<string[]>([]);
    const [sand2Operators, setSand2Operators] = useState<string[]>([]);
    const sand1Total = (Number(sand1Morning) || 0) + (Number(sand1Afternoon) || 0);
    const sand2Total = (Number(sand2Morning) || 0) + (Number(sand2Afternoon) || 0);
    const sandGrandTotal = sand1Total + sand2Total;

    // Fuel State
    const [fuelAmount, setFuelAmount] = useState('');
    const [fuelLiters, setFuelLiters] = useState('');
    const [fuelType, setFuelType] = useState<any>('Diesel');
    const [fuelUnit, setFuelUnit] = useState('ลิตร');
    const [fuelDetails, setFuelDetails] = useState('');

    // Events State
    const [eventDesc, setEventDesc] = useState('');
    const [eventType, setEventType] = useState('info');
    const [eventPriority, setEventPriority] = useState('normal');

    const nextStep = () => setStep(s => Math.min(s + 1, STEPS.length - 1));
    const prevStep = () => setStep(s => Math.max(s - 1, 0));

    return (
        <div className="min-h-screen bg-slate-50 p-3 sm:p-4 lg:p-6 animate-fade-in relative">
            {/* Header */}
            <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between mb-4 sm:mb-8 gap-3">
                <div>
                    <h2 className="text-lg sm:text-2xl font-bold text-slate-800">บันทึกงานประจำวัน (Daily Wizard)</h2>
                    <p className="text-slate-500 text-xs sm:text-sm">ระบบช่วยบันทึกข้อมูลแบบทีละขั้นตอน</p>
                </div>
                <div className="flex gap-1.5 sm:gap-2 overflow-x-auto pb-1 hide-scrollbar w-full sm:w-auto">
                    {STEPS.map((s, i) => (
                        <div key={s.id} className={`flex items-center gap-1 sm:gap-2 px-2 sm:px-3 py-1.5 rounded-full text-xs font-medium transition-colors shrink-0 ${step === i ? 'bg-indigo-600 text-white' : i < step ? 'bg-emerald-100 text-emerald-700' : 'bg-slate-200 text-slate-500'}`}>
                            <s.icon size={12} />
                            <span className="hidden sm:inline">{s.label}</span>
                        </div>
                    ))}
                </div>
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-12 gap-4 sm:gap-6 lg:gap-8">
                {/* Left: Wizard Form */}
                <div className="lg:col-span-8 space-y-6">
                    <Card className="p-6 min-h-[500px] flex flex-col relative overflow-hidden">

                        {/* Step 0: Date */}
                        {step === 0 && (
                            <div className="flex flex-col items-center justify-center h-full space-y-6 animate-slide-up">
                                <div className="w-16 h-16 bg-indigo-100 rounded-full flex items-center justify-center text-indigo-600 mb-2">
                                    <Calendar size={32} />
                                </div>
                                <h3 className="text-xl font-bold text-slate-800">เลือกวันที่ต้องการบันทึก</h3>
                                <div className="w-full max-w-sm">
                                    <DatePicker label="วันที่" value={date} onChange={setDate} />
                                </div>
                                <div className="p-4 bg-orange-50 text-orange-700 rounded-xl text-sm border border-orange-100 max-w-md text-center">
                                    💡 ระบบจะดึงข้อมูลเก่าของวันนี้มาแสดงให้ตรวจสอบด้วยครับ
                                </div>
                                <Button onClick={nextStep} className="mt-8 px-8 py-3 text-lg shadow-lg shadow-indigo-200">
                                    เริ่มบันทึก <ChevronRight className="ml-2" />
                                </Button>
                            </div>
                        )}

                        {/* Step 1: Labor - Canvas Style */}
                        {step === 1 && (
                            <div className="h-full flex flex-col animate-slide-up">
                                <div className="flex justify-between items-center mb-3">
                                    <h3 className="font-bold text-lg flex items-center gap-2"><Users className="text-emerald-500" /> บันทึกค่าแรง / OT</h3>
                                    <span className="text-xs text-slate-400">{new Date(date).toLocaleDateString('th-TH', { day: 'numeric', month: 'short', year: '2-digit' })}</span>
                                </div>

                                <div className="flex gap-3 mb-4">
                                    <button onClick={() => setLaborStatus('Work')} className={`flex-1 py-3 rounded-xl border text-base transition-all ${laborStatus === 'Work' ? 'bg-emerald-50 border-emerald-500 text-emerald-700 font-bold' : 'bg-white hover:bg-slate-50'}`}>✅ มาทำงาน</button>
                                    <button onClick={() => setLaborStatus('OT')} className={`flex-1 py-3 rounded-xl border text-base transition-all ${laborStatus === 'OT' ? 'bg-amber-50 border-amber-500 text-amber-700 font-bold' : 'bg-white hover:bg-slate-50'}`}>🕒 OT</button>
                                </div>

                                {/* === OT MODE: Clean form layout === */}
                                {laborStatus === 'OT' && (
                                    <div className="flex-1 flex flex-col">
                                        <div className="flex-1 bg-white p-5 rounded-2xl border border-slate-200 shadow-sm space-y-5">
                                            {/* Date */}
                                            <div>
                                                <label className="text-sm font-bold text-slate-700 mb-1.5 block">วันที่</label>
                                                <input type="date" value={date} readOnly
                                                    className="w-full px-4 py-3 border border-slate-300 rounded-xl text-base text-slate-800 bg-slate-50" />
                                            </div>

                                            {/* Employee selector */}
                                            <div className="border border-slate-200 rounded-xl p-4">
                                                <div className="flex justify-between items-center mb-3">
                                                    <span className="text-sm font-bold text-slate-700">เลือกพนักงาน ({selectedEmps.length})</span>
                                                    <input placeholder="ค้นหาชื่อ..." value={laborSearch} onChange={e => setLaborSearch(e.target.value)}
                                                        className="text-sm border rounded-lg px-3 py-1.5 w-32" />
                                                </div>
                                                <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
                                                    {employees.filter(e => e.name.includes(laborSearch) || e.nickname.includes(laborSearch)).map(emp => {
                                                        const isSelected = selectedEmps.includes(emp.id);
                                                        return (
                                                            <button key={emp.id}
                                                                onClick={() => setSelectedEmps(prev => prev.includes(emp.id) ? prev.filter(id => id !== emp.id) : [...prev, emp.id])}
                                                                className={`px-3 py-2.5 rounded-xl text-sm text-left font-medium transition-all border-2 ${isSelected ? 'border-slate-800 bg-slate-50 text-slate-800' : 'border-slate-200 bg-white text-slate-500 hover:border-slate-300'}`}>
                                                                {emp.nickname} ({emp.name})
                                                            </button>
                                                        );
                                                    })}
                                                </div>
                                            </div>

                                            {/* OT Rate */}
                                            <div>
                                                <label className="text-sm font-bold text-slate-700 mb-1.5 block">ค่า OT (บาท/คน/ชม.)</label>
                                                <input type="number" placeholder="" value={otRate} onChange={e => setOtRate(e.target.value)}
                                                    className="w-full px-4 py-3.5 border border-slate-300 rounded-xl text-base text-slate-800 focus:border-slate-500 focus:outline-none transition-colors" />
                                            </div>

                                            {/* OT Hours */}
                                            <div>
                                                <label className="text-sm font-bold text-slate-700 mb-1.5 block">จำนวนชั่วโมง OT</label>
                                                <input type="number" placeholder="เช่น 2.5" value={otHours} onChange={e => setOtHours(e.target.value)}
                                                    className="w-full px-4 py-3 border border-slate-300 rounded-xl text-base text-slate-800 focus:border-slate-500 focus:outline-none transition-colors" />
                                            </div>

                                            {/* OT Description */}
                                            <div>
                                                <label className="text-sm font-bold text-slate-700 mb-1.5 block">รายละเอียดงาน OT</label>
                                                <input type="text" placeholder="ทำอะไร..." value={otDesc} onChange={e => setOtDesc(e.target.value)}
                                                    className="w-full px-4 py-3 border border-slate-300 rounded-xl text-base text-slate-800 focus:border-slate-500 focus:outline-none transition-colors" />
                                            </div>

                                            {/* OT Summary */}
                                            {selectedEmps.length > 0 && Number(otRate) > 0 && Number(otHours) > 0 && (
                                                <div className="bg-amber-50 p-3 rounded-xl border border-amber-200 text-center">
                                                    <span className="text-sm text-amber-800">รวม: <span className="font-bold text-lg">{(Number(otRate) * Number(otHours) * selectedEmps.length).toLocaleString()}</span> บาท</span>
                                                    <span className="text-xs text-amber-600 block">({selectedEmps.length} คน × {otRate} บาท × {otHours} ชม.)</span>
                                                </div>
                                            )}

                                            {/* Save */}
                                            <button onClick={() => {
                                                if (selectedEmps.length === 0) return alert('กรุณาเลือกพนักงาน');
                                                if (!otRate) return alert('กรุณาระบุค่า OT');
                                                const rate = Number(otRate) || 0;
                                                const hours = Number(otHours) || 0;
                                                const totalAmount = rate * hours * selectedEmps.length;
                                                const empNames = selectedEmps.map(id => employees.find(e => e.id === id)?.nickname || '').join(', ');
                                                onSaveTransaction({
                                                    id: Date.now().toString(), date, employeeIds: selectedEmps,
                                                    type: 'Expense', category: 'Labor', subCategory: 'OT', laborStatus: 'OT',
                                                    amount: totalAmount, otAmount: rate, otHours: hours, otDescription: otDesc,
                                                    description: `OT ${otDesc} (${otHours}ชม.) ${selectedEmps.length}คน [${empNames}]`
                                                } as Transaction);
                                                setSelectedEmps([]); setOtRate(''); setOtHours(''); setOtDesc(''); setLaborStatus('Work');
                                            }} className="w-full py-3.5 bg-slate-800 hover:bg-slate-900 text-white text-base font-bold rounded-xl transition-colors">
                                                บันทึก
                                            </button>
                                        </div>
                                        <div className="mt-auto pt-3 flex justify-between">
                                            <Button variant="secondary" onClick={prevStep}>ย้อนกลับ</Button>
                                            <Button onClick={nextStep}>ถัดไป <ChevronRight size={18} /></Button>
                                        </div>
                                    </div>
                                )}

                                {/* === WORK MODE: Canvas layout === */}
                                {laborStatus === 'Work' && (
                                    <>
                                        {/* Employee Pool - Draggable chips */}
                                        <div className="mb-3">
                                            <div className="flex justify-between items-center mb-2">
                                                <span className="text-sm font-bold text-slate-500">👥 พนักงาน — คลิกเลือกแล้วกดย้ายใส่กล่องงาน</span>
                                                <input placeholder="ค้นหา..." value={laborSearch} onChange={e => setLaborSearch(e.target.value)} className="text-sm border rounded-lg px-3 py-1.5 w-32" />
                                            </div>
                                            <div className="flex flex-wrap gap-2 bg-slate-50 p-3 rounded-xl border max-h-[120px] overflow-y-auto">
                                                {employees.filter(e => e.name.includes(laborSearch) || e.nickname.includes(laborSearch)).map(emp => {
                                                    const isAssigned = Object.values(workAssignments).some(ids => ids.includes(emp.id));
                                                    const isSelected = selectedEmps.includes(emp.id);
                                                    const saved = dayTransactions.find(t => t.category === 'Labor' && t.employeeIds?.includes(emp.id));
                                                    const leaveRecord = transactions.find(t => t.category === 'Labor' && (t.laborStatus === 'Leave' || t.laborStatus === 'Sick' || t.laborStatus === 'Personal') && t.employeeIds?.includes(emp.id) && t.date <= date && (t.leaveDays ? new Date(new Date(t.date).getTime() + (t.leaveDays - 1) * 86400000).toISOString().split('T')[0] >= date : t.date === date));
                                                    const isAbsent = !isAssigned && !saved && !leaveRecord;
                                                    return (
                                                        <div key={emp.id}
                                                            draggable onDragStart={() => setDragEmployee(emp.id)} onDragEnd={() => setDragEmployee(null)}
                                                            onClick={() => setSelectedEmps(prev => prev.includes(emp.id) ? prev.filter(id => id !== emp.id) : [...prev, emp.id])}
                                                            title={leaveRecord ? `ลา: ${new Date(leaveRecord.date).toLocaleDateString('th-TH')}${leaveRecord.leaveDays ? ` (${leaveRecord.leaveDays} วัน)` : ''} - ${leaveRecord.leaveReason || leaveRecord.laborStatus}` : isAbsent && saved === undefined ? '' : ''}
                                                            className={`px-3 py-2 rounded-xl text-sm font-semibold cursor-grab active:cursor-grabbing select-none transition-all
                                                        ${leaveRecord ? 'bg-yellow-100 text-yellow-700 border-2 border-yellow-400 ring-1 ring-yellow-200' :
                                                                    isAssigned ? 'bg-emerald-100 text-emerald-600 border border-emerald-300 opacity-50' :
                                                                        isSelected ? 'bg-indigo-600 text-white shadow-md scale-105' :
                                                                            saved ? 'bg-emerald-50 text-emerald-700 border border-emerald-200' :
                                                                                'bg-white text-slate-600 border border-slate-200 hover:border-indigo-300 hover:shadow-sm'}`}
                                                        >
                                                            {emp.nickname}{leaveRecord ? ' 🏖️ลา' : saved && !isAssigned ? ' ✅' : ''}
                                                        </div>
                                                    );
                                                })}
                                            </div>
                                            {selectedEmps.length > 0 && <p className="text-xs text-indigo-600 mt-1.5 font-medium">เลือก {selectedEmps.length} คน — กดปุ่ม "ย้าย" ในกล่องงานด้านล่าง</p>}
                                        </div>

                                        {/* Work Category Canvas Boxes */}
                                        <div className="flex-1 overflow-y-auto mb-3">
                                            <span className="text-sm font-bold text-slate-500 mb-2 block">📋 ประเภทงาน (ลากหรือกดย้ายพนักงานใส่)</span>
                                            <div className="grid grid-cols-2 gap-3">
                                                {[...DEFAULT_WORK_CATEGORIES, ...customCategories.map(c => ({ ...c, color: 'bg-purple-500', bgLight: 'bg-purple-50 border-purple-200' }))].map(cat => {
                                                    const assigned = workAssignments[cat.id] || [];
                                                    return (
                                                        <div key={cat.id}
                                                            onDragOver={e => e.preventDefault()}
                                                            onDrop={e => {
                                                                e.preventDefault(); if (dragEmployee) {
                                                                    setWorkAssignments(prev => {
                                                                        const u = { ...prev };
                                                                        Object.keys(u).forEach(k => { u[k] = u[k].filter(id => id !== dragEmployee); });
                                                                        u[cat.id] = [...(u[cat.id] || []), dragEmployee];
                                                                        return u;
                                                                    }); setDragEmployee(null);
                                                                }
                                                            }}
                                                            className={`p-3 rounded-xl border-2 border-dashed min-h-[80px] transition-all ${cat.bgLight} ${dragEmployee ? 'border-indigo-400 bg-indigo-50/30' : ''}`}
                                                        >
                                                            <div className="flex justify-between items-center mb-1.5">
                                                                <span className={`text-xs font-bold text-white px-2 py-1 rounded-full ${cat.color}`}>{cat.label}</span>
                                                                <span className="text-xs font-bold text-slate-400">{assigned.length} คน</span>
                                                            </div>
                                                            <div className="flex flex-wrap gap-1.5">
                                                                {assigned.map(eid => {
                                                                    const emp = employees.find(e => e.id === eid); return emp ? (
                                                                        <span key={eid} className="px-2 py-1 bg-white rounded-lg text-xs font-semibold border flex items-center gap-1">
                                                                            {emp.nickname}
                                                                            <button onClick={() => setWorkAssignments(prev => ({ ...prev, [cat.id]: prev[cat.id].filter(id => id !== eid) }))} className="text-red-400 hover:text-red-600 ml-0.5 text-base leading-none">×</button>
                                                                        </span>) : null;
                                                                })}
                                                                {assigned.length === 0 && <span className="text-xs text-slate-400 italic">ลากหรือย้ายคนมาวาง...</span>}
                                                            </div>
                                                            {selectedEmps.length > 0 && (
                                                                <button onClick={() => {
                                                                    setWorkAssignments(prev => {
                                                                        const u = { ...prev };
                                                                        selectedEmps.forEach(id => { Object.keys(u).forEach(k => { u[k] = (u[k] || []).filter(eid => eid !== id); }); });
                                                                        u[cat.id] = [...(u[cat.id] || []), ...selectedEmps];
                                                                        return u;
                                                                    }); setSelectedEmps([]);
                                                                }} className="mt-1.5 w-full py-1.5 text-xs bg-indigo-100 text-indigo-700 rounded-lg hover:bg-indigo-200 font-bold">
                                                                    ⬇️ ย้าย {selectedEmps.length} คน มาที่นี่
                                                                </button>
                                                            )}
                                                        </div>
                                                    );
                                                })}
                                            </div>
                                            <div className="flex gap-2 mt-3">
                                                <input value={newCategoryName} onChange={e => setNewCategoryName(e.target.value)} placeholder="เพิ่มประเภทงานใหม่..." className="flex-1 text-sm border rounded-xl px-3 py-2" />
                                                <button onClick={() => { if (!newCategoryName.trim()) return; setCustomCategories(prev => [...prev, { id: `c_${Date.now()}`, label: newCategoryName.trim() }]); setNewCategoryName(''); }} className="px-4 py-2 bg-purple-500 text-white text-sm rounded-xl hover:bg-purple-600 font-bold">+ เพิ่ม</button>
                                            </div>
                                        </div>

                                        <div className="pt-2 border-t space-y-2">
                                            <Button onClick={() => {
                                                const allAssigned = Object.entries(workAssignments).flatMap(([, ids]) => ids);
                                                const allEmps = [...new Set([...allAssigned, ...selectedEmps])];
                                                if (allEmps.length === 0) return alert('เลือกหรือลากพนักงานใส่กล่องงานก่อนครับ');
                                                const base = { id: Date.now().toString(), date, employeeIds: allEmps };
                                                const allCats = [...DEFAULT_WORK_CATEGORIES, ...customCategories.map(c => ({ ...c, color: '', bgLight: '' }))];
                                                const desc = Object.entries(workAssignments).filter(([, ids]) => ids.length > 0).map(([catId, ids]) => {
                                                    const cat = allCats.find(c => c.id === catId); const names = ids.map(id => employees.find(e => e.id === id)?.nickname || '').join(',');
                                                    return `${cat?.label || catId}: ${names}`;
                                                }).join(' | ');
                                                let total = 0; allEmps.forEach(id => { const e = employees.find(x => x.id === id); if (e) total += (e.type === 'Monthly' ? e.baseWage / 30 : e.baseWage); });
                                                const t = { ...base, type: 'Expense', category: 'Labor', subCategory: 'Attendance', laborStatus: 'Work', description: `ค่าแรง (${allEmps.length} คน)${desc ? ` [${desc}]` : ''}`, amount: total, workAssignments: { ...workAssignments } };
                                                onSaveTransaction(t as any); setSelectedEmps([]); setWorkAssignments({});
                                            }} className="w-full bg-emerald-600 hover:bg-emerald-700 py-3 text-base">
                                                <CheckCircle2 size={18} className="mr-2" /> บันทึกค่าแรง ({Object.values(workAssignments).flat().length + selectedEmps.length} คน)
                                            </Button>
                                            <div className="flex justify-between">
                                                <Button variant="secondary" onClick={prevStep}>ย้อนกลับ</Button>
                                                <Button onClick={nextStep}>ถัดไป <ChevronRight size={18} /></Button>
                                            </div>
                                        </div>
                                    </>
                                )}
                            </div>
                        )}

                        {/* Step 2: Vehicle */}
                        {step === 2 && (
                            <div className="h-full flex flex-col animate-slide-up">
                                <h3 className="font-bold text-lg mb-4 flex items-center gap-2"><Truck className="text-amber-500" /> บันทึกการใช้รถ</h3>
                                <div className="mb-4 flex gap-2 overflow-x-auto pb-2">
                                    {dayTransactions.filter(t => t.category === 'Vehicle').map(t => (
                                        <div key={t.id} className="min-w-[200px] p-2 bg-amber-50 border border-amber-100 rounded-lg text-xs">
                                            <div className="font-bold text-amber-900">{t.vehicleId}</div>
                                            <div className="text-amber-700">{t.workDetails}</div>
                                        </div>
                                    ))}
                                    {dayTransactions.filter(t => t.category === 'Vehicle').length === 0 && <span className="text-sm text-slate-400 italic">ยังไม่มีรายการรถวันนี้</span>}
                                </div>
                                <div className="space-y-4 bg-white p-4 rounded-xl border mb-4">
                                    <div className="grid grid-cols-2 gap-4">
                                        <Select label="รถ/เครื่องจักร" value={vehCar} onChange={(e: any) => setVehCar(e.target.value)}><option value="">-- เลือกรถ --</option>{settings.cars.map(c => <option key={c}>{c}</option>)}</Select>
                                        <Select label="คนขับ" value={vehDriver} onChange={(e: any) => setVehDriver(e.target.value)}><option value="">-- เลือกคนขับ --</option>{employees.map(e => <option key={e.id} value={e.id}>{e.nickname}</option>)}</Select>
                                    </div>
                                    <div className="grid grid-cols-2 gap-4">
                                        <Input label="ค่าจ้างรถ (บาท)" type="number" value={vehMachineWage} onChange={(e: any) => setVehMachineWage(e.target.value)} />
                                        <Input label="เบี้ยเลี้ยงคนขับ" type="number" value={vehWage} onChange={(e: any) => setVehWage(e.target.value)} />
                                    </div>
                                    <div className="flex flex-col gap-1">
                                        <label className="text-sm font-medium text-slate-700">รายละเอียดงาน</label>
                                        <textarea className="border rounded-xl p-2 text-sm" rows={2} value={vehDetails} onChange={e => setVehDetails(e.target.value)} placeholder="ขนดิน, ปรับพื้นที่..." />
                                    </div>
                                    <Button onClick={() => {
                                        if (!vehCar || !vehDriver) return alert('ข้อมูลไม่ครบ');
                                        onSaveTransaction({
                                            id: Date.now().toString(), date, type: 'Expense', category: 'Vehicle',
                                            description: `รถ: ${vehCar} (${vehDetails})`, amount: Number(vehWage) + Number(vehMachineWage),
                                            vehicleId: vehCar, driverId: vehDriver, vehicleWage: Number(vehMachineWage), driverWage: Number(vehWage),
                                            workDetails: vehDetails, location: vehLocation
                                        } as Transaction);
                                        setVehCar(''); setVehDetails(''); setVehWage(''); setVehMachineWage('');
                                    }} className="w-full bg-amber-500 hover:bg-amber-600">บันทึกรายการรถ</Button>
                                </div>
                                <div className="mt-auto flex justify-between">
                                    <Button variant="secondary" onClick={prevStep}>ย้อนกลับ</Button>
                                    <Button onClick={nextStep}>ถัดไป <ChevronRight size={18} /></Button>
                                </div>
                            </div>
                        )}

                        {/* Step 3: Vehicle Trips - Canvas Style */}
                        {step === 3 && (
                            <div className="h-full flex flex-col animate-slide-up">
                                {/* Header with date and saved totals */}
                                <div className="flex flex-col gap-2 mb-4">
                                    <div className="flex justify-between items-center">
                                        <h3 className="font-bold text-lg flex items-center gap-2"><Truck className="text-blue-500" /> บันทึกรถและจำนวนเที่ยวรถ</h3>
                                        {(() => {
                                            const savedTrips = dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'VehicleTrip');
                                            const savedTotalTrips = savedTrips.reduce((sum, t) => sum + ((t as any).perCarTrips || 0), 0);
                                            const savedTotalCubic = savedTrips.reduce((sum, t) => sum + ((t as any).perCarCubic || 0), 0);
                                            const displayTrips = totalTrips > 0 ? totalTrips : savedTotalTrips;
                                            const displayCubic = totalTrips > 0 ? totalCubic : savedTotalCubic;
                                            return (
                                                <div className="flex gap-2">
                                                    <div className={`${displayTrips > 0 ? 'bg-blue-600' : 'bg-slate-400'} text-white px-3 py-2 rounded-xl text-xs font-bold shadow-md`}>
                                                        {displayTrips} เที่ยว
                                                    </div>
                                                    <div className={`${displayCubic > 0 ? 'bg-emerald-600' : 'bg-slate-400'} text-white px-3 py-2 rounded-xl text-xs font-bold shadow-md`}>
                                                        {displayCubic} คิว
                                                    </div>
                                                </div>
                                            );
                                        })()}
                                    </div>
                                    <div className="text-sm text-slate-500 flex items-center gap-1.5">
                                        📅 วันที่: <span className="font-semibold text-indigo-600">{new Date(date).toLocaleDateString('th-TH', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}</span>
                                    </div>
                                </div>

                                {/* Morning / Afternoon Trip Counts + Cubic per trip */}
                                <div className="bg-gradient-to-r from-amber-50 to-blue-50 p-4 rounded-xl border border-amber-100 mb-4">
                                    <p className="text-sm font-bold text-slate-700 mb-3">จำนวนเที่ยวรวม</p>
                                    <div className="grid grid-cols-3 gap-3">
                                        <div>
                                            <label className="text-xs font-medium text-amber-700 mb-1 block">☀️ ช่วงเช้า (เที่ยว)</label>
                                            <input type="number" placeholder="0" value={tripMorning} onChange={e => setTripMorning(e.target.value)}
                                                className="w-full px-3 py-2.5 border-2 border-amber-200 rounded-xl text-center text-lg font-bold text-amber-800 bg-white focus:border-amber-400 focus:outline-none transition-colors" />
                                        </div>
                                        <div>
                                            <label className="text-xs font-medium text-blue-700 mb-1 block">🌙 ช่วงบ่าย (เที่ยว)</label>
                                            <input type="number" placeholder="0" value={tripAfternoon} onChange={e => setTripAfternoon(e.target.value)}
                                                className="w-full px-3 py-2.5 border-2 border-blue-200 rounded-xl text-center text-lg font-bold text-blue-800 bg-white focus:border-blue-400 focus:outline-none transition-colors" />
                                        </div>
                                        <div>
                                            <label className="text-xs font-medium text-emerald-700 mb-1 block">📦 คิว/เที่ยว</label>
                                            <input type="number" placeholder="3" value={cubicPerTrip} onChange={e => setCubicPerTrip(e.target.value)}
                                                className="w-full px-3 py-2.5 border-2 border-emerald-200 rounded-xl text-center text-lg font-bold text-emerald-800 bg-white focus:border-emerald-400 focus:outline-none transition-colors" />
                                        </div>
                                    </div>
                                    {totalTrips > 0 && (() => {
                                        const validCount = tripEntries.filter(e => e.vehicle).length || 1;
                                        const tripsPerCar = Math.floor(totalTrips / validCount);
                                        const remainder = totalTrips % validCount;
                                        // Calculate total cubic considering drum 10-wheel gets 6 cubic/trip
                                        const cubicDefault = Number(cubicPerTrip) || 3;
                                        let displayTotalCubic = 0;
                                        tripEntries.filter(e => e.vehicle).forEach((entry, idx) => {
                                            const carTrips = tripsPerCar + (idx < remainder ? 1 : 0);
                                            const isDrum10 = entry.vehicle.includes('ดรัม') && entry.vehicle.includes('10');
                                            displayTotalCubic += carTrips * (isDrum10 ? 6 : cubicDefault);
                                        });
                                        if (validCount <= 1) displayTotalCubic = totalTrips * cubicDefault;
                                        return (
                                            <div className="mt-3 p-3 bg-white/70 rounded-lg text-sm font-medium text-slate-600 space-y-1">
                                                <div className="text-center">
                                                    รวม <span className="font-bold text-blue-700">{totalTrips}</span> เที่ยว ÷ <span className="font-bold text-purple-700">{validCount}</span> คัน = <span className="font-bold text-indigo-700">{tripsPerCar}{remainder > 0 ? `~${tripsPerCar + 1}` : ''}</span> เที่ยว/คัน
                                                </div>
                                                <div className="text-center">
                                                    รวมทราย <span className="font-bold text-lg text-rose-600">{displayTotalCubic} คิว</span>
                                                    <span className="text-xs text-slate-400 ml-1">(รถดรัม10ล้อ = 6 คิว/เที่ยว, อื่นๆ = {cubicDefault} คิว/เที่ยว)</span>
                                                </div>
                                            </div>
                                        );
                                    })()}
                                </div>

                                {/* Saved entries from today */}
                                {dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'VehicleTrip').length > 0 && (
                                    <div className="mb-4 flex gap-2 overflow-x-auto pb-2">
                                        {dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'VehicleTrip').map(t => (
                                            <div key={t.id} className="min-w-[200px] p-2.5 bg-emerald-50 border border-emerald-200 rounded-lg text-xs">
                                                <div className="font-bold text-emerald-900">✅ {t.vehicleId}</div>
                                                <div className="text-emerald-700 font-semibold">{(t as any).perCarTrips || (t as any).tripCount} เที่ยว • {(t as any).perCarCubic || (t as any).totalCubic || 0} คิว</div>
                                                <div className="text-emerald-600 mt-0.5">{t.workDetails || '-'}</div>
                                                <div className="text-emerald-500/70 mt-1 text-[10px]">📅 {new Date(t.date).toLocaleDateString('th-TH', { day: 'numeric', month: 'short', year: '2-digit' })}</div>
                                            </div>
                                        ))}
                                    </div>
                                )}

                                {/* Canvas: Vehicle Cards */}
                                <p className="text-sm font-medium text-slate-500 mb-2">เลือกรถและคนขับ ({tripEntries.length} คัน)</p>
                                <div className="flex-1 overflow-y-auto space-y-3 mb-4 pr-1">
                                    {tripEntries.map((entry, idx) => (
                                        <div key={entry.id} className="relative bg-white p-4 rounded-xl border-2 border-blue-100 hover:border-blue-300 shadow-sm hover:shadow-md transition-all">
                                            <div className="flex justify-between items-center mb-3">
                                                <span className="text-xs font-bold text-blue-500 bg-blue-50 px-2 py-1 rounded-lg">🚛 คันที่ {idx + 1}</span>
                                                {tripEntries.length > 1 && (
                                                    <button onClick={() => removeTripCard(entry.id)} className="p-1.5 text-slate-300 hover:text-red-500 hover:bg-red-50 rounded-lg transition-colors" title="ลบ">
                                                        <Trash2 size={14} />
                                                    </button>
                                                )}
                                            </div>
                                            <div className="grid grid-cols-2 gap-3 mb-2">
                                                <Select label="รถ" value={entry.vehicle} onChange={(e: any) => updateTripCard(entry.id, 'vehicle', e.target.value)}>
                                                    <option value="">-- เลือกรถ --</option>
                                                    {settings.cars.map(c => <option key={c}>{c}</option>)}
                                                </Select>
                                                <Select label="คนขับ" value={entry.driver} onChange={(e: any) => updateTripCard(entry.id, 'driver', e.target.value)}>
                                                    <option value="">-- เลือกคนขับ --</option>
                                                    {employees.map(e => <option key={e.id} value={e.id}>{e.nickname}</option>)}
                                                </Select>
                                            </div>
                                            <Input label="รายละเอียดงาน" value={entry.work} onChange={(e: any) => updateTripCard(entry.id, 'work', e.target.value)} placeholder="ขนดิน, ขนทราย..." />
                                        </div>
                                    ))}

                                    <button onClick={addTripCard} className="w-full py-4 border-2 border-dashed border-slate-200 hover:border-blue-400 rounded-xl text-slate-400 hover:text-blue-500 flex items-center justify-center gap-2 transition-all hover:bg-blue-50/50">
                                        <Plus size={20} /> เพิ่มรถอีกคัน
                                    </button>
                                </div>

                                {/* Save all + navigation */}
                                <div className="pt-4 border-t space-y-3">
                                    <Button onClick={() => {
                                        const valid = tripEntries.filter(e => e.vehicle);
                                        if (valid.length === 0) return alert('กรุณาเลือกรถอย่างน้อย 1 คัน');
                                        if (totalTrips === 0) return alert('กรุณาใส่จำนวนเที่ยว (เช้า หรือ บ่าย)');
                                        const tripsPerCar = Math.floor(totalTrips / valid.length);
                                        const remainder = totalTrips % valid.length;
                                        const cubicDefault = Number(cubicPerTrip) || 3;
                                        valid.forEach((entry, idx) => {
                                            const driverName = employees.find(e => e.id === entry.driver)?.nickname || '';
                                            const carTrips = tripsPerCar + (idx < remainder ? 1 : 0);
                                            const isDrum10 = entry.vehicle.includes('ดรัม') && entry.vehicle.includes('10');
                                            const carCubicPerTrip = isDrum10 ? 6 : cubicDefault;
                                            const carCubic = carTrips * carCubicPerTrip;
                                            onSaveTransaction({
                                                id: Date.now().toString() + entry.id, date, type: 'Expense', category: 'DailyLog', subCategory: 'VehicleTrip',
                                                description: `${entry.vehicle}${driverName ? ` (${driverName})` : ''}: ${carTrips} เที่ยว × ${carCubicPerTrip} คิว = ${carCubic} คิว - ${entry.work}`, amount: 0,
                                                vehicleId: entry.vehicle, driverId: entry.driver, tripCount: totalTrips,
                                                tripMorning: Number(tripMorning) || 0, tripAfternoon: Number(tripAfternoon) || 0,
                                                cubicPerTrip: carCubicPerTrip, totalCubic: carCubic,
                                                perCarTrips: carTrips, perCarCubic: carCubic,
                                                workDetails: entry.work
                                            } as Transaction);
                                        });
                                        setTripEntries([{ id: Date.now().toString(), vehicle: '', driver: '', work: '' }]);
                                        setTripMorning(''); setTripAfternoon('');
                                    }} className="w-full bg-blue-500 hover:bg-blue-600 py-3 text-base">
                                        <CheckCircle2 size={18} className="mr-2" /> บันทึกทั้งหมด ({tripEntries.filter(e => e.vehicle).length} คัน, {totalTrips} เที่ยวรวม)
                                    </Button>
                                    <div className="flex justify-between">
                                        <Button variant="secondary" onClick={prevStep}>ย้อนกลับ</Button>
                                        <Button onClick={nextStep}>ถัดไป <ChevronRight size={18} /></Button>
                                    </div>
                                </div>
                            </div>
                        )}

                        {/* Step 4: Sand Washing */}
                        {step === 4 && (
                            <div className="h-full flex flex-col animate-slide-up">
                                <div className="flex justify-between items-center mb-3">
                                    <h3 className="font-bold text-lg flex items-center gap-2"><Droplets className="text-cyan-500" /> บันทึกการล้างทราย</h3>
                                    <span className="text-xs text-slate-400">{new Date(date).toLocaleDateString('th-TH', { day: 'numeric', month: 'short', year: '2-digit' })}</span>
                                </div>

                                {/* Saved sand entries */}
                                {dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'Sand').length > 0 && (
                                    <div className="mb-3 flex gap-2 overflow-x-auto pb-2">
                                        {dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'Sand').map(t => (
                                            <div key={t.id} className="min-w-[180px] p-2.5 bg-cyan-50 border border-cyan-200 rounded-xl text-xs relative">
                                                <div className="font-bold text-cyan-800">🌊 {t.description}</div>
                                                <div className="text-cyan-700 font-semibold">เช้า {(t as any).sandMorning || 0} + บ่าย {(t as any).sandAfternoon || 0} = {((t as any).sandMorning || 0) + ((t as any).sandAfternoon || 0)} คิว</div>
                                                {onDeleteTransaction && <button onClick={() => onDeleteTransaction(t.id)} className="absolute top-1.5 right-1.5 p-0.5 text-cyan-300 hover:text-red-500"><Trash2 size={10} /></button>}
                                            </div>
                                        ))}
                                    </div>
                                )}

                                <div className="flex-1 space-y-3 overflow-y-auto">
                                    {/* Machine 1 */}
                                    <div className="bg-gradient-to-r from-blue-50 to-cyan-50 p-4 rounded-xl border border-blue-200">
                                        <p className="text-sm font-bold text-blue-800 mb-2">🏭 เครื่องร่อน 1 (เก่า)</p>
                                        <div className="grid grid-cols-3 gap-3 mb-2">
                                            <div>
                                                <label className="text-xs font-medium text-amber-700 mb-1 block">☀️ เช้า (คิว)</label>
                                                <input type="number" placeholder="0" value={sand1Morning} onChange={e => setSand1Morning(e.target.value)}
                                                    className="w-full px-3 py-2 border-2 border-amber-200 rounded-xl text-center text-lg font-bold text-amber-800 bg-white focus:border-amber-400 focus:outline-none" />
                                            </div>
                                            <div>
                                                <label className="text-xs font-medium text-blue-700 mb-1 block">🌙 บ่าย (คิว)</label>
                                                <input type="number" placeholder="0" value={sand1Afternoon} onChange={e => setSand1Afternoon(e.target.value)}
                                                    className="w-full px-3 py-2 border-2 border-blue-200 rounded-xl text-center text-lg font-bold text-blue-800 bg-white focus:border-blue-400 focus:outline-none" />
                                            </div>
                                            <div className="flex flex-col items-center justify-center bg-white/70 rounded-xl border">
                                                <span className="text-[10px] text-slate-400">รวม</span>
                                                <span className="text-xl font-black text-blue-700">{sand1Total}</span>
                                                <span className="text-[10px] text-slate-400">คิว</span>
                                            </div>
                                        </div>
                                        <div>
                                            <label className="text-xs font-medium text-blue-700 mb-1 block">👷 พนักงานที่ล้าง</label>
                                            <div className="flex flex-wrap gap-1.5">
                                                {(workAssignments['wash1'] || []).length > 0 ? (workAssignments['wash1'] || []).map(eid => {
                                                    const emp = employees.find(e => e.id === eid);
                                                    return emp ? <span key={eid} className="px-2.5 py-1 rounded-lg text-xs font-medium bg-blue-500 text-white shadow-sm">{emp.nickname}</span> : null;
                                                }) : <span className="text-xs text-slate-400 italic">ยังไม่มีข้อมูล (กรุณาลากพนักงานใส่กล่อง "ล้างทราย เครื่องร่อน 1" ในขั้นค่าแรง)</span>}
                                            </div>
                                        </div>
                                    </div>

                                    {/* Machine 2 */}
                                    <div className="bg-gradient-to-r from-cyan-50 to-teal-50 p-4 rounded-xl border border-cyan-200">
                                        <p className="text-sm font-bold text-cyan-800 mb-2">🏭 เครื่องร่อน 2 (ใหม่)</p>
                                        <div className="grid grid-cols-3 gap-3 mb-2">
                                            <div>
                                                <label className="text-xs font-medium text-amber-700 mb-1 block">☀️ เช้า (คิว)</label>
                                                <input type="number" placeholder="0" value={sand2Morning} onChange={e => setSand2Morning(e.target.value)}
                                                    className="w-full px-3 py-2 border-2 border-amber-200 rounded-xl text-center text-lg font-bold text-amber-800 bg-white focus:border-amber-400 focus:outline-none" />
                                            </div>
                                            <div>
                                                <label className="text-xs font-medium text-blue-700 mb-1 block">🌙 บ่าย (คิว)</label>
                                                <input type="number" placeholder="0" value={sand2Afternoon} onChange={e => setSand2Afternoon(e.target.value)}
                                                    className="w-full px-3 py-2 border-2 border-blue-200 rounded-xl text-center text-lg font-bold text-blue-800 bg-white focus:border-blue-400 focus:outline-none" />
                                            </div>
                                            <div className="flex flex-col items-center justify-center bg-white/70 rounded-xl border">
                                                <span className="text-[10px] text-slate-400">รวม</span>
                                                <span className="text-xl font-black text-cyan-700">{sand2Total}</span>
                                                <span className="text-[10px] text-slate-400">คิว</span>
                                            </div>
                                        </div>
                                        <div>
                                            <label className="text-xs font-medium text-cyan-700 mb-1 block">👷 พนักงานที่ล้าง</label>
                                            <div className="flex flex-wrap gap-1.5">
                                                {(workAssignments['wash2'] || []).length > 0 ? (workAssignments['wash2'] || []).map(eid => {
                                                    const emp = employees.find(e => e.id === eid);
                                                    return emp ? <span key={eid} className="px-2.5 py-1 rounded-lg text-xs font-medium bg-cyan-500 text-white shadow-sm">{emp.nickname}</span> : null;
                                                }) : <span className="text-xs text-slate-400 italic">ยังไม่มีข้อมูล (กรุณาลากพนักงานใส่กล่อง "ล้างทราย เครื่องร่อน 2" ในขั้นค่าแรง)</span>}
                                            </div>
                                        </div>
                                    </div>

                                    {/* Grand total */}
                                    {sandGrandTotal > 0 && (
                                        <div className="bg-gradient-to-r from-emerald-100 to-teal-100 p-3 rounded-xl text-center border border-emerald-200">
                                            <span className="text-sm font-bold text-emerald-800">รวมล้างทรายทั้งหมด: </span>
                                            <span className="text-2xl font-black text-emerald-700">{sandGrandTotal}</span>
                                            <span className="text-sm text-emerald-600"> คิว/วัน</span>
                                            <div className="text-[10px] text-emerald-600 mt-1">เครื่อง 1: {sand1Total} คิว | เครื่อง 2: {sand2Total} คิว</div>
                                        </div>
                                    )}
                                </div>

                                <div className="pt-3 border-t space-y-2">
                                    <Button onClick={() => {
                                        if (sandGrandTotal === 0) return alert('กรุณาใส่จำนวนทรายที่ล้างได้');
                                        const opNames1 = sand1Operators.map(id => employees.find(e => e.id === id)?.nickname || '').join(', ');
                                        const opNames2 = sand2Operators.map(id => employees.find(e => e.id === id)?.nickname || '').join(', ');
                                        if (sand1Total > 0) {
                                            onSaveTransaction({
                                                id: Date.now().toString() + '_s1', date, type: 'Expense', category: 'DailyLog', subCategory: 'Sand',
                                                description: `ล้างทราย เครื่องร่อน 1 (เก่า)${opNames1 ? ` [${opNames1}]` : ''}`, amount: 0,
                                                sandMorning: Number(sand1Morning) || 0, sandAfternoon: Number(sand1Afternoon) || 0,
                                                sandOperators: sand1Operators, sandMachineType: 'Old'
                                            } as Transaction);
                                        }
                                        if (sand2Total > 0) {
                                            onSaveTransaction({
                                                id: Date.now().toString() + '_s2', date, type: 'Expense', category: 'DailyLog', subCategory: 'Sand',
                                                description: `ล้างทราย เครื่องร่อน 2 (ใหม่)${opNames2 ? ` [${opNames2}]` : ''}`, amount: 0,
                                                sandMorning: Number(sand2Morning) || 0, sandAfternoon: Number(sand2Afternoon) || 0,
                                                sandOperators: sand2Operators, sandMachineType: 'New'
                                            } as Transaction);
                                        }
                                        setSand1Morning(''); setSand1Afternoon(''); setSand2Morning(''); setSand2Afternoon('');
                                        setSand1Operators([]); setSand2Operators([]);
                                    }} className="w-full bg-cyan-500 hover:bg-cyan-600 py-2.5">
                                        <Droplets size={16} className="mr-1" /> บันทึกข้อมูลล้างทราย ({sandGrandTotal} คิว)
                                    </Button>
                                    <div className="flex justify-between">
                                        <Button variant="secondary" onClick={prevStep}>ย้อนกลับ</Button>
                                        <Button onClick={nextStep}>ถัดไป <ChevronRight size={18} /></Button>
                                    </div>
                                </div>
                            </div>
                        )}

                        {/* Step 5: Fuel */}
                        {step === 5 && (
                            <div className="h-full flex flex-col animate-slide-up">
                                <h3 className="font-bold text-xl text-slate-800 mb-5">Fuel Entry</h3>

                                {/* Saved fuel entries */}
                                {dayTransactions.filter(t => t.category === 'Fuel').length > 0 && (
                                    <div className="mb-4 space-y-2">
                                        <p className="text-sm font-semibold text-slate-500">รายการซื้อน้ำมันวันนี้ ({dayTransactions.filter(t => t.category === 'Fuel').length} รอบ)</p>
                                        <div className="flex gap-2 overflow-x-auto pb-2">
                                            {dayTransactions.filter(t => t.category === 'Fuel').map(t => (
                                                <div key={t.id} className="min-w-[200px] p-3 bg-red-50 border border-red-100 rounded-xl text-xs relative">
                                                    <div className="font-bold text-red-800">⛽ {(t as any).fuelType === 'Diesel' ? 'ดีเซล' : 'เบนซิน'}</div>
                                                    <div className="text-red-700 mt-1 font-semibold">{t.amount?.toLocaleString()} บาท • {(t as any).quantity || 0} {(t as any).unit === 'gallon' ? 'แกลลอน' : 'ลิตร'}</div>
                                                    {t.workDetails && <div className="text-red-600/70 mt-1">{t.workDetails}</div>}
                                                    {onDeleteTransaction && <button onClick={() => onDeleteTransaction(t.id)} className="absolute top-2 right-2 p-1 text-red-300 hover:text-red-600"><Trash2 size={12} /></button>}
                                                </div>
                                            ))}
                                        </div>
                                        {(() => {
                                            const fuelTx = dayTransactions.filter(t => t.category === 'Fuel');
                                            const totalBaht = fuelTx.reduce((s, t) => s + (t.amount || 0), 0);
                                            return <div className="bg-red-100/50 p-2 rounded-lg text-sm text-center text-red-800 font-medium">รวมวันนี้: <span className="font-bold">{totalBaht.toLocaleString()}</span> บาท</div>;
                                        })()}
                                    </div>
                                )}

                                {/* Clean fuel entry form */}
                                <div className="flex-1 bg-white p-6 rounded-2xl border border-slate-200 shadow-sm space-y-5">
                                    {/* Date */}
                                    <div>
                                        <label className="text-sm font-medium text-slate-600 mb-1.5 block">วันที่</label>
                                        <input type="date" value={date} readOnly
                                            className="w-full px-4 py-3 border border-slate-300 rounded-xl text-base text-slate-800 bg-slate-50" />
                                    </div>

                                    {/* Fuel Type - Radio style */}
                                    <div className="grid grid-cols-2 gap-3">
                                        <button onClick={() => setFuelType('Diesel')}
                                            className={`flex items-center gap-3 px-4 py-3 rounded-xl border-2 transition-all text-base font-medium ${fuelType === 'Diesel' ? 'border-slate-800 bg-white' : 'border-slate-200 bg-white hover:border-slate-300'}`}>
                                            <span className={`w-5 h-5 rounded-full border-2 flex items-center justify-center ${fuelType === 'Diesel' ? 'border-slate-800' : 'border-slate-300'}`}>
                                                {fuelType === 'Diesel' && <span className="w-3 h-3 rounded-full bg-slate-800"></span>}
                                            </span>
                                            ดีเซล
                                        </button>
                                        <button onClick={() => setFuelType('Benzine')}
                                            className={`flex items-center gap-3 px-4 py-3 rounded-xl border-2 transition-all text-base font-medium ${fuelType === 'Benzine' ? 'border-slate-800 bg-white' : 'border-slate-200 bg-white hover:border-slate-300'}`}>
                                            <span className={`w-5 h-5 rounded-full border-2 flex items-center justify-center ${fuelType === 'Benzine' ? 'border-slate-800' : 'border-slate-300'}`}>
                                                {fuelType === 'Benzine' && <span className="w-3 h-3 rounded-full bg-slate-800"></span>}
                                            </span>
                                            เบนซิน
                                        </button>
                                    </div>

                                    {/* Quantity + Unit */}
                                    <div className="grid grid-cols-2 gap-4">
                                        <div>
                                            <label className="text-sm font-medium text-slate-600 mb-1.5 block">จำนวนลิตร</label>
                                            <input type="number" placeholder="" value={fuelLiters} onChange={e => setFuelLiters(e.target.value)}
                                                className="w-full px-4 py-3 border border-slate-300 rounded-xl text-base text-slate-800 focus:border-slate-500 focus:outline-none transition-colors" />
                                        </div>
                                        <div>
                                            <label className="text-sm font-medium text-slate-600 mb-1.5 block">หน่วย</label>
                                            <select value={fuelUnit} onChange={e => setFuelUnit(e.target.value)}
                                                className="w-full px-4 py-3 border border-slate-300 rounded-xl text-base text-slate-800 bg-white focus:border-slate-500 focus:outline-none transition-colors appearance-none">
                                                <option value="ลิตร">ลิตร</option>
                                                <option value="แกลลอน">แกลลอน</option>
                                            </select>
                                        </div>
                                    </div>

                                    {/* Price */}
                                    <div>
                                        <label className="text-sm font-medium text-slate-600 mb-1.5 block">ราคาซื้อน้ำมัน (บาท)</label>
                                        <input type="number" placeholder="" value={fuelAmount} onChange={e => setFuelAmount(e.target.value)}
                                            className="w-full px-4 py-4 border border-slate-300 rounded-xl text-lg text-slate-800 focus:border-slate-500 focus:outline-none transition-colors" />
                                    </div>

                                    {/* Details (optional) */}
                                    <div>
                                        <label className="text-sm font-medium text-slate-600 mb-1.5 block">รายละเอียดเพิ่มเติม <span className="text-slate-400 font-normal">(ไม่บังคับ)</span></label>
                                        <input type="text" placeholder="เช่น ซื้อที่ปั๊มหน้าแคมป์" value={fuelDetails} onChange={e => setFuelDetails(e.target.value)}
                                            className="w-full px-4 py-3 border border-slate-300 rounded-xl text-base text-slate-800 focus:border-slate-500 focus:outline-none transition-colors" />
                                    </div>

                                    {/* Save button */}
                                    <button onClick={() => {
                                        if (!fuelAmount) return alert('กรุณาระบุราคาซื้อน้ำมัน');
                                        const unitLabel = fuelUnit === 'แกลลอน' ? 'gallon' : 'L';
                                        onSaveTransaction({
                                            id: Date.now().toString(), date, type: 'Expense', category: 'Fuel',
                                            description: `ซื้อน้ำมัน ${fuelType === 'Diesel' ? 'ดีเซล' : 'เบนซิน'}: ${fuelLiters || 0} ${fuelUnit} ${fuelAmount} บาท${fuelDetails ? ` - ${fuelDetails}` : ''}`,
                                            amount: Number(fuelAmount),
                                            quantity: Number(fuelLiters), unit: unitLabel, fuelType,
                                            workDetails: fuelDetails
                                        } as Transaction);
                                        setFuelAmount(''); setFuelLiters(''); setFuelDetails('');
                                    }} className="w-full py-3.5 bg-slate-800 hover:bg-slate-900 text-white text-base font-bold rounded-xl transition-colors">
                                        บันทึก
                                    </button>
                                </div>

                                <div className="mt-auto pt-3 flex justify-between">
                                    <Button variant="secondary" onClick={prevStep}>ย้อนกลับ</Button>
                                    <Button onClick={nextStep}>ถัดไป <ChevronRight size={18} /></Button>
                                </div>
                            </div>
                        )}

                        {/* Step 6: Important Events */}
                        {step === 6 && (
                            <div className="h-full flex flex-col animate-slide-up">
                                <div className="flex justify-between items-center mb-3">
                                    <h3 className="font-bold text-lg flex items-center gap-2"><AlertTriangle className="text-orange-500" /> เหตุการณ์สำคัญประจำวัน</h3>
                                    <span className="text-xs text-slate-400">{new Date(date).toLocaleDateString('th-TH', { day: 'numeric', month: 'short', year: '2-digit' })}</span>
                                </div>

                                {/* Saved events */}
                                {dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'Event').length > 0 && (
                                    <div className="mb-3 space-y-2">
                                        <p className="text-xs font-bold text-slate-500">📌 เหตุการณ์ที่บันทึกแล้ว</p>
                                        {dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'Event').map(t => (
                                            <div key={t.id} className={`p-3 rounded-xl border text-xs relative ${(t as any).eventPriority === 'urgent' ? 'bg-red-50 border-red-200' :
                                                (t as any).eventType === 'warning' ? 'bg-amber-50 border-amber-200' :
                                                    (t as any).eventType === 'success' ? 'bg-emerald-50 border-emerald-200' :
                                                        'bg-blue-50 border-blue-200'
                                                }`}>
                                                <div className="flex items-center gap-2 mb-1">
                                                    <span className="text-sm">{(t as any).eventType === 'warning' ? '⚠️' : (t as any).eventType === 'success' ? '✅' : (t as any).eventType === 'problem' ? '🚨' : 'ℹ️'}</span>
                                                    <span className="font-bold">{t.description}</span>
                                                    {(t as any).eventPriority === 'urgent' && <span className="px-1.5 py-0.5 bg-red-500 text-white rounded-full text-[9px] font-bold">ด่วน!</span>}
                                                </div>
                                                {onDeleteTransaction && <button onClick={() => onDeleteTransaction(t.id)} className="absolute top-2 right-2 p-0.5 text-slate-300 hover:text-red-500"><Trash2 size={10} /></button>}
                                            </div>
                                        ))}
                                    </div>
                                )}

                                <div className="flex-1 space-y-3">
                                    {/* Event type selector */}
                                    <div className="grid grid-cols-4 gap-2">
                                        {[{ v: 'info', l: 'ℹ️ ข้อมูล', c: 'border-blue-400 bg-blue-50' }, { v: 'warning', l: '⚠️ เตือน', c: 'border-amber-400 bg-amber-50' }, { v: 'problem', l: '🚨 ปัญหา', c: 'border-red-400 bg-red-50' }, { v: 'success', l: '✅ สำเร็จ', c: 'border-emerald-400 bg-emerald-50' }].map(opt => (
                                            <button key={opt.v} onClick={() => setEventType(opt.v)}
                                                className={`py-2 rounded-xl border-2 text-xs font-medium transition-all ${eventType === opt.v ? opt.c + ' font-bold shadow-sm' : 'border-slate-200 bg-white hover:bg-slate-50'}`}>
                                                {opt.l}
                                            </button>
                                        ))}
                                    </div>

                                    {/* Priority */}
                                    <div className="flex gap-3">
                                        <button onClick={() => setEventPriority('normal')} className={`flex-1 py-2 rounded-xl border text-xs transition-all ${eventPriority === 'normal' ? 'bg-slate-100 border-slate-400 font-bold' : 'bg-white'}`}>ปกติ</button>
                                        <button onClick={() => setEventPriority('urgent')} className={`flex-1 py-2 rounded-xl border text-xs transition-all ${eventPriority === 'urgent' ? 'bg-red-100 border-red-400 font-bold text-red-700' : 'bg-white'}`}>🔴 ด่วน!</button>
                                    </div>

                                    {/* Event description */}
                                    <div>
                                        <label className="text-xs font-medium text-slate-600 mb-1 block">📝 รายละเอียดเหตุการณ์</label>
                                        <textarea value={eventDesc} onChange={e => setEventDesc(e.target.value)}
                                            placeholder="เช่น ฝนตกหนักต้องหยุดงาน, เครื่องจักรเสีย, ทรายถูกส่งมาไม่ครบ, งานเสร็จเร็วกว่ากำหนด..."
                                            className="w-full px-3 py-3 border-2 border-slate-200 rounded-xl text-sm focus:border-orange-400 focus:outline-none transition-colors" rows={4} />
                                    </div>

                                    {/* Quick templates */}
                                    <div>
                                        <p className="text-[10px] text-slate-400 mb-1">🏷️ เทมเพลตด่วน:</p>
                                        <div className="flex flex-wrap gap-1.5">
                                            {['ฝนตก หยุดงาน', 'เครื่องจักรเสีย', 'ทรายไม่ครบ', 'คนงานมาสาย', 'งานเสร็จตามแผน', 'ไฟฟ้าดับ', 'อุบัติเหตุเล็กน้อย'].map(tmpl => (
                                                <button key={tmpl} onClick={() => setEventDesc(prev => prev ? `${prev}, ${tmpl}` : tmpl)}
                                                    className="px-2 py-1 bg-slate-100 hover:bg-orange-100 text-xs rounded-lg text-slate-600 hover:text-orange-700 transition-colors border border-transparent hover:border-orange-200">
                                                    {tmpl}
                                                </button>
                                            ))}
                                        </div>
                                    </div>
                                </div>

                                <div className="pt-3 border-t space-y-2">
                                    <Button onClick={() => {
                                        if (!eventDesc.trim()) return alert('กรุณาระบุรายละเอียดเหตุการณ์');
                                        onSaveTransaction({
                                            id: Date.now().toString(), date, type: 'Expense', category: 'DailyLog', subCategory: 'Event',
                                            description: eventDesc.trim(), amount: 0,
                                            eventType, eventPriority
                                        } as Transaction);
                                        setEventDesc(''); setEventType('info'); setEventPriority('normal');
                                    }} className="w-full bg-orange-500 hover:bg-orange-600 py-2.5">
                                        <AlertTriangle size={16} className="mr-1" /> บันทึกเหตุการณ์
                                    </Button>
                                    <div className="flex justify-between">
                                        <Button variant="secondary" onClick={prevStep}>ย้อนกลับ</Button>
                                        <Button onClick={nextStep}>ถัดไป <ChevronRight size={18} /></Button>
                                    </div>
                                </div>
                            </div>
                        )}

                        {/* Step 7: Summary */}
                        {step === 7 && (
                            <div className="h-full flex flex-col animate-slide-up text-center">
                                <div className="flex flex-col items-center justify-center mb-6">
                                    <FileText size={48} className="text-emerald-400 mb-4" />
                                    <h3 className="text-2xl font-bold text-slate-800 mb-2">บันทึกข้อมูลเรียบร้อยแล้ว</h3>
                                    <p className="text-slate-500">สรุปข้อมูลที่คุณบันทึกในวันนี้ ({new Date(date).toLocaleDateString('th-TH')})</p>
                                </div>

                                <div className="grid grid-cols-3 sm:grid-cols-6 gap-2 sm:gap-3 w-full mb-6">
                                    <div className="bg-emerald-50 p-2 sm:p-3 rounded-xl border border-emerald-100 text-center">
                                        <div className="text-lg sm:text-2xl font-bold text-emerald-600">{dayTransactions.filter(t => t.category === 'Labor').length}</div>
                                        <div className="text-[10px] sm:text-xs text-emerald-800">ค่าแรง</div>
                                    </div>
                                    <div className="bg-amber-50 p-2 sm:p-3 rounded-xl border border-amber-100 text-center">
                                        <div className="text-lg sm:text-2xl font-bold text-amber-600">{dayTransactions.filter(t => t.category === 'Vehicle').length}</div>
                                        <div className="text-[10px] sm:text-xs text-amber-800">การใช้รถ</div>
                                    </div>
                                    <div className="bg-blue-50 p-2 sm:p-3 rounded-xl border border-blue-100 text-center">
                                        <div className="text-lg sm:text-2xl font-bold text-blue-600">{dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'VehicleTrip').length}</div>
                                        <div className="text-[10px] sm:text-xs text-blue-800">เที่ยวรถ</div>
                                    </div>
                                    <div className="bg-cyan-50 p-2 sm:p-3 rounded-xl border border-cyan-100 text-center">
                                        <div className="text-lg sm:text-2xl font-bold text-cyan-600">{dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'Sand').length}</div>
                                        <div className="text-[10px] sm:text-xs text-cyan-800">ล้างทราย</div>
                                    </div>
                                    <div className="bg-red-50 p-2 sm:p-3 rounded-xl border border-red-100 text-center">
                                        <div className="text-lg sm:text-2xl font-bold text-red-600">{dayTransactions.filter(t => t.category === 'Fuel').length}</div>
                                        <div className="text-[10px] sm:text-xs text-red-800">น้ำมัน</div>
                                    </div>
                                    <div className="bg-orange-50 p-2 sm:p-3 rounded-xl border border-orange-100 text-center">
                                        <div className="text-lg sm:text-2xl font-bold text-orange-600">{dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'Event').length}</div>
                                        <div className="text-[10px] sm:text-xs text-orange-800">เหตุการณ์</div>
                                    </div>
                                </div>

                                {/* Detailed list of today's records */}
                                <div className="flex-1 w-full bg-slate-50/50 rounded-xl border border-slate-200 overflow-hidden flex flex-col mb-4">
                                    <div className="bg-slate-100 px-4 py-2 border-b border-slate-200 text-left">
                                        <p className="font-bold text-slate-700 text-sm">รายการที่บันทึกแล้ววันนี้</p>
                                    </div>
                                    <div className="overflow-y-auto max-h-[250px] p-2 space-y-2 text-left">
                                        {dayTransactions.length === 0 ? (
                                            <p className="text-center text-slate-400 py-4 text-sm">ไม่มีรายการบันทึกในวันนี้</p>
                                        ) : (
                                            dayTransactions.map(t => (
                                                <div key={t.id} className="bg-white p-3 rounded-lg border border-slate-200 text-sm flex justify-between items-center hover:bg-slate-50">
                                                    <div className="flex-1">
                                                        <div className="flex items-center gap-2 mb-1">
                                                            {t.category === 'Labor' && <span className="bg-emerald-100 text-emerald-700 text-[10px] px-1.5 py-0.5 rounded font-bold">ค่าแรง</span>}
                                                            {t.category === 'Vehicle' && <span className="bg-amber-100 text-amber-700 text-[10px] px-1.5 py-0.5 rounded font-bold">ใช้รถ</span>}
                                                            {t.category === 'Fuel' && <span className="bg-red-100 text-red-700 text-[10px] px-1.5 py-0.5 rounded font-bold">น้ำมัน</span>}
                                                            {t.category === 'DailyLog' && t.subCategory === 'VehicleTrip' && <span className="bg-blue-100 text-blue-700 text-[10px] px-1.5 py-0.5 rounded font-bold">เที่ยวรถ</span>}
                                                            {t.category === 'DailyLog' && t.subCategory === 'Sand' && <span className="bg-cyan-100 text-cyan-700 text-[10px] px-1.5 py-0.5 rounded font-bold">ทราย</span>}
                                                            {t.category === 'DailyLog' && t.subCategory === 'Event' && <span className="bg-orange-100 text-orange-700 text-[10px] px-1.5 py-0.5 rounded font-bold">เหตุการณ์</span>}
                                                            <span className="font-medium text-slate-700">{t.description}</span>
                                                        </div>
                                                        <div className="text-xs text-slate-500">
                                                            {t.amount > 0 && <span className="mr-3">ยอดเงิน: ฿{t.amount.toLocaleString()}</span>}
                                                            {((t as any).perCarTrips || (t as any).tripCount) && <span className="mr-3">จำนวน: {(t as any).perCarTrips || (t as any).tripCount} เที่ยว</span>}
                                                            {((t as any).perCarCubic || (t as any).totalCubic) && <span className="mr-3">ปริมาณ: {(t as any).perCarCubic || (t as any).totalCubic} คิว</span>}
                                                            {(t as any).quantity && <span className="mr-3">ปริมาณ: {(t as any).quantity} {(t as any).unit === 'gallon' ? 'แกลลอน' : 'ลิตร'}</span>}
                                                        </div>
                                                    </div>
                                                    {onDeleteTransaction && (
                                                        <button onClick={() => onDeleteTransaction(t.id)} className="p-2 text-slate-400 hover:text-red-500 hover:bg-red-50 rounded-lg transition-colors" title="ลบรายการ">
                                                            <Trash2 size={16} />
                                                        </button>
                                                    )}
                                                </div>
                                            ))
                                        )}
                                    </div>
                                </div>

                                <Button onClick={() => setStep(0)} className="w-full sm:w-auto px-8 mx-auto mt-auto">
                                    เสร็จสิ้น / เริ่มบันทึกวันอื่น
                                </Button>
                            </div>
                        )}
                    </Card>
                </div>

                {/* Right: Daily Dashboard (V.3 Enhancements) */}
                <div className="lg:col-span-4 flex flex-col gap-4">
                    {/* At-a-Glance Stats */}
                    <div className="grid grid-cols-2 gap-3 sm:gap-4">
                        <Card className="p-3 sm:p-4 bg-emerald-50 dark:bg-emerald-500/10 border-emerald-100 dark:border-emerald-500/20 flex flex-col">
                            <div className="flex justify-between items-start mb-2">
                                <Users size={16} className="text-emerald-500" />
                                <span className="text-[10px] font-bold px-1.5 py-0.5 rounded bg-emerald-100 dark:bg-emerald-500/20 text-emerald-700 dark:text-emerald-300">คนงาน</span>
                            </div>
                            <span className="text-2xl font-bold text-emerald-700 dark:text-emerald-400">
                                {dayTransactions.filter(t => t.category === 'Labor' && t.laborStatus === 'Work').reduce((acc, t) => acc + (t.employeeIds?.length || 0), 0)} <span className="text-sm font-normal text-emerald-600/70">คน</span>
                            </span>
                        </Card>

                        <Card className="p-3 sm:p-4 bg-cyan-50 dark:bg-cyan-500/10 border-cyan-100 dark:border-cyan-500/20 flex flex-col">
                            <div className="flex justify-between items-start mb-2">
                                <span className="text-xl">🌊</span>
                                <span className="text-[10px] font-bold px-1.5 py-0.5 rounded bg-cyan-100 dark:bg-cyan-500/20 text-cyan-700 dark:text-cyan-300">ทราย</span>
                            </div>
                            <span className="text-2xl font-bold text-cyan-700 dark:text-cyan-400">
                                {dayTransactions.filter(t => t.category === 'DailyLog' && t.subCategory === 'Sand').reduce((acc, t) => acc + (t.sandMorning || 0) + (t.sandAfternoon || 0), 0)} <span className="text-sm font-normal text-cyan-600/70">คิว</span>
                            </span>
                        </Card>

                        <Card className="p-3 sm:p-4 bg-orange-50 dark:bg-orange-500/10 border-orange-100 dark:border-orange-500/20 flex flex-col">
                            <div className="flex justify-between items-start mb-2">
                                <span className="text-xl">🚜</span>
                                <span className="text-[10px] font-bold px-1.5 py-0.5 rounded bg-orange-100 dark:bg-orange-500/20 text-orange-700 dark:text-orange-300">รถ/จักร</span>
                            </div>
                            <span className="text-2xl font-bold text-orange-700 dark:text-orange-400">
                                {dayTransactions.filter(t => t.category === 'Vehicle' || t.category === 'DailyLog').length} <span className="text-sm font-normal text-orange-600/70">คัน</span>
                            </span>
                        </Card>

                        <Card className="p-3 sm:p-4 bg-red-50 dark:bg-rose-500/10 border-red-100 dark:border-rose-500/20 flex flex-col">
                            <div className="flex justify-between items-start mb-2">
                                <Fuel size={16} className="text-red-500" />
                                <span className="text-[10px] font-bold px-1.5 py-0.5 rounded bg-red-100 dark:bg-rose-500/20 text-red-700 dark:text-rose-300">น้ำมัน</span>
                            </div>
                            <span className="text-2xl font-bold text-red-700 dark:text-rose-400">
                                {dayTransactions.filter(t => t.category === 'Fuel').reduce((acc, t) => acc + (t.quantity || 0), 0)} <span className="text-sm font-normal text-red-600/70">ลิตร</span>
                            </span>
                        </Card>
                    </div>

                    <Card className="flex-1 flex flex-col min-h-[400px] bg-white dark:bg-[#0f111a]/80 backdrop-blur-xl border-slate-200 dark:border-white/10 shadow-xl relative overflow-hidden">
                        <div className="p-4 border-b border-slate-100 dark:border-white/5 flex justify-between items-center bg-slate-50/50 dark:bg-white/[0.02]">
                            <h3 className="font-bold text-slate-800 dark:text-white flex items-center gap-2">
                                <FileText size={16} className="text-indigo-500" /> รายการบันทึกวันนี้
                            </h3>
                            <span className="text-xs font-bold bg-indigo-100 dark:bg-indigo-500/20 text-indigo-700 dark:text-indigo-400 px-2 py-1 rounded-full">
                                {dayTransactions.length} รายการ
                            </span>
                        </div>

                        <div className="flex-1 overflow-y-auto p-3 sm:p-4 space-y-3">
                            {dayTransactions.length === 0 ? (
                                <div className="h-full flex flex-col items-center justify-center text-slate-400 dark:text-slate-500 opacity-60">
                                    <FileText size={48} className="mb-3 opacity-50" />
                                    <p>ยังไม่มีรายการบันทึก</p>
                                </div>
                            ) : (
                                dayTransactions.map(t => (
                                    <div key={t.id} className="p-3 bg-white dark:bg-white/[0.03] rounded-xl border border-slate-100 dark:border-white/5 hover:border-indigo-300 dark:hover:border-indigo-500/50 hover:shadow-md transition-all group relative">
                                        <div className="flex justify-between items-start mb-1.5">
                                            <span className={`text-[9px] sm:text-[10px] uppercase font-bold px-1.5 py-0.5 rounded tracking-wide ${t.category === 'Labor' ? 'bg-emerald-100 dark:bg-emerald-500/20 text-emerald-700 dark:text-emerald-400' :
                                                t.category === 'Vehicle' ? 'bg-amber-100 dark:bg-amber-500/20 text-amber-700 dark:text-amber-400' :
                                                    t.category === 'Fuel' ? 'bg-red-100 dark:bg-rose-500/20 text-red-700 dark:text-rose-400' :
                                                        t.category === 'DailyLog' ? 'bg-blue-100 dark:bg-blue-500/20 text-blue-700 dark:text-blue-400' :
                                                            'bg-slate-100 dark:bg-white/10 text-slate-600 dark:text-slate-400'
                                                }`}>{t.category}</span>
                                            {t.amount > 0 && <span className="font-bold text-sm text-slate-800 dark:text-white text-right">฿{t.amount.toLocaleString()}</span>}
                                        </div>
                                        <p className="text-xs font-medium text-slate-700 dark:text-slate-300 mb-1 leading-snug">{t.description}</p>

                                        <div className="flex flex-wrap gap-2 text-[10px] text-slate-500 dark:text-slate-400 mt-2 bg-slate-50 dark:bg-white/[0.02] p-1.5 rounded-lg border border-slate-100 dark:border-white/5">
                                            {t.otHours && <span className="flex items-center gap-1"><span className="w-1.5 h-1.5 rounded-full bg-amber-500"></span>OT: {t.otHours} ชม.</span>}
                                            {t.workDetails && <span className="flex items-center gap-1"><span className="w-1.5 h-1.5 rounded-full bg-indigo-500"></span>งานรถ: {t.workDetails}</span>}
                                            {t.machineHours && <span className="flex items-center gap-1"><span className="w-1.5 h-1.5 rounded-full bg-orange-500"></span>ชม.: {t.machineHours}</span>}
                                            {t.quantity && <span className="flex items-center gap-1"><span className="w-1.5 h-1.5 rounded-full bg-cyan-500"></span>จำนวน: {t.quantity}</span>}
                                            {(!t.otHours && !t.workDetails && !t.machineHours && !t.quantity) && <span>วันที่: {formatDateBE(t.date)}</span>}
                                        </div>

                                        {/* Simple Delete Button */}
                                        {onDeleteTransaction && (
                                            <button onClick={() => onDeleteTransaction(t.id)} className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 p-1.5 bg-red-100 hover:bg-red-500 text-red-600 hover:text-white rounded-lg transition-all" title="ลบรายการ">
                                                <Trash2 size={12} />
                                            </button>
                                        )}
                                    </div>
                                ))
                            )}
                        </div>

                        {/* Daily Total Expense Summary Footer */}
                        <div className="p-4 bg-slate-50/80 dark:bg-black/20 border-t border-slate-100 dark:border-white/5 flex justify-between items-center backdrop-blur-md">
                            <div>
                                <span className="text-xs font-bold text-slate-500 dark:text-slate-400 block mb-0.5">รวมค่าใช้จ่ายวันนี้</span>
                                <span className="text-[10px] text-slate-400 dark:text-slate-500">ค่าแรง, รถ, น้ำมัน ฯลฯ</span>
                            </div>
                            <span className="text-xl sm:text-2xl font-black text-rose-600 dark:text-rose-400 tracking-tight">
                                ฿{dayTransactions.filter(t => t.type === 'Expense').reduce((s, t) => s + t.amount, 0).toLocaleString()}
                            </span>
                        </div>
                    </Card>
                </div>
            </div>
        </div>
    );
};

export default DailyStepRecorder;
