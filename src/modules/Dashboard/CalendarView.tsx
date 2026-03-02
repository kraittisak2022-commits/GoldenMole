import { useState } from 'react';
import { XCircle } from 'lucide-react';
import Card from '../../components/ui/Card';
import { Transaction, Employee } from '../../types';

const CalendarView = ({ transactions, employees }: { transactions: Transaction[], employees: Employee[] }) => {
    const [selectedDay, setSelectedDay] = useState<string | null>(null);

    const daysInMonth = Array.from({ length: 31 }, (_, i) => {
        const d = i + 1;
        const today = new Date();
        const dateStr = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(d).padStart(2, '0')}`;

        const dayTrans = transactions.filter(t => t.date === dateStr);
        const inc = dayTrans.filter(t => t.type === 'Income').reduce((s, t) => s + t.amount, 0);
        const exp = dayTrans.filter(t => t.type === 'Expense').reduce((s, t) => s + t.amount, 0);

        // Count Attendance & Get Leave Names
        const workingEmpIds = new Set(dayTrans.filter(t => t.category === 'Labor' && t.laborStatus === 'Work').flatMap(t => t.employeeIds || []));
        const leaveTrans = dayTrans.filter(t => t.category === 'Leave');
        const leaveEmpIds = new Set(leaveTrans.flatMap(t => t.employeeIds || []));

        // Map leave IDs to names
        const leaveNames = Array.from(leaveEmpIds).map(id => {
            const emp = employees.find(e => e.id === id);
            return emp ? (emp.nickname || emp.name) : 'Unknown';
        });

        const presentCount = workingEmpIds.size;
        const leaveCount = leaveEmpIds.size;
        const missingCount = employees.length - presentCount - leaveCount;

        return { day: d, inc, exp, date: dateStr, presentCount, leaveCount, missingCount, transactions: dayTrans, leaveNames };
        // Get Daily Logs
        const machineLogs = dayTrans.filter(t => t.category === 'DailyLog' && t.subCategory === 'MachineWork');
        const sandLogs = dayTrans.filter(t => t.category === 'DailyLog' && t.subCategory === 'SandProduction');
        const eventLogs = dayTrans.filter(t => t.category === 'DailyLog' && t.subCategory === 'GeneralEvent');

        return { day: d, inc, exp, date: dateStr, presentCount, leaveCount, missingCount, transactions: dayTrans, leaveNames, machineLogs, sandLogs, eventLogs };
    });

    return (
        <Card className="p-6 animate-fade-in">
            <h3 className="font-bold mb-6 text-lg text-slate-700">ปฏิทินการทำงาน & การเงิน (เดือนปัจจุบัน)</h3>
            <div className="grid grid-cols-7 gap-2 mb-2 text-center text-sm font-bold text-slate-400">
                {['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].map((d, i) => <div key={i}>{d}</div>)}
            </div>
            <div className="grid grid-cols-7 gap-2">
                {daysInMonth.map((d, i) => (
                    <div key={i} onClick={() => setSelectedDay(d.date)} className="aspect-square border rounded-lg p-1 flex flex-col justify-between hover:bg-slate-50 transition-colors min-h-[100px] relative group cursor-pointer">
                        <div className="flex justify-between items-start">
                            <span className="text-xs text-slate-400 font-medium">{d.day}</span>
                            <div className="flex gap-1">
                                {d.presentCount > 0 && <div className="w-1.5 h-1.5 rounded-full bg-emerald-400" title={`มา: ${d.presentCount}`} />}
                                {d.leaveCount > 0 && <div className="w-1.5 h-1.5 rounded-full bg-amber-400" title={`ลา: ${d.leaveCount}`} />}
                                {d.missingCount > 0 && <div className="w-1.5 h-1.5 rounded-full bg-slate-200" title={`ขาด: ${d.missingCount}`} />}
                            </div>
                        </div>

                        {/* Display Leave Names */}
                        <div className="flex flex-col gap-0.5 mt-1 overflow-hidden">
                            {d.leaveNames.slice(0, 3).map((name, idx) => (
                                <span key={idx} className="text-[9px] bg-amber-100 text-amber-700 px-1 rounded truncate">ลา: {name}</span>
                            ))}
                            {d.leaveNames.length > 3 && <span className="text-[9px] text-amber-500 pl-1">+{d.leaveNames.length - 3}</span>}
                        </div>

                        <div className="flex flex-col gap-0.5 text-[10px] text-right mt-auto">
                            {d.inc > 0 && <span className="text-emerald-600 font-bold">+{d.inc.toLocaleString()}</span>}
                            {d.exp > 0 && <span className="text-red-500">-{d.exp.toLocaleString()}</span>}
                        </div>
                    </div>
                ))}
            </div>

            {/* Modal for Day Details */}
            {selectedDay && (() => {
                const dayDetails = daysInMonth.find(d => d.date === selectedDay);
                if (!dayDetails) return null;

                return (
                    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-[110] p-4">
                        <Card className="w-full max-w-2xl p-6 max-h-[85vh] overflow-y-auto relative animate-slide-up">
                            <button onClick={() => setSelectedDay(null)} className="absolute top-4 right-4 text-slate-400 hover:text-slate-600"><XCircle /></button>
                            <h3 className="font-bold text-xl mb-6 text-center text-slate-800">รายละเอียดวันที่ {new Date(selectedDay).toLocaleDateString('th-TH', { dateStyle: 'full' })}</h3>

                            {/* Summary of People */}
                            <div className="grid grid-cols-3 gap-2 mb-6">
                                <div className="bg-emerald-50 p-2 rounded text-center border border-emerald-100">
                                    <p className="text-xs text-emerald-600">มาทำงาน</p>
                                    <p className="font-bold text-lg text-emerald-700">{dayDetails.presentCount}</p>
                                </div>
                                <div className="bg-amber-50 p-2 rounded text-center border border-amber-100">
                                    <p className="text-xs text-amber-600">ลางาน</p>
                                    <p className="font-bold text-lg text-amber-700">{dayDetails.leaveCount}</p>
                                </div>
                                <div className="bg-slate-50 p-2 rounded text-center border border-slate-200">
                                    <p className="text-xs text-slate-500">ขาดงาน</p>
                                    <p className="font-bold text-lg text-slate-600">{dayDetails.missingCount}</p>
                                </div>
                            </div>

                            {/* Daily Log Section (V.3 Enhancements) */}
                            <div className="space-y-4 mb-6">
                                <h4 className="font-bold text-sm text-slate-700 bg-slate-100 p-2 rounded-lg">บันทึกประจำวัน</h4>

                                {/* Machine Logs */}
                                {(dayDetails.machineLogs || []).map(t => (
                                    <div key={t.id} className="flex items-start gap-3 p-3 border rounded-xl bg-orange-50 border-orange-100">
                                        <div className="bg-orange-100 p-2 rounded-full"><code className="text-xl">🚜</code></div>
                                        <div>
                                            <div className="font-bold text-orange-900">{t.machineId} <span className="text-sm font-normal text-slate-500">({t.machineHours} ชม.)</span></div>
                                            <div className="text-sm text-slate-600">{t.note || t.description}</div>
                                            <div className="text-xs text-slate-400 flex gap-2 mt-1">📍 {t.location || 'ไม่ระบุ'}</div>
                                        </div>
                                    </div>
                                ))}

                                {/* Sand Logs */}
                                <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                                    {(dayDetails.sandLogs || []).map(t => (
                                        <div key={t.id} className={`p-3 border rounded-xl ${(t as any).sandMachineType === 'Old' ? 'bg-amber-50 border-amber-100' : 'bg-blue-50 border-blue-100'}`}>
                                            <div className="flex justify-between items-center mb-1">
                                                <span className={`text-xs font-bold px-2 py-0.5 rounded ${(t as any).sandMachineType === 'Old' ? 'bg-amber-100 text-amber-700' : 'bg-blue-100 text-blue-700'}`}>
                                                    {(t as any).sandMachineType === 'Old' ? 'เครื่องเก่า' : 'เครื่องใหม่'}
                                                </span>
                                                <span className="font-bold text-lg text-slate-800">{t.quantity} คิว</span>
                                            </div>
                                            <div className="text-xs text-slate-500">เช้า {(t as any).sandMorning} / บ่าย {(t as any).sandAfternoon}</div>
                                            <div className="text-xs text-slate-500 mt-1">คนคุม: {((t as any).sandOperators || []).join(', ')}</div>
                                        </div>
                                    ))}
                                </div>

                                {/* General Events */}
                                {(dayDetails.eventLogs || []).map(t => (
                                    <div key={t.id} className="flex gap-3 p-3 border rounded-xl bg-purple-50 border-purple-100">
                                        <div className="font-bold text-purple-600 text-sm min-w-[50px]">{(t as any).eventTime}</div>
                                        <div className="text-sm text-slate-700">{t.description}</div>
                                    </div>
                                ))}

                                {/* Empty State for Logs */}
                                {(!(dayDetails.machineLogs || []).length &&
                                    !(dayDetails.sandLogs || []).length &&
                                    !(dayDetails.eventLogs || []).length) &&
                                    <div className="text-center text-slate-400 text-sm py-2 italic">- ไม่มีบันทึกเหตุการณ์ -</div>}
                            </div>

                            {/* Transaction List */}
                            <h4 className="font-bold text-sm mb-2 text-slate-700">รายการธุรกรรม</h4>
                            <div className="space-y-2">
                                {(dayDetails.transactions || []).map(t => (
                                    <div key={t.id} className="border p-3 rounded-lg flex justify-between items-center text-sm">
                                        <div>
                                            <div className="font-bold">{t.description}</div>
                                            <div className="text-xs text-slate-500">{t.category} {t.subCategory ? `• ${t.subCategory}` : ''}</div>
                                        </div>
                                        <div className={`font-bold ${t.type === 'Income' ? 'text-emerald-600' : t.category === 'Leave' ? 'text-amber-500' : 'text-red-500'}`}>
                                            {t.type === 'Income' ? '+' : ''}{t.amount > 0 ? `฿${t.amount.toLocaleString()}` : t.laborStatus === 'Leave' ? 'ลา' : '-'}
                                        </div>
                                    </div>
                                ))}
                                {(dayDetails.transactions || []).length === 0 && <p className="text-center text-slate-400 text-sm">ไม่มีรายการบันทึก</p>}
                            </div>
                        </Card>
                    </div>
                );
            })()}
        </Card>
    );
};

export default CalendarView;
