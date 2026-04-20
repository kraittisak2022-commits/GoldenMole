import { useState, useEffect } from 'react';
import { Search, Plus, Edit2, Trash2, XCircle, Briefcase, CalendarClock, Wallet, Target, Activity, UserCircle, Briefcase as BriefcaseIcon } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import Select from '../../components/ui/Select';
import { formatDateBE } from '../../utils';
import { Employee, Transaction, SalaryHistoryItem, KPIEvaluation, AppSettings } from '../../types';

interface EmployeeManagerProps {
    employees: Employee[];
    setEmployees: (emps: Employee[]) => void;
    transactions: Transaction[];
    settings: AppSettings;
    setSettings: (settings: AppSettings | ((prev: AppSettings) => AppSettings)) => void;
}

const EmployeeManager = ({ employees, setEmployees, transactions, settings, setSettings }: EmployeeManagerProps) => {
    const [section, setSection] = useState<'employees' | 'positions'>('employees');
    const [isModalOpen, setIsModalOpen] = useState(false);
    const [editingEmp, setEditingEmp] = useState<Partial<Employee>>({});
    const [viewingEmp, setViewingEmp] = useState<Employee | null>(null);
    const [searchTerm, setSearchTerm] = useState('');
    const [activeTab, setActiveTab] = useState('work');
    const [isAddingKpi, setIsAddingKpi] = useState(false);
    const [newKpi, setNewKpi] = useState({ date: new Date().toISOString().split('T')[0], score: 100, maxScore: 100, notes: '', evaluator: 'Admin' });

    const DEFAULT_POSITIONS = ['คนขับรถ', 'รับจ้างรายวัน'];
    const positions = (settings.employeePositions && settings.employeePositions.length > 0)
        ? settings.employeePositions
        : DEFAULT_POSITIONS;
    const [newPositionName, setNewPositionName] = useState('');
    useEffect(() => {
        if (settings.employeePositions && settings.employeePositions.length > 0) return;
        setSettings(prev => ({ ...prev, employeePositions: [...DEFAULT_POSITIONS] }));
    }, [settings.employeePositions, setSettings]);

    const handleSave = () => {
        if (editingEmp.id) {
            const oldEmp = employees.find(e => e.id === editingEmp.id);
            const posList = editingEmp.positions ?? (editingEmp.position ? [editingEmp.position] : []);
            let updatedEmp = { ...oldEmp, ...editingEmp, positions: posList.length ? posList : undefined, position: undefined } as Employee;
            const newWage = editingEmp.baseWage != null ? Number(editingEmp.baseWage) : undefined;

            if (oldEmp && (oldEmp.baseWage ?? 0) !== (newWage ?? 0) && newWage != null && newWage > 0) {
                const historyItem: SalaryHistoryItem = {
                    id: Date.now().toString(),
                    date: new Date().toISOString().split('T')[0],
                    oldWage: oldEmp.baseWage ?? 0,
                    newWage: newWage,
                    type: (editingEmp.type || oldEmp.type) as any,
                    reason: 'ปรับฐานเงินเดือน'
                };
                updatedEmp.salaryHistory = [...(oldEmp.salaryHistory || []), historyItem];
            }

            setEmployees(employees.map((e: Employee) => e.id === editingEmp.id ? updatedEmp : e));
        } else {
            const posList = editingEmp.positions ?? (editingEmp.position ? [editingEmp.position] : []);
            setEmployees([...employees, {
                ...editingEmp,
                id: Date.now().toString(),
                name: editingEmp.name ?? '',
                nickname: editingEmp.nickname ?? '',
                type: (editingEmp.type || 'Daily') as any,
                baseWage: editingEmp.baseWage != null ? Number(editingEmp.baseWage) : undefined,
                positions: posList.length ? posList : undefined,
                position: undefined,
                salaryHistory: []
            } as Employee]);
        }
        setIsModalOpen(false);
        setEditingEmp({});
    };

    const handleDelete = (id: string) => { if (confirm('ลบพนักงาน?')) setEmployees(employees.filter((e: Employee) => e.id !== id)); };
    const filtered = employees.filter((e: Employee) => (e.name || '').toLowerCase().includes(searchTerm.toLowerCase()) || (e.nickname || '').toLowerCase().includes(searchTerm.toLowerCase()));

    // Employee Detail View Logic
    const getEmpHistory = (id: string, filterFn: (t: Transaction) => boolean) => transactions.filter((t: Transaction) => (t.employeeIds?.includes(id) || t.employeeId === id) && filterFn(t)).sort((a: Transaction, b: Transaction) => b.date.localeCompare(a.date));

    const laborHistory = viewingEmp ? getEmpHistory(viewingEmp.id, t => t.category === 'Labor' && (t.laborStatus === 'Work' || t.laborStatus === 'OT' || t.laborStatus === 'Advance')) : [];
    const leaveHistory = viewingEmp ? getEmpHistory(viewingEmp.id, t => t.category === 'Labor' && (t.laborStatus === 'Leave' || t.laborStatus === 'Sick' || t.laborStatus === 'Personal')) : [];
    const payrollHistory = viewingEmp ? getEmpHistory(viewingEmp.id, t => t.category === 'Payroll') : [];

    const saveKpi = () => {
        if (!viewingEmp) return;
        const historyItem: KPIEvaluation = { ...newKpi, id: Date.now().toString(), score: Number(newKpi.score), maxScore: Number(newKpi.maxScore) };
        const updatedEmp = { ...viewingEmp, kpiHistory: [...(viewingEmp.kpiHistory || []), historyItem] };
        setEmployees(employees.map(e => e.id === viewingEmp.id ? updatedEmp : e));
        setViewingEmp(updatedEmp);
        setIsAddingKpi(false);
        setNewKpi({ date: new Date().toISOString().split('T')[0], score: 100, maxScore: 100, notes: '', evaluator: 'Admin' });
    };

    return (
        <div className="space-y-6 animate-fade-in">
            <div className="flex gap-2 border-b border-slate-200 pb-2 mb-4">
                <button onClick={() => setSection('employees')} className={`flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-bold transition-colors ${section === 'employees' ? 'bg-slate-800 text-white' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'}`}>
                    <UserCircle size={18} /> พนักงาน
                </button>
                <button onClick={() => setSection('positions')} className={`flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-bold transition-colors ${section === 'positions' ? 'bg-slate-800 text-white' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'}`}>
                    <BriefcaseIcon size={18} /> ตำแหน่งพนักงาน
                </button>
            </div>

            {section === 'employees' && (
                <>
            <div className="flex justify-between items-center">
                <div className="relative w-64">
                    <Search className="absolute left-3 top-2.5 w-4 h-4 text-slate-400" />
                    <input className="pl-9 pr-4 py-2 w-full border rounded-lg" placeholder="ค้นหา..." value={searchTerm} onChange={e => setSearchTerm(e.target.value)} />
                </div>
                <Button onClick={() => { setEditingEmp({}); setIsModalOpen(true); }}><Plus size={18} /> เพิ่มพนักงาน</Button>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {filtered.map((emp: Employee) => (
                    <Card key={emp.id} className="p-4">
                        <div className="flex justify-between items-start mb-2">
                            <div className="flex items-center gap-3">
                                <div className="w-10 h-10 rounded-full bg-slate-100 flex items-center justify-center font-bold text-slate-600">{(emp.nickname || emp.name || '—').charAt(0)}</div>
                                <div><h4 className="font-bold">{emp.nickname || emp.name || '—'}</h4><p className="text-xs text-slate-500">{emp.type}{(emp.positions?.length || emp.position) ? ` • ${(emp.positions || (emp.position ? [emp.position] : [])).join(', ')}` : ''} • {(emp.baseWage != null && emp.baseWage > 0) ? `฿${emp.baseWage}` : 'ยังไม่ระบุค่าแรง'}</p></div>
                            </div>
                            <div className="flex gap-1">
                                <button onClick={() => { setEditingEmp(emp); setIsModalOpen(true); }} className="p-1 text-slate-400 hover:text-amber-500"><Edit2 size={16} /></button>
                                <button onClick={() => handleDelete(emp.id)} className="p-1 text-slate-400 hover:text-red-500"><Trash2 size={16} /></button>
                            </div>
                        </div>
                        <Button variant="outline" onClick={() => setViewingEmp(emp)} className="w-full text-xs h-8 mt-2">ดูรายละเอียด</Button>
                    </Card>
                ))}
            </div>
                </>
            )}

            {section === 'positions' && (
                <div className="space-y-4">
                    <p className="text-sm text-slate-500">จัดการตำแหน่งสำหรับระบุให้พนักงาน (ไม่บังคับ)</p>
                    <div className="flex gap-2 flex-wrap items-center">
                        <input className="border rounded-lg px-3 py-2 w-48" placeholder="ชื่อตำแหน่งใหม่" value={newPositionName} onChange={e => setNewPositionName(e.target.value)} />
                        <Button onClick={() => {
                            const nextPos = newPositionName.trim();
                            if (!nextPos) return;
                            if (positions.includes(nextPos)) return;
                            setSettings(prev => ({ ...prev, employeePositions: [...positions, nextPos] }));
                            setNewPositionName('');
                        }}><Plus size={16} /> เพิ่มตำแหน่ง</Button>
                    </div>
                    <div className="flex flex-wrap gap-2">
                        {positions.map((pos, i) => (
                            <span key={i} className="inline-flex items-center gap-1 px-3 py-1.5 bg-slate-100 rounded-lg text-sm">
                                {pos}
                                <button
                                    type="button"
                                    onClick={() => setSettings(prev => ({ ...prev, employeePositions: positions.filter((_, j) => j !== i) }))}
                                    className="text-slate-400 hover:text-red-500"
                                >
                                    ×
                                </button>
                            </span>
                        ))}
                        {positions.length === 0 && <span className="text-slate-400 text-sm">ยังไม่มีตำแหน่ง</span>}
                    </div>
                </div>
            )}

            {isModalOpen && (
                <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
                    <Card className="w-full max-w-md p-6">
                        <h3 className="font-bold text-lg mb-4">{editingEmp.id ? 'แก้ไข' : 'เพิ่มพนักงาน'}</h3>
                        <p className="text-xs text-slate-500 mb-2">ชื่อ เบอร์ ค่าแรง ไม่บังคับ — กรอกเท่าที่มีแล้วกดบันทึกได้เลย (ค่าแรงใส่ทีหลังได้ ระบบจะถามเมื่อนำพนักงานไปใช้)</p>
                        <div className="space-y-4">
                            <Input label="ชื่อ (ไม่บังคับ)" value={editingEmp.name || ''} onChange={(e: any) => setEditingEmp({ ...editingEmp, name: e.target.value })} placeholder="ชื่อ-นามสกุล" />
                            <Input label="ชื่อเล่น (ไม่บังคับ)" value={editingEmp.nickname || ''} onChange={(e: any) => setEditingEmp({ ...editingEmp, nickname: e.target.value })} placeholder="ชื่อที่เรียก" />
                            <div>
                                <label className="block text-sm font-medium text-slate-700 mb-2">ตำแหน่ง (เลือกได้หลายตำแหน่ง)</label>
                                <div className="flex flex-wrap gap-2">
                                    {positions.map(p => {
                                        const list = editingEmp.positions ?? (editingEmp.position ? [editingEmp.position] : []);
                                        const checked = list.includes(p);
                                        return (
                                            <label key={p} className="inline-flex items-center gap-1.5 px-3 py-2 rounded-lg border bg-white cursor-pointer hover:bg-slate-50">
                                                <input type="checkbox" checked={checked} onChange={() => {
                                                    const next = checked ? list.filter(x => x !== p) : [...list, p];
                                                    setEditingEmp({ ...editingEmp, positions: next.length ? next : undefined, position: undefined });
                                                }} className="rounded border-slate-300" />
                                                <span className="text-sm text-slate-700">{p}</span>
                                            </label>
                                        );
                                    })}
                                    {positions.length === 0 && <span className="text-sm text-slate-400">ไปที่แท็บ ตำแหน่งพนักงาน เพื่อเพิ่มตำแหน่ง</span>}
                                </div>
                            </div>
                            <Input label="เบอร์ (ไม่บังคับ)" value={editingEmp.phone || ''} onChange={(e: any) => setEditingEmp({ ...editingEmp, phone: e.target.value })} placeholder="หมายเลขโทรศัพท์" />
                            <Select label="ประเภท" value={editingEmp.type || 'Daily'} onChange={(e: any) => setEditingEmp({ ...editingEmp, type: e.target.value })}>
                                <option value="Daily">รายวัน</option>
                                <option value="Monthly">รายเดือน</option>
                            </Select>
                            <Input label="ค่าแรง (ไม่บังคับ — ใส่ทีหลังได้)" type="number" min="0" value={editingEmp.baseWage ?? ''} onChange={(e: any) => setEditingEmp({ ...editingEmp, baseWage: e.target.value === '' ? undefined : Number(e.target.value) })} placeholder="บาท" />
                            <div className="flex gap-2 mt-4">
                                <Button variant="outline" onClick={() => setIsModalOpen(false)} className="flex-1">ยกเลิก</Button>
                                <Button onClick={handleSave} className="flex-1">บันทึก</Button>
                            </div>
                        </div>
                    </Card>
                </div>
            )}
            {viewingEmp && (
                <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
                    <Card className="w-full max-w-4xl p-0 overflow-hidden flex flex-col max-h-[90vh]">
                        <div className="bg-slate-800 text-white p-6 flex justify-between items-start shrink-0">
                            <div className="flex gap-4 items-center">
                                <div className="w-16 h-16 rounded-full bg-slate-700 font-bold text-2xl flex items-center justify-center">{(viewingEmp.nickname || '?').charAt(0)}</div>
                                <div>
                                    <h3 className="font-bold text-2xl">{viewingEmp.nickname}</h3>
                                    <p className="text-slate-300">{viewingEmp.type === 'Daily' ? 'รายวัน' : 'รายเดือน'}{(viewingEmp.positions?.length || viewingEmp.position) ? ` • ${(viewingEmp.positions || (viewingEmp.position ? [viewingEmp.position] : [])).join(', ')}` : ''} • {(viewingEmp.baseWage != null && viewingEmp.baseWage > 0) ? `฿${viewingEmp.baseWage}` : 'ยังไม่ระบุค่าแรง'} • 📞 {viewingEmp.phone || '-'}</p>
                                </div>
                            </div>
                            <button onClick={() => setViewingEmp(null)} className="text-slate-400 hover:text-white"><XCircle size={24} /></button>
                        </div>

                        <div className="flex px-4 border-b bg-slate-50 overflow-x-auto shrink-0 hide-scrollbar">
                            {[
                                { id: 'work', label: 'ประวัติการทำงาน', icon: Briefcase },
                                { id: 'leave', label: 'ประวัติการลา/ขาด', icon: CalendarClock },
                                { id: 'payroll', label: 'การจ่ายเงินเดือน', icon: Wallet },
                                { id: 'kpi', label: 'ประเมิน KPI', icon: Target },
                                { id: 'salary', label: 'ปรับฐานเงินเดือน', icon: Activity },
                            ].map(tab => (
                                <button key={tab.id} onClick={() => setActiveTab(tab.id)} className={`px-4 py-3 text-sm font-bold flex items-center gap-2 border-b-2 whitespace-nowrap transition-colors ${activeTab === tab.id ? 'border-blue-600 text-blue-700 bg-blue-50/50' : 'border-transparent text-slate-500 hover:text-slate-700 hover:bg-slate-100'}`}>
                                    <tab.icon size={16} /> {tab.label}
                                </button>
                            ))}
                        </div>

                        <div className="p-6 overflow-y-auto flex-1 bg-white">
                            {activeTab === 'work' && (
                                <div className="space-y-4 animate-fade-in">
                                    <h4 className="font-bold text-lg text-slate-800 mb-4 flex items-center gap-2"><Briefcase className="text-blue-500" /> ประวัติการทำงานและค่าแรง</h4>
                                    <div className="border rounded-xl overflow-hidden">
                                        <table className="w-full text-sm text-left">
                                            <thead className="bg-slate-50 border-b"><tr><th className="p-3">วันที่</th><th className="p-3">ประเภท</th><th className="p-3">รายละเอียด</th><th className="p-3 text-right">จำนวน</th></tr></thead>
                                            <tbody className="divide-y">
                                                {laborHistory.map((t) => (
                                                    <tr key={t.id} className="hover:bg-slate-50 transition-colors">
                                                        <td className="p-3">{formatDateBE(t.date)}</td>
                                                        <td className="p-3">
                                                            <span className={`px-2 py-1 rounded text-xs font-bold ${t.laborStatus === 'OT' ? 'bg-amber-100 text-amber-700' : t.laborStatus === 'Advance' ? 'bg-red-100 text-red-700' : 'bg-emerald-100 text-emerald-700'}`}>
                                                                {t.laborStatus === 'OT' ? 'OT' : t.laborStatus === 'Advance' ? 'เบิกเงิน' : 'ทำงาน'}
                                                            </span>
                                                        </td>
                                                        <td className="p-3">{t.description}</td>
                                                        <td className="p-3 text-right font-medium">฿{t.laborStatus === 'OT' ? (t.otAmount || 0) : t.laborStatus === 'Advance' ? (t.advanceAmount || 0) : (viewingEmp.baseWage ?? 0)}</td>
                                                    </tr>
                                                ))}
                                                {laborHistory.length === 0 && <tr><td colSpan={4} className="p-8 text-center text-slate-400">ไม่มีประวัติการทำงาน</td></tr>}
                                            </tbody>
                                        </table>
                                    </div>
                                </div>
                            )}

                            {activeTab === 'leave' && (
                                <div className="space-y-4 animate-fade-in">
                                    <h4 className="font-bold text-lg text-slate-800 mb-4 flex items-center gap-2"><CalendarClock className="text-orange-500" /> ประวัติการลา/ขาด</h4>
                                    <div className="border rounded-xl overflow-hidden">
                                        <table className="w-full text-sm text-left">
                                            <thead className="bg-slate-50 border-b"><tr><th className="p-3">วันที่</th><th className="p-3">ประเภท</th><th className="p-3">เหตุผล</th><th className="p-3 text-right">จำนวนวัน</th></tr></thead>
                                            <tbody className="divide-y">
                                                {leaveHistory.map((t) => (
                                                    <tr key={t.id} className="hover:bg-slate-50 transition-colors">
                                                        <td className="p-3">{formatDateBE(t.date)}</td>
                                                        <td className="p-3">
                                                            <span className={`px-2 py-1 rounded text-xs font-bold ${t.laborStatus === 'Sick' ? 'bg-blue-100 text-blue-700' : t.laborStatus === 'Personal' ? 'bg-orange-100 text-orange-700' : 'bg-yellow-100 text-yellow-700'}`}>
                                                                {t.laborStatus === 'Sick' ? 'ลาป่วย' : t.laborStatus === 'Personal' ? 'ลากิจ' : 'ลา'}
                                                            </span>
                                                        </td>
                                                        <td className="p-3">{t.leaveReason || t.description || '-'}</td>
                                                        <td className="p-3 text-right font-medium">{t.leaveDays || 1} วัน</td>
                                                    </tr>
                                                ))}
                                                {leaveHistory.length === 0 && <tr><td colSpan={4} className="p-8 text-center text-slate-400">ไม่มีประวัติการลา</td></tr>}
                                            </tbody>
                                        </table>
                                    </div>
                                </div>
                            )}

                            {activeTab === 'payroll' && (
                                <div className="space-y-4 animate-fade-in">
                                    <h4 className="font-bold text-lg text-slate-800 mb-4 flex items-center gap-2"><Wallet className="text-emerald-500" /> ประวัติการจ่ายเงินเดือน</h4>
                                    <div className="border rounded-xl overflow-hidden">
                                        <table className="w-full text-sm text-left">
                                            <thead className="bg-slate-50 border-b"><tr><th className="p-3">วันที่จ่าย</th><th className="p-3">งวดเวลา</th><th className="p-3">รายการ</th><th className="p-3 text-right">ยอดสุทธิ</th></tr></thead>
                                            <tbody className="divide-y">
                                                {payrollHistory.map((t) => (
                                                    <tr key={t.id} className="hover:bg-slate-50 transition-colors">
                                                        <td className="p-3 font-medium">{formatDateBE(t.date)}</td>
                                                        <td className="p-3 text-slate-500">{formatDateBE(t.payrollPeriod?.start)} ถึง {formatDateBE(t.payrollPeriod?.end)}</td>
                                                        <td className="p-3">{t.description}</td>
                                                        <td className="p-3 text-right font-bold text-emerald-600">฿{t.amount.toLocaleString()}</td>
                                                    </tr>
                                                ))}
                                                {payrollHistory.length === 0 && <tr><td colSpan={4} className="p-8 text-center text-slate-400">ไม่มีประวัติการจ่ายเงินเดือน</td></tr>}
                                            </tbody>
                                        </table>
                                    </div>
                                </div>
                            )}

                            {activeTab === 'kpi' && (
                                <div className="space-y-4 animate-fade-in">
                                    <div className="flex justify-between items-center mb-4">
                                        <h4 className="font-bold text-lg text-slate-800 flex items-center gap-2"><Target className="text-purple-500" /> ประวัติผลประเมิน KPI</h4>
                                        <Button onClick={() => setIsAddingKpi(!isAddingKpi)} className="px-3 py-1.5 text-xs h-8">{isAddingKpi ? 'ยกเลิก' : '+ เพิ่มผลประเมิน'}</Button>
                                    </div>

                                    {isAddingKpi && (
                                        <div className="bg-purple-50 p-4 rounded-xl border border-purple-100 mb-4 space-y-3 animate-slide-up">
                                            <h5 className="font-bold text-purple-800">บันทึกผล KPI ใหม่</h5>
                                            <div className="grid grid-cols-2 gap-3">
                                                <Input type="date" label="วันที่ประเมิน" value={newKpi.date} onChange={(e: any) => setNewKpi({ ...newKpi, date: e.target.value })} />
                                                <Input label="ผู้ประเมิน" value={newKpi.evaluator} onChange={(e: any) => setNewKpi({ ...newKpi, evaluator: e.target.value })} />
                                                <Input type="number" label="คะแนนที่ได้" value={newKpi.score} onChange={(e: any) => setNewKpi({ ...newKpi, score: Number(e.target.value) })} />
                                                <Input type="number" label="คะแนนเต็ม" value={newKpi.maxScore} onChange={(e: any) => setNewKpi({ ...newKpi, maxScore: Number(e.target.value) })} />
                                            </div>
                                            <Input label="ความคิดเห็น / รายละเอียด" value={newKpi.notes} onChange={(e: any) => setNewKpi({ ...newKpi, notes: e.target.value })} />
                                            <Button onClick={saveKpi} className="w-full bg-purple-600 hover:bg-purple-700 text-white">บันทึก KPI</Button>
                                        </div>
                                    )}

                                    <div className="space-y-3">
                                        {viewingEmp.kpiHistory && viewingEmp.kpiHistory.map(kpi => (
                                            <div key={kpi.id} className="border rounded-xl p-4 hover:shadow-md transition-all bg-white relative overflow-hidden">
                                                <div className={`absolute left-0 top-0 bottom-0 w-1 ${kpi.score / kpi.maxScore >= 0.8 ? 'bg-emerald-500' : kpi.score / kpi.maxScore >= 0.5 ? 'bg-amber-500' : 'bg-red-500'}`}></div>
                                                <div className="flex justify-between items-start mb-2 pl-2">
                                                    <div>
                                                        <div className="font-bold text-slate-800 text-lg">คะแนน: <span className={kpi.score / kpi.maxScore >= 0.8 ? 'text-emerald-600' : kpi.score / kpi.maxScore >= 0.5 ? 'text-amber-600' : 'text-red-600'}>{kpi.score}</span> / {kpi.maxScore}
                                                            <span className="text-sm text-slate-400 font-normal ml-2">({Math.round((kpi.score / kpi.maxScore) * 100)}%)</span>
                                                        </div>
                                                        <div className="text-xs text-slate-500 mt-0.5">วันที่: {formatDateBE(kpi.date)} • ผู้ประเมิน: {kpi.evaluator}</div>
                                                    </div>
                                                </div>
                                                {kpi.notes && <div className="pl-2 mt-2 pt-2 border-t text-sm text-slate-600">📝 {kpi.notes}</div>}
                                            </div>
                                        ))}
                                        {(!viewingEmp.kpiHistory || viewingEmp.kpiHistory.length === 0) && <p className="text-center text-slate-400 py-8 border rounded-xl bg-slate-50">ไม่มีประวัติการประเมิน KPI</p>}
                                    </div>
                                </div>
                            )}

                            {activeTab === 'salary' && (
                                <div className="space-y-4 animate-fade-in">
                                    <h4 className="font-bold text-lg text-slate-800 mb-4 flex items-center gap-2"><Activity className="text-indigo-500" /> ประวัติการปรับฐานเงินเดือน</h4>
                                    <div className="border rounded-xl overflow-hidden">
                                        <table className="w-full text-sm text-left">
                                            <thead className="bg-slate-50 border-b"><tr><th className="p-3">วันที่</th><th className="p-3">ประเภท</th><th className="p-3 text-right">เดิม</th><th className="p-3 text-right">ใหม่</th><th className="p-3">เหตุผล</th></tr></thead>
                                            <tbody className="divide-y">
                                                {viewingEmp.salaryHistory && viewingEmp.salaryHistory.map((h) => (
                                                    <tr key={h.id} className="hover:bg-slate-50 transition-colors">
                                                        <td className="p-3">{formatDateBE(h.date)}</td>
                                                        <td className="p-3">{h.type === 'Daily' ? 'รายวัน' : 'รายเดือน'}</td>
                                                        <td className="p-3 text-right text-slate-500 line-through">฿{h.oldWage}</td>
                                                        <td className="p-3 text-right font-bold text-emerald-600">฿{h.newWage}</td>
                                                        <td className="p-3">{h.reason || '-'}</td>
                                                    </tr>
                                                ))}
                                                {(!viewingEmp.salaryHistory || viewingEmp.salaryHistory.length === 0) && <tr><td colSpan={5} className="p-8 text-center text-slate-400">ไม่มีประวัติการปรับฐานเงินเดือน</td></tr>}
                                            </tbody>
                                        </table>
                                    </div>
                                </div>
                            )}
                        </div>
                    </Card>
                </div>
            )}
        </div>
    );
};

export default EmployeeManager;
