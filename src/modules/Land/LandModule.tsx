import React, { useState, useMemo } from 'react';
import { FolderOpen, Edit2, Trash2, ArrowRight, FileText } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import Select from '../../components/ui/Select';
import { getToday, formatDateBE } from '../../utils';
import { LandProject, Transaction, LandStatus } from '../../types';

interface LandModuleProps {
    projects: LandProject[];
    setProjects: (projects: LandProject[]) => void;
    onSave: (t: Transaction) => void;
    transactions: Transaction[];
}

const LandModule = ({ projects, setProjects, onSave, transactions }: LandModuleProps) => {
    const [tab, setTab] = useState<'Create' | 'Record' | 'Overview' | 'Details'>('Overview');
    const [newProj, setNewProj] = useState<Partial<LandProject>>({ status: 'Deposit' });
    const [selectedProject, setSelectedProject] = useState<LandProject | null>(null);
    const [exp, setExp] = useState({ id: '', date: getToday(), desc: '', amount: '' });
    const [extraExpType, setExtraExpType] = useState('ค่าโอนที่ดิน');
    const [extraAmount, setExtraAmount] = useState('');
    const [editMode, setEditMode] = useState<string | null>(null);
    const [successAnim, setSuccessAnim] = useState(false);

    const triggerSuccess = () => { setSuccessAnim(true); setTimeout(() => setSuccessAnim(false), 500); };
    const groupedProjects = useMemo(() => { const groups: Record<string, LandProject[]> = {}; projects.forEach((p: LandProject) => { const g = p.group || 'ทั่วไป'; if (!groups[g]) groups[g] = []; groups[g].push(p); }); return groups; }, [projects]);

    const handleCreate = () => {
        if (!newProj.name || !newProj.fullPrice) return alert('กรุณากรอกข้อมูลจำเป็น');
        setProjects([...projects, { ...newProj, id: Date.now().toString(), purchaseDate: getToday() } as LandProject]);
        triggerSuccess();
        setNewProj({ status: 'Deposit' });
    };
    const handleDeleteProject = (e: React.MouseEvent, id: string) => { e.stopPropagation(); if (confirm('ยืนยันลบโครงการ?')) { setProjects(projects.filter((p: LandProject) => p.id !== id)); setTab('Overview'); } };
    const handleUpdateProject = (updated: LandProject) => { setProjects(projects.map((p: LandProject) => p.id === updated.id ? updated : p)); setEditMode(null); triggerSuccess(); };
    const handleRecordExtra = () => { if (!selectedProject || !extraAmount) return; onSave({ id: Date.now().toString(), date: getToday(), type: 'Expense', category: 'Land', subCategory: extraExpType, description: `${extraExpType} (${selectedProject.name})`, amount: Number(extraAmount), projectId: selectedProject.id } as Transaction); triggerSuccess(); setExtraAmount(''); };
    const updateStatus = (e: React.MouseEvent, id: string, status: LandStatus) => { e.stopPropagation(); setProjects(projects.map((p: LandProject) => p.id === id ? { ...p, status } : p)); triggerSuccess(); };

    if (tab === 'Details' && selectedProject) {
        const projTrans = transactions.filter((t: Transaction) => t.projectId === selectedProject.id);
        const _paidAmount = selectedProject.deposit + projTrans.filter((t: Transaction) => t.subCategory === 'Installment').reduce((s: number, t: Transaction) => s + t.amount, 0);
        const extraCost = projTrans.filter((t: Transaction) => ['ค่าโอนที่ดิน', 'ภาษีที่ดิน', 'ค่านายหน้า'].includes(t.subCategory || '')).reduce((s: number, t: Transaction) => s + t.amount, 0);

        return (
            <div className="space-y-6 animate-fade-in">
                <button onClick={() => setTab('Overview')} className="flex items-center gap-2 text-slate-500 hover:text-slate-800"><ArrowRight className="rotate-180" /> กลับหน้ารายการ</button>
                <Card className="p-6">
                    <div className="flex justify-between items-start mb-6">
                        <div><h2 className="text-2xl font-bold text-slate-800">{selectedProject.name}</h2><p className="text-slate-500">{selectedProject.group} • เจ้าของ: {selectedProject.sellerName}</p></div>
                    </div>
                    <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm bg-slate-50 p-4 rounded-xl border">
                        <div><p className="text-slate-400">โฉนด</p><p className="font-medium">{selectedProject.titleDeed}</p></div>
                        <div><p className="text-slate-400">พื้นที่</p><p className="font-medium">{selectedProject.rai}-{selectedProject.ngan}-{selectedProject.sqWah}</p></div>
                        <div><p className="text-slate-400">ราคาซื้อ</p><p className="font-medium">฿{selectedProject.fullPrice.toLocaleString()}</p></div>
                        <div><p className="text-slate-400">ซื้อเมื่อ</p><p className="font-medium">{formatDateBE(selectedProject.purchaseDate)}</p></div>
                    </div>
                </Card>
                <Card className="p-6">
                    <h3 className="font-bold mb-4 flex items-center gap-2"><FileText className="text-blue-500" /> ค่าใช้จ่ายเพิ่มเติม (โอน/ภาษี/นายหน้า)</h3>
                    <div className="text-3xl font-bold text-slate-800 mb-2">฿{extraCost.toLocaleString()}</div>
                    <p className="text-xs text-slate-400 mb-6">*ยอดนี้ไม่รวมในราคาที่ดิน</p>
                    <div className="space-y-2">
                        <div className="flex gap-2">
                            <Select className="text-xs" value={extraExpType} onChange={(e: any) => setExtraExpType(e.target.value)}>
                                <option value="ค่าโอนที่ดิน">ค่าโอนที่ดิน</option>
                                <option value="ภาษีที่ดิน">ภาษีที่ดิน</option>
                                <option value="ค่านายหน้า">ค่านายหน้า</option>
                                <option value="อื่นๆ">อื่นๆ</option>
                            </Select>
                            <Input type="number" placeholder="จำนวนเงิน" className="text-xs" value={extraAmount} onChange={(e: any) => setExtraAmount(e.target.value)} />
                            <Button className="text-xs py-1" onClick={handleRecordExtra}>บันทึก</Button>
                        </div>
                    </div>
                </Card>
                <Card className="p-0 overflow-hidden border border-slate-200 shadow-sm">
                    <div className="p-4 bg-gradient-to-r from-slate-50 to-slate-100 border-b flex items-center gap-2">
                        <FileText size={18} className="text-slate-500" />
                        <span className="font-bold text-slate-700">ประวัติการทำรายการ</span>
                    </div>
                    <div className="overflow-x-auto">
                        <table className="w-full text-sm text-left">
                            <thead className="bg-slate-50 text-slate-500 text-xs uppercase tracking-wider">
                                <tr><th className="p-3 font-semibold">วันที่</th><th className="p-3 font-semibold">รายการ</th><th className="p-3 text-right font-semibold">จำนวนเงิน</th></tr>
                            </thead>
                            <tbody className="divide-y divide-slate-100">
                                <tr className="hover:bg-emerald-50/50"><td className="p-3 font-medium text-slate-600">{formatDateBE(selectedProject.purchaseDate)}</td><td className="p-3">วางมัดจำตั้งต้น</td><td className="p-3 text-right font-bold text-emerald-600">฿{selectedProject.deposit.toLocaleString()}</td></tr>
                                {projTrans.map((t: Transaction) => (
                                    <tr key={t.id} className="hover:bg-slate-50 transition-colors">
                                        <td className="p-3 text-slate-600">{formatDateBE(t.date)}</td>
                                        <td className="p-3">{t.description} <span className="bg-slate-200/80 text-slate-600 text-xs px-1.5 py-0.5 rounded">{t.subCategory}</span></td>
                                        <td className="p-3 text-right font-semibold text-slate-800">฿{t.amount.toLocaleString()}</td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                </Card>
            </div>
        );
    }

    return (
        <div className={`space-y-6 animate-fade-in ${successAnim ? 'animate-bounce-short' : ''}`}>
            <div className="flex justify-center gap-2"><Button variant={tab === 'Overview' ? 'primary' : 'outline'} onClick={() => setTab('Overview')}>ภาพรวมที่ดิน</Button><Button variant={tab === 'Create' ? 'primary' : 'outline'} onClick={() => setTab('Create')}>สร้างแปลงใหม่</Button></div>
            {tab === 'Overview' && (
                <div>
                    {Object.entries(groupedProjects).map(([group, projs]) => (
                        <div key={group} className="space-y-3 mb-6">
                            <h3 className="font-bold text-slate-500 text-sm flex items-center gap-2"><FolderOpen size={16} /> {group}</h3>
                            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                                {projs.map(p => {
                                    const paid = transactions.filter(t => t.projectId === p.id).reduce((s, t) => s + t.amount, 0);
                                    const percent = Math.min((paid / p.fullPrice) * 100, 100);
                                    if (editMode === p.id) {
                                        return (
                                            <Card key={p.id} className="p-6">
                                                <h4 className="font-bold mb-4">แก้ไขโครงการ</h4>
                                                <div className="space-y-2">
                                                    <Input label="ชื่อ" value={p.name} onChange={(e: any) => handleUpdateProject({ ...p, name: e.target.value })} />
                                                    <Input label="ราคาซื้อ" type="number" value={p.fullPrice} onChange={(e: any) => handleUpdateProject({ ...p, fullPrice: Number(e.target.value) })} />
                                                    <div className="flex gap-2 mt-4"><Button onClick={() => setEditMode(null)} className="w-full bg-emerald-600">เสร็จสิ้น</Button></div>
                                                </div>
                                            </Card>
                                        );
                                    }
                                    return (
                                        <Card key={p.id} className="p-6 relative overflow-hidden cursor-pointer hover:shadow-md transition-all">
                                            <div onClick={() => { setSelectedProject(p); setTab('Details'); }}>
                                                <div className="flex justify-between items-start mb-4">
                                                    <div><h3 className="font-bold text-lg text-slate-800">{p.name}</h3><p className="text-xs text-slate-500">{p.group}</p></div>
                                                </div>
                                                <div className="space-y-2 text-sm">
                                                    <div className="flex justify-between"><span>ราคาเต็ม</span><span>฿{p.fullPrice.toLocaleString()}</span></div>
                                                    <div className="flex justify-between"><span>จ่ายแล้ว</span><span className="text-emerald-600 font-bold">฿{paid.toLocaleString()}</span></div>
                                                    <div className="h-2 bg-slate-100 rounded-full overflow-hidden mt-2"><div className="h-full bg-emerald-500" style={{ width: `${percent}%` }}></div></div>
                                                </div>
                                            </div>
                                            <div className="flex gap-2 mt-4 pt-4 border-t relative z-10">
                                                {p.status !== 'Transferred' && <button onClick={(e) => updateStatus(e, p.id, 'PaidFull')} className="text-xs bg-amber-50 text-amber-600 px-2 py-1 rounded border border-amber-200 hover:bg-amber-100">โอนเงินครบ</button>}
                                                {p.status !== 'Transferred' && <button onClick={(e) => updateStatus(e, p.id, 'Transferred')} className="text-xs bg-emerald-50 text-emerald-600 px-2 py-1 rounded border border-emerald-200 hover:bg-emerald-100">โอนสำเร็จ</button>}
                                                <div className="ml-auto flex gap-1">
                                                    <button onClick={(e) => { e.stopPropagation(); setEditMode(p.id); }} className="p-1 text-slate-400 hover:text-amber-500"><Edit2 size={16} /></button>
                                                    <button onClick={(e) => handleDeleteProject(e, p.id)} className="p-1 text-slate-400 hover:text-red-500"><Trash2 size={16} /></button>
                                                </div>
                                            </div>
                                        </Card>
                                    );
                                })}
                            </div>
                        </div>
                    ))}
                </div>
            )}
            {tab === 'Create' && (
                <Card className="p-6 max-w-xl mx-auto">
                    <h3 className="font-bold mb-4">สร้างแปลงที่ดิน</h3>
                    <div className="space-y-4">
                        <Input label="ชื่อโครงการ" value={newProj.name || ''} onChange={(e: any) => setNewProj({ ...newProj, name: e.target.value })} />
                        <Input label="กลุ่ม/โซน" value={newProj.group || ''} onChange={(e: any) => setNewProj({ ...newProj, group: e.target.value })} />
                        <Input label="ชื่อเจ้าของ" value={newProj.sellerName || ''} onChange={(e: any) => setNewProj({ ...newProj, sellerName: e.target.value })} />
                        <Input label="เลขโฉนด" value={newProj.titleDeed || ''} onChange={(e: any) => setNewProj({ ...newProj, titleDeed: e.target.value })} />
                        <div className="flex gap-2">
                            <Input label="ไร่" type="number" value={newProj.rai || ''} onChange={(e: any) => setNewProj({ ...newProj, rai: Number(e.target.value) })} />
                            <Input label="งาน" type="number" value={newProj.ngan || ''} onChange={(e: any) => setNewProj({ ...newProj, ngan: Number(e.target.value) })} />
                            <Input label="ตร.วา" type="number" value={newProj.sqWah || ''} onChange={(e: any) => setNewProj({ ...newProj, sqWah: Number(e.target.value) })} />
                        </div>
                        <Input label="ราคาเต็ม" type="number" value={newProj.fullPrice || ''} onChange={(e: any) => setNewProj({ ...newProj, fullPrice: Number(e.target.value) })} />
                        <Input label="มัดจำตั้งต้น" type="number" value={newProj.deposit || ''} onChange={(e: any) => setNewProj({ ...newProj, deposit: Number(e.target.value) })} />
                        <Button onClick={handleCreate} className="w-full">ยืนยัน</Button>
                    </div>
                </Card>
            )}
            {tab === 'Record' && (
                <Card className="p-6 max-w-xl mx-auto">
                    <h3 className="font-bold mb-4">บันทึกค่าใช้จ่าย</h3>
                    <div className="space-y-4">
                        <Select label="โครงการ" value={exp.id} onChange={(e: any) => setExp({ ...exp, id: e.target.value })}>
                            <option value="">-- เลือกโครงการ --</option>
                            {projects.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
                        </Select>
                        <Input label="รายการ" value={exp.desc} onChange={(e: any) => setExp({ ...exp, desc: e.target.value })} />
                        <Input label="จำนวนเงิน" type="number" value={exp.amount} onChange={(e: any) => setExp({ ...exp, amount: e.target.value })} />
                        <Button onClick={() => { onSave({ id: Date.now().toString(), date: exp.date, type: 'Expense', category: 'Land', description: `ที่ดิน: ${exp.desc}`, amount: Number(exp.amount), projectId: exp.id }); triggerSuccess(); }} className="w-full">บันทึก</Button>
                    </div>
                </Card>
            )}
        </div>
    );
};

export default LandModule;
