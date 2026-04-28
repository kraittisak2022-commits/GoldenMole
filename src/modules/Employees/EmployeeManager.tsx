import { useState, useEffect } from 'react';
import { Search, Plus, Edit2, Trash2, XCircle, Briefcase, CalendarClock, Wallet, Target, Activity, UserCircle, Briefcase as BriefcaseIcon, Download } from 'lucide-react';
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
    /**
     * Accepts both replacement arrays and functional updaters.
     * IMPORTANT: callers must use the functional form for bulk operations
     * because the `transactions` prop may be a filtered/masked subset of
     * the real transaction store. Replacing with a subset would cause the
     * parent to delete every transaction outside the subset.
     */
    setTransactions: (txs: Transaction[] | ((prev: Transaction[]) => Transaction[])) => void;
    settings: AppSettings;
    setSettings: (settings: AppSettings | ((prev: AppSettings) => AppSettings)) => void;
}

const EmployeeManager = ({ employees, setEmployees, transactions, setTransactions, settings, setSettings }: EmployeeManagerProps) => {
    const [section, setSection] = useState<'employees' | 'positions' | 'health'>('employees');
    const [isModalOpen, setIsModalOpen] = useState(false);
    const [editingEmp, setEditingEmp] = useState<Partial<Employee>>({});
    const [viewingEmp, setViewingEmp] = useState<Employee | null>(null);
    const [searchTerm, setSearchTerm] = useState('');
    const [activeTab, setActiveTab] = useState('work');
    const [isAddingKpi, setIsAddingKpi] = useState(false);
    const [newKpi, setNewKpi] = useState({ date: new Date().toISOString().split('T')[0], score: 100, maxScore: 100, notes: '', evaluator: 'Admin' });
    const [actionMsg, setActionMsg] = useState<string | null>(null);
    const [showInactive, setShowInactive] = useState(false);
    const [isMergeOpen, setIsMergeOpen] = useState(false);
    const [mergeFromId, setMergeFromId] = useState('');
    const [mergeToId, setMergeToId] = useState('');
    const [mergeKeepInactive, setMergeKeepInactive] = useState(true);
    const [localUndo, setLocalUndo] = useState<{ message: string; expiresAt: number; undo: () => void } | null>(null);
    const normalize = (v: string) => v.trim().toLowerCase();
    const formatPhone = (raw?: string) => {
        const digits = String(raw || '').replace(/\D/g, '');
        if (digits.length === 10) return `${digits.slice(0, 3)}-${digits.slice(3, 6)}-${digits.slice(6)}`;
        if (digits.length === 9) return `${digits.slice(0, 2)}-${digits.slice(2, 5)}-${digits.slice(5)}`;
        return digits;
    };
    const pushUndo = (message: string, undo: () => void) => {
        setLocalUndo({ message, undo, expiresAt: Date.now() + 20000 });
    };

    const DEFAULT_POSITIONS = ['คนขับรถ', 'รับจ้างรายวัน'];
    const positions = (settings.employeePositions && settings.employeePositions.length > 0)
        ? settings.employeePositions
        : DEFAULT_POSITIONS;
    const [newPositionName, setNewPositionName] = useState('');
    useEffect(() => {
        if (settings.employeePositions && settings.employeePositions.length > 0) return;
        setSettings(prev => ({ ...prev, employeePositions: [...DEFAULT_POSITIONS] }));
    }, [settings.employeePositions, setSettings]);
    useEffect(() => {
        if (!localUndo) return;
        const ms = Math.max(0, localUndo.expiresAt - Date.now());
        const t = window.setTimeout(() => setLocalUndo(null), ms);
        return () => window.clearTimeout(t);
    }, [localUndo]);

    const handleSave = () => {
        const name = String(editingEmp.name || '').trim();
        const nickname = String(editingEmp.nickname || '').trim();
        const phoneDigits = String(editingEmp.phone || '').replace(/\D/g, '').trim();
        if (!name && !nickname) {
            alert('กรุณากรอกอย่างน้อย "ชื่อ" หรือ "ชื่อเล่น"');
            return;
        }
        if (phoneDigits && (phoneDigits.length < 9 || phoneDigits.length > 10)) {
            alert('เบอร์โทรควรเป็นตัวเลข 9-10 หลัก');
            return;
        }
        if (!editingEmp.id) {
            const duplicate = employees.find(e => {
                const sameNick = nickname && normalize(e.nickname || '') === normalize(nickname);
                const sameName = name && normalize(e.name || '') === normalize(name);
                const samePhone = phoneDigits && String(e.phone || '').replace(/\D/g, '') === phoneDigits;
                return sameNick || (sameName && samePhone) || (sameName && !phoneDigits);
            });
            if (duplicate) {
                const dupLabel = duplicate.nickname || duplicate.name || duplicate.id;
                if (!confirm(`พบข้อมูลพนักงานที่อาจซ้ำกับ "${dupLabel}"\nต้องการบันทึกต่อหรือไม่?`)) return;
            }
        }
        if (editingEmp.id) {
            const oldEmp = employees.find(e => e.id === editingEmp.id);
            const posList = editingEmp.positions ?? (editingEmp.position ? [editingEmp.position] : []);
            let updatedEmp = { ...oldEmp, ...editingEmp, positions: posList.length ? posList : undefined, position: undefined } as Employee;
            const newWage = editingEmp.baseWage != null ? Number(editingEmp.baseWage) : undefined;
            updatedEmp.phone = phoneDigits || undefined;
            updatedEmp.name = name;
            updatedEmp.nickname = nickname;

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
            setActionMsg('อัปเดตข้อมูลพนักงานแล้ว');
        } else {
            const posList = editingEmp.positions ?? (editingEmp.position ? [editingEmp.position] : []);
            setEmployees([...employees, {
                ...editingEmp,
                id: Date.now().toString(),
                name,
                nickname,
                type: (editingEmp.type || 'Daily') as any,
                baseWage: editingEmp.baseWage != null ? Number(editingEmp.baseWage) : undefined,
                phone: phoneDigits || undefined,
                positions: posList.length ? posList : undefined,
                position: undefined,
                salaryHistory: []
            } as Employee]);
            setActionMsg('เพิ่มพนักงานใหม่แล้ว');
        }
        setIsModalOpen(false);
        setEditingEmp({});
    };

    const handleDelete = (id: string) => {
        const refCount = transactions.filter(t => t.employeeId === id || t.employeeIds?.includes(id) || t.driverId === id || t.sandOperators?.includes(id)).length;
        if (refCount > 0) {
            const inactive = confirm(`พนักงานคนนี้ถูกอ้างอิงในรายการ ${refCount} รายการ\nแนะนำให้เปลี่ยนเป็น Inactive แทนลบถาวร\n\nกด "ตกลง" เพื่อเปลี่ยนเป็น Inactive`);
            if (inactive) {
                const prevEmployees = employees;
                setEmployees(employees.map((e: Employee) => e.id === id ? { ...e, inactive: true } : e));
                setActionMsg('เปลี่ยนสถานะพนักงานเป็น Inactive แล้ว');
                pushUndo('ตั้งค่า Inactive แล้ว (Undo ได้ 20 วินาที)', () => setEmployees(prevEmployees));
            }
            return;
        }
        if (!confirm('ลบพนักงาน?')) return;
        const prevEmployees = employees;
        setEmployees(employees.filter((e: Employee) => e.id !== id));
        setActionMsg('ลบพนักงานแล้ว');
        pushUndo('ลบพนักงานแล้ว (Undo ได้ 20 วินาที)', () => setEmployees(prevEmployees));
    };
    const filtered = employees.filter((e: Employee) => (showInactive || !e.inactive) && ((e.name || '').toLowerCase().includes(searchTerm.toLowerCase()) || (e.nickname || '').toLowerCase().includes(searchTerm.toLowerCase())));
    const exportRows = (rows: string[][], filename: string) => {
        const csv = rows.map(r => r.map(v => `"${String(v ?? '').replace(/"/g, '""')}"`).join(',')).join('\n');
        const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = filename;
        a.click();
        URL.revokeObjectURL(url);
    };
    const exportEmployeeCsv = () => {
        if (!viewingEmp) return;
        const rows: string[][] = [['ประเภท', 'วันที่', 'รายละเอียด', 'จำนวนเงิน']];
        laborHistory.forEach(t => rows.push(['Work', t.date, t.description, String(t.amount || 0)]));
        leaveHistory.forEach(t => rows.push(['Leave', t.date, t.leaveReason || t.description || '-', String(t.leaveDays || 1)]));
        payrollHistory.forEach(t => rows.push(['Payroll', t.date, t.description, String(t.amount || 0)]));
        (viewingEmp.kpiHistory || []).forEach(k => rows.push(['KPI', k.date, `${k.score}/${k.maxScore} ${k.notes || ''}`, '']));
        (viewingEmp.salaryHistory || []).forEach(s => rows.push(['Salary', s.date, s.reason || '-', `${s.oldWage} -> ${s.newWage}`]));
        exportRows(rows, `employee_${viewingEmp.nickname || viewingEmp.name || viewingEmp.id}.csv`);
    };
    const exportEmployeePdf = () => {
        if (!viewingEmp) return;
        const win = window.open('', '_blank');
        if (!win) return;
        const title = viewingEmp.nickname || viewingEmp.name || viewingEmp.id;
        win.document.write(`<html><head><title>${title}</title><style>body{font-family:sans-serif;padding:16px} table{width:100%;border-collapse:collapse;margin-top:12px} th,td{border:1px solid #ccc;padding:6px;font-size:12px;text-align:left}</style></head><body>`);
        win.document.write(`<h2>Employee Report: ${title}</h2>`);
        win.document.write('<table><thead><tr><th>ประเภท</th><th>วันที่</th><th>รายละเอียด</th><th>ค่า</th></tr></thead><tbody>');
        laborHistory.forEach(t => win.document.write(`<tr><td>Work</td><td>${t.date}</td><td>${t.description}</td><td>${t.amount || 0}</td></tr>`));
        leaveHistory.forEach(t => win.document.write(`<tr><td>Leave</td><td>${t.date}</td><td>${t.leaveReason || t.description || '-'}</td><td>${t.leaveDays || 1}</td></tr>`));
        payrollHistory.forEach(t => win.document.write(`<tr><td>Payroll</td><td>${t.date}</td><td>${t.description}</td><td>${t.amount || 0}</td></tr>`));
        (viewingEmp.kpiHistory || []).forEach(k => win.document.write(`<tr><td>KPI</td><td>${k.date}</td><td>${k.notes || ''}</td><td>${k.score}/${k.maxScore}</td></tr>`));
        (viewingEmp.salaryHistory || []).forEach(s => win.document.write(`<tr><td>Salary</td><td>${s.date}</td><td>${s.reason || '-'}</td><td>${s.oldWage} -> ${s.newWage}</td></tr>`));
        win.document.write('</tbody></table></body></html>');
        win.document.close();
        win.focus();
        win.print();
    };
    const runMergeEmployees = () => {
        if (!mergeFromId || !mergeToId || mergeFromId === mergeToId) {
            alert('กรุณาเลือกพนักงานต้นทางและปลายทางให้ถูกต้อง');
            return;
        }
        const src = employees.find(e => e.id === mergeFromId);
        const dst = employees.find(e => e.id === mergeToId);
        if (!src || !dst) return;
        if (!confirm(`ยืนยันรวมข้อมูลจาก "${src.nickname || src.name || src.id}" -> "${dst.nickname || dst.name || dst.id}" ?`)) return;
        const mapId = (id?: string) => (id === mergeFromId ? mergeToId : id);
        const mapIds = (ids?: string[]) => ids ? Array.from(new Set(ids.map(i => i === mergeFromId ? mergeToId : i))) : ids;
        const remapTransaction = (t: Transaction): Transaction => {
            const nextWorkTypeByEmployee = t.workTypeByEmployee ? Object.fromEntries(Object.entries(t.workTypeByEmployee).map(([k, v]) => [k === mergeFromId ? mergeToId : k, v])) : undefined;
            const nextWorkAssignments = t.workAssignments ? Object.fromEntries(Object.entries(t.workAssignments).map(([k, arr]) => [k, Array.from(new Set((arr || []).map(i => i === mergeFromId ? mergeToId : i)))])) : undefined;
            return {
                ...t,
                employeeId: mapId(t.employeeId),
                driverId: mapId(t.driverId),
                employeeIds: mapIds(t.employeeIds),
                sandOperators: mapIds(t.sandOperators),
                workTypeByEmployee: nextWorkTypeByEmployee as any,
                workAssignments: nextWorkAssignments as any,
            };
        };
        const prevEmployees = employees;
        // Snapshot the FULL transaction list captured atomically inside the
        // updater. The `transactions` prop may be a filtered/masked subset
        // (e.g. hidden ids removed via hiddenTransactionIds, or restricted
        // categories), so we must never replace the parent state with that
        // subset — doing so would silently delete every excluded row from
        // the database.
        let prevAllTransactions: Transaction[] = [];
        setTransactions(prev => {
            prevAllTransactions = prev;
            return prev.map(remapTransaction);
        });
        const mergedTarget: Employee = {
            ...dst,
            phone: dst.phone || src.phone,
            positions: Array.from(new Set([...(dst.positions || (dst.position ? [dst.position] : [])), ...(src.positions || (src.position ? [src.position] : []))])),
            salaryHistory: [...(dst.salaryHistory || []), ...(src.salaryHistory || [])],
            kpiHistory: [...(dst.kpiHistory || []), ...(src.kpiHistory || [])],
        };
        const nextEmployees = employees
            .map(e => e.id === mergeToId ? mergedTarget : e)
            .filter(e => mergeKeepInactive ? true : e.id !== mergeFromId)
            .map(e => e.id === mergeFromId && mergeKeepInactive ? { ...e, inactive: true } : e);
        setEmployees(nextEmployees);
        setActionMsg('รวมพนักงานซ้ำและย้ายข้อมูลธุรกรรมแล้ว');
        pushUndo('รวมพนักงานแล้ว (Undo ได้ 20 วินาที)', () => {
            setEmployees(prevEmployees);
            // Restore using the full snapshot we captured inside the updater
            // above so we don't accidentally delete rows that were filtered
            // out of the visible subset.
            setTransactions(() => prevAllTransactions);
        });
        setIsMergeOpen(false);
        setMergeFromId('');
        setMergeToId('');
    };

    // Employee Detail View Logic
    const getEmpHistory = (id: string, filterFn: (t: Transaction) => boolean) => transactions.filter((t: Transaction) => (t.employeeIds?.includes(id) || t.employeeId === id) && filterFn(t)).sort((a: Transaction, b: Transaction) => b.date.localeCompare(a.date));

    const laborHistory = viewingEmp ? getEmpHistory(viewingEmp.id, t => t.category === 'Labor' && (t.laborStatus === 'Work' || t.laborStatus === 'OT' || t.laborStatus === 'Advance')) : [];
    const leaveHistory = viewingEmp ? getEmpHistory(viewingEmp.id, t => t.category === 'Labor' && (t.laborStatus === 'Leave' || t.laborStatus === 'Sick' || t.laborStatus === 'Personal')) : [];
    const payrollHistory = viewingEmp ? getEmpHistory(viewingEmp.id, t => t.category === 'Payroll') : [];

    const saveKpi = () => {
        if (!viewingEmp) return;
        const score = Number(newKpi.score);
        const maxScore = Number(newKpi.maxScore);
        if (maxScore <= 0) {
            alert('คะแนนเต็มต้องมากกว่า 0');
            return;
        }
        if (score < 0) {
            alert('คะแนนที่ได้ต้องไม่ติดลบ');
            return;
        }
        const historyItem: KPIEvaluation = { ...newKpi, id: Date.now().toString(), score: Number(newKpi.score), maxScore: Number(newKpi.maxScore) };
        const updatedEmp = { ...viewingEmp, kpiHistory: [...(viewingEmp.kpiHistory || []), historyItem] };
        setEmployees(employees.map(e => e.id === viewingEmp.id ? updatedEmp : e));
        setViewingEmp(updatedEmp);
        setIsAddingKpi(false);
        setNewKpi({ date: new Date().toISOString().split('T')[0], score: 100, maxScore: 100, notes: '', evaluator: 'Admin' });
        setActionMsg('บันทึกผล KPI แล้ว');
    };
    const healthIssues = (() => {
        const issues: Array<{ id: string; level: 'warn' | 'info'; label: string; employeeId?: string; fixable?: boolean }> = [];
        employees.forEach(emp => {
            const name = String(emp.name || '').trim();
            const nick = String(emp.nickname || '').trim();
            const phoneDigits = String(emp.phone || '').replace(/\D/g, '');
            if (!name && !nick) issues.push({ id: `missing_name_${emp.id}`, level: 'warn', label: `พนักงาน ${emp.id} ไม่มีชื่อ/ชื่อเล่น`, employeeId: emp.id, fixable: true });
            if (phoneDigits && !(phoneDigits.length === 9 || phoneDigits.length === 10)) issues.push({ id: `bad_phone_${emp.id}`, level: 'warn', label: `${nick || name || emp.id} เบอร์โทรไม่ถูกต้อง`, employeeId: emp.id, fixable: true });
            if ((emp.baseWage ?? 0) <= 0 && !emp.inactive) issues.push({ id: `missing_wage_${emp.id}`, level: 'info', label: `${nick || name || emp.id} ยังไม่ระบุค่าแรง`, employeeId: emp.id });
        });
        const keyMap = new Map<string, Employee[]>();
        employees.filter(e => !e.inactive).forEach(e => {
            const key = normalize(e.nickname || '') || normalize(e.name || '');
            if (!key) return;
            const arr = keyMap.get(key) || [];
            arr.push(e);
            keyMap.set(key, arr);
        });
        keyMap.forEach((arr, key) => {
            if (arr.length > 1) issues.push({ id: `dup_${key}`, level: 'warn', label: `พบพนักงานชื่อซ้ำ/ใกล้เคียง "${key}" ${arr.length} รายการ` });
        });
        return issues;
    })();
    const fixEmployeeIssue = (employeeId: string) => {
        const prevEmployees = employees;
        const next = employees.map(e => {
            if (e.id !== employeeId) return e;
            const name = String(e.name || '').trim();
            const nickname = String(e.nickname || '').trim();
            const phoneDigits = String(e.phone || '').replace(/\D/g, '');
            return {
                ...e,
                name: name || (nickname ? e.name : `พนักงาน-${e.id.slice(-4)}`),
                nickname: nickname || (name ? e.nickname : `พนง-${e.id.slice(-4)}`),
                phone: phoneDigits || undefined,
            };
        });
        setEmployees(next);
        pushUndo('แก้ไขข้อมูลพนักงานแล้ว (Undo ได้ 20 วินาที)', () => setEmployees(prevEmployees));
    };
    const fixAllSafeIssues = () => {
        const prevEmployees = employees;
        const next = employees.map(e => {
            const name = String(e.name || '').trim();
            const nickname = String(e.nickname || '').trim();
            const phoneDigits = String(e.phone || '').replace(/\D/g, '');
            return {
                ...e,
                name: name || (nickname ? e.name : `พนักงาน-${e.id.slice(-4)}`),
                nickname: nickname || (name ? e.nickname : `พนง-${e.id.slice(-4)}`),
                phone: phoneDigits || undefined,
            };
        });
        setEmployees(next);
        pushUndo('แก้ไขข้อมูลปลอดภัยทั้งหมดแล้ว (Undo ได้ 20 วินาที)', () => setEmployees(prevEmployees));
    };

    return (
        <div className="space-y-6 animate-fade-in">
            {actionMsg && (
                <div className="rounded-xl border border-emerald-200 bg-emerald-50 px-4 py-2 text-sm text-emerald-700 flex items-center justify-between">
                    <span>{actionMsg}</span>
                    <button type="button" onClick={() => setActionMsg(null)} className="text-emerald-600 hover:text-emerald-800">ปิด</button>
                </div>
            )}
            {localUndo && (
                <div className="rounded-xl border border-amber-300 bg-amber-50 px-4 py-2 text-sm text-amber-900 flex items-center justify-between">
                    <span>{localUndo.message}</span>
                    <button type="button" onClick={() => { localUndo.undo(); setLocalUndo(null); }} className="px-2 py-1 rounded bg-amber-600 text-white hover:bg-amber-700">Undo</button>
                </div>
            )}
            <div className="flex gap-2 border-b border-slate-200 pb-2 mb-4">
                <button onClick={() => setSection('employees')} className={`flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-bold transition-colors ${section === 'employees' ? 'bg-slate-800 text-white' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'}`}>
                    <UserCircle size={18} /> พนักงาน
                </button>
                <button onClick={() => setSection('positions')} className={`flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-bold transition-colors ${section === 'positions' ? 'bg-slate-800 text-white' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'}`}>
                    <BriefcaseIcon size={18} /> ตำแหน่งพนักงาน
                </button>
                <button onClick={() => setSection('health')} className={`flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-bold transition-colors ${section === 'health' ? 'bg-slate-800 text-white' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'}`}>
                    <Activity size={18} /> Health Check
                </button>
            </div>

            {section === 'employees' && (
                <>
            <div className="flex justify-between items-center">
                <div className="relative w-64">
                    <Search className="absolute left-3 top-2.5 w-4 h-4 text-slate-400" />
                    <input className="pl-9 pr-4 py-2 w-full border rounded-lg" placeholder="ค้นหา..." value={searchTerm} onChange={e => setSearchTerm(e.target.value)} />
                </div>
                <div className="flex items-center gap-2">
                    <label className="text-xs text-slate-600 inline-flex items-center gap-1">
                        <input type="checkbox" checked={showInactive} onChange={e => setShowInactive(e.target.checked)} />
                        แสดง Inactive
                    </label>
                    <Button variant="outline" onClick={() => setIsMergeOpen(true)}>รวมพนักงานซ้ำ</Button>
                    <Button onClick={() => { setEditingEmp({}); setIsModalOpen(true); }}><Plus size={18} /> เพิ่มพนักงาน</Button>
                </div>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {filtered.map((emp: Employee) => (
                    <Card key={emp.id} className="p-4">
                        <div className="flex justify-between items-start mb-2">
                            <div className="flex items-center gap-3">
                                <div className="w-10 h-10 rounded-full bg-slate-100 flex items-center justify-center font-bold text-slate-600">{(emp.nickname || emp.name || '—').charAt(0)}</div>
                                <div><h4 className="font-bold">{emp.nickname || emp.name || '—'} {emp.inactive && <span className="text-[10px] px-1.5 py-0.5 rounded bg-slate-200 text-slate-700 ml-1">Inactive</span>}</h4><p className="text-xs text-slate-500">{emp.type}{(emp.positions?.length || emp.position) ? ` • ${(emp.positions || (emp.position ? [emp.position] : [])).join(', ')}` : ''} • {(emp.baseWage != null && emp.baseWage > 0) ? `฿${emp.baseWage}` : 'ยังไม่ระบุค่าแรง'} • 📞 {formatPhone(emp.phone) || '-'}</p></div>
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
                                    onClick={() => {
                                        const impacted = employees.filter(emp => (emp.positions || (emp.position ? [emp.position] : [])).includes(pos)).length;
                                        const msg = impacted > 0
                                            ? `ตำแหน่ง "${pos}" ถูกใช้งานโดยพนักงาน ${impacted} คน\nหากลบ ตำแหน่งนี้จะหายจากตัวเลือกในอนาคต\n\nยืนยันลบหรือไม่?`
                                            : `ยืนยันลบตำแหน่ง "${pos}" หรือไม่?`;
                                        if (!confirm(msg)) return;
                                        setSettings(prev => ({ ...prev, employeePositions: positions.filter((_, j) => j !== i) }));
                                        setActionMsg(`ลบตำแหน่ง "${pos}" แล้ว`);
                                    }}
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
            {section === 'health' && (
                <div className="space-y-4">
                    <div className="flex items-center justify-between">
                        <h3 className="font-bold text-lg">Employee Health Check</h3>
                        <Button variant="outline" onClick={fixAllSafeIssues}>แก้ไขทั้งหมด (Safe)</Button>
                    </div>
                    <p className="text-sm text-slate-500">ตรวจชื่อ/ชื่อเล่นว่าง, เบอร์โทรผิดรูปแบบ, ค่าแรงหาย และชื่อซ้ำใกล้เคียง</p>
                    <div className="space-y-2">
                        {healthIssues.map(issue => (
                            <div key={issue.id} className={`p-3 rounded-lg border ${issue.level === 'warn' ? 'bg-amber-50 border-amber-200' : 'bg-blue-50 border-blue-200'} flex items-center justify-between gap-2`}>
                                <span className="text-sm">{issue.label}</span>
                                {issue.fixable && issue.employeeId && <Button variant="outline" className="h-8 text-xs" onClick={() => fixEmployeeIssue(issue.employeeId)}>แก้ไข</Button>}
                            </div>
                        ))}
                        {healthIssues.length === 0 && <div className="p-5 rounded-lg border bg-emerald-50 border-emerald-200 text-emerald-700 text-sm">ไม่พบปัญหาข้อมูลพนักงาน</div>}
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
                            <Input label="เบอร์ (ไม่บังคับ)" value={editingEmp.phone || ''} onChange={(e: any) => setEditingEmp({ ...editingEmp, phone: String(e.target.value || '').replace(/[^\d]/g, '') })} placeholder="หมายเลขโทรศัพท์ (ตัวเลข 9-10 หลัก)" />
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
            {isMergeOpen && (
                <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
                    <Card className="w-full max-w-lg p-6">
                        <h3 className="font-bold text-lg mb-3">รวมพนักงานซ้ำ</h3>
                        <p className="text-xs text-slate-500 mb-4">ระบบจะย้าย `employeeId`, `employeeIds`, `driverId` และรายการอ้างอิงในธุรกรรมทั้งหมดไปยังพนักงานปลายทาง</p>
                        <div className="space-y-3">
                            <Select label="พนักงานต้นทาง (ที่จะถูกรวม)" value={mergeFromId} onChange={(e: any) => setMergeFromId(e.target.value)}>
                                <option value="">-- เลือก --</option>
                                {employees.map(e => <option key={e.id} value={e.id}>{e.nickname || e.name || e.id}</option>)}
                            </Select>
                            <Select label="พนักงานปลายทาง (เก็บไว้)" value={mergeToId} onChange={(e: any) => setMergeToId(e.target.value)}>
                                <option value="">-- เลือก --</option>
                                {employees.map(e => <option key={e.id} value={e.id}>{e.nickname || e.name || e.id}</option>)}
                            </Select>
                            <label className="text-sm inline-flex items-center gap-2">
                                <input type="checkbox" checked={mergeKeepInactive} onChange={e => setMergeKeepInactive(e.target.checked)} />
                                เก็บพนักงานต้นทางไว้เป็น Inactive (ไม่ลบทิ้ง)
                            </label>
                            <div className="flex gap-2 pt-1">
                                <Button variant="outline" className="flex-1" onClick={() => setIsMergeOpen(false)}>ยกเลิก</Button>
                                <Button className="flex-1" onClick={runMergeEmployees}>รวมข้อมูล</Button>
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
                                    <h3 className="font-bold text-2xl">{viewingEmp.nickname || viewingEmp.name || viewingEmp.id}</h3>
                                    <p className="text-slate-300">{viewingEmp.type === 'Daily' ? 'รายวัน' : 'รายเดือน'}{(viewingEmp.positions?.length || viewingEmp.position) ? ` • ${(viewingEmp.positions || (viewingEmp.position ? [viewingEmp.position] : [])).join(', ')}` : ''} • {(viewingEmp.baseWage != null && viewingEmp.baseWage > 0) ? `฿${viewingEmp.baseWage}` : 'ยังไม่ระบุค่าแรง'} • 📞 {formatPhone(viewingEmp.phone) || '-'}</p>
                                </div>
                            </div>
                            <div className="flex items-center gap-2">
                                <Button variant="outline" className="text-xs h-8 bg-white/10 border-white/20 text-white hover:bg-white/20" onClick={exportEmployeeCsv}><Download size={14} /> CSV</Button>
                                <Button variant="outline" className="text-xs h-8 bg-white/10 border-white/20 text-white hover:bg-white/20" onClick={exportEmployeePdf}><Download size={14} /> PDF</Button>
                                <button onClick={() => setViewingEmp(null)} className="text-slate-400 hover:text-white"><XCircle size={24} /></button>
                            </div>
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
                                                <div className={`absolute left-0 top-0 bottom-0 w-1 ${((kpi.maxScore > 0 ? kpi.score / kpi.maxScore : 0) >= 0.8) ? 'bg-emerald-500' : ((kpi.maxScore > 0 ? kpi.score / kpi.maxScore : 0) >= 0.5) ? 'bg-amber-500' : 'bg-red-500'}`}></div>
                                                <div className="flex justify-between items-start mb-2 pl-2">
                                                    <div>
                                                        <div className="font-bold text-slate-800 text-lg">คะแนน: <span className={(kpi.maxScore > 0 ? kpi.score / kpi.maxScore : 0) >= 0.8 ? 'text-emerald-600' : (kpi.maxScore > 0 ? kpi.score / kpi.maxScore : 0) >= 0.5 ? 'text-amber-600' : 'text-red-600'}>{kpi.score}</span> / {kpi.maxScore}
                                                            <span className="text-sm text-slate-400 font-normal ml-2">({kpi.maxScore > 0 ? Math.round((kpi.score / kpi.maxScore) * 100) : 0}%)</span>
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
