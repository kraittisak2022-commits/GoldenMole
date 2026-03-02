import { useState, useMemo } from 'react';
import { Calendar, Users, Truck, Fuel, CheckCircle2, ChevronRight, FileText, Plus, Trash2 } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import Select from '../../components/ui/Select';
import { getToday } from '../../utils';
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
    { id: 3, label: 'เครื่องจักร/ทราย', icon: FileText },
    { id: 4, label: 'น้ำมัน', icon: Fuel },
    { id: 5, label: 'ตรวจสอบ & บันทึก', icon: CheckCircle2 }
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

    // Vehicle State
    const [vehCar, setVehCar] = useState('');
    const [vehDriver, setVehDriver] = useState('');
    const [vehWage, setVehWage] = useState('');
    const [vehMachineWage, setVehMachineWage] = useState('');
    const [vehDetails, setVehDetails] = useState('');
    const [vehLocation, setVehLocation] = useState(settings.locations[0] || '');

    // Daily Log State (Machine/Sand)
    const [logType, setLogType] = useState<'Machine' | 'Sand'>('Machine');
    const [machineId, setMachineId] = useState('');
    const [machineHours, setMachineHours] = useState('');
    const [machineWork, setMachineWork] = useState('');
    const [sandMorning, setSandMorning] = useState('');
    const [sandAfternoon, setSandAfternoon] = useState('');

    // Fuel State
    const [fuelCar, setFuelCar] = useState('');
    const [fuelAmount, setFuelAmount] = useState('');
    const [fuelLiters, setFuelLiters] = useState('');
    const [fuelType, setFuelType] = useState<any>('Diesel');

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
                                    <Input type="date" label="วันที่" value={date} onChange={(e: any) => setDate(e.target.value)} className="text-center text-lg" />
                                </div>
                                <div className="p-4 bg-orange-50 text-orange-700 rounded-xl text-sm border border-orange-100 max-w-md text-center">
                                    💡 ระบบจะดึงข้อมูลเก่าของวันนี้มาแสดงให้ตรวจสอบด้วยครับ
                                </div>
                                <Button onClick={nextStep} className="mt-8 px-8 py-3 text-lg shadow-lg shadow-indigo-200">
                                    เริ่มบันทึก <ChevronRight className="ml-2" />
                                </Button>
                            </div>
                        )}

                        {/* Step 1: Labor */}
                        {step === 1 && (
                            <div className="h-full flex flex-col animate-slide-up">
                                <h3 className="font-bold text-lg mb-4 flex items-center gap-2"><Users className="text-emerald-500" /> บันทึกค่าแรง / OT</h3>

                                <div className="flex gap-4 mb-4">
                                    <button onClick={() => setLaborStatus('Work')} className={`flex-1 py-3 rounded-xl border flex justify-center items-center gap-2 transition-all ${laborStatus === 'Work' ? 'bg-emerald-50 border-emerald-500 text-emerald-700 font-bold' : 'bg-white hover:bg-slate-50'}`}>มาทำงาน (Work)</button>
                                    <button onClick={() => setLaborStatus('OT')} className={`flex-1 py-3 rounded-xl border flex justify-center items-center gap-2 transition-all ${laborStatus === 'OT' ? 'bg-amber-50 border-amber-500 text-amber-700 font-bold' : 'bg-white hover:bg-slate-50'}`}>ล่วงเวลา (OT)</button>
                                </div>

                                {laborStatus === 'OT' && (
                                    <div className="bg-amber-50 p-4 rounded-xl mb-4 border border-amber-100 grid grid-cols-2 gap-4">
                                        <Input label="ชั่วโมง OT" type="number" placeholder="เช่น 3" value={otHours} onChange={(e: any) => setOtHours(e.target.value)} />
                                        <Input label="รายละเอียดงาน OT" placeholder="ทำปูน, เทพื้น..." value={otDesc} onChange={(e: any) => setOtDesc(e.target.value)} />
                                    </div>
                                )}

                                <div className="flex justify-between items-center mb-2">
                                    <span className="text-sm font-medium text-slate-500">เลือกพนักงาน ({selectedEmps.length})</span>
                                    <input placeholder="ค้นหา..." value={laborSearch} onChange={e => setLaborSearch(e.target.value)} className="text-sm border rounded-lg px-2 py-1" />
                                </div>

                                <div className="flex-1 overflow-y-auto border rounded-xl bg-slate-50 p-2 sm:p-4 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2 content-start">
                                    {employees.filter(e => e.name.includes(laborSearch)).map(emp => {
                                        const status = dayTransactions.find(t => t.category === 'Labor' && t.employeeIds?.includes(emp.id));
                                        const isWork = status && status.laborStatus === 'Work' && status.subCategory === 'Attendance';
                                        const isOT = dayTransactions.find(t => t.category === 'Labor' && t.subCategory === 'OT' && t.employeeIds?.includes(emp.id));

                                        return (
                                            <div
                                                key={emp.id}
                                                onClick={() => setSelectedEmps(prev => prev.includes(emp.id) ? prev.filter(id => id !== emp.id) : [...prev, emp.id])}
                                                className={`p-3 rounded-lg border cursor-pointer flex justify-between items-center transition-all ${selectedEmps.includes(emp.id) ? 'bg-slate-800 text-white border-slate-700 shadow-md' : 'bg-white hover:border-indigo-300'}`}
                                            >
                                                <div className="flex flex-col">
                                                    <span className="text-sm font-medium">{emp.nickname}</span>
                                                    <div className="flex gap-1 mt-1">
                                                        {isWork && <span className="text-[10px] bg-emerald-100 text-emerald-600 px-1 rounded">✅ Work</span>}
                                                        {isOT && <span className="text-[10px] bg-amber-100 text-amber-600 px-1 rounded">🕒 OT</span>}
                                                    </div>
                                                </div>
                                                {selectedEmps.includes(emp.id) && <CheckCircle2 size={16} className="text-emerald-400" />}
                                            </div>
                                        );
                                    })}
                                </div>

                                <div className="mt-4 pt-4 border-t flex justify-between">
                                    <Button variant="secondary" onClick={prevStep}>ย้อนกลับ</Button>
                                    <Button onClick={() => {
                                        if (selectedEmps.length === 0) return alert('เลือกคนก่อนครับ');
                                        const base = { id: Date.now().toString(), date, employeeIds: selectedEmps };
                                        let t: any = {};
                                        if (laborStatus === 'Work') {
                                            let total = 0;
                                            selectedEmps.forEach(id => { const e = employees.find(x => x.id === id); if (e) total += (e.type === 'Monthly' ? e.baseWage / 30 : e.baseWage); });
                                            t = { ...base, type: 'Expense', category: 'Labor', subCategory: 'Attendance', laborStatus: 'Work', description: `ค่าแรงรายวัน (${selectedEmps.length} คน)`, amount: total };
                                        } else {
                                            const rate = Number(prompt("ระบุค่า OT ต่อคน (บาท):", "100") || 0);
                                            t = { ...base, type: 'Expense', category: 'Labor', subCategory: 'OT', laborStatus: 'OT', amount: rate * selectedEmps.length, otAmount: rate, otHours: Number(otHours), otDescription: otDesc, description: `OT ${otDesc} (${otHours} ชม.)` };
                                        }
                                        onSaveTransaction(t);
                                        setSelectedEmps([]);
                                        setLaborStatus('Work');
                                    }} className="px-6 bg-emerald-600 hover:bg-emerald-700">
                                        <Plus size={18} className="mr-2" /> บันทึกรายการ
                                    </Button>
                                    <Button onClick={nextStep}>ถัดไป <ChevronRight size={18} /></Button>
                                </div>
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
                                        <Select label="รถ/เครื่องจักร" value={vehCar} onChange={(e: any) => setVehCar(e.target.value)}>{settings.cars.map(c => <option key={c}>{c}</option>)}</Select>
                                        <Select label="คนขับ" value={vehDriver} onChange={(e: any) => setVehDriver(e.target.value)}>{employees.map(e => <option key={e.id} value={e.id}>{e.nickname}</option>)}</Select>
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

                        {/* Step 3: Daily Log (Machine & Sand) */}
                        {step === 3 && (
                            <div className="h-full flex flex-col animate-slide-up">
                                <h3 className="font-bold text-lg mb-4 flex items-center gap-2"><FileText className="text-blue-500" /> บันทึกเครื่องจักร / ทราย</h3>

                                <div className="flex gap-4 mb-4">
                                    <button onClick={() => setLogType('Machine')} className={`flex-1 py-3 rounded-xl border flex justify-center items-center gap-2 transition-all ${logType === 'Machine' ? 'bg-blue-50 border-blue-500 text-blue-700 font-bold' : 'bg-white hover:bg-slate-50'}`}>เครื่องจักร (Machine)</button>
                                    <button onClick={() => setLogType('Sand')} className={`flex-1 py-3 rounded-xl border flex justify-center items-center gap-2 transition-all ${logType === 'Sand' ? 'bg-orange-50 border-orange-500 text-orange-700 font-bold' : 'bg-white hover:bg-slate-50'}`}>ล้างทราย (Sand)</button>
                                </div>

                                <div className="mb-4 flex gap-2 overflow-x-auto pb-2">
                                    {dayTransactions.filter(t => t.category === 'DailyLog').map(t => (
                                        <div key={t.id} className="min-w-[150px] p-2 bg-blue-50 border border-blue-100 rounded-lg text-xs">
                                            <div className="font-bold text-blue-900">{t.subCategory}</div>
                                            <div className="text-blue-700">{t.description.split(':')[1]?.trim() || t.description}</div>
                                        </div>
                                    ))}
                                    {dayTransactions.filter(t => t.category === 'DailyLog').length === 0 && <span className="text-sm text-slate-400 italic">ยังไม่มีรายการบันทึกวันนี้</span>}
                                </div>

                                {logType === 'Machine' && (
                                    <div className="space-y-4 bg-white p-4 rounded-xl border mb-4">
                                        <Select label="เครื่องจักร" value={machineId} onChange={(e: any) => setMachineId(e.target.value)}>{settings.cars.map(c => <option key={c}>{c}</option>)}</Select>
                                        <div className="grid grid-cols-2 gap-4">
                                            <Input label="ชั่วโมงทำงาน" type="number" value={machineHours} onChange={(e: any) => setMachineHours(e.target.value)} />
                                            <Input label="รายละเอียดงาน" value={machineWork} onChange={(e: any) => setMachineWork(e.target.value)} placeholder="ขุดบ่อ, ปรับที่..." />
                                        </div>
                                        <Button onClick={() => {
                                            if (!machineId || !machineHours) return alert('ข้อมูลไม่ครบ');
                                            onSaveTransaction({
                                                id: Date.now().toString(), date, type: 'Expense', category: 'DailyLog', subCategory: 'Machine',
                                                description: `เครื่องจักร: ${machineId} (${machineHours} ชม.) - ${machineWork}`, amount: 0,
                                                machineId, machineHours: Number(machineHours), machineWorkType: machineWork
                                            } as Transaction);
                                            setMachineId(''); setMachineHours(''); setMachineWork('');
                                        }} className="w-full bg-blue-500 hover:bg-blue-600">บันทึกเครื่องจักร</Button>
                                    </div>
                                )}

                                {logType === 'Sand' && (
                                    <div className="space-y-4 bg-white p-4 rounded-xl border mb-4">
                                        <div className="grid grid-cols-2 gap-4">
                                            <Input label="ช่วงเช้า (คิว)" type="number" value={sandMorning} onChange={(e: any) => setSandMorning(e.target.value)} />
                                            <Input label="ช่วงบ่าย (คิว)" type="number" value={sandAfternoon} onChange={(e: any) => setSandAfternoon(e.target.value)} />
                                        </div>
                                        <Button onClick={() => {
                                            if (!sandMorning && !sandAfternoon) return alert('ใส่ข้อมูลอย่างน้อย 1 ช่อง');
                                            const total = Number(sandMorning || 0) + Number(sandAfternoon || 0);
                                            onSaveTransaction({
                                                id: Date.now().toString(), date, type: 'Income', category: 'DailyLog', subCategory: 'Sand',
                                                description: `ล้างทราย: รวม ${total} คิว (เช้า: ${sandMorning || 0}, บ่าย: ${sandAfternoon || 0})`, amount: 0,
                                                sandMorning: Number(sandMorning), sandAfternoon: Number(sandAfternoon)
                                            } as Transaction);
                                            setSandMorning(''); setSandAfternoon('');
                                        }} className="w-full bg-orange-500 hover:bg-orange-600">บันทึกล้างทราย</Button>
                                    </div>
                                )}

                                <div className="mt-auto flex justify-between">
                                    <Button variant="secondary" onClick={prevStep}>ย้อนกลับ</Button>
                                    <Button onClick={nextStep}>ถัดไป <ChevronRight size={18} /></Button>
                                </div>
                            </div>
                        )}

                        {/* Step 4: Fuel */}
                        {step === 4 && (
                            <div className="h-full flex flex-col animate-slide-up">
                                <h3 className="font-bold text-lg mb-4 flex items-center gap-2"><Fuel className="text-red-500" /> บันทึกน้ำมัน</h3>
                                <div className="mb-4 flex gap-2 overflow-x-auto pb-2">
                                    {dayTransactions.filter(t => t.category === 'Fuel').map(t => (
                                        <div key={t.id} className="min-w-[150px] p-2 bg-red-50 border border-red-100 rounded-lg text-xs">
                                            <div className="font-bold text-red-900">{t.vehicleId}</div>
                                            <div className="text-red-700">{t.quantity} ลิตร</div>
                                        </div>
                                    ))}
                                    {dayTransactions.filter(t => t.category === 'Fuel').length === 0 && <span className="text-sm text-slate-400 italic">ยังไม่มีรายการน้ำมันวันนี้</span>}
                                </div>
                                <div className="space-y-4 bg-white p-4 rounded-xl border mb-4">
                                    <Select label="รถที่เติม" value={fuelCar} onChange={(e: any) => setFuelCar(e.target.value)}>{settings.cars.map(c => <option key={c}>{c}</option>)}</Select>
                                    <div className="grid grid-cols-2 gap-4">
                                        <Input label="จำนวนเงิน (บาท)" type="number" value={fuelAmount} onChange={(e: any) => setFuelAmount(e.target.value)} />
                                        <Input label="จำนวนลิตร" type="number" value={fuelLiters} onChange={(e: any) => setFuelLiters(e.target.value)} />
                                    </div>
                                    <select value={fuelType} onChange={(e) => setFuelType(e.target.value)} className="w-full p-2 border rounded-xl text-sm">
                                        <option value="Diesel">ดีเซล (Diesel)</option>
                                        <option value="Benzine">เบนซิน (Benzine)</option>
                                    </select>
                                    <Button onClick={() => {
                                        if (!fuelCar || !fuelAmount) return alert('ข้อมูลไม่ครบ');
                                        onSaveTransaction({
                                            id: Date.now().toString(), date, type: 'Expense', category: 'Fuel',
                                            description: `น้ำมัน: ${fuelCar} ${fuelLiters} ลิตร`, amount: Number(fuelAmount),
                                            vehicleId: fuelCar, quantity: Number(fuelLiters), unit: 'L', fuelType
                                        } as Transaction);
                                        setFuelCar(''); setFuelAmount(''); setFuelLiters('');
                                    }} className="w-full bg-red-500 hover:bg-red-600">บันทึกรายการน้ำมัน</Button>
                                </div>
                                <div className="mt-auto flex justify-between">
                                    <Button variant="secondary" onClick={prevStep}>ย้อนกลับ</Button>
                                    <Button onClick={nextStep}>ถัดไป <ChevronRight size={18} /></Button>
                                </div>
                            </div>
                        )}

                        {/* Step 5: Summary */}
                        {step === 5 && (
                            <div className="h-full flex flex-col items-center justify-center animate-slide-up text-center">
                                <FileText size={48} className="text-slate-300 mb-4" />
                                <h3 className="text-2xl font-bold text-slate-800 mb-2">บันทึกข้อมูลเรียบร้อยแล้ว</h3>
                                <p className="text-slate-500 mb-8">ตรวจสอบรายการทั้งหมดได้ที่ตารางด้านขวา</p>

                                <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 sm:gap-4 w-full max-w-lg">
                                    <div className="bg-emerald-50 p-4 rounded-xl border border-emerald-100">
                                        <div className="text-2xl font-bold text-emerald-600">{dayTransactions.filter(t => t.category === 'Labor').length}</div>
                                        <div className="text-xs text-emerald-800">ค่าแรง</div>
                                    </div>
                                    <div className="bg-amber-50 p-4 rounded-xl border border-amber-100">
                                        <div className="text-2xl font-bold text-amber-600">{dayTransactions.filter(t => t.category === 'Vehicle').length}</div>
                                        <div className="text-xs text-amber-800">รถ</div>
                                    </div>
                                    <div className="bg-blue-50 p-4 rounded-xl border border-blue-100">
                                        <div className="text-2xl font-bold text-blue-600">{dayTransactions.filter(t => t.category === 'DailyLog').length}</div>
                                        <div className="text-xs text-blue-800">Daily Log</div>
                                    </div>
                                    <div className="bg-red-50 p-4 rounded-xl border border-red-100">
                                        <div className="text-2xl font-bold text-red-600">{dayTransactions.filter(t => t.category === 'Fuel').length}</div>
                                        <div className="text-xs text-red-800">น้ำมัน</div>
                                    </div>
                                </div>

                                <Button onClick={() => setStep(0)} className="mt-8">
                                    เริ่มบันทึกวันอื่นใหม่
                                </Button>
                            </div>
                        )}
                    </Card>
                </div>

                {/* Right: Daily Summary List */}
                <div className="lg:col-span-4">
                    <Card className="h-full flex flex-col bg-slate-900 text-white border-slate-800">
                        <div className="p-4 border-b border-slate-800 flex justify-between items-center bg-slate-950 rounded-t-xl">
                            <h3 className="font-bold">รายการวันนี้: {date}</h3>
                            <span className="text-xs bg-slate-800 px-2 py-1 rounded text-slate-400">{dayTransactions.length} รายการ</span>
                        </div>
                        <div className="flex-1 overflow-y-auto p-4 space-y-3">
                            {dayTransactions.length === 0 ? (
                                <div className="text-center text-slate-600 py-10">
                                    ยังไม่มีรายการ<br />ในวันนี้
                                </div>
                            ) : (
                                dayTransactions.map(t => (
                                    <div key={t.id} className="p-3 bg-slate-800 rounded-xl border border-slate-700 hover:border-indigo-500/50 transition-all group relative">
                                        <div className="flex justify-between items-start mb-1">
                                            <span className={`text-[10px] uppercase font-bold px-1.5 py-0.5 rounded ${t.category === 'Labor' ? 'bg-emerald-500/10 text-emerald-400' :
                                                t.category === 'Vehicle' ? 'bg-amber-500/10 text-amber-400' :
                                                    t.category === 'Fuel' ? 'bg-red-500/10 text-red-400' :
                                                        t.category === 'DailyLog' ? 'bg-blue-500/10 text-blue-400' :
                                                            'bg-slate-700 text-slate-400'
                                                }`}>{t.category}</span>
                                            <span className="font-mono font-medium text-indigo-300">฿{t.amount.toLocaleString()}</span>
                                        </div>
                                        <p className="text-xs text-slate-300 line-clamp-2">{t.description}</p>
                                        <div className="mt-2 text-[10px] text-slate-500 flex gap-2">
                                            {t.otHours && <span>OT: {t.otHours} ชม.</span>}
                                            {t.workDetails && <span>งาน: {t.workDetails}</span>}
                                        </div>
                                        {/* Simple Delete Button (Optional) */}
                                        {onDeleteTransaction && (
                                            <button onClick={() => onDeleteTransaction(t.id)} className="absolute top-2 right-2 opacity-0 group-hover:opacity-100 p-1 bg-red-500/20 hover:bg-red-500 text-red-500 hover:text-white rounded transition-all">
                                                <Trash2 size={12} />
                                            </button>
                                        )}
                                    </div>
                                ))
                            )}
                        </div>
                        <div className="p-4 bg-slate-950 border-t border-slate-800 text-right">
                            <span className="text-sm text-slate-500 mr-2">รวมรายจ่าย:</span>
                            <span className="text-xl font-bold text-white">฿{dayTransactions.reduce((s, t) => s + t.amount, 0).toLocaleString()}</span>
                        </div>
                    </Card>
                </div>
            </div>
        </div>
    );
};

export default DailyStepRecorder;
