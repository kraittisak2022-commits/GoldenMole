import { useState, useMemo, useEffect } from 'react';
import { Briefcase, Clock, Coins, CalendarDays, CheckCircle2, Trash2, Pencil, History } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import Select from '../../components/ui/Select';
import { getToday, normalizeDate, formatDateBE } from '../../utils';
import {
    LABOR_MENU_WORK_CATEGORY_ID,
    LABOR_MENU_WORK_CATEGORY_LABEL,
    dailyWageForWorkType,
    getLaborWorkAndOtEmployeeIdsForDate,
    getVehicleDriverIdsForDate,
} from '../../utils/laborWage';
import { Employee, WorkType, AppSettings, Transaction } from '../../types';

interface LaborModuleProps {
    employees: Employee[];
    settings: AppSettings;
    onSaveTransaction: (t: any) => void;
    onDeleteTransaction?: (id: string) => void;
    transactions: Transaction[];
    setTransactions: (t: any) => void;
    ensureEmployeeWage?: (emp: Employee) => Promise<number>;
}

const LaborModule = ({ employees, settings, onSaveTransaction, onDeleteTransaction, transactions, ensureEmployeeWage }: LaborModuleProps) => {
    const [activeTab, setActiveTab] = useState<'Attendance' | 'OT' | 'Advance' | 'Leave'>('Attendance');
    const [selectedIds, setSelectedIds] = useState<string[]>([]);
    const [formDate, setFormDate] = useState(getToday());
    /** เมื่อกำลังแก้ไขรายการเดิม */
    const [editingId, setEditingId] = useState<string | null>(null);

    // Attendance
    const [location, setLocation] = useState(settings.locations[0] || '');
    const [jobDetail, setJobDetail] = useState(settings.jobDescriptions[0] || '');
    const [workType, setWorkType] = useState<WorkType>('FullDay');
    const [specialPay, setSpecialPay] = useState('');

    // Other
    const [otAmount, setOtAmount] = useState('');
    const [formOtHours, setFormOtHours] = useState('');
    const [formOtDesc, setFormOtDesc] = useState('');
    const [advanceAmount, setAdvanceAmount] = useState('');
    const [leaveType, setLeaveType] = useState('Personal');
    const [leaveReason, setLeaveReason] = useState('');
    const [leaveDays, setLeaveDays] = useState('1');
    const [empSearch, setEmpSearch] = useState('');
    const [successAnim, setSuccessAnim] = useState(false);

    const normDate = normalizeDate(formDate);
    const dayTransactions = useMemo(() =>
        transactions.filter(t => normalizeDate(t.date) === normDate),
        [transactions, normDate]
    );

    const dayLaborAttendance = useMemo(() =>
        dayTransactions.filter((t: Transaction) => t.category === 'Labor' && t.subCategory === 'Attendance').sort((a, b) => a.id.localeCompare(b.id)),
        [dayTransactions]
    );
    const dayLaborOT = useMemo(() =>
        dayTransactions.filter((t: Transaction) => t.category === 'Labor' && t.subCategory === 'OT'),
        [dayTransactions]
    );
    const dayLeave = useMemo(() =>
        dayTransactions.filter((t: Transaction) => t.category === 'Leave' || t.laborStatus === 'Leave'),
        [dayTransactions]
    );
    const dayAdvance = useMemo(() =>
        dayTransactions.filter((t: Transaction) => t.category === 'Labor' && t.subCategory === 'Advance'),
        [dayTransactions]
    );

    useEffect(() => {
        if (activeTab === 'Attendance' && dayLaborAttendance.length > 0 && !editingId) {
            const latest = dayLaborAttendance[dayLaborAttendance.length - 1] as Transaction;
            setSelectedIds(latest.employeeIds || []);
            setWorkType((latest.workType as WorkType) || 'FullDay');
            setSpecialPay(latest.specialAmount != null ? String(latest.specialAmount) : '');
            const match = settings.jobDescriptions.find(j => latest.description?.includes(j));
            if (match) setJobDetail(match);
        }
        if (activeTab === 'Leave' && dayLeave.length > 0 && !editingId) {
            const latest = dayLeave[dayLeave.length - 1] as any;
            setLeaveType(latest.leaveType === 'Sick' ? 'Sick' : 'Personal');
            setLeaveReason(latest.leaveReason || '');
            setLeaveDays(latest.leaveDays != null ? String(latest.leaveDays) : '1');
        }
    }, [formDate, activeTab, dayLaborAttendance.length, dayLeave.length, editingId, settings.jobDescriptions]);

    const filteredEmps = employees.filter((e: Employee) => e.name.toLowerCase().includes(empSearch.toLowerCase()) || e.nickname?.toLowerCase().includes(empSearch.toLowerCase()));

    const triggerSuccess = () => { setSuccessAnim(true); setTimeout(() => setSuccessAnim(false), 1000); };

    const loadAttendanceForEdit = (t: Transaction) => {
        setSelectedIds(t.employeeIds || []);
        setWorkType((t.workType as WorkType) || 'FullDay');
        setSpecialPay(t.specialAmount != null ? String(t.specialAmount) : '');
        const match = settings.jobDescriptions.find(j => t.description?.includes(j));
        if (match) setJobDetail(match);
        setEditingId(t.id);
    };
    const loadLeaveForEdit = (t: any) => {
        setSelectedIds(t.employeeIds?.length ? t.employeeIds : (t.employeeId ? [t.employeeId] : []));
        setLeaveType(t.leaveType === 'Sick' ? 'Sick' : 'Personal');
        setLeaveReason(t.leaveReason || '');
        setLeaveDays(t.leaveDays != null ? String(t.leaveDays) : '1');
        setEditingId(t.id);
    };
    const loadOTForEdit = (t: any) => {
        setSelectedIds(t.employeeIds || []);
        setOtAmount(t.otAmount != null ? String(t.otAmount) : '');
        setFormOtHours(t.otHours != null ? String(t.otHours) : '');
        setFormOtDesc(t.otDescription || '');
        setEditingId(t.id);
    };
    const loadAdvanceForEdit = (t: any) => {
        setSelectedIds(t.employeeIds || []);
        setAdvanceAmount(t.advanceAmount != null ? String(t.advanceAmount) : '');
        setEditingId(t.id);
    };

    const getEmployeeDisplayName = (emp?: Employee) => {
        if (!emp) return '';
        const nickname = String(emp.nickname || '').trim();
        if (nickname) return nickname;
        const name = String(emp.name || '').trim();
        if (name) return name;
        return `#${emp?.id || ''}`;
    };

    const handleSave = async () => {
        const newId = Date.now().toString();
        const driverIdsToday = getVehicleDriverIdsForDate(transactions || [], formDate);
        const existingLaborIdSet = getLaborWorkAndOtEmployeeIdsForDate(transactions || [], formDate, editingId);

        if (activeTab === 'Attendance') {
            const allEmps = [...new Set([...selectedIds, ...driverIdsToday])];
            if (allEmps.length === 0) return alert('กรุณาเลือกพนักงาน หรือมีรายการใช้รถที่ระบุคนขับในวันนี้');
            const alreadyRecorded = allEmps.filter((id: string) => existingLaborIdSet.has(id));
            if (alreadyRecorded.length > 0) {
                const names = alreadyRecorded.map((id: string) => (getEmployeeDisplayName(employees.find((e: Employee) => e.id === id)) || id)).join(', ');
                return alert(`ไม่สามารถบันทึกซ้ำได้ — พนักงานต่อไปนี้มีรายการค่าแรง/OT วันที่นี้แล้ว: ${names}\nกรุณาตรวจสอบที่เมนู "บันทึกงานประจำวัน" หรือลบรายการเดิมก่อน`);
            }
        }

        if (activeTab === 'OT') {
            if (selectedIds.length === 0) return alert('เลือกพนักงาน');
            const alreadyRecorded = selectedIds.filter((id: string) => existingLaborIdSet.has(id));
            if (alreadyRecorded.length > 0) {
                const names = alreadyRecorded.map((id: string) => (getEmployeeDisplayName(employees.find((e: Employee) => e.id === id)) || id)).join(', ');
                return alert(`ไม่สามารถบันทึกซ้ำได้ — พนักงานต่อไปนี้มีรายการค่าแรง/OT วันที่นี้แล้ว: ${names}\nกรุณาตรวจสอบที่เมนู "บันทึกงานประจำวัน" หรือลบรายการเดิมก่อน`);
            }
        }

        if (activeTab !== 'Attendance' && activeTab !== 'OT' && selectedIds.length === 0) return alert('เลือกพนักงาน');

        const base = { id: newId, date: formDate };

        if (editingId && onDeleteTransaction) {
            onDeleteTransaction(editingId);
            setEditingId(null);
        }

        if (activeTab === 'Attendance') {
            const allEmps = [...new Set([...selectedIds, ...getVehicleDriverIdsForDate(transactions || [], formDate)])];
            const special = Number(specialPay);
            let total = 0;
            const workTypeByEmployee: Record<string, 'FullDay' | 'HalfDay'> = {};
            try {
                for (const id of allEmps) {
                    const emp = employees.find((e: Employee) => e.id === id);
                    if (!emp) continue;
                    const wage = ensureEmployeeWage ? await ensureEmployeeWage(emp) : (emp.baseWage ?? 0);
                    workTypeByEmployee[id] = workType;
                    total += dailyWageForWorkType(emp, wage, workType) + special;
                }
            } catch {
                return;
            }
            const driverOnlyIds = driverIdsToday.filter((id) => !selectedIds.includes(id));
            const driverOnlyNames = [...new Set(driverOnlyIds)]
                .map((id) => getEmployeeDisplayName(employees.find((e: Employee) => e.id === id)))
                .filter(Boolean)
                .join(', ');
            const namesInMenu = selectedIds
                .map((id) => getEmployeeDisplayName(employees.find((e: Employee) => e.id === id)))
                .filter(Boolean)
                .join(', ');
            const workLabel = workType === 'HalfDay' ? 'ครึ่งวัน' : 'เต็มวัน';
            const descCore = `ค่าแรง (${allEmps.length} คน) ${workLabel} [${LABOR_MENU_WORK_CATEGORY_LABEL}: ${namesInMenu || '—'}] [งาน: ${jobDetail}]${special > 0 ? ` +พิเศษ ${special}/คน` : ''}`;
            const description = driverOnlyNames ? `${descCore} [คนขับจากงานใช้รถ: ${driverOnlyNames}]` : descCore;
            const workAssignments: Record<string, string[]> = {};
            if (selectedIds.length > 0) workAssignments[LABOR_MENU_WORK_CATEGORY_ID] = [...selectedIds];
            onSaveTransaction({
                ...base,
                employeeIds: allEmps,
                type: 'Expense',
                category: 'Labor',
                subCategory: 'Attendance',
                laborStatus: 'Work',
                workType,
                workTypeByEmployee,
                workAssignments,
                customWorkCategories: [{ id: LABOR_MENU_WORK_CATEGORY_ID, label: LABOR_MENU_WORK_CATEGORY_LABEL }],
                description,
                location,
                amount: total,
                specialAmount: special,
            } as Transaction);
        } else if (activeTab === 'OT') {
            const hours = Number(formOtHours) || 0;
            const rate = Number(otAmount) || 0;
            const empNames = selectedIds.map((id) => getEmployeeDisplayName(employees.find((e: Employee) => e.id === id))).filter(Boolean).join(', ');
            onSaveTransaction({
                ...base,
                employeeIds: selectedIds,
                type: 'Expense',
                category: 'Labor',
                subCategory: 'OT',
                laborStatus: 'OT',
                description: `OT ${formOtDesc || 'เหมาจ่าย'} (${hours}ชม.) ${selectedIds.length}คน [${empNames}]`,
                amount: rate * hours * selectedIds.length,
                otAmount: rate,
                otHours: formOtHours ? hours : undefined,
                otDescription: formOtDesc,
            } as Transaction);
        } else if (activeTab === 'Advance') {
            onSaveTransaction({ ...base, employeeIds: selectedIds, type: 'Expense', category: 'Labor', subCategory: 'Advance', laborStatus: 'Advance', description: `เบิกล่วงหน้า`, amount: Number(advanceAmount) * selectedIds.length, advanceAmount: Number(advanceAmount) });
        } else if (activeTab === 'Leave') {
            onSaveTransaction({ ...base, employeeIds: selectedIds, type: 'Leave', category: 'Leave', laborStatus: 'Leave', leaveType, description: `ลา${leaveType === 'Sick' ? 'ป่วย' : 'กิจ'}: ${leaveReason}`, amount: 0, leaveReason, leaveDays: Number(leaveDays) });
        }
        triggerSuccess();
        setSelectedIds([]);
        setEditingId(null);
    };

    return (
        <div className={`space-y-4 sm:space-y-6 animate-fade-in ${successAnim ? 'animate-bounce-short' : ''}`}>
            <div className="flex justify-center bg-white p-1 rounded-xl shadow-sm w-full sm:w-fit mx-auto overflow-x-auto hide-scrollbar">
                {[{ id: 'Attendance', l: 'ลงเวลา', i: Briefcase }, { id: 'OT', l: 'OT', i: Clock }, { id: 'Advance', l: 'เบิก', i: Coins }, { id: 'Leave', l: 'ลา', i: CalendarDays }].map(t => <button key={t.id} onClick={() => { setActiveTab(t.id as any); setEditingId(null); }} className={`flex gap-2 px-3 sm:px-4 py-2 rounded-lg transition-all whitespace-nowrap shrink-0 text-sm ${activeTab === t.id ? 'bg-slate-800 text-white' : 'text-slate-500 hover:bg-slate-50'}`}><t.i className="w-4 h-4" /> {t.l}</button>)}
            </div>
            <Card className="p-4 sm:p-6 max-w-4xl mx-auto">
                <div className="flex flex-col sm:flex-row gap-3 sm:gap-4 mb-4">
                    <Input type="date" value={formDate} onChange={(e: any) => { setFormDate(e.target.value); setEditingId(null); }} label="วันที่" />
                    {activeTab === 'Attendance' && <div className="w-full"><Select value={location} onChange={(e: any) => setLocation(e.target.value)} label="สถานที่">{settings.locations.map((l: string) => <option key={l}>{l}</option>)}</Select></div>}
                </div>

                {/* รายการในวันนี้ — แสดงและแก้ไข/ลบได้ */}
                {activeTab === 'Attendance' && dayLaborAttendance.length > 0 && (
                    <div className="mb-4 p-3 bg-slate-50 rounded-xl border border-slate-200">
                        <p className="text-sm font-semibold text-slate-700 mb-2">รายการค่าแรงในวันนี้ ({dayLaborAttendance.length})</p>
                        <div className="space-y-2 max-h-40 overflow-y-auto">
                            {dayLaborAttendance.map((t: Transaction) => (
                                <div key={t.id} className={`flex items-center justify-between p-2 rounded-lg border text-sm ${editingId === t.id ? 'bg-emerald-50 border-emerald-300' : 'bg-white border-slate-200'}`}>
                                    <span className="truncate">{t.description} — ฿{t.amount?.toLocaleString()}</span>
                                    <div className="flex gap-1 shrink-0">
                                        <button type="button" onClick={() => loadAttendanceForEdit(t)} className="p-1.5 rounded text-slate-600 hover:bg-slate-200" title="แก้ไข"><Pencil size={14} /></button>
                                        {onDeleteTransaction && <button type="button" onClick={() => { if (confirm('ลบรายการนี้?')) { onDeleteTransaction(t.id); setEditingId(null); } }} className="p-1.5 rounded text-red-600 hover:bg-red-50" title="ลบ"><Trash2 size={14} /></button>}
                                    </div>
                                </div>
                            ))}
                        </div>
                        {editingId && <button type="button" onClick={() => setEditingId(null)} className="mt-2 text-xs text-slate-500 hover:text-slate-700">ล้างเพื่อเพิ่มใหม่</button>}
                    </div>
                )}
                {activeTab === 'OT' && dayLaborOT.length > 0 && (
                    <div className="mb-4 p-3 bg-slate-50 rounded-xl border border-slate-200">
                        <p className="text-sm font-semibold text-slate-700 mb-2">รายการ OT ในวันนี้ ({dayLaborOT.length})</p>
                        <div className="space-y-2 max-h-40 overflow-y-auto">
                            {dayLaborOT.map((t: Transaction) => (
                                <div key={t.id} className={`flex items-center justify-between p-2 rounded-lg border text-sm ${editingId === t.id ? 'bg-emerald-50 border-emerald-300' : 'bg-white border-slate-200'}`}>
                                    <span className="truncate">{t.description} — ฿{t.amount?.toLocaleString()}</span>
                                    <div className="flex gap-1 shrink-0">
                                        <button type="button" onClick={() => loadOTForEdit(t)} className="p-1.5 rounded text-slate-600 hover:bg-slate-200" title="แก้ไข"><Pencil size={14} /></button>
                                        {onDeleteTransaction && <button type="button" onClick={() => { if (confirm('ลบรายการนี้?')) { onDeleteTransaction(t.id); setEditingId(null); } }} className="p-1.5 rounded text-red-600 hover:bg-red-50" title="ลบ"><Trash2 size={14} /></button>}
                                    </div>
                                </div>
                            ))}
                        </div>
                        {editingId && <button type="button" onClick={() => setEditingId(null)} className="mt-2 text-xs text-slate-500 hover:text-slate-700">ล้างเพื่อเพิ่มใหม่</button>}
                    </div>
                )}
                {activeTab === 'Advance' && dayAdvance.length > 0 && (
                    <div className="mb-4 p-3 bg-slate-50 rounded-xl border border-slate-200">
                        <p className="text-sm font-semibold text-slate-700 mb-2">รายการเบิกในวันนี้ ({dayAdvance.length})</p>
                        <div className="space-y-2 max-h-40 overflow-y-auto">
                            {dayAdvance.map((t: Transaction) => (
                                <div key={t.id} className={`flex items-center justify-between p-2 rounded-lg border text-sm ${editingId === t.id ? 'bg-emerald-50 border-emerald-300' : 'bg-white border-slate-200'}`}>
                                    <span className="truncate">{t.description} — ฿{t.amount?.toLocaleString()}</span>
                                    <div className="flex gap-1 shrink-0">
                                        <button type="button" onClick={() => loadAdvanceForEdit(t)} className="p-1.5 rounded text-slate-600 hover:bg-slate-200" title="แก้ไข"><Pencil size={14} /></button>
                                        {onDeleteTransaction && <button type="button" onClick={() => { if (confirm('ลบรายการนี้?')) { onDeleteTransaction(t.id); setEditingId(null); } }} className="p-1.5 rounded text-red-600 hover:bg-red-50" title="ลบ"><Trash2 size={14} /></button>}
                                    </div>
                                </div>
                            ))}
                        </div>
                        {editingId && <button type="button" onClick={() => setEditingId(null)} className="mt-2 text-xs text-slate-500 hover:text-slate-700">ล้างเพื่อเพิ่มใหม่</button>}
                    </div>
                )}
                {activeTab === 'Leave' && dayLeave.length > 0 && (
                    <div className="mb-4 p-3 bg-slate-50 rounded-xl border border-slate-200">
                        <p className="text-sm font-semibold text-slate-700 mb-2">รายการลาในวันนี้ ({dayLeave.length})</p>
                        <div className="space-y-2 max-h-40 overflow-y-auto">
                            {dayLeave.map((t: Transaction) => (
                                <div key={t.id} className={`flex items-center justify-between p-2 rounded-lg border text-sm ${editingId === t.id ? 'bg-emerald-50 border-emerald-300' : 'bg-white border-slate-200'}`}>
                                    <span className="truncate">{(t as any).employeeIds?.map((id: string) => employees.find(e => e.id === id)?.nickname || id).join(', ')} — {(t as any).description}</span>
                                    <div className="flex gap-1 shrink-0">
                                        <button type="button" onClick={() => loadLeaveForEdit(t)} className="p-1.5 rounded text-slate-600 hover:bg-slate-200" title="แก้ไข"><Pencil size={14} /></button>
                                        {onDeleteTransaction && <button type="button" onClick={() => { if (confirm('ลบรายการนี้?')) { onDeleteTransaction(t.id); setEditingId(null); } }} className="p-1.5 rounded text-red-600 hover:bg-red-50" title="ลบ"><Trash2 size={14} /></button>}
                                    </div>
                                </div>
                            ))}
                        </div>
                        {editingId && <button type="button" onClick={() => setEditingId(null)} className="mt-2 text-xs text-slate-500 hover:text-slate-700">ล้างเพื่อเพิ่มใหม่</button>}
                    </div>
                )}

                {activeTab === 'Attendance' && (
                    <div className="flex gap-4 mb-4 p-3 bg-slate-50 rounded-lg border border-slate-200">
                        <label className="flex items-center gap-2 cursor-pointer"><input type="radio" name="wt" checked={workType === 'FullDay'} onChange={() => setWorkType('FullDay')} className="accent-slate-800" /> เต็มวัน (Full Day)</label>
                        <label className="flex items-center gap-2 cursor-pointer"><input type="radio" name="wt" checked={workType === 'HalfDay'} onChange={() => setWorkType('HalfDay')} className="accent-slate-800" /> ครึ่งวัน (Half Day)</label>
                    </div>
                )}

                <div className="mb-6 p-3 sm:p-4 border rounded-xl bg-slate-50 max-h-80 overflow-y-auto"><div className="flex flex-col sm:flex-row justify-between items-start sm:items-center mb-3 gap-2"><label className="text-sm font-bold text-slate-700">เลือกพนักงาน ({selectedIds.length})</label><input className="text-sm border rounded px-2 py-1 w-full sm:w-auto" placeholder="ค้นหาชื่อ..." value={empSearch} onChange={e => setEmpSearch(e.target.value)} /></div><div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-2">{filteredEmps.map((e: Employee) => <div key={e.id} onClick={() => setSelectedIds(p => p.includes(e.id) ? p.filter(x => x !== e.id) : [...p, e.id])} className={`p-2 border rounded-lg cursor-pointer flex justify-between items-center transition-all ${selectedIds.includes(e.id) ? 'bg-slate-800 text-white' : 'bg-white'}`}><span className="text-sm truncate">{e.nickname || e.name || e.id}</span>{selectedIds.includes(e.id) && <CheckCircle2 size={16} className="shrink-0" />}</div>)}</div></div>
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

            {/* ประวัติรายการค่าแรง/ลา/OT/เบิก */}
            {(() => {
                const laborHistory = (transactions || [])
                    .filter((t: Transaction) => t.category === 'Labor' || t.category === 'Leave')
                    .sort((a: Transaction, b: Transaction) => b.date.localeCompare(a.date))
                    .slice(0, 25);
                return (
                    <Card className="p-0 overflow-hidden border border-slate-200 shadow-sm max-w-4xl mx-auto">
                        <div className="p-4 bg-gradient-to-r from-slate-50 to-emerald-50/50 border-b flex items-center gap-2">
                            <History size={18} className="text-slate-500" />
                            <span className="font-bold text-slate-700">ประวัติรายการ ({laborHistory.length} รายการ)</span>
                        </div>
                        <div className="divide-y divide-slate-100 max-h-[380px] overflow-y-auto">
                            {laborHistory.length === 0 ? (
                                <div className="p-8 text-center text-slate-400 text-sm">ยังไม่มีรายการ</div>
                            ) : (
                                laborHistory.map((t: Transaction) => {
                                    const isLabor = t.category === 'Labor';
                                    const sub = t.subCategory || (t.laborStatus || '');
                                    const label = isLabor ? (sub === 'Attendance' ? 'ลงเวลา' : sub === 'OT' ? 'OT' : sub === 'Advance' ? 'เบิก' : sub) : 'ลา';
                                    return (
                                        <div key={t.id} className={`p-4 flex justify-between items-center gap-3 hover:bg-slate-50/80 transition-colors group ${editingId === t.id ? 'bg-emerald-50 ring-1 ring-emerald-200' : ''}`}>
                                            <div className="min-w-0 flex-1">
                                                <div className="font-medium text-slate-800 truncate">{t.description}</div>
                                                <div className="text-xs text-slate-500 mt-0.5">{formatDateBE(t.date)} • {label}</div>
                                            </div>
                                            <div className="flex items-center gap-2 shrink-0">
                                                {t.amount != null && t.amount > 0 && <span className="font-bold text-slate-700 tabular-nums">฿{t.amount.toLocaleString()}</span>}
                                                <button type="button" onClick={() => { setFormDate(t.date?.slice(0, 10) || formDate); if (sub === 'Attendance') loadAttendanceForEdit(t); else if (sub === 'OT') loadOTForEdit(t); else if (sub === 'Advance') loadAdvanceForEdit(t); else if (t.category === 'Leave') loadLeaveForEdit(t); }} className="p-2 rounded-lg text-slate-400 hover:text-emerald-600 hover:bg-emerald-50 opacity-0 group-hover:opacity-100 transition-all" title="แก้ไข"><Pencil size={16} /></button>
                                                {onDeleteTransaction && <button type="button" onClick={() => { if (confirm('ลบรายการนี้?')) onDeleteTransaction(t.id); setEditingId(null); }} className="p-2 rounded-lg text-slate-400 hover:text-red-600 hover:bg-red-50 opacity-0 group-hover:opacity-100 transition-all" title="ลบ"><Trash2 size={16} /></button>}
                                            </div>
                                        </div>
                                    );
                                })
                            )}
                        </div>
                    </Card>
                );
            })()}
        </div>
    );
};

export default LaborModule;
