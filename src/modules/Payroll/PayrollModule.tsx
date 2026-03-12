import React, { useState, useMemo, useRef } from 'react';
import { CheckCircle2, History, FileCheck, Eye, XCircle, Printer, Download, Users, Plus, Minus, DownloadCloud } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import FormatNumber from '../../components/ui/FormatNumber';
import { getFirstDayOfMonth, getLastDayOfMonth, getToday, formatDateBE } from '../../utils';
import { Employee, Transaction } from '../../types';

interface PayrollModuleProps {
    employees: Employee[];
    transactions: Transaction[];
    onSaveTransaction: (t: Transaction) => void;
}

const PayrollModule = ({ employees, transactions, onSaveTransaction }: PayrollModuleProps) => {
    const [view, setView] = useState<'Calculate' | 'History'>('Calculate');
    const [range, setRange] = useState({ start: getFirstDayOfMonth(), end: getLastDayOfMonth() });
    const [search, setSearch] = useState('');
    const [selectedEmp, setSelectedEmp] = useState<any>(null);
    const [slipEmp, setSlipEmp] = useState<any>(null);

    // --- NEW: History Filters ---
    const [historySearch, setHistorySearch] = useState('');
    const [historyRange, setHistoryRange] = useState({ start: '2024-01-01', end: '2026-12-31' });
    const [viewHistoryItem, setViewHistoryItem] = useState<Transaction | null>(null);

    // --- NEW: Payroll Manual Adjustments ---
    // store by empId: { bonus: number, deduction: number, note: string }
    const [adjustments, setAdjustments] = useState<Record<string, { bonus: number, deduction: number, note: string }>>({});
    const [editingAdj, setEditingAdj] = useState<string | null>(null);

    // --- Helpers ---
    const setLastMonth = () => {
        const today = new Date();
        const firstDay = new Date(today.getFullYear(), today.getMonth() - 1, 1);
        const lastDay = new Date(today.getFullYear(), today.getMonth(), 0);
        setRange({ start: firstDay.toISOString().split('T')[0], end: lastDay.toISOString().split('T')[0] });
    };

    const setCurrentMonth = () => {
        const today = new Date();
        const firstDay = new Date(today.getFullYear(), today.getMonth(), 1);
        const lastDay = new Date(today.getFullYear(), today.getMonth() + 1, 0);
        setRange({ start: firstDay.toISOString().split('T')[0], end: lastDay.toISOString().split('T')[0] });
    };

    const getPayrollHistory = () => transactions.filter(t => t.category === 'Payroll').sort((a, b) => b.date.localeCompare(a.date));
    const checkOverlap = (empId: string, start: string, end: string) => transactions.some(t => t.category === 'Payroll' && t.employeeId === empId && t.payrollPeriod && (start <= t.payrollPeriod.end && end >= t.payrollPeriod.start));

    const calculatePayroll = (emp: Employee) => {
        const empTrans = transactions.filter(t => t.date >= range.start && t.date <= range.end && (t.employeeId === emp.id || t.employeeIds?.includes(emp.id)));
        const fullDays = empTrans.filter(t => t.laborStatus === 'Work' && (t.workType === 'FullDay' || !t.workType)).length;
        const halfDays = empTrans.filter(t => t.laborStatus === 'Work' && t.workType === 'HalfDay').length;
        const ot = empTrans.reduce((s, t) => s + (t.otAmount || 0), 0);
        const adv = empTrans.reduce((s, t) => s + (t.advanceAmount || 0), 0);
        const special = empTrans.reduce((s, t) => s + (t.specialAmount || 0), 0);

        const adj = adjustments[emp.id] || { bonus: 0, deduction: 0, note: '' };

        let basePay = emp.type === 'Monthly' ? emp.baseWage : (fullDays * emp.baseWage) + (halfDays * (emp.baseWage / 2));
        const totalIncome = basePay + ot + special + adj.bonus;
        const totalDeductions = adv + adj.deduction;
        const netPay = totalIncome - totalDeductions;
        const isPaid = checkOverlap(emp.id, range.start, range.end);

        return { ...emp, fullDays, halfDays, income: totalIncome, net: netPay, ot, adv, special, basePay, transactions: empTrans, isPaid, customBonus: adj.bonus, customDeduction: adj.deduction, adjNote: adj.note };
    };

    const payrollData = useMemo(() => employees.filter(e => e.name.toLowerCase().includes(search.toLowerCase()) || e.nickname.toLowerCase().includes(search.toLowerCase())).map(emp => calculatePayroll(emp)), [employees, transactions, range, search, adjustments]);

    const totalEstimatedPayroll = useMemo(() => payrollData.filter(p => !p.isPaid).reduce((sum, p) => sum + p.net, 0), [payrollData]);
    const unpaidCount = payrollData.filter(p => !p.isPaid).length;

    const handleConfirmPayment = (p: any, bypassAlert = false) => {
        if (p.isPaid) {
            if (!bypassAlert) alert(`จ่ายเงินให้ ${p.name} ซ้ำไม่ได้ (มีการจ่ายในงวดนี้ไปแล้ว)`);
            return false;
        }
        const payrollDetails = {
            fullDays: p.fullDays,
            halfDays: p.halfDays,
            basePay: p.basePay,
            ot: p.ot,
            special: p.special,
            adv: p.adv,
            customBonus: p.customBonus,
            customDeduction: p.customDeduction,
            adjNote: p.adjNote,
            net: p.net
        };
        onSaveTransaction({
            id: Date.now().toString() + Math.random().toString(36).substring(7),
            date: getToday(),
            type: 'Expense',
            category: 'Payroll',
            description: `เงินเดือน ${p.name} ${p.adjNote ? `(${p.adjNote})` : ''}`,
            amount: p.net,
            employeeId: p.id,
            payrollPeriod: { start: range.start, end: range.end },
            payrollSnapshot: payrollDetails
        } as Transaction);
        return true;
    };

    const handleBulkPay = () => {
        const unpaidEmps = payrollData.filter(p => !p.isPaid);
        if (unpaidEmps.length === 0) return alert('ไม่มีพนักงานที่รอจ่ายเงินเดือนในงวดนี้');

        const confirmMsg = `ต้องการยืนยันการจ่ายเงินเดือนให้พนักงาน ${unpaidEmps.length} คน\nยอดรวม ${totalEstimatedPayroll.toLocaleString()} บาท ใช่หรือไม่?`;
        if (confirm(confirmMsg)) {
            let successCount = 0;
            unpaidEmps.forEach(p => {
                const success = handleConfirmPayment(p, true);
                if (success) successCount++;
            });
            alert(`ทำรายการจ่ายเงินเดือนสำเร็จ ${successCount} รายการ`);
            setEditingAdj(null);
        }
    };

    const handleSaveAdjustment = (empId: string, b: number, d: number, n: string) => {
        setAdjustments(prev => ({ ...prev, [empId]: { bonus: b, deduction: d, note: n } }));
        setEditingAdj(null);
    };

    const filteredHistory = getPayrollHistory().filter(t => {
        const inDate = t.date >= historyRange.start && t.date <= historyRange.end;
        const inName = t.description.toLowerCase().includes(historySearch.toLowerCase());
        return inDate && inName;
    });

    const slipRef = useRef<HTMLDivElement>(null);
    const handlePrintSlip = () => {
        window.print();
    };

    return (
        <div className="space-y-6 animate-fade-in pb-20">
            {/* Header / Tabs */}
            <div className="flex flex-col sm:flex-row justify-between items-center bg-white p-4 rounded-2xl shadow-sm border border-slate-100 gap-4">
                <div className="flex bg-slate-100 p-1 rounded-xl w-full sm:w-auto">
                    <button
                        onClick={() => setView('Calculate')}
                        className={`flex-1 sm:flex-none px-6 py-2.5 rounded-lg text-sm font-bold transition-all ${view === 'Calculate' ? 'bg-white shadow text-emerald-600' : 'text-slate-500 hover:text-slate-700'}`}
                    >
                        จัดทำเงินเดือน
                    </button>
                    <button
                        onClick={() => setView('History')}
                        className={`flex-1 sm:flex-none px-6 py-2.5 rounded-lg text-sm font-bold transition-all ${view === 'History' ? 'bg-white shadow text-emerald-600' : 'text-slate-500 hover:text-slate-700'}`}
                    >
                        ประวัติการจ่าย
                    </button>
                </div>

                {view === 'Calculate' && unpaidCount > 0 && (
                    <Button onClick={handleBulkPay} className="w-full sm:w-auto bg-emerald-600 hover:bg-emerald-700 shadow-md shadow-emerald-500/20">
                        <CheckCircle2 className="mr-2" size={18} /> อนุมัติการจ่ายทั้งหมด ({unpaidCount} คน)
                    </Button>
                )}
            </div>

            {view === 'Calculate' ? (
                <>
                    {/* Summary Dashboard for Current Period */}
                    <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                        <Card className="p-5 flex items-center gap-4 bg-gradient-to-br from-emerald-50 to-teal-50 border-emerald-100/50">
                            <div className="w-12 h-12 rounded-full bg-emerald-100 text-emerald-600 flex items-center justify-center shrink-0">
                                <Users size={24} />
                            </div>
                            <div>
                                <p className="text-sm font-bold text-slate-500 uppercase tracking-wider">รอจ่ายงวดนี้</p>
                                <p className="text-2xl font-bold text-slate-800">{unpaidCount} <span className="text-sm font-normal text-slate-500">คน</span></p>
                            </div>
                        </Card>
                        <Card className="p-5 flex items-center gap-4 bg-gradient-to-br from-blue-50 to-indigo-50 border-blue-100/50 md:col-span-2">
                            <div className="w-12 h-12 rounded-full bg-blue-100 text-blue-600 flex items-center justify-center shrink-0">
                                <FormatNumber value={totalEstimatedPayroll} className="text-xl" />
                            </div>
                            <div className="flex-1">
                                <p className="text-sm font-bold text-slate-500 uppercase tracking-wider">ยอดรวมประเมินที่ต้องจ่าย (รออนุมัติ)</p>
                                <p className="text-3xl font-bold text-blue-700">฿{totalEstimatedPayroll.toLocaleString()}</p>
                            </div>
                        </Card>
                    </div>

                    {/* Filter Bar */}
                    <Card className="p-3 sm:p-4 flex flex-col sm:flex-row gap-3 sm:gap-4 items-stretch sm:items-center">
                        <Input placeholder="ค้นหาชื่อพนักงาน..." value={search} onChange={(e: any) => setSearch(e.target.value)} className="w-full sm:w-64" />
                        <div className="flex-1"></div>
                        <div className="flex flex-col sm:flex-row items-center gap-3">
                            <span className="text-sm font-bold text-slate-500 whitespace-nowrap">งวดที่จ่าย:</span>
                            <div className="flex items-center gap-2 bg-slate-50 p-1.5 rounded-xl border border-slate-200 w-full sm:w-auto">
                                <input type="date" value={range.start} onChange={(e) => setRange({ ...range, start: e.target.value })} className="bg-transparent text-sm font-medium text-slate-700 outline-none w-full sm:w-auto" />
                                <span className="text-slate-400">-</span>
                                <input type="date" value={range.end} onChange={(e) => setRange({ ...range, end: e.target.value })} className="bg-transparent text-sm font-medium text-slate-700 outline-none w-full sm:w-auto" />
                            </div>
                            <div className="flex gap-1 w-full sm:w-auto">
                                <button onClick={setCurrentMonth} className="flex-1 sm:flex-none px-3 py-1.5 text-xs font-bold bg-emerald-50 text-emerald-700 rounded-lg border border-emerald-200 hover:bg-emerald-100 whitespace-nowrap transition-colors">เดือนนี้</button>
                                <button onClick={setLastMonth} className="flex-1 sm:flex-none px-3 py-1.5 text-xs font-bold bg-white text-slate-600 rounded-lg border border-slate-200 hover:bg-slate-50 whitespace-nowrap transition-colors">เดือนก่อน</button>
                            </div>
                        </div>
                    </Card>

                    {/* Employee List */}
                    <div className="grid grid-cols-1 gap-4">
                        {payrollData.map(p => (
                            <Card key={p.id} className={`p-0 overflow-hidden border transition-all ${p.isPaid ? 'border-emerald-200 bg-emerald-50/30 opacity-75' : 'border-slate-200 bg-white hover:border-blue-300 hover:shadow-md'}`}>
                                <div className="p-4 sm:p-5 flex flex-col lg:flex-row justify-between items-start lg:items-center gap-4 sm:gap-6">
                                    <div className="flex items-center gap-4 w-full lg:w-1/3">
                                        <div className={`w-12 h-12 rounded-full flex items-center justify-center font-bold text-lg shrink-0 ${p.isPaid ? 'bg-emerald-100 text-emerald-600' : 'bg-blue-100 text-blue-600'}`}>
                                            {p.nickname.charAt(0)}
                                        </div>
                                        <div className="flex-1 min-w-0">
                                            <h4 className="font-bold text-lg text-slate-800 truncate">{p.nickname}</h4>
                                            <p className="text-sm text-slate-500 truncate">{p.type === 'Monthly' ? 'รายเดือน' : 'รายวัน'} • ฐาน ฿{p.baseWage}</p>
                                            {p.isPaid && <span className="inline-flex text-xs bg-emerald-100 text-emerald-700 font-bold items-center gap-1 px-2 py-0.5 rounded-full mt-1"><CheckCircle2 size={12} /> ยืนยันจ่ายแล้ว</span>}
                                        </div>
                                    </div>

                                    <div className="flex w-full lg:w-2/3 justify-between lg:justify-end items-center gap-4 sm:gap-8">
                                        <div className="text-center bg-slate-50 px-4 py-2 rounded-xl border border-slate-100 min-w-[100px]">
                                            <p className="text-slate-400 text-[10px] font-bold uppercase tracking-wider mb-1">วันทำงาน</p>
                                            <p className="font-bold text-slate-700">{p.fullDays} <span className="text-xs text-slate-500 font-normal">({p.halfDays} ครึ่ง)</span></p>
                                        </div>

                                        <div className="flex-1 grid grid-cols-2 gap-2 text-xs">
                                            <div className="text-right">
                                                <div className="text-slate-500">ฐาน + OT: <span className="font-bold text-slate-700">{(p.basePay + p.ot + p.special).toLocaleString()}</span></div>
                                                <div className="text-emerald-600">โบนัส: <span className="font-bold">+{p.customBonus.toLocaleString()}</span></div>
                                            </div>
                                            <div className="text-right">
                                                <div className="text-red-500">เบิกล่วงหน้า: <span className="font-bold">-{p.adv.toLocaleString()}</span></div>
                                                <div className="text-rose-600">หักอื่นๆ: <span className="font-bold">-{p.customDeduction.toLocaleString()}</span></div>
                                            </div>
                                        </div>

                                        <div className="text-right min-w-[120px]">
                                            <p className="text-slate-400 text-[10px] font-bold uppercase tracking-wider mb-0.5">ยอดสุทธิ</p>
                                            <p className={`font-bold text-2xl tracking-tight ${p.isPaid ? 'text-emerald-600' : 'text-blue-600'}`}><FormatNumber value={p.net} /></p>
                                        </div>
                                    </div>
                                </div>

                                {/* Action Bar for each employee */}
                                <div className={`flex flex-wrap items-center gap-2 p-3 bg-slate-50 border-t ${p.isPaid ? 'border-emerald-100 bg-emerald-100/20' : 'border-slate-100'}`}>
                                    <Button variant="ghost" onClick={() => setSelectedEmp(p)} className="text-sm px-4 py-1.5 hover:bg-white text-slate-600 shadow-sm border border-slate-200">
                                        <History size={14} className="mr-2" /> ดูข้อมูลดิบ
                                    </Button>

                                    {!p.isPaid && (
                                        <Button variant="ghost" onClick={() => setEditingAdj(p.id)} className="text-sm px-4 py-1.5 hover:bg-white text-amber-600 shadow-sm border border-slate-200">
                                            <Plus size={14} className="mr-1" /><Minus size={14} className="mr-1" /> ปรับยอด (โบนัส/หัก)
                                        </Button>
                                    )}

                                    <div className="flex-1"></div>

                                    <Button
                                        variant="outline"
                                        onClick={() => setSlipEmp(p)}
                                        className="text-sm px-4 py-1.5 bg-white border-slate-300 text-slate-700"
                                    >
                                        <Printer size={14} className="mr-2" /> พิมพ์สลิป
                                    </Button>

                                    {!p.isPaid && (
                                        <Button
                                            onClick={() => {
                                                if (confirm(`ยืนยันจ่ายเงินเดือน ${p.name} ยอด ${p.net.toLocaleString()} บาท?`)) {
                                                    handleConfirmPayment(p);
                                                    setSlipEmp(null);
                                                }
                                            }}
                                            className="text-sm px-6 py-1.5 bg-blue-600 hover:bg-blue-700 text-white shadow-md shadow-blue-500/20"
                                        >
                                            ยืนยันจ่ายคนนี้
                                        </Button>
                                    )}
                                </div>

                                {/* Edit Adjustment Panel (Inline) */}
                                {editingAdj === p.id && (
                                    <div className="p-4 bg-amber-50 border-t border-amber-100 animate-slide-down">
                                        <h5 className="font-bold text-amber-800 mb-3 text-sm">ปรับปรุงยอด (เพิ่มโบนัส / หักเงิน)</h5>
                                        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-4">
                                            <Input label="โบนัส/เบี้ยขยัน (+)" type="number" defaultValue={(adjustments[p.id]?.bonus || 0).toString()} id={`bonus-${p.id}`} className="bg-white" />
                                            <Input label="หักค่าสาย/ขาด/อื่นๆ (-)" type="number" defaultValue={(adjustments[p.id]?.deduction || 0).toString()} id={`deduction-${p.id}`} className="bg-white" />
                                            <Input label="หมายเหตุ (ถ้ามี)" type="text" defaultValue={adjustments[p.id]?.note || ''} id={`note-${p.id}`} className="bg-white" />
                                        </div>
                                        <div className="flex justify-end gap-2">
                                            <Button variant="ghost" onClick={() => setEditingAdj(null)} className="text-slate-500">ยกเลิก</Button>
                                            <Button onClick={() => {
                                                const b = parseFloat((document.getElementById(`bonus-${p.id}`) as HTMLInputElement).value) || 0;
                                                const d = parseFloat((document.getElementById(`deduction-${p.id}`) as HTMLInputElement).value) || 0;
                                                const n = (document.getElementById(`note-${p.id}`) as HTMLInputElement).value || '';
                                                handleSaveAdjustment(p.id, b, d, n);
                                            }} className="bg-amber-600 hover:bg-amber-700 text-white shadow-md">บันทึกยอดชั่วคราว</Button>
                                        </div>
                                    </div>
                                )}
                            </Card>
                        ))}
                    </div>
                </>
            ) : (
                <Card className="p-0 overflow-hidden">
                    <div className="p-4 sm:p-5 border-b bg-slate-50 flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
                        <span className="font-bold text-lg text-slate-800">ประวัติการจ่ายเงินเดือน</span>
                        <div className="flex flex-col sm:flex-row gap-3 w-full sm:w-auto">
                            <Input placeholder="ค้นหาชื่อพนักงาน..." value={historySearch} onChange={(e: any) => setHistorySearch(e.target.value)} className="w-full sm:w-48 text-sm" />
                            <div className="flex items-center gap-2 bg-white border border-slate-200 rounded-xl px-3 py-1.5 shadow-sm">
                                <input type="date" value={historyRange.start} onChange={e => setHistoryRange({ ...historyRange, start: e.target.value })} className="text-sm font-medium text-slate-600 outline-none w-full sm:w-auto bg-transparent" />
                                <span className="text-slate-300">-</span>
                                <input type="date" value={historyRange.end} onChange={e => setHistoryRange({ ...historyRange, end: e.target.value })} className="text-sm font-medium text-slate-600 outline-none w-full sm:w-auto bg-transparent" />
                            </div>
                        </div>
                    </div>
                    <div className="max-h-[600px] overflow-y-auto overflow-x-auto p-4">
                        <div className="grid grid-cols-1 gap-3">
                            {filteredHistory.length === 0 ? (
                                <div className="text-center py-10 text-slate-400">ไม่พบประวัติการจ่ายในช่วงเวลานี้</div>
                            ) : (
                                filteredHistory.map(t => (
                                    <div key={t.id} className="bg-white border border-slate-100 p-4 rounded-2xl flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 hover:shadow-md transition-shadow group">
                                        <div className="flex items-center gap-4">
                                            <div className="w-10 h-10 rounded-full bg-emerald-100 text-emerald-600 flex items-center justify-center font-bold">
                                                <CheckCircle2 size={20} />
                                            </div>
                                            <div>
                                                <div className="font-bold text-slate-800">{t.description}</div>
                                                <div className="text-xs font-medium text-slate-500 mt-0.5">
                                                    วันที่จ่าย: <span className="text-slate-700">{formatDateBE(t.date)}</span> •
                                                    งวด: <span className="text-slate-700">{t.payrollPeriod ? `${formatDateBE(t.payrollPeriod.start)} ถึง ${formatDateBE(t.payrollPeriod.end)}` : '-'}</span>
                                                </div>
                                            </div>
                                        </div>
                                        <div className="flex items-center w-full sm:w-auto justify-between sm:justify-end gap-6 bg-slate-50 sm:bg-transparent p-3 sm:p-0 rounded-xl">
                                            <div className="text-right">
                                                <div className="text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-0.5">ยอดสุทธิ</div>
                                                <div className="font-bold text-lg text-emerald-600"><FormatNumber value={t.amount} /></div>
                                            </div>
                                            <Button variant="ghost" onClick={() => setViewHistoryItem(t)} className="bg-white border shadow-sm px-3 hover:bg-slate-50 text-slate-600 group-hover:border-emerald-300">
                                                <Eye size={16} className="mr-2" /> เรียกดู
                                            </Button>
                                        </div>
                                    </div>
                                ))
                            )}
                        </div>
                    </div>
                </Card>
            )}

            {/* View History Detail Modal */}
            {viewHistoryItem && (
                <div className="fixed inset-0 bg-slate-900/60 backdrop-blur-sm flex items-center justify-center z-[110] p-4 font-sans">
                    <Card className="w-full max-w-md p-0 relative animate-slide-up overflow-hidden shadow-2xl border-0">
                        <div className="bg-slate-800 text-white p-6 pb-8 relative">
                            <button onClick={() => setViewHistoryItem(null)} className="absolute top-4 right-4 text-white/50 hover:text-white transition-colors bg-white/10 rounded-full p-1"><XCircle size={20} /></button>
                            <h3 className="text-lg font-bold opacity-90 mb-1">ใบสำคัญจ่ายเงินเดือน</h3>
                            <h2 className="text-2xl font-black">{viewHistoryItem.description.replace('เงินเดือน ', '')}</h2>
                            <div className="absolute -bottom-4 left-6 right-6 h-8 bg-white rounded-t-2xl"></div>
                        </div>
                        <div className="p-6 pt-2 bg-white space-y-4 text-slate-700">
                            <div className="grid grid-cols-2 gap-4 text-sm bg-slate-50 p-4 rounded-xl border border-slate-100">
                                <div><span className="block text-xs text-slate-400 font-bold uppercase mb-1">วันที่จ่าย</span><span className="font-bold">{formatDateBE(viewHistoryItem.date)}</span></div>
                                <div><span className="block text-xs text-slate-400 font-bold uppercase mb-1">งวดบัญชี</span><span className="font-bold">{viewHistoryItem.payrollPeriod ? `${formatDateBE(viewHistoryItem.payrollPeriod.start)} - ${formatDateBE(viewHistoryItem.payrollPeriod.end)}` : '-'}</span></div>
                            </div>

                            {viewHistoryItem.payrollSnapshot && (
                                <div className="space-y-0 text-sm border border-slate-100 rounded-xl overflow-hidden shadow-sm">
                                    <div className="bg-slate-50 px-4 py-2 font-bold text-slate-500 text-xs uppercase tracking-wider border-b">รายละเอียดรายได้</div>
                                    <div className="flex justify-between px-4 py-2.5 border-b"><span className="font-medium">ค่าแรง ({viewHistoryItem.payrollSnapshot.fullDays} วัน + {viewHistoryItem.payrollSnapshot.halfDays} ครึ่ง)</span><span>{viewHistoryItem.payrollSnapshot.basePay?.toLocaleString() || 0}</span></div>
                                    <div className="flex justify-between px-4 py-2.5 border-b"><span>ค่าล่วงเวลา (OT)</span><span>{viewHistoryItem.payrollSnapshot.ot?.toLocaleString() || 0}</span></div>
                                    <div className="flex justify-between px-4 py-2.5 border-b"><span>พิเศษอื่นๆ</span><span>{viewHistoryItem.payrollSnapshot.special?.toLocaleString() || 0}</span></div>
                                    <div className="flex justify-between px-4 py-2.5 border-b text-emerald-600 font-medium bg-emerald-50/30"><span>โบนัส / เบี้ยขยัน</span><span>+{viewHistoryItem.payrollSnapshot.customBonus?.toLocaleString() || 0}</span></div>

                                    <div className="bg-rose-50 px-4 py-2 font-bold text-rose-500 text-xs uppercase tracking-wider border-b border-t-4 border-t-white">รายการหัก</div>
                                    <div className="flex justify-between px-4 py-2.5 border-b"><span className="text-red-500">เบิกล่วงหน้า</span><span className="text-red-500">-{viewHistoryItem.payrollSnapshot.adv?.toLocaleString() || 0}</span></div>
                                    <div className="flex justify-between px-4 py-2.5 border-b bg-rose-50/30"><span className="text-rose-600">หักอื่นๆ (สาย/ขาด)</span><span className="text-rose-600">-{viewHistoryItem.payrollSnapshot.customDeduction?.toLocaleString() || 0}</span></div>
                                    {viewHistoryItem.payrollSnapshot.adjNote && (
                                        <div className="px-4 py-2 text-xs text-slate-400 italic bg-slate-50">หมายเหตุ: {viewHistoryItem.payrollSnapshot.adjNote}</div>
                                    )}
                                </div>
                            )}

                            <div className="flex justify-between items-center pt-4 pb-2">
                                <span className="text-sm font-bold text-slate-500 uppercase tracking-widest">ยอดสุทธิ (NET)</span>
                                <span className="text-3xl font-black text-emerald-600 tracking-tight"><FormatNumber value={viewHistoryItem.amount} /></span>
                            </div>
                        </div>
                    </Card>
                </div>
            )}

            {/* RAW DATA MODAL */}
            {selectedEmp && (<div className="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50 p-4"><Card className="w-full max-w-3xl p-0 overflow-hidden shadow-2xl flex flex-col max-h-[90vh]">
                <div className="flex justify-between items-center p-5 border-b bg-slate-50">
                    <div>
                        <h3 className="font-bold text-xl text-slate-800">ข้อมูลการลงงานดิบ: {selectedEmp.name}</h3>
                        <p className="text-xs text-slate-500 mt-1">ตั้งแต่วันที่ {formatDateBE(range.start)} ถึง {formatDateBE(range.end)}</p>
                    </div>
                    <button onClick={() => setSelectedEmp(null)} className="p-2 hover:bg-slate-200 rounded-full text-slate-500 transition-colors"><XCircle /></button>
                </div>
                <div className="overflow-y-auto p-0 flex-1 bg-white">
                    <table className="w-full text-sm text-left">
                        <thead className="bg-slate-100 text-slate-600 sticky top-0 shadow-sm">
                            <tr>
                                <th className="p-4 font-bold">วันที่</th>
                                <th className="p-4 font-bold">หมวดหมู่</th>
                                <th className="p-4 font-bold">รายละเอียด</th>
                                <th className="p-4 font-bold text-right">จำนวน/หน่วย</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-slate-100">
                            {selectedEmp.transactions.length === 0 ? (
                                <tr><td colSpan={4} className="p-8 text-center text-slate-400">ไม่มีข้อมูลการลงงานในช่วงนี้</td></tr>
                            ) : (
                                selectedEmp.transactions.map((t: Transaction) => (
                                    <tr key={t.id} className="hover:bg-slate-50 transition-colors">
                                        <td className="p-4 font-medium text-slate-700">{formatDateBE(t.date)}</td>
                                        <td className="p-4"><span className="px-2.5 py-1 bg-slate-100 text-slate-600 rounded-lg text-xs font-bold">{t.category}</span></td>
                                        <td className="p-4 text-slate-600">{t.description}</td>
                                        <td className="p-4 text-right font-bold text-slate-800">
                                            {t.laborStatus === 'Work' ? (t.workType === 'HalfDay' ? <span className="text-amber-600 bg-amber-50 px-2 py-0.5 rounded">0.5 วัน</span> : <span className="text-emerald-600 bg-emerald-50 px-2 py-0.5 rounded">1 วัน</span>) : (t.amount > 0 ? t.amount.toLocaleString() : '-')}
                                        </td>
                                    </tr>
                                ))
                            )}
                        </tbody>
                    </table>
                </div>
                <div className="p-4 bg-slate-50 border-t text-right">
                    <Button onClick={() => setSelectedEmp(null)} variant="outline" className="bg-white">ปิดหน้าต่าง</Button>
                </div>
            </Card></div>)}

            {/* PRINT SLIP MODAL */}
            {slipEmp && (
                <div className="fixed inset-0 bg-slate-900/80 backdrop-blur-md flex items-center justify-center z-[100] p-4 font-sans print:bg-white print:p-0 print:block overflow-y-auto">
                    {/* The Printable Area */}
                    <div className="w-full max-w-2xl mx-auto my-8 relative flex flex-col gap-6 print:m-0 print:max-w-none print:shadow-none">

                        {/* Action Buttons (Hidden on Print) */}
                        <div className="flex justify-end gap-3 print:hidden sticky top-4 z-10 w-full max-w-[800px] mx-auto px-4 mt-6">
                            <Button variant="outline" onClick={() => setSlipEmp(null)} className="bg-white text-slate-700 hover:bg-slate-100 border-none shadow-lg">
                                ปิดหน้าต่าง
                            </Button>
                            {!slipEmp.isPaid && (
                                <Button onClick={() => {
                                    handleConfirmPayment(slipEmp);
                                    setSlipEmp(null);
                                }} className="bg-emerald-500 text-white shadow-lg hover:bg-emerald-600 border border-emerald-400">
                                    <CheckCircle2 size={16} className="mr-2" /> ยืนยันจ่ายเงิน
                                </Button>
                            )}
                            <Button onClick={handlePrintSlip} className="bg-blue-600 text-white shadow-lg hover:bg-blue-700">
                                <Printer size={16} className="mr-2" /> พิมพ์สลิป (A4)
                            </Button>
                        </div>

                        {/* Slip Template 1 (For Employee) */}
                        <Card className="w-full p-0 overflow-hidden shadow-2xl bg-white border border-slate-200 print:shadow-none print:border-none print:rounded-none" id="print-slip" ref={slipRef}>
                            {/* Header */}
                            <div className="bg-slate-800 text-white p-6 sm:p-8 flex justify-between items-center print:bg-slate-100 print:text-black print:border-b-2 print:border-slate-800">
                                <div>
                                    <h2 className="text-2xl sm:text-3xl font-black mb-1">ใบแจ้งเงินเดือน</h2>
                                    <p className="text-white/70 print:text-slate-500 font-medium tracking-widest text-xs uppercase">PAYSLIP</p>
                                </div>
                                <div className="text-right">
                                    <h1 className="text-xl sm:text-2xl font-bold text-amber-500 print:text-slate-800 tracking-tight">GOLDENMOLE</h1>
                                    <p className="text-xs text-white/50 print:text-slate-400 font-medium">Construction & Sandbox</p>
                                </div>
                            </div>

                            {/* Employee Info Box */}
                            <div className="px-6 sm:px-8 py-6 bg-slate-50 border-b flex flex-col sm:flex-row gap-6 print:bg-white justify-between">
                                <div className="flex flex-col">
                                    <p className="text-xs font-bold text-slate-400 uppercase tracking-widest mb-1 mt-0">ชื่อพนักงาน</p>
                                    <p className="text-xl font-bold text-slate-800">{slipEmp.nickname}</p>
                                </div>
                                <div className="flex flex-col text-left sm:text-right">
                                    <p className="text-xs font-bold text-slate-400 uppercase tracking-widest mb-1 mt-0">งวดที่จ่าย (Period)</p>
                                    <p className="text-base font-bold text-slate-800">{formatDateBE(range.start)} - {formatDateBE(range.end)}</p>
                                </div>
                            </div>

                            <div className="p-6 sm:p-8 grid grid-cols-1 md:grid-cols-2 gap-8 sm:gap-12">
                                {/* Left Column: Earnings */}
                                <div>
                                    <h4 className="font-bold text-sm text-slate-800 border-b-2 border-slate-200 pb-2 mb-4 uppercase tracking-wider flex items-center justify-between">
                                        <span>รายได้ (Earnings)</span>
                                        <span className="text-xs text-slate-400 font-normal">บาท (THB)</span>
                                    </h4>
                                    <div className="space-y-4 text-sm font-medium text-slate-600">
                                        <div className="flex justify-between items-center bg-slate-50/50 p-2 rounded">
                                            <span>ค่าแรงปกติ <span className="text-xs text-slate-400 block font-normal">{slipEmp.fullDays} วัน, {slipEmp.halfDays} ครึ่ง (ฐาน ฿{slipEmp.baseWage})</span></span>
                                            <span className="font-bold text-slate-800 text-base">{slipEmp.basePay.toLocaleString(undefined, { minimumFractionDigits: 2 })}</span>
                                        </div>
                                        <div className="flex justify-between items-center p-2">
                                            <span>ค่าล่วงเวลา (OT)</span>
                                            <span className="font-bold text-slate-800 text-base">{slipEmp.ot.toLocaleString(undefined, { minimumFractionDigits: 2 })}</span>
                                        </div>
                                        <div className="flex justify-between items-center bg-slate-50/50 p-2 rounded">
                                            <span>รายได้พิเศษอื่นๆ</span>
                                            <span className="font-bold text-slate-800 text-base">{slipEmp.special.toLocaleString(undefined, { minimumFractionDigits: 2 })}</span>
                                        </div>
                                        {(slipEmp.customBonus > 0) && (
                                            <div className="flex justify-between items-center p-2 text-emerald-600 bg-emerald-50 rounded">
                                                <span>โบนัส / เบี้ยขยัน</span>
                                                <span className="font-bold text-base">+{slipEmp.customBonus.toLocaleString(undefined, { minimumFractionDigits: 2 })}</span>
                                            </div>
                                        )}
                                    </div>
                                    <div className="mt-6 pt-4 border-t-2 border-slate-800 flex justify-between items-center">
                                        <span className="font-bold text-slate-800">รวมรายได้ (Total Earnings)</span>
                                        <span className="text-xl font-bold text-slate-800">{slipEmp.income.toLocaleString(undefined, { minimumFractionDigits: 2 })}</span>
                                    </div>
                                </div>

                                {/* Right Column: Deductions */}
                                <div>
                                    <h4 className="font-bold text-sm text-rose-600 border-b-2 border-rose-200 pb-2 mb-4 uppercase tracking-wider flex items-center justify-between">
                                        <span>รายการหัก (Deductions)</span>
                                        <span className="text-xs text-rose-400 font-normal">บาท (THB)</span>
                                    </h4>
                                    <div className="space-y-4 text-sm font-medium text-slate-600">
                                        <div className="flex justify-between items-center bg-rose-50/50 p-2 rounded">
                                            <span>เบิกล่วงหน้า (Advance)</span>
                                            <span className="font-bold text-rose-600 text-base">{slipEmp.adv.toLocaleString(undefined, { minimumFractionDigits: 2 })}</span>
                                        </div>
                                        {(slipEmp.customDeduction > 0) && (
                                            <div className="flex justify-between items-center p-2 bg-rose-50 rounded">
                                                <span>หักอื่นๆ (สาย/ขาด/ลา)</span>
                                                <span className="font-bold text-rose-600 text-base">{slipEmp.customDeduction.toLocaleString(undefined, { minimumFractionDigits: 2 })}</span>
                                            </div>
                                        )}
                                        {slipEmp.adjNote && (
                                            <div className="text-xs text-slate-400 italic px-2">หมายเหตุหัก: {slipEmp.adjNote}</div>
                                        )}
                                    </div>
                                    <div className="mt-6 pt-4 border-t-2 border-rose-600 flex justify-between items-center">
                                        <span className="font-bold text-rose-600">รวมรายการหัก (Total Deductions)</span>
                                        <span className="text-xl font-bold text-rose-600">{(slipEmp.adv + slipEmp.customDeduction).toLocaleString(undefined, { minimumFractionDigits: 2 })}</span>
                                    </div>
                                </div>
                            </div>

                            {/* Net Pay Footer */}
                            <div className="bg-emerald-50 px-6 sm:px-8 py-6 border-t border-emerald-200 flex flex-col sm:flex-row justify-between items-center gap-4 print:bg-white print:border-t-2 print:border-slate-800 print:mt-8">
                                <div>
                                    <p className="text-xs font-bold text-emerald-600 uppercase tracking-widest mb-1 print:text-slate-800">ยอดสุทธิที่ต้องชำระ (Net Pay)</p>
                                    <p className="text-sm font-medium text-emerald-700/80 print:text-slate-500">จ่ายสุทธิ โอนเข้าบัญชี หรือ จ่ายเงินสด</p>
                                </div>
                                <div className="text-4xl sm:text-5xl font-black text-emerald-600 tracking-tighter print:text-slate-900 border-b-[3px] border-emerald-600 print:border-slate-800 pb-1">
                                    <FormatNumber value={slipEmp.net} />
                                </div>
                            </div>

                            {/* Signatures */}
                            <div className="px-6 sm:px-8 pt-16 pb-12 grid grid-cols-2 gap-16 text-center text-sm">
                                <div className="space-y-4">
                                    <div className="border-b border-dashed border-slate-400 mx-8"></div>
                                    <div className="space-y-1">
                                        <p className="font-bold text-slate-700">ผู้รับเงิน (Employee)</p>
                                        <p className="text-xs text-slate-400">วันที่ ............/............/............</p>
                                    </div>
                                </div>
                                <div className="space-y-4">
                                    <div className="border-b border-dashed border-slate-400 mx-8"></div>
                                    <div className="space-y-1">
                                        <p className="font-bold text-slate-700">ผู้อนุมัติ (Authorized Signature)</p>
                                        <p className="text-xs text-slate-400">วันที่ ............/............/............</p>
                                    </div>
                                </div>
                            </div>
                        </Card>

                    </div>

                    {/* Print CSS hiding rule */}
                    <style dangerouslySetInnerHTML={{
                        __html: `
                        @media print {
                            body * {
                                visibility: hidden;
                            }
                            #print-slip, #print-slip * {
                                visibility: visible;
                            }
                            #print-slip {
                                position: absolute;
                                left: 0;
                                top: 0;
                                width: 100%;
                            }
                        }
                    `}} />
                </div>
            )}
        </div>
    );
};

export default PayrollModule;
