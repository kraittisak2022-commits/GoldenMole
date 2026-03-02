import { useState } from 'react';
import { Search, Plus, Edit2, Trash2, XCircle } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import Select from '../../components/ui/Select';
import { Employee, Transaction, SalaryHistoryItem } from '../../types';

interface EmployeeManagerProps {
    employees: Employee[];
    setEmployees: (emps: Employee[]) => void;
    transactions: Transaction[];
}

const EmployeeManager = ({ employees, setEmployees, transactions }: EmployeeManagerProps) => {
    const [isModalOpen, setIsModalOpen] = useState(false);
    const [editingEmp, setEditingEmp] = useState<Partial<Employee>>({});
    const [viewingEmp, setViewingEmp] = useState<Employee | null>(null);
    const [searchTerm, setSearchTerm] = useState('');

    const handleSave = () => {
        if (!editingEmp.name || !editingEmp.baseWage) return;
        if (editingEmp.id) {
            // Update existing
            const oldEmp = employees.find(e => e.id === editingEmp.id);
            let updatedEmp = { ...oldEmp, ...editingEmp } as Employee;

            // Check if wage changed
            if (oldEmp && oldEmp.baseWage !== editingEmp.baseWage) {
                const historyItem: SalaryHistoryItem = {
                    id: Date.now().toString(),
                    date: new Date().toISOString().split('T')[0],
                    oldWage: oldEmp.baseWage,
                    newWage: editingEmp.baseWage!,
                    type: editingEmp.type || oldEmp.type,
                    reason: 'ปรับฐานเงินเดือน'
                };
                updatedEmp.salaryHistory = [...(oldEmp.salaryHistory || []), historyItem];
            }

            setEmployees(employees.map((e: Employee) => e.id === editingEmp.id ? updatedEmp : e));
        } else {
            // Create new
            setEmployees([...employees, {
                ...editingEmp,
                id: Date.now().toString(),
                type: editingEmp.type || 'Daily',
                salaryHistory: []
            } as Employee]);
        }
        setIsModalOpen(false);
        setEditingEmp({});
    };

    const handleDelete = (id: string) => { if (confirm('ลบพนักงาน?')) setEmployees(employees.filter((e: Employee) => e.id !== id)); };
    const filtered = employees.filter((e: Employee) => e.name.toLowerCase().includes(searchTerm.toLowerCase()) || e.nickname.toLowerCase().includes(searchTerm.toLowerCase()));

    // Employee Detail View Logic
    const getEmpHistory = (id: string) => transactions.filter((t: Transaction) => t.employeeIds?.includes(id) || t.employeeId === id).sort((a: Transaction, b: Transaction) => b.date.localeCompare(a.date));

    return (
        <div className="space-y-6 animate-fade-in">
            <div className="flex justify-between items-center">
                <div className="relative w-64">
                    <Search className="absolute left-3 top-2.5 w-4 h-4 text-slate-400" />
                    <input className="pl-9 pr-4 py-2 w-full border rounded-lg" placeholder="ค้นหา..." value={searchTerm} onChange={e => setSearchTerm(e.target.value)} />
                </div>
                <Button onClick={() => { setEditingEmp({}); setIsModalOpen(true); }}><Plus size={18} /> เพิ่ม</Button>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {filtered.map((emp: Employee) => (
                    <Card key={emp.id} className="p-4">
                        <div className="flex justify-between items-start mb-2">
                            <div className="flex items-center gap-3">
                                <div className="w-10 h-10 rounded-full bg-slate-100 flex items-center justify-center font-bold text-slate-600">{emp.nickname.charAt(0)}</div>
                                <div><h4 className="font-bold">{emp.nickname} ({emp.name})</h4><p className="text-xs text-slate-500">{emp.type} • ฿{emp.baseWage}</p></div>
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
            {isModalOpen && (
                <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
                    <Card className="w-full max-w-md p-6">
                        <h3 className="font-bold text-lg mb-4">{editingEmp.id ? 'แก้ไข' : 'เพิ่ม'}</h3>
                        <div className="space-y-4">
                            <Input label="ชื่อ" value={editingEmp.name || ''} onChange={(e: any) => setEditingEmp({ ...editingEmp, name: e.target.value })} />
                            <Input label="ชื่อเล่น" value={editingEmp.nickname || ''} onChange={(e: any) => setEditingEmp({ ...editingEmp, nickname: e.target.value })} />
                            <Input label="เบอร์" value={editingEmp.phone || ''} onChange={(e: any) => setEditingEmp({ ...editingEmp, phone: e.target.value })} />
                            <Select label="ประเภท" value={editingEmp.type || 'Daily'} onChange={(e: any) => setEditingEmp({ ...editingEmp, type: e.target.value })}>
                                <option value="Daily">รายวัน</option>
                                <option value="Monthly">รายเดือน</option>
                            </Select>
                            <Input label="ค่าแรง" type="number" value={editingEmp.baseWage || ''} onChange={(e: any) => setEditingEmp({ ...editingEmp, baseWage: Number(e.target.value) })} />
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
                    <Card className="w-full max-w-lg p-6 max-h-[80vh] overflow-y-auto">
                        <div className="flex justify-between items-center mb-4"><h3 className="font-bold text-lg">{viewingEmp.name} ({viewingEmp.nickname})</h3><button onClick={() => setViewingEmp(null)}><XCircle /></button></div>
                        <div className="grid grid-cols-2 gap-4 mb-6"><div className="bg-slate-50 p-3 rounded">เบอร์: {viewingEmp.phone}</div><div className="bg-slate-50 p-3 rounded">ค่าแรง: {viewingEmp.baseWage}</div></div>
                        {viewingEmp.salaryHistory && viewingEmp.salaryHistory.length > 0 && (
                            <div className="mb-6">
                                <h4 className="font-bold mb-2">ประวัติการปรับเงินเดือน</h4>
                                <div className="max-h-40 overflow-y-auto border rounded-lg">
                                    <table className="w-full text-sm text-left">
                                        <thead className="bg-slate-100 text-slate-600"><tr><th className="p-2">วันที่</th><th className="p-2">ประเภท</th><th className="p-2 text-right">เดิม</th><th className="p-2 text-right">ใหม่</th></tr></thead>
                                        <tbody>
                                            {viewingEmp.salaryHistory.map((h) => (
                                                <tr key={h.id} className="border-b last:border-0 hover:bg-slate-50">
                                                    <td className="p-2">{h.date}</td>
                                                    <td className="p-2">{h.type === 'Daily' ? 'รายวัน' : 'รายเดือน'}</td>
                                                    <td className="p-2 text-right text-slate-500">{h.oldWage}</td>
                                                    <td className="p-2 text-right font-medium text-emerald-600">{h.newWage}</td>
                                                </tr>
                                            ))}
                                        </tbody>
                                    </table>
                                </div>
                            </div>
                        )}
                        <h4 className="font-bold mb-2">ประวัติการทำงาน</h4>
                        <div className="max-h-60 overflow-y-auto">
                            <table className="w-full text-sm text-left">
                                <thead className="bg-slate-100"><tr><th className="p-2">วันที่</th><th className="p-2">รายการ</th><th className="p-2 text-right">สถานะ</th></tr></thead>
                                <tbody>
                                    {getEmpHistory(viewingEmp.id).map((t: Transaction) => (
                                        <tr key={t.id} className="border-b">
                                            <td className="p-2">{t.date}</td>
                                            <td className="p-2">{t.description}</td>
                                            <td className={`p-2 text-right ${t.laborStatus === 'Work' ? 'text-emerald-600' : 'text-slate-500'}`}>{t.laborStatus === 'Work' ? (t.workType === 'HalfDay' ? '0.5' : '1') : t.amount}</td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                        </div>
                    </Card>
                </div>
            )}
        </div>
    );
};

export default EmployeeManager;
