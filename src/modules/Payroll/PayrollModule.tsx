import { useState, useMemo } from 'react';
import { CheckCircle2, History, FileCheck, Eye, XCircle } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import Input from '../../components/ui/Input';
import FormatNumber from '../../components/ui/FormatNumber';
import { getFirstDayOfMonth, getLastDayOfMonth, getToday } from '../../utils';
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
    const [historyRange, setHistoryRange] = useState({ start: '2023-01-01', end: '2024-12-31' });
    const [viewHistoryItem, setViewHistoryItem] = useState<Transaction | null>(null);

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

        let basePay = emp.type === 'Monthly' ? emp.baseWage : (fullDays * emp.baseWage) + (halfDays * (emp.baseWage / 2));
        const totalIncome = basePay + ot + special;
        const netPay = totalIncome - adv;
        const isPaid = checkOverlap(emp.id, range.start, range.end);

        return { ...emp, fullDays, halfDays, income: totalIncome, net: netPay, ot, adv, special, basePay, transactions: empTrans, isPaid };
    };

    const payrollData = useMemo(() => employees.filter(e => e.name.toLowerCase().includes(search.toLowerCase()) || e.nickname.toLowerCase().includes(search.toLowerCase())).map(emp => calculatePayroll(emp)), [employees, transactions, range, search]);

    const handleConfirmPayment = (p: any) => {
        if (p.isPaid) return alert('จ่ายซ้ำไม่ได้');
        const payrollDetails = {
            fullDays: p.fullDays,
            halfDays: p.halfDays,
            basePay: p.basePay,
            ot: p.ot,
            special: p.special,
            adv: p.adv,
            net: p.net
        };
        onSaveTransaction({
            id: Date.now().toString(),
            date: getToday(),
            type: 'Expense',
            category: 'Payroll',
            description: `เงินเดือน ${p.name}`,
            amount: p.net,
            employeeId: p.id,
            payrollPeriod: { start: range.start, end: range.end },
            payrollSnapshot: payrollDetails
        } as Transaction);
        setSlipEmp(null);
    };

    const filteredHistory = getPayrollHistory().filter(t => {
        const inDate = t.date >= historyRange.start && t.date <= historyRange.end;
        const inName = t.description.toLowerCase().includes(historySearch.toLowerCase());
        return inDate && inName;
    });

    return (
        <div className="space-y-6 animate-fade-in">
            <div className="flex flex-wrap gap-2 justify-center mb-4"><Button variant={view === 'Calculate' ? 'primary' : 'outline'} onClick={() => setView('Calculate')}>คำนวณเงินเดือน</Button><Button variant={view === 'History' ? 'primary' : 'outline'} onClick={() => setView('History')}>ประวัติการจ่าย</Button></div>
            {view === 'Calculate' ? (
                <>
                    <Card className="p-3 sm:p-4 flex flex-col gap-3 sm:gap-4">
                        <div className="flex flex-col sm:flex-row gap-2 sm:gap-3 items-stretch sm:items-center w-full">
                            <Input placeholder="ค้นหา..." value={search} onChange={(e: any) => setSearch(e.target.value)} className="w-full sm:w-48" />
                            <div className="flex items-center gap-2 bg-slate-50 p-1 rounded-lg border">
                                <input type="date" value={range.start} onChange={(e) => setRange({ ...range, start: e.target.value })} className="bg-transparent text-xs outline-none w-full sm:w-auto" />-<input type="date" value={range.end} onChange={(e) => setRange({ ...range, end: e.target.value })} className="bg-transparent text-xs outline-none w-full sm:w-auto" />
                            </div>
                            <div className="flex gap-1">
                                <button onClick={setCurrentMonth} className="px-2 py-1 text-xs bg-emerald-50 text-emerald-600 rounded border border-emerald-100 hover:bg-emerald-100 whitespace-nowrap">เดือนนี้</button>
                                <button onClick={setLastMonth} className="px-2 py-1 text-xs bg-slate-50 text-slate-600 rounded border border-slate-200 hover:bg-slate-100 whitespace-nowrap">เดือนก่อน</button>
                            </div>
                        </div>
                    </Card>
                    <div className="grid grid-cols-1 gap-4">
                        {payrollData.map(p => (
                            <Card key={p.id} className={`p-3 sm:p-4 flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3 sm:gap-4 ${p.isPaid ? 'opacity-60 bg-slate-50' : ''}`}>
                                <div className="flex items-center gap-4 w-full md:w-auto">
                                    <div className="w-12 h-12 rounded-full bg-slate-100 flex items-center justify-center font-bold text-slate-600 text-lg">{p.nickname.charAt(0)}</div>
                                    <div>
                                        <h4 className="font-bold text-lg">{p.name}</h4>
                                        <p className="text-xs text-slate-500">{p.type} • ฿{p.baseWage}/วัน</p>
                                        {p.isPaid && <span className="text-xs text-emerald-600 font-bold flex items-center gap-1"><CheckCircle2 size={10} /> จ่ายแล้ว</span>}
                                    </div>
                                </div>
                                <div className="flex gap-8 text-sm text-center">
                                    <div><p className="text-slate-400 text-xs">วัน</p><p className="font-bold">{p.fullDays} <span className="text-xs text-slate-400">({p.halfDays} ครึ่ง)</span></p></div>
                                    <div><p className="text-slate-400 text-xs">สุทธิ</p><p className="font-bold text-xl text-slate-800"><FormatNumber value={p.net} /></p></div>
                                </div>
                                <div className="flex gap-2">
                                    <Button variant="outline" onClick={() => setSelectedEmp(p)} className="px-3"><History size={16} /></Button>
                                    <Button onClick={() => setSlipEmp(p)} disabled={p.isPaid} className="px-3 bg-emerald-600"><FileCheck size={16} /></Button>
                                </div>
                            </Card>
                        ))}
                    </div>
                </>
            ) : (
                <Card className="p-0 overflow-hidden">
                    <div className="p-3 sm:p-4 border-b bg-slate-50 flex flex-col sm:flex-row justify-between items-start sm:items-center gap-2">
                        <span className="font-bold">ประวัติการจ่าย</span>
                        <div className="flex flex-col sm:flex-row gap-2 w-full sm:w-auto">
                            <Input placeholder="ค้นหาชื่อ..." value={historySearch} onChange={(e: any) => setHistorySearch(e.target.value)} className="w-full sm:w-32 text-xs" />
                            <div className="flex items-center gap-1 bg-white border rounded px-2"><input type="date" value={historyRange.start} onChange={e => setHistoryRange({ ...historyRange, start: e.target.value })} className="text-xs outline-none w-full sm:w-24" />- <input type="date" value={historyRange.end} onChange={e => setHistoryRange({ ...historyRange, end: e.target.value })} className="text-xs outline-none w-full sm:w-24" /></div>
                        </div>
                    </div>
                    <div className="max-h-[600px] overflow-y-auto overflow-x-auto">
                        <table className="w-full text-sm text-left min-w-[500px]">
                            <thead className="bg-white sticky top-0"><tr><th className="p-4">วันที่จ่าย</th><th className="p-4">รายการ</th><th className="p-4 text-right">จำนวนเงิน</th><th className="p-4"></th></tr></thead>
                            <tbody>{filteredHistory.map(t => <tr key={t.id} className="border-b hover:bg-slate-50"><td className="p-4">{t.date}</td><td className="p-4"><div className="font-bold">{t.description}</div><div className="text-xs text-slate-400">งวด: {t.payrollPeriod?.start} ถึง {t.payrollPeriod?.end}</div></td><td className="p-4 text-right font-bold text-emerald-600"><FormatNumber value={t.amount} /></td><td className="p-4 text-center"><Button variant="ghost" onClick={() => setViewHistoryItem(t)} size="sm" className="px-2"><Eye size={16} /></Button></td></tr>)}</tbody>
                        </table>
                    </div>
                </Card>
            )}

            {/* View History Detail Modal */}
            {viewHistoryItem && (
                <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-[110] p-4">
                    <Card className="w-full max-w-md p-6 relative animate-slide-up">
                        <button onClick={() => setViewHistoryItem(null)} className="absolute top-4 right-4 text-slate-400 hover:text-slate-600"><XCircle /></button>
                        <h3 className="text-lg font-bold mb-4 text-center border-b pb-4">รายละเอียดการจ่าย</h3>
                        <div className="space-y-3 text-sm">
                            <div className="flex justify-between"><span className="text-slate-500">วันที่จ่าย</span><span>{viewHistoryItem.date}</span></div>
                            <div className="flex justify-between"><span className="text-slate-500">รายการ</span><span className="font-bold">{viewHistoryItem.description}</span></div>
                            <div className="flex justify-between"><span className="text-slate-500">งวด</span><span>{viewHistoryItem.payrollPeriod?.start} - {viewHistoryItem.payrollPeriod?.end}</span></div>

                            {viewHistoryItem.payrollSnapshot && (
                                <div className="bg-slate-50 p-3 rounded-lg border mt-2 space-y-2">
                                    <div className="flex justify-between text-xs"><span>วันทำงาน</span><span>{viewHistoryItem.payrollSnapshot.fullDays} + {viewHistoryItem.payrollSnapshot.halfDays / 2}</span></div>
                                    <div className="flex justify-between text-xs"><span>ฐานเงินเดือน</span><span>{viewHistoryItem.payrollSnapshot.basePay?.toLocaleString()}</span></div>
                                    <div className="flex justify-between text-xs text-blue-600"><span>OT</span><span>{viewHistoryItem.payrollSnapshot.ot?.toLocaleString()}</span></div>
                                    <div className="flex justify-between text-xs text-purple-600"><span>พิเศษ</span><span>{viewHistoryItem.payrollSnapshot.special?.toLocaleString()}</span></div>
                                    <div className="flex justify-between text-xs text-red-500"><span>หักเบิก</span><span>-{viewHistoryItem.payrollSnapshot.adv?.toLocaleString()}</span></div>
                                </div>
                            )}

                            <div className="border-t pt-2 mt-2">
                                <div className="flex justify-between"><span className="text-slate-500">ยอดสุทธิ</span><span className="text-xl font-bold text-emerald-600">฿{viewHistoryItem.amount.toLocaleString()}</span></div>
                            </div>
                        </div>
                    </Card>
                </div>
            )}

            {selectedEmp && (<div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"><Card className="w-full max-w-2xl p-6 max-h-[80vh] overflow-y-auto"><div className="flex justify-between items-center mb-6"><h3 className="font-bold text-xl">รายละเอียด: {selectedEmp.name}</h3><button onClick={() => setSelectedEmp(null)}><XCircle /></button></div><table className="w-full text-sm text-left"><thead className="bg-slate-50 sticky top-0"><tr><th className="p-3">วันที่</th><th className="p-3">รายการ</th><th className="p-3 text-right">สถานะ</th></tr></thead><tbody className="divide-y">{selectedEmp.transactions.map((t: Transaction) => <tr key={t.id}><td className="p-3">{t.date}</td><td className="p-3">{t.description}</td><td className="p-3 text-right">{t.laborStatus === 'Work' ? (t.workType === 'HalfDay' ? '0.5' : '1') : (t.amount || 0)}</td></tr>)}</tbody></table></Card></div>)}
            {slipEmp && (<div className="fixed inset-0 bg-black/50 flex items-center justify-center z-[100] p-4"><Card className="w-full max-w-md p-0 overflow-hidden animate-slide-up"><div className="bg-slate-800 text-white p-6 text-center"><h3 className="text-xl font-bold mb-1">ใบแจ้งเงินเดือน</h3></div><div className="p-6 space-y-4"><div className="text-center mb-6"><h2 className="text-2xl font-bold">{slipEmp.name}</h2></div><div className="space-y-2 text-sm border-b pb-4"><div className="flex justify-between"><span>ค่าแรง ({slipEmp.fullDays} วัน + {slipEmp.halfDays} ครึ่ง)</span><span>{slipEmp.basePay.toLocaleString()}</span></div><div className="flex justify-between"><span>ค่าล่วงเวลา (OT)</span><span>{slipEmp.ot.toLocaleString()}</span></div><div className="flex justify-between"><span>รายได้พิเศษ</span><span>{slipEmp.special.toLocaleString()}</span></div><div className="flex justify-between text-emerald-600 font-bold pt-2"><span>รวมรายได้</span><span>{slipEmp.income.toLocaleString()}</span></div></div><div className="space-y-2 text-sm border-b pb-4"><div className="flex justify-between text-red-500"><span>หักเบิกล่วงหน้า</span><span>-{slipEmp.adv.toLocaleString()}</span></div></div><div className="flex justify-between items-center pt-2"><span className="text-lg font-bold text-slate-700">ยอดสุทธิ</span><span className="text-3xl font-bold text-slate-900"><FormatNumber value={slipEmp.net} /></span></div><div className="flex gap-2 mt-6"><Button variant="outline" onClick={() => setSlipEmp(null)} className="flex-1">ยกเลิก</Button><Button onClick={() => handleConfirmPayment(slipEmp)} disabled={slipEmp.isPaid} className="flex-1 bg-emerald-600">ยืนยัน</Button></div></div></Card></div>)}
        </div>
    );
};

export default PayrollModule;
