import { useState } from 'react';
import { Briefcase, Clock, Coins, CalendarDays, CheckCircle2 } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import Select from '../../components/ui/Select';
import { getToday } from '../../utils';
import { Employee, WorkType, AppSettings, Transaction } from '../../types';

interface LaborModuleProps {
    employees: Employee[];
    settings: AppSettings;
    onSaveTransaction: (t: any) => void;
    transactions: Transaction[];
    setTransactions: (t: any) => void;
    ensureEmployeeWage?: (emp: Employee) => Promise<number>;
}

const LaborModule = ({ employees, settings, onSaveTransaction, transactions, ensureEmployeeWage }: LaborModuleProps) => {
    const [activeTab, setActiveTab] = useState<'Attendance' | 'OT' | 'Advance' | 'Leave'>('Attendance');
    const [selectedIds, setSelectedIds] = useState<string[]>([]);
    const [formDate, setFormDate] = useState(getToday());

    // Attendance
    const [location, setLocation] = useState(settings.locations[0] || '');
    const [jobDetail, setJobDetail] = useState(settings.jobDescriptions[0] || '');
    const [workType, setWorkType] = useState<WorkType>('FullDay');
    const [specialPay, setSpecialPay] = useState('');

    // Other
    const [otAmount, setOtAmount] = useState('');
    const [formOtHours, setFormOtHours] = useState(''); // New State
    const [formOtDesc, setFormOtDesc] = useState(''); // New State
    const [advanceAmount, setAdvanceAmount] = useState('');
    const [leaveType, setLeaveType] = useState('Personal');
    const [leaveReason, setLeaveReason] = useState('');
    const [leaveDays, setLeaveDays] = useState('1');
    const [empSearch, setEmpSearch] = useState('');
    const [successAnim, setSuccessAnim] = useState(false);

    const filteredEmps = employees.filter((e: Employee) => e.name.toLowerCase().includes(empSearch.toLowerCase()) || e.nickname?.toLowerCase().includes(empSearch.toLowerCase()));

    const triggerSuccess = () => { setSuccessAnim(true); setTimeout(() => setSuccessAnim(false), 1000); };

    const handleSave = async () => {
        if (selectedIds.length === 0) return alert('เลือกพนักงาน');
        const base = { id: Date.now().toString(), date: formDate, employeeIds: selectedIds };

        if (activeTab === 'Attendance' || activeTab === 'OT') {
            const existingLaborIds = (transactions || [])
                .filter((t: Transaction) => t.date === formDate && t.category === 'Labor' && (t.laborStatus === 'Work' || t.laborStatus === 'OT'))
                .flatMap((t: Transaction) => t.employeeIds || []);
            const alreadyRecorded = selectedIds.filter((id: string) => existingLaborIds.includes(id));
            if (alreadyRecorded.length > 0) {
                const names = alreadyRecorded.map((id: string) => employees.find((e: Employee) => e.id === id)?.nickname || id).join(', ');
                return alert(`ไม่สามารถบันทึกซ้ำได้ — พนักงานต่อไปนี้มีรายการค่าแรง/OT วันที่นี้แล้ว: ${names}\nกรุณาตรวจสอบที่เมนู "บันทึกงานประจำวัน" หรือลบรายการเดิมก่อน`);
            }
        }

        if (activeTab === 'Attendance') {
            const special = Number(specialPay);
            let total = 0;
            try {
                for (const id of selectedIds) {
                    const emp = employees.find((e: Employee) => e.id === id);
                    if (!emp) continue;
                    const wage = ensureEmployeeWage ? await ensureEmployeeWage(emp) : (emp.baseWage ?? 0);
                    const daily = emp.type === 'Monthly' ? wage / 30 : wage;
                    total += (workType === 'HalfDay' ? daily / 2 : daily) + special;
                }
            } catch {
                return;
            }
            onSaveTransaction({
                ...base, type: 'Expense', category: 'Labor', subCategory: 'Attendance',
                laborStatus: 'Work', workType,
                description: `งาน: ${jobDetail} (${workType === 'HalfDay' ? 'ครึ่งวัน' : 'เต็มวัน'}) ${special > 0 ? `+พิเศษ ${special}` : ''}`,
                location, amount: total, specialAmount: special
            });
        } else if (activeTab === 'OT') {
            // Updated OT Logic
            onSaveTransaction({
                ...base,
                type: 'Expense',
                category: 'Labor',
                subCategory: 'OT',
                laborStatus: 'OT',
                description: `OT: ${formOtDesc || 'เหมาจ่าย'} (${formOtHours ? formOtHours + ' ชม.' : ''})`,
                amount: Number(otAmount) * selectedIds.length,
                otAmount: Number(otAmount),
                otHours: formOtHours ? Number(formOtHours) : undefined,
                otDescription: formOtDesc
            });
        } else if (activeTab === 'Advance') {
            onSaveTransaction({ ...base, type: 'Expense', category: 'Labor', subCategory: 'Advance', laborStatus: 'Advance', description: `เบิกล่วงหน้า`, amount: Number(advanceAmount) * selectedIds.length, advanceAmount: Number(advanceAmount) });
        } else if (activeTab === 'Leave') {
            onSaveTransaction({ ...base, type: 'Leave', category: 'Leave', laborStatus: 'Leave', leaveType, description: `ลา${leaveType === 'Sick' ? 'ป่วย' : 'กิจ'}: ${leaveReason}`, amount: 0, leaveReason, leaveDays: Number(leaveDays) });
        }
        triggerSuccess();
        setSelectedIds([]);
    };

    return (
        <div className={`space-y-4 sm:space-y-6 animate-fade-in ${successAnim ? 'animate-bounce-short' : ''}`}>
            <div className="flex justify-center bg-white p-1 rounded-xl shadow-sm w-full sm:w-fit mx-auto overflow-x-auto hide-scrollbar">
                {[{ id: 'Attendance', l: 'ลงเวลา', i: Briefcase }, { id: 'OT', l: 'OT', i: Clock }, { id: 'Advance', l: 'เบิก', i: Coins }, { id: 'Leave', l: 'ลา', i: CalendarDays }].map(t => <button key={t.id} onClick={() => setActiveTab(t.id as any)} className={`flex gap-2 px-3 sm:px-4 py-2 rounded-lg transition-all whitespace-nowrap shrink-0 text-sm ${activeTab === t.id ? 'bg-slate-800 text-white' : 'text-slate-500 hover:bg-slate-50'}`}><t.i className="w-4 h-4" /> {t.l}</button>)}
            </div>
            <Card className="p-4 sm:p-6 max-w-4xl mx-auto">
                <div className="flex flex-col sm:flex-row gap-3 sm:gap-4 mb-4"><Input type="date" value={formDate} onChange={(e: any) => setFormDate(e.target.value)} label="วันที่" />{activeTab === 'Attendance' && <div className="w-full"><Select value={location} onChange={(e: any) => setLocation(e.target.value)} label="สถานที่">{settings.locations.map((l: string) => <option key={l}>{l}</option>)}</Select></div>}</div>

                {activeTab === 'Attendance' && (
                    <div className="flex gap-4 mb-4 p-3 bg-slate-50 rounded-lg border border-slate-200">
                        <label className="flex items-center gap-2 cursor-pointer"><input type="radio" name="wt" checked={workType === 'FullDay'} onChange={() => setWorkType('FullDay')} className="accent-slate-800" /> เต็มวัน (Full Day)</label>
                        <label className="flex items-center gap-2 cursor-pointer"><input type="radio" name="wt" checked={workType === 'HalfDay'} onChange={() => setWorkType('HalfDay')} className="accent-slate-800" /> ครึ่งวัน (Half Day)</label>
                    </div>
                )}

                <div className="mb-6 p-3 sm:p-4 border rounded-xl bg-slate-50 max-h-80 overflow-y-auto"><div className="flex flex-col sm:flex-row justify-between items-start sm:items-center mb-3 gap-2"><label className="text-sm font-bold text-slate-700">เลือกพนักงาน ({selectedIds.length})</label><input className="text-sm border rounded px-2 py-1 w-full sm:w-auto" placeholder="ค้นหาชื่อ..." value={empSearch} onChange={e => setEmpSearch(e.target.value)} /></div><div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-2">{filteredEmps.map((e: Employee) => <div key={e.id} onClick={() => setSelectedIds(p => p.includes(e.id) ? p.filter(x => x !== e.id) : [...p, e.id])} className={`p-2 border rounded-lg cursor-pointer flex justify-between items-center transition-all ${selectedIds.includes(e.id) ? 'bg-slate-800 text-white' : 'bg-white'}`}><span className="text-sm truncate">{e.nickname}</span>{selectedIds.includes(e.id) && <CheckCircle2 size={16} className="shrink-0" />}</div>)}</div></div>
                <div className="space-y-4">
                    {activeTab === 'Attendance' && (
                        <>
                            <Select value={jobDetail} onChange={(e: any) => setJobDetail(e.target.value)} label="รายละเอียดงาน">{settings.jobDescriptions.map((j: string) => <option key={j}>{j}</option>)}</Select>
                            <Input type="number" value={specialPay} onChange={(e: any) => setSpecialPay(e.target.value)} label="ค่าจ้างพิเศษ (บาท/คน)" className="input-highlight text-emerald-600 border-emerald-200" />
                        </>
                    )}
                    {activeTab === 'OT' && (
                        <>
                            <Input type="number" value={otAmount} onChange={(e: any) => setOtAmount(e.target.value)} label="ค่า OT (บาท/คน/ชม.)" className="input-highlight" />
                            <Input type="number" value={formOtHours} onChange={(e: any) => setFormOtHours(e.target.value)} label="จำนวนชั่วโมง OT" placeholder="เช่น 2.5" />
                            <Input value={formOtDesc} onChange={(e: any) => setFormOtDesc(e.target.value)} label="รายละเอียดงาน OT" placeholder="ทำอะไร..." />
                        </>
                    )}
                    {activeTab === 'Advance' && <Input type="number" value={advanceAmount} onChange={(e: any) => setAdvanceAmount(e.target.value)} label="ยอดเบิก (บาท/คน)" className="input-highlight text-red-600 border-red-200" />}
                    {activeTab === 'Leave' && <><Select value={leaveType} onChange={(e: any) => setLeaveType(e.target.value)} label="ประเภท"><option value="Personal">ลากิจ</option><option value="Sick">ลาป่วย</option></Select><Input type="number" value={leaveDays} onChange={(e: any) => setLeaveDays(e.target.value)} label="จำนวนวัน" /><Input value={leaveReason} onChange={(e: any) => setLeaveReason(e.target.value)} label="เหตุผล" /></>}
                    <Button onClick={handleSave} className="w-full mt-4">บันทึก</Button>
                </div>
            </Card>
        </div>
    );
};

export default LaborModule;
