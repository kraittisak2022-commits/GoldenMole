import React, { useState, useMemo, useRef } from 'react';
import { CheckCircle2, History, Eye, XCircle, Printer, Users, Plus, Minus, Banknote, Calendar, Wallet } from 'lucide-react';
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

/** คำนวณแบงค์จ่าย (1000, 500, 100) จากยอดบาท */
function getBanknoteBreakdown(amount: number): { b1000: number; b500: number; b100: number; remainder: number } {
    const a = Math.round(amount);
    const b1000 = Math.floor(a / 1000);
    let r = a % 1000;
    const b500 = Math.floor(r / 500);
    r = r % 500;
    const b100 = Math.floor(r / 100);
    const remainder = r % 100;
    return { b1000, b500, b100, remainder };
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
        const isHalfDay = (t: Transaction) => {
            if (t.laborStatus !== 'Work') return false;
            if (t.workTypeByEmployee && emp.id in t.workTypeByEmployee) return t.workTypeByEmployee[emp.id] === 'HalfDay';
            return t.workType === 'HalfDay';
        };
        const fullDays = empTrans.filter(t => t.laborStatus === 'Work' && !isHalfDay(t)).length;
        const halfDays = empTrans.filter(t => isHalfDay(t)).length;
        const ot = empTrans.reduce((s, t) => s + (t.otAmount || 0), 0);
        const adv = empTrans.reduce((s, t) => s + (t.advanceAmount || 0), 0);
        const special = empTrans.reduce((s, t) => s + (t.specialAmount || 0), 0);

        const adj = adjustments[emp.id] || { bonus: 0, deduction: 0, note: '' };

        const base = emp.baseWage ?? 0;
        let basePay = emp.type === 'Monthly' ? base : (fullDays * base) + (halfDays * (base / 2));
        const totalIncome = basePay + ot + special + adj.bonus;
        const totalDeductions = adv + adj.deduction;
        const netPay = totalIncome - totalDeductions;
        const isPaid = checkOverlap(emp.id, range.start, range.end);

        return { ...emp, fullDays, halfDays, income: totalIncome, net: netPay, ot, adv, special, basePay, transactions: empTrans, isPaid, customBonus: adj.bonus, customDeduction: adj.deduction, adjNote: adj.note };
    };

    const payrollData = useMemo(() => employees.filter(e => e.name.toLowerCase().includes(search.toLowerCase()) || e.nickname.toLowerCase().includes(search.toLowerCase())).map(emp => calculatePayroll(emp)), [employees, transactions, range, search, adjustments]);

    const totalEstimatedPayroll = useMemo(() => payrollData.filter(p => !p.isPaid).reduce((sum, p) => sum + p.net, 0), [payrollData]);
    const unpaidCount = payrollData.filter(p => !p.isPaid).length;
    const paidInPeriod = payrollData.filter(p => p.isPaid);
    const paidCount = paidInPeriod.length;
    const totalPaidInPeriod = useMemo(() => paidInPeriod.reduce((sum, p) => sum + p.net, 0), [payrollData]);

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
        <div className="space-y-6 animate-fade-in pb-20 font-[family-name:var(--font-prompt)]">
            {/* Page title */}
            <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
                <div className="flex items-center gap-3">
                    <div className="w-12 h-12 rounded-2xl bg-gradient-to-br from-emerald-500 to-teal-600 flex items-center justify-center shadow-lg shadow-emerald-500/25 text-white">
                        <Banknote size={26} />
                    </div>
                    <div>
                        <h1 className="text-2xl font-bold text-slate-800 tracking-tight">เงินเดือน</h1>
                        <p className="text-sm text-slate-500">จัดทำเงินเดือนและประวัติการจ่าย</p>
                    </div>
                </div>
            </div>

            {/* Tabs */}
            <div className="flex flex-col sm:flex-row justify-between items-stretch sm:items-center gap-4">
                <div className="flex bg-slate-100/80 p-1.5 rounded-xl w-full sm:w-auto border border-slate-200/60">
                    <button
                        onClick={() => setView('Calculate')}
                        className={`flex-1 sm:flex-none px-5 py-3 rounded-lg text-sm font-bold transition-all duration-200 ${view === 'Calculate' ? 'bg-white shadow-md text-emerald-700 border border-emerald-100' : 'text-slate-500 hover:text-slate-700 hover:bg-white/50'}`}
                    >
                        <span className="flex items-center justify-center gap-2">
                            <Wallet size={18} /> จัดทำเงินเดือน
                        </span>
                    </button>
                    <button
                        onClick={() => setView('History')}
                        className={`flex-1 sm:flex-none px-5 py-3 rounded-lg text-sm font-bold transition-all duration-200 ${view === 'History' ? 'bg-white shadow-md text-emerald-700 border border-emerald-100' : 'text-slate-500 hover:text-slate-700 hover:bg-white/50'}`}
                    >
                        <span className="flex items-center justify-center gap-2">
                            <History size={18} /> ประวัติการจ่าย
                        </span>
                    </button>
                </div>

                {view === 'Calculate' && unpaidCount > 0 && (
                    <Button onClick={handleBulkPay} className="w-full sm:w-auto bg-emerald-600 hover:bg-emerald-700 shadow-lg shadow-emerald-500/25 text-white font-bold">
                        <CheckCircle2 className="mr-2" size={20} /> อนุมัติจ่ายทั้งหมด ({unpaidCount} คน)
                    </Button>
                )}
            </div>

            {view === 'Calculate' ? (
                <>
                    {/* Summary cards */}
                    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
                        <Card className="p-5 flex items-center gap-4 bg-gradient-to-br from-slate-50 to-slate-100/50 border-slate-200/60">
                            <div className="w-14 h-14 rounded-2xl bg-slate-200/80 text-slate-600 flex items-center justify-center shrink-0">
                                <Users size={28} />
                            </div>
                            <div className="min-w-0">
                                <p className="text-xs font-bold text-slate-500 uppercase tracking-wider">พนักงานทั้งหมด (งวดนี้)</p>
                                <p className="text-2xl font-bold text-slate-800">{payrollData.length} <span className="text-sm font-normal text-slate-500">คน</span></p>
                            </div>
                        </Card>
                        <Card className="p-5 flex items-center gap-4 bg-gradient-to-br from-amber-50 to-orange-50/50 border-amber-200/50">
                            <div className="w-14 h-14 rounded-2xl bg-amber-100 text-amber-600 flex items-center justify-center shrink-0">
                                <Wallet size={28} />
                            </div>
                            <div className="min-w-0">
                                <p className="text-xs font-bold text-amber-700/80 uppercase tracking-wider">รอจ่าย</p>
                                <p className="text-2xl font-bold text-slate-800">{unpaidCount} <span className="text-sm font-normal text-slate-500">คน</span></p>
                            </div>
                        </Card>
                        <Card className="p-5 flex items-center gap-4 bg-gradient-to-br from-blue-50 to-indigo-50/50 border-blue-200/50">
                            <div className="w-14 h-14 rounded-2xl bg-blue-100 text-blue-600 flex items-center justify-center shrink-0">
                                <Banknote size={28} />
                            </div>
                            <div className="min-w-0">
                                <p className="text-xs font-bold text-blue-700/80 uppercase tracking-wider">ยอดรอจ่าย (ประเมิน)</p>
                                <p className="text-xl font-bold text-blue-700">฿{totalEstimatedPayroll.toLocaleString()}</p>
                            </div>
                        </Card>
                        <Card className="p-5 flex items-center gap-4 bg-gradient-to-br from-emerald-50 to-teal-50/50 border-emerald-200/50">
                            <div className="w-14 h-14 rounded-2xl bg-emerald-100 text-emerald-600 flex items-center justify-center shrink-0">
                                <CheckCircle2 size={28} />
                            </div>
                            <div className="min-w-0">
                                <p className="text-xs font-bold text-emerald-700/80 uppercase tracking-wider">จ่ายแล้วในงวดนี้</p>
                                <p className="text-2xl font-bold text-slate-800">{paidCount} <span className="text-sm font-normal text-slate-500">คน</span> · ฿{totalPaidInPeriod.toLocaleString()}</p>
                            </div>
                        </Card>
                    </div>

                    {/* แบงค์จ่ายในงวดนี้ (ยอดรอจ่าย) */}
                    {unpaidCount > 0 && totalEstimatedPayroll > 0 && (() => {
                        const bank = getBanknoteBreakdown(totalEstimatedPayroll);
                        return (
                            <Card className="p-4 sm:p-5 border-2 border-amber-200/60 bg-gradient-to-r from-amber-50/80 to-orange-50/50">
                                <div className="flex flex-wrap items-center gap-4 sm:gap-6">
                                    <div className="flex items-center gap-2">
                                        <Banknote className="text-amber-600 shrink-0" size={24} />
                                        <span className="font-bold text-slate-800">แบงค์จ่ายในงวดนี้ (ยอดรอจ่าย)</span>
                                    </div>
                                    <div className="flex flex-wrap items-center gap-4 text-sm">
                                        <span className="font-semibold text-slate-700">ยอดจ่ายรวม: <span className="text-lg text-amber-700">฿{totalEstimatedPayroll.toLocaleString()}</span></span>
                                        <span className="px-3 py-1.5 rounded-xl bg-amber-100 text-amber-800 font-bold">แบงค์ 1,000 × {bank.b1000}</span>
                                        <span className="px-3 py-1.5 rounded-xl bg-amber-100 text-amber-800 font-bold">แบงค์ 500 × {bank.b500}</span>
                                        <span className="px-3 py-1.5 rounded-xl bg-amber-100 text-amber-800 font-bold">แบงค์ 100 × {bank.b100}</span>
                                        {bank.remainder > 0 && <span className="px-3 py-1.5 rounded-xl bg-slate-100 text-slate-600 font-medium">เศษ {bank.remainder} บาท</span>}
                                    </div>
                                </div>
                            </Card>
                        );
                    })()}

                    {/* Filter Bar */}
                    <Card className="p-4 flex flex-col sm:flex-row gap-4 items-stretch sm:items-center border-slate-200/60">
                        <div className="flex-1 min-w-0">
                            <Input placeholder="ค้นหาชื่อ หรือชื่อเล่นพนักงาน..." value={search} onChange={(e: any) => setSearch(e.target.value)} className="w-full sm:max-w-xs" />
                        </div>
                        <div className="flex flex-col sm:flex-row items-stretch sm:items-center gap-3 flex-wrap">
                            <span className="text-sm font-bold text-slate-600 flex items-center gap-1.5"><Calendar size={16} /> งวดที่จ่าย:</span>
                            <div className="flex items-center gap-2 bg-slate-50 p-2 rounded-xl border border-slate-200">
                                <input type="date" value={range.start} onChange={(e) => setRange({ ...range, start: e.target.value })} className="bg-transparent text-sm font-medium text-slate-700 outline-none min-w-0" />
                                <span className="text-slate-400 font-medium">ถึง</span>
                                <input type="date" value={range.end} onChange={(e) => setRange({ ...range, end: e.target.value })} className="bg-transparent text-sm font-medium text-slate-700 outline-none min-w-0" />
                            </div>
                            <div className="flex gap-2">
                                <button onClick={setCurrentMonth} className="px-4 py-2 text-sm font-bold bg-emerald-100 text-emerald-700 rounded-xl border border-emerald-200 hover:bg-emerald-200/80 transition-colors">เดือนนี้</button>
                                <button onClick={setLastMonth} className="px-4 py-2 text-sm font-bold bg-slate-100 text-slate-600 rounded-xl border border-slate-200 hover:bg-slate-200 transition-colors">เดือนก่อน</button>
                            </div>
                        </div>
                    </Card>

                    {/* Employee List */}
                    <div className="space-y-4">
                        <h2 className="text-lg font-bold text-slate-700 flex items-center gap-2">
                            <Users size={20} /> รายชื่อพนักงาน ({payrollData.length} คน)
                        </h2>
                        {payrollData.map(p => (
                            <Card key={p.id} className={`p-0 overflow-hidden border-2 transition-all duration-200 ${p.isPaid ? 'border-emerald-200 bg-emerald-50/40' : 'border-slate-200 bg-white hover:border-emerald-200/80 hover:shadow-lg'}`}>
                                <div className="p-5 flex flex-col gap-5">
                                    {/* Row 1: Identity + Status + Net */}
                                    <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
                                        <div className="flex items-center gap-4 min-w-0">
                                            <div className={`w-14 h-14 rounded-2xl flex items-center justify-center font-bold text-xl shrink-0 ${p.isPaid ? 'bg-emerald-100 text-emerald-700' : 'bg-slate-100 text-slate-600'}`}>
                                                {p.nickname.charAt(0)}
                                            </div>
                                            <div className="min-w-0">
                                                <h4 className="font-bold text-lg text-slate-800 truncate">{p.name}</h4>
                                                <p className="text-sm text-slate-500 truncate">{p.nickname !== p.name ? `ชื่อเรียก: ${p.nickname}` : ''}</p>
                                                <div className="flex flex-wrap items-center gap-2 mt-1">
                                                    <span className="text-xs font-medium px-2.5 py-0.5 rounded-lg bg-slate-100 text-slate-600">{p.type === 'Monthly' ? 'รายเดือน' : 'รายวัน'}</span>
                                                    {(p.positions?.length ? p.positions : p.position ? [p.position] : []).map((pos, i) => (
                                                        <span key={i} className="text-xs font-medium px-2.5 py-0.5 rounded-lg bg-blue-50 text-blue-700">{pos}</span>
                                                    ))}
                                                    {p.isPaid && <span className="inline-flex text-xs bg-emerald-100 text-emerald-700 font-bold items-center gap-1 px-2.5 py-1 rounded-full"><CheckCircle2 size={12} /> จ่ายแล้ว</span>}
                                                </div>
                                            </div>
                                        </div>
                                        <div className="text-left md:text-right shrink-0">
                                            <p className="text-xs font-bold text-slate-500 uppercase tracking-wider mb-0.5">ยอดสุทธิ (บาท)</p>
                                            <p className={`font-bold text-2xl tracking-tight ${p.isPaid ? 'text-emerald-600' : 'text-slate-800'}`}>฿<FormatNumber value={p.net} /></p>
                                        </div>
                                    </div>

                                    {/* Row 2: Full breakdown */}
                                    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 pt-4 border-t border-slate-100">
                                        <div className="bg-slate-50 rounded-xl p-3 border border-slate-100">
                                            <p className="text-[10px] font-bold text-slate-500 uppercase tracking-wider mb-1">วันทำงาน</p>
                                            <p className="font-bold text-slate-800">{p.fullDays} วันเต็ม{p.halfDays > 0 ? ` + ${p.halfDays} ครึ่งวัน` : ''}</p>
                                            <p className="text-xs text-slate-500 mt-0.5">ฐาน ฿{(p.baseWage ?? 0).toLocaleString()}/{p.type === 'Monthly' ? 'เดือน' : 'วัน'}</p>
                                        </div>
                                        <div className="bg-green-50/50 rounded-xl p-3 border border-green-100">
                                            <p className="text-[10px] font-bold text-slate-500 uppercase tracking-wider mb-1">รายได้</p>
                                            <p className="text-sm text-slate-700">ค่าแรง: ฿{(p.basePay ?? 0).toLocaleString()}</p>
                                            <p className="text-sm text-slate-700">OT: ฿{(p.ot ?? 0).toLocaleString()} · พิเศษ: ฿{(p.special ?? 0).toLocaleString()}</p>
                                            {((p.customBonus ?? 0) > 0) && <p className="text-sm text-emerald-600 font-medium">โบนัส: +฿{(p.customBonus ?? 0).toLocaleString()}</p>}
                                        </div>
                                        <div className="bg-rose-50/50 rounded-xl p-3 border border-rose-100">
                                            <p className="text-[10px] font-bold text-slate-500 uppercase tracking-wider mb-1">รายการหัก</p>
                                            <p className="text-sm text-slate-700">เบิกล่วงหน้า: ฿{(p.adv ?? 0).toLocaleString()}</p>
                                            {((p.customDeduction ?? 0) > 0) && <p className="text-sm text-rose-600 font-medium">หักอื่นๆ: ฿{(p.customDeduction ?? 0).toLocaleString()}</p>}
                                        </div>
                                        <div className="bg-slate-50 rounded-xl p-3 border border-slate-100 flex flex-col justify-center">
                                            <p className="text-[10px] font-bold text-slate-500 uppercase tracking-wider mb-1">รวมรายได้ - หัก</p>
                                            <p className="text-sm text-slate-600">รวมรายได้: ฿{(p.income ?? 0).toLocaleString()}</p>
                                            <p className="text-sm text-slate-600">รวมหัก: ฿{((p.adv ?? 0) + (p.customDeduction ?? 0)).toLocaleString()}</p>
                                        </div>
                                    </div>
                                    {/* แบงค์จ่าย (ยอดสุทธิ) - แต่ละคน */}
                                    <div className="rounded-xl p-3 border border-amber-200/60 bg-amber-50/50 flex flex-wrap items-center gap-3">
                                        {(() => {
                                            const bank = getBanknoteBreakdown(p.net ?? 0);
                                            return (
                                                <>
                                                    <span className="text-[10px] font-bold text-amber-700 uppercase tracking-wider">แบงค์จ่าย (ยอด ฿{(p.net ?? 0).toLocaleString()})</span>
                                                    <span className="px-2.5 py-1 rounded-lg bg-amber-100 text-amber-800 font-bold text-sm">แบงค์ 1,000 × {bank.b1000}</span>
                                                    <span className="px-2.5 py-1 rounded-lg bg-amber-100 text-amber-800 font-bold text-sm">แบงค์ 500 × {bank.b500}</span>
                                                    <span className="px-2.5 py-1 rounded-lg bg-amber-100 text-amber-800 font-bold text-sm">แบงค์ 100 × {bank.b100}</span>
                                                    {bank.remainder > 0 && <span className="text-slate-600 text-sm font-medium">เศษ {bank.remainder} บาท</span>}
                                                </>
                                            );
                                        })()}
                                    </div>
                                    {p.adjNote && (
                                        <div className="text-xs text-slate-500 italic bg-amber-50 border border-amber-100 rounded-lg px-3 py-2">หมายเหตุ: {p.adjNote}</div>
                                    )}
                                </div>

                                {/* Action Bar */}
                                <div className={`flex flex-wrap items-center gap-2 p-4 border-t ${p.isPaid ? 'border-emerald-100 bg-emerald-50/30' : 'border-slate-100 bg-slate-50/50'}`}>
                                    <Button variant="ghost" onClick={() => setSelectedEmp(p)} className="text-sm px-4 py-2 hover:bg-white text-slate-600 border border-slate-200 rounded-xl">
                                        <History size={16} className="mr-2" /> ดูข้อมูลดิบ
                                    </Button>
                                    {!p.isPaid && (
                                        <Button variant="ghost" onClick={() => setEditingAdj(p.id)} className="text-sm px-4 py-2 hover:bg-amber-50 text-amber-700 border border-amber-200 rounded-xl">
                                            <Plus size={16} className="mr-1" /><Minus size={16} className="mr-1" /> ปรับยอด (โบนัส/หัก)
                                        </Button>
                                    )}
                                    <div className="flex-1" />
                                    <Button variant="outline" onClick={() => setSlipEmp(p)} className="text-sm px-4 py-2 bg-white border-slate-300 text-slate-700 rounded-xl">
                                        <Printer size={16} className="mr-2" /> พิมพ์สลิป
                                    </Button>
                                    {!p.isPaid && (
                                        <Button onClick={() => { if (confirm(`ยืนยันจ่ายเงินเดือน ${p.name} ยอด ฿${p.net.toLocaleString()} บาท?`)) { handleConfirmPayment(p); setSlipEmp(null); } }} className="text-sm px-5 py-2 bg-emerald-600 hover:bg-emerald-700 text-white rounded-xl shadow-md">
                                            ยืนยันจ่ายคนนี้
                                        </Button>
                                    )}
                                </div>

                                {editingAdj === p.id && (
                                    <div className="p-5 bg-amber-50/80 border-t-2 border-amber-200 animate-slide-down">
                                        <h5 className="font-bold text-amber-800 mb-3">ปรับปรุงยอด (โบนัส / หัก)</h5>
                                        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-4">
                                            <Input label="โบนัส/เบี้ยขยัน (+ บาท)" type="number" defaultValue={(adjustments[p.id]?.bonus || 0).toString()} id={`bonus-${p.id}`} className="bg-white" />
                                            <Input label="หักค่าสาย/ขาด/อื่นๆ (- บาท)" type="number" defaultValue={(adjustments[p.id]?.deduction || 0).toString()} id={`deduction-${p.id}`} className="bg-white" />
                                            <Input label="หมายเหตุ" type="text" defaultValue={adjustments[p.id]?.note || ''} id={`note-${p.id}`} className="bg-white" />
                                        </div>
                                        <div className="flex justify-end gap-2">
                                            <Button variant="ghost" onClick={() => setEditingAdj(null)} className="text-slate-600">ยกเลิก</Button>
                                            <Button onClick={() => {
                                                const b = parseFloat((document.getElementById(`bonus-${p.id}`) as HTMLInputElement)?.value || '0') || 0;
                                                const d = parseFloat((document.getElementById(`deduction-${p.id}`) as HTMLInputElement)?.value || '0') || 0;
                                                const n = (document.getElementById(`note-${p.id}`) as HTMLInputElement)?.value || '';
                                                handleSaveAdjustment(p.id, b, d, n);
                                            }} className="bg-amber-600 hover:bg-amber-700 text-white rounded-xl">บันทึก</Button>
                                        </div>
                                    </div>
                                )}
                            </Card>
                        ))}
                    </div>
                </>
            ) : (
                <Card className="p-0 overflow-hidden border-slate-200/60">
                    <div className="p-5 border-b border-slate-200 bg-gradient-to-r from-slate-50 to-white flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
                        <h2 className="font-bold text-xl text-slate-800 flex items-center gap-2">
                            <History size={22} /> ประวัติการจ่ายเงินเดือน
                        </h2>
                        <div className="flex flex-col sm:flex-row gap-3 w-full sm:w-auto">
                            <Input placeholder="ค้นหาชื่อพนักงาน..." value={historySearch} onChange={(e: any) => setHistorySearch(e.target.value)} className="w-full sm:w-56 text-sm" />
                            <div className="flex items-center gap-2 bg-white border border-slate-200 rounded-xl px-3 py-2">
                                <Calendar size={16} className="text-slate-400 shrink-0" />
                                <input type="date" value={historyRange.start} onChange={e => setHistoryRange({ ...historyRange, start: e.target.value })} className="text-sm font-medium text-slate-600 outline-none bg-transparent min-w-0" />
                                <span className="text-slate-300">–</span>
                                <input type="date" value={historyRange.end} onChange={e => setHistoryRange({ ...historyRange, end: e.target.value })} className="text-sm font-medium text-slate-600 outline-none bg-transparent min-w-0" />
                            </div>
                        </div>
                    </div>
                    <div className="overflow-x-auto">
                        <table className="w-full text-left text-sm">
                            <thead className="bg-slate-100 text-slate-600 border-b border-slate-200">
                                <tr>
                                    <th className="p-4 font-bold">วันที่จ่าย</th>
                                    <th className="p-4 font-bold">ชื่อพนักงาน / รายละเอียด</th>
                                    <th className="p-4 font-bold">งวดบัญชี</th>
                                    <th className="p-4 font-bold text-right">ยอดสุทธิ (บาท)</th>
                                    <th className="p-4 font-bold text-center w-28">การดำเนินการ</th>
                                </tr>
                            </thead>
                            <tbody className="divide-y divide-slate-100">
                                {filteredHistory.length === 0 ? (
                                    <tr><td colSpan={5} className="p-12 text-center text-slate-400">ไม่พบประวัติการจ่ายในช่วงเวลานี้</td></tr>
                                ) : (
                                    filteredHistory.map(t => (
                                        <tr key={t.id} className="hover:bg-slate-50/80 transition-colors">
                                            <td className="p-4 font-medium text-slate-700 whitespace-nowrap">{formatDateBE(t.date)}</td>
                                            <td className="p-4">
                                                <div className="font-bold text-slate-800">{t.description}</div>
                                            </td>
                                            <td className="p-4 text-slate-600">{t.payrollPeriod ? `${formatDateBE(t.payrollPeriod.start)} – ${formatDateBE(t.payrollPeriod.end)}` : '-'}</td>
                                            <td className="p-4 text-right font-bold text-emerald-600">฿{(t.amount ?? 0).toLocaleString()}</td>
                                            <td className="p-4 text-center">
                                                <Button variant="ghost" onClick={() => setViewHistoryItem(t)} className="text-slate-600 hover:bg-emerald-50 hover:text-emerald-700 border border-slate-200 rounded-lg px-3 py-1.5 text-sm">
                                                    <Eye size={14} className="mr-1.5 inline" /> ดูรายละเอียด
                                                </Button>
                                            </td>
                                        </tr>
                                    ))
                                )}
                            </tbody>
                        </table>
                    </div>
                </Card>
            )}

            {/* View History Detail Modal - ใบสำคัญจ่ายเงินเดือน */}
            {viewHistoryItem && (() => {
                const snap = viewHistoryItem.payrollSnapshot;
                const totalEarnings = snap ? ((snap.basePay ?? 0) + (snap.ot ?? 0) + (snap.special ?? 0) + (snap.customBonus ?? 0)) : 0;
                const totalDeductions = snap ? ((snap.adv ?? 0) + (snap.customDeduction ?? 0)) : 0;
                return (
                    <div className="fixed inset-0 bg-slate-900/60 backdrop-blur-sm flex items-center justify-center z-[110] p-4">
                        <Card className="w-full max-w-lg p-0 relative animate-slide-up overflow-hidden shadow-2xl border-0">
                            <div className="bg-gradient-to-br from-slate-800 to-slate-900 text-white p-6 pb-8 relative">
                                <button onClick={() => setViewHistoryItem(null)} className="absolute top-4 right-4 text-white/60 hover:text-white transition-colors bg-white/10 rounded-full p-2"><XCircle size={20} /></button>
                                <h3 className="text-sm font-bold text-white/80 uppercase tracking-wider mb-1">ใบสำคัญจ่ายเงินเดือน</h3>
                                <h2 className="text-2xl font-black">{viewHistoryItem.description.replace('เงินเดือน ', '')}</h2>
                                <div className="absolute -bottom-4 left-6 right-6 h-8 bg-white rounded-t-2xl" />
                            </div>
                            <div className="p-6 pt-6 bg-white space-y-5 text-slate-700">
                                <div className="grid grid-cols-2 gap-4 text-sm bg-slate-50 p-4 rounded-xl border border-slate-100">
                                    <div><span className="block text-xs text-slate-500 font-bold uppercase mb-1">วันที่จ่าย</span><span className="font-bold text-slate-800">{formatDateBE(viewHistoryItem.date)}</span></div>
                                    <div><span className="block text-xs text-slate-500 font-bold uppercase mb-1">งวดบัญชี</span><span className="font-bold text-slate-800">{viewHistoryItem.payrollPeriod ? `${formatDateBE(viewHistoryItem.payrollPeriod.start)} – ${formatDateBE(viewHistoryItem.payrollPeriod.end)}` : '-'}</span></div>
                                </div>

                                {snap && (
                                    <>
                                        <div className="border border-slate-200 rounded-xl overflow-hidden">
                                            <div className="bg-slate-100 px-4 py-2.5 font-bold text-slate-600 text-xs uppercase tracking-wider border-b">รายได้</div>
                                            <div className="divide-y divide-slate-100">
                                                <div className="flex justify-between px-4 py-3"><span className="text-slate-600">ค่าแรง ({snap.fullDays} วันเต็ม + {snap.halfDays} ครึ่งวัน)</span><span className="font-semibold">฿{(snap.basePay ?? 0).toLocaleString()}</span></div>
                                                <div className="flex justify-between px-4 py-3"><span className="text-slate-600">ค่าล่วงเวลา (OT)</span><span className="font-semibold">฿{(snap.ot ?? 0).toLocaleString()}</span></div>
                                                <div className="flex justify-between px-4 py-3"><span className="text-slate-600">พิเศษอื่นๆ</span><span className="font-semibold">฿{(snap.special ?? 0).toLocaleString()}</span></div>
                                                <div className="flex justify-between px-4 py-3 bg-emerald-50/50"><span className="text-emerald-700 font-medium">โบนัส / เบี้ยขยัน</span><span className="font-semibold text-emerald-700">+฿{(snap.customBonus ?? 0).toLocaleString()}</span></div>
                                            </div>
                                            <div className="flex justify-between px-4 py-3 bg-slate-50 border-t-2 border-slate-200 font-bold text-slate-800"><span>รวมรายได้</span><span>฿{totalEarnings.toLocaleString()}</span></div>
                                        </div>
                                        <div className="border border-slate-200 rounded-xl overflow-hidden">
                                            <div className="bg-rose-50 px-4 py-2.5 font-bold text-rose-600 text-xs uppercase tracking-wider border-b">รายการหัก</div>
                                            <div className="divide-y divide-slate-100">
                                                <div className="flex justify-between px-4 py-3"><span className="text-rose-600">เบิกล่วงหน้า</span><span className="font-semibold text-rose-600">-฿{(snap.adv ?? 0).toLocaleString()}</span></div>
                                                <div className="flex justify-between px-4 py-3 bg-rose-50/30"><span className="text-rose-600 font-medium">หักอื่นๆ (สาย/ขาด)</span><span className="font-semibold text-rose-600">-฿{(snap.customDeduction ?? 0).toLocaleString()}</span></div>
                                            </div>
                                            <div className="flex justify-between px-4 py-3 bg-rose-50/50 border-t-2 border-rose-200 font-bold text-rose-700"><span>รวมรายการหัก</span><span>-฿{totalDeductions.toLocaleString()}</span></div>
                                        </div>
                                        {snap.adjNote && (
                                            <div className="text-sm text-slate-500 italic bg-amber-50 border border-amber-100 rounded-lg px-4 py-2">หมายเหตุ: {snap.adjNote}</div>
                                        )}
                                    </>
                                )}

                                <div className="flex justify-between items-center pt-4 pb-2 border-t-2 border-slate-200">
                                    <span className="text-sm font-bold text-slate-600 uppercase tracking-wider">ยอดสุทธิที่จ่าย (บาท)</span>
                                    <span className="text-2xl font-black text-emerald-600">฿<FormatNumber value={viewHistoryItem.amount ?? 0} /></span>
                                </div>

                                {/* แบงค์จ่าย (ใบสำคัญ) */}
                                {(() => {
                                    const amt = viewHistoryItem.amount ?? 0;
                                    const bank = getBanknoteBreakdown(amt);
                                    return (
                                        <div className="pt-4 border-t border-amber-200 rounded-xl bg-amber-50/50 p-4">
                                            <p className="text-xs font-bold text-amber-700 uppercase tracking-wider mb-2">แบงค์จ่าย (ยอด ฿{amt.toLocaleString()})</p>
                                            <div className="flex flex-wrap gap-3 text-sm">
                                                <span className="px-3 py-1.5 rounded-lg bg-amber-100 text-amber-800 font-bold">แบงค์ 1,000 × {bank.b1000}</span>
                                                <span className="px-3 py-1.5 rounded-lg bg-amber-100 text-amber-800 font-bold">แบงค์ 500 × {bank.b500}</span>
                                                <span className="px-3 py-1.5 rounded-lg bg-amber-100 text-amber-800 font-bold">แบงค์ 100 × {bank.b100}</span>
                                                {bank.remainder > 0 && <span className="text-slate-600 font-medium">เศษ {bank.remainder} บาท</span>}
                                            </div>
                                        </div>
                                    );
                                })()}
                            </div>
                        </Card>
                    </div>
                );
            })()}

            {/* Raw data modal - ข้อมูลการลงงานดิบ */}
            {selectedEmp && (
                <div className="fixed inset-0 bg-slate-900/60 backdrop-blur-sm flex items-center justify-center z-50 p-4">
                    <Card className="w-full max-w-4xl p-0 overflow-hidden shadow-2xl flex flex-col max-h-[90vh] border-0">
                        <div className="flex justify-between items-start p-5 border-b border-slate-200 bg-gradient-to-r from-slate-50 to-white">
                            <div>
                                <h3 className="font-bold text-xl text-slate-800">ข้อมูลการลงงานดิบ</h3>
                                <p className="text-slate-600 mt-0.5">{selectedEmp.name} {selectedEmp.nickname !== selectedEmp.name && `(${selectedEmp.nickname})`}</p>
                                <p className="text-xs text-slate-500 mt-1">งวด {formatDateBE(range.start)} – {formatDateBE(range.end)} · รวม {selectedEmp.transactions?.length ?? 0} รายการ</p>
                            </div>
                            <button onClick={() => setSelectedEmp(null)} className="p-2 hover:bg-slate-200 rounded-xl text-slate-500 transition-colors"><XCircle size={22} /></button>
                        </div>
                        <div className="overflow-x-auto overflow-y-auto flex-1">
                            <table className="w-full text-sm text-left">
                                <thead className="bg-slate-100 text-slate-600 sticky top-0 border-b border-slate-200">
                                    <tr>
                                        <th className="p-3 font-bold">วันที่</th>
                                        <th className="p-3 font-bold">หมวดหมู่</th>
                                        <th className="p-3 font-bold">รายละเอียด</th>
                                        <th className="p-3 font-bold text-center">วันทำงาน</th>
                                        <th className="p-3 font-bold text-right">OT</th>
                                        <th className="p-3 font-bold text-right">เบิก</th>
                                        <th className="p-3 font-bold text-right">พิเศษ</th>
                                    </tr>
                                </thead>
                                <tbody className="divide-y divide-slate-100">
                                    {(!selectedEmp.transactions || selectedEmp.transactions.length === 0) ? (
                                        <tr><td colSpan={7} className="p-10 text-center text-slate-400">ไม่มีข้อมูลการลงงานในช่วงนี้</td></tr>
                                    ) : (
                                        selectedEmp.transactions.map((t: Transaction) => {
                                            const isHalf = t.laborStatus === 'Work' && (t.workTypeByEmployee && selectedEmp.id in t.workTypeByEmployee ? t.workTypeByEmployee[selectedEmp.id] === 'HalfDay' : t.workType === 'HalfDay');
                                            return (
                                                <tr key={t.id} className="hover:bg-slate-50/80">
                                                    <td className="p-3 font-medium text-slate-700 whitespace-nowrap">{formatDateBE(t.date)}</td>
                                                    <td className="p-3"><span className="px-2 py-1 bg-slate-100 text-slate-600 rounded-lg text-xs font-bold">{t.category}</span></td>
                                                    <td className="p-3 text-slate-600">{t.description}</td>
                                                    <td className="p-3 text-center">
                                                        {t.laborStatus === 'Work' ? (isHalf ? <span className="text-amber-600 bg-amber-50 px-2 py-1 rounded-lg font-medium">0.5 วัน</span> : <span className="text-emerald-600 bg-emerald-50 px-2 py-1 rounded-lg font-medium">1 วัน</span>) : '-'}
                                                    </td>
                                                    <td className="p-3 text-right font-medium text-slate-700">{(t.otAmount ?? 0) > 0 ? `฿${(t.otAmount ?? 0).toLocaleString()}` : '-'}</td>
                                                    <td className="p-3 text-right font-medium text-rose-600">{(t.advanceAmount ?? 0) > 0 ? `฿${(t.advanceAmount ?? 0).toLocaleString()}` : '-'}</td>
                                                    <td className="p-3 text-right font-medium text-blue-600">{(t.specialAmount ?? 0) > 0 ? `฿${(t.specialAmount ?? 0).toLocaleString()}` : '-'}</td>
                                                </tr>
                                            );
                                        })
                                    )}
                                </tbody>
                            </table>
                        </div>
                        <div className="p-4 bg-slate-50 border-t border-slate-200 flex justify-end gap-2">
                            <Button onClick={() => setSelectedEmp(null)} variant="outline" className="rounded-xl bg-white">ปิด</Button>
                        </div>
                    </Card>
                </div>
            )}

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

                        {/* Slip Template (For Employee) */}
                        <Card className="w-full p-0 overflow-hidden shadow-2xl bg-white border-2 border-slate-200 print:shadow-none print:border-none print:rounded-none" id="print-slip" ref={slipRef}>
                            <div className="bg-gradient-to-br from-slate-800 to-slate-900 text-white p-6 sm:p-8 flex justify-between items-center print:bg-slate-100 print:text-black print:border-b-2 print:border-slate-800">
                                <div>
                                    <h2 className="text-2xl sm:text-3xl font-black mb-1">ใบแจ้งเงินเดือน</h2>
                                    <p className="text-white/70 print:text-slate-500 font-medium tracking-widest text-xs uppercase">PAYSLIP</p>
                                </div>
                                <div className="text-right">
                                    <h1 className="text-xl sm:text-2xl font-bold text-amber-400 print:text-slate-800 tracking-tight">GOLDENMOLE</h1>
                                    <p className="text-xs text-white/50 print:text-slate-400 font-medium">Construction & Sandbox</p>
                                </div>
                            </div>

                            <div className="px-6 sm:px-8 py-6 bg-slate-50 border-b border-slate-100 flex flex-col sm:flex-row gap-6 print:bg-white justify-between">
                                <div>
                                    <p className="text-xs font-bold text-slate-500 uppercase tracking-wider mb-1">ชื่อพนักงาน</p>
                                    <p className="text-xl font-bold text-slate-800">{slipEmp.name}</p>
                                    {slipEmp.nickname !== slipEmp.name && <p className="text-sm text-slate-500">ชื่อเรียก: {slipEmp.nickname}</p>}
                                </div>
                                <div className="text-left sm:text-right">
                                    <p className="text-xs font-bold text-slate-500 uppercase tracking-wider mb-1">งวดที่จ่าย (Period)</p>
                                    <p className="text-base font-bold text-slate-800">{formatDateBE(range.start)} – {formatDateBE(range.end)}</p>
                                    <p className="text-xs text-slate-500 mt-0.5">{slipEmp.type === 'Monthly' ? 'รายเดือน' : 'รายวัน'} · ฐาน ฿{(slipEmp.baseWage ?? 0).toLocaleString()}</p>
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
                                            <span>ค่าแรงปกติ <span className="text-xs text-slate-400 block font-normal">{slipEmp.fullDays} วัน, {slipEmp.halfDays} ครึ่ง (ฐาน ฿{slipEmp.baseWage ?? 0})</span></span>
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
                                    ฿<FormatNumber value={slipEmp.net} />
                                </div>
                            </div>

                            {/* แบงค์จ่าย (ใบสลิป) */}
                            {(() => {
                                const bank = getBanknoteBreakdown(slipEmp.net ?? 0);
                                return (
                                    <div className="px-6 sm:px-8 py-4 border-t border-amber-200 bg-amber-50/50 print:bg-slate-50 print:border-slate-200">
                                        <p className="text-xs font-bold text-amber-700 uppercase tracking-wider mb-2 print:text-slate-600">แบงค์จ่าย (สำหรับจ่ายเงินสด) — ยอดจ่าย ฿{(slipEmp.net ?? 0).toLocaleString()}</p>
                                        <div className="flex flex-wrap gap-4 text-sm font-medium text-slate-700">
                                            <span>แบงค์ 1,000 บาท × <strong>{bank.b1000}</strong></span>
                                            <span>แบงค์ 500 บาท × <strong>{bank.b500}</strong></span>
                                            <span>แบงค์ 100 บาท × <strong>{bank.b100}</strong></span>
                                            {bank.remainder > 0 && <span className="text-slate-500">เศษ <strong>{bank.remainder}</strong> บาท</span>}
                                        </div>
                                    </div>
                                );
                            })()}

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
